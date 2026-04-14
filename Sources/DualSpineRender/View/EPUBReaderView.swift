#if canImport(UIKit)
import SwiftUI
import UIKit
import WebKit
import DualSpineCore

/// The primary EPUB rendering surface. A SwiftUI wrapper around `WKWebView`
/// that uses `EPUBSchemeHandler` to serve content directly from the ZIP archive.
///
/// "Highlight" and "Remove Highlight" appear in the native text selection menu
/// (next to Copy, Look Up, Translate) — not in a separate UI bar.
@MainActor
public struct EPUBReaderView: UIViewRepresentable {
    let document: EPUBDocument
    let resourceActor: EPUBResourceActor
    @Binding var spineIndex: Int
    var themeCSS: String?
    var isPaginated: Bool
    /// Pagination transition mode: "slide" or "fade"
    var paginationMode: String
    var highlights: [HighlightRecord]
    var onMessage: ((EPUBBridgeMessage) -> Void)?
    /// Called when the user taps a color in the floating highlight toolbar.
    /// Provides the selection payload and chosen tint hex.
    var onHighlightRequest: ((_ selection: EPUBBridgeMessage.SelectionPayload, _ tintHex: String) -> Void)?
    /// Called when the user taps "Remove Highlight" in the floating toolbar.
    var onRemoveHighlightRequest: ((String) -> Void)?

    public init(
        document: EPUBDocument,
        resourceActor: EPUBResourceActor,
        spineIndex: Binding<Int>,
        themeCSS: String? = nil,
        isPaginated: Bool = false,
        paginationMode: String = "slide",
        highlights: [HighlightRecord] = [],
        onMessage: ((EPUBBridgeMessage) -> Void)? = nil,
        onHighlightRequest: ((_ selection: EPUBBridgeMessage.SelectionPayload, _ tintHex: String) -> Void)? = nil,
        onRemoveHighlightRequest: ((String) -> Void)? = nil
    ) {
        self.document = document
        self.resourceActor = resourceActor
        self._spineIndex = spineIndex
        self.themeCSS = themeCSS
        self.isPaginated = isPaginated
        self.paginationMode = paginationMode
        self.highlights = highlights
        self.onMessage = onMessage
        self.onHighlightRequest = onHighlightRequest
        self.onRemoveHighlightRequest = onRemoveHighlightRequest
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> DualSpineWebView {
        let configuration = WKWebViewConfiguration()

        let schemeHandler = EPUBSchemeHandler(
            resourceActor: resourceActor,
            contentBasePath: document.contentBasePath
        )
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: EPUBSchemeHandler.scheme)

        context.coordinator.bridge.register(in: configuration)

        let webView = DualSpineWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.bouncesZoom = false

        // Register Highlight / Remove Highlight in the system edit menu
        webView.registerMenuItems()

        let coordinator = context.coordinator
        webView.onHighlightAction = { [weak coordinator] in
            coordinator?.showColorPicker()
        }
        webView.onRemoveHighlight = { [weak coordinator] highlightID in
            coordinator?.handleRemoveHighlightMenuAction(highlightID: highlightID)
        }

        context.coordinator.webView = webView
        context.coordinator.schemeHandler = schemeHandler
        context.coordinator.loadSpineItem(at: spineIndex)

        return webView
    }

    public func updateUIView(_ webView: DualSpineWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self  // Keep closures fresh

        if coordinator.currentSpineIndex != spineIndex {
            coordinator.loadSpineItem(at: spineIndex)
        }

        if let css = themeCSS, css != coordinator.currentThemeCSS {
            coordinator.currentThemeCSS = css
            coordinator.bridge.applyTheme(css, in: webView)
        }

        // Handle mode changes: paginated toggle OR pagination mode switch (slide↔fade)
        let modeChanged = isPaginated != coordinator.currentPaginated
            || (isPaginated && paginationMode != coordinator.currentPaginationMode)
        if modeChanged {
            let wasPaginated = coordinator.currentPaginated
            coordinator.currentPaginated = isPaginated
            coordinator.currentPaginationMode = paginationMode
            if isPaginated {
                coordinator.bridge.disablePagination(in: webView)
                Task { @MainActor [weak coordinator] in
                    try? await Task.sleep(for: .milliseconds(80))
                    if let webView = coordinator?.webView {
                        coordinator?.bridge.enablePagination(mode: paginationMode, in: webView)
                    }
                }
            } else {
                coordinator.bridge.disablePagination(in: webView)
                // Switching from paginated to scroll: re-enable continuous scroll
                if wasPaginated {
                    Task { @MainActor [weak coordinator] in
                        try? await Task.sleep(for: .milliseconds(80))
                        if let webView = coordinator?.webView {
                            coordinator?.enableContinuousScroll(in: webView)
                        }
                    }
                }
            }
        }

        // Apply highlights when they change
        let spineHighlights = highlights.filter { $0.spineIndex == coordinator.currentSpineIndex }
        if spineHighlights != coordinator.appliedHighlights {
            coordinator.appliedHighlights = spineHighlights
            let commands = spineHighlights.map { record in
                EPUBBridgeController.HighlightCommand(
                    id: record.id.uuidString,
                    rangeStart: record.rangeStart,
                    rangeEnd: record.rangeEnd,
                    color: HighlightTint.cssColor(hex: record.tintHex)
                )
            }
            coordinator.bridge.applyHighlights(commands, in: webView)
        }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: EPUBReaderView
        let bridge = EPUBBridgeController()
        weak var webView: DualSpineWebView?
        var schemeHandler: EPUBSchemeHandler?
        var currentSpineIndex: Int = -1
        var currentThemeCSS: String?
        var currentPaginated: Bool = false
        var currentPaginationMode: String = "slide"
        var appliedHighlights: [HighlightRecord] = []
        var didAutoAdvance: Bool = false
        var lastSelection: EPUBBridgeMessage.SelectionPayload?
        let chapterCache: ChapterCache

        /// Window of spine indices currently injected into the DOM.
        /// Used by scroll mode to avoid re-injecting chapters.
        var injectedSpineIndices: Set<Int> = []

        init(parent: EPUBReaderView) {
            self.parent = parent
            self.chapterCache = ChapterCache(
                document: parent.document,
                resourceActor: parent.resourceActor
            )
            super.init()

            bridge.onMessage = { [weak self] message in
                self?.handleBridgeMessage(message)
            }

            // Kick off bulk chapter preload in background
            Task.detached(priority: .utility) { [chapterCache] in
                await chapterCache.preloadAll()
            }
        }

        /// Append a chapter's XHTML into the current document for continuous scroll.
        func appendContinuousChapter(spineIndex: Int, in webView: WKWebView) {
            injectContinuousChapter(spineIndex: spineIndex, prepend: false, in: webView)
        }

        /// Prepend a chapter's XHTML above the current content (scroll-up navigation).
        func prependContinuousChapter(spineIndex: Int, in webView: WKWebView) {
            injectContinuousChapter(spineIndex: spineIndex, prepend: true, in: webView)
        }

        private func injectContinuousChapter(spineIndex: Int, prepend: Bool, in webView: WKWebView) {
            let doc = parent.document
            let resolved = doc.package.resolvedSpine
            guard spineIndex >= 0, spineIndex < resolved.count else { return }
            if injectedSpineIndices.contains(spineIndex) { return }
            injectedSpineIndices.insert(spineIndex)

            let href = resolved[spineIndex].1.href
            let jsFunc = prepend ? "__dualSpine_prependChapter" : "__dualSpine_appendChapter"
            let cache = chapterCache

            Task {
                guard let html = await cache.html(forSpineIndex: spineIndex) else { return }
                let escaped = html
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "$", with: "\\$")
                let hrefEscaped = href.replacingOccurrences(of: "'", with: "\\'")
                let js = "window.\(jsFunc)(`\(escaped)`, \(spineIndex), '\(hrefEscaped)')"
                await MainActor.run {
                    webView.evaluateJavaScript(js)
                }
            }
        }

        /// Enable continuous scroll: load the ENTIRE book into the DOM in a
        /// SINGLE bulk DOM operation (not N separate evaluateJavaScript calls).
        /// After this runs, every chapter is scrollable; TOC navigation is
        /// instant native scroll.
        func enableContinuousScroll(in webView: WKWebView) {
            let doc = parent.document
            let resolved = doc.package.resolvedSpine
            guard currentSpineIndex < resolved.count else { return }

            let current = currentSpineIndex
            let total = resolved.count
            let currentHref = resolved[current].1.href

            injectedSpineIndices = [current]

            let setupJS = """
            window.__dualSpine_continuousEnabled = true;
            window.__dualSpine_currentContinuousIndex = \(current);
            window.__dualSpine_wrapAsContinuousChapter(\(current), '\(currentHref)');
            """

            webView.evaluateJavaScript(setupJS) { [weak self] _, _ in
                guard let self, let webView = self.webView else { return }
                // Gather all other chapters' HTML in parallel, then inject in ONE call
                Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self else { return }
                    let cache = self.chapterCache
                    var items: [(idx: Int, href: String, body: String)] = []

                    await withTaskGroup(of: (Int, String, String)?.self) { group in
                        for idx in 0..<total where idx != current {
                            let href = resolved[idx].1.href
                            group.addTask {
                                guard let fullHtml = await cache.html(forSpineIndex: idx) else { return nil }
                                let body = Self.extractBody(from: fullHtml)
                                return (idx, href, body)
                            }
                        }
                        for await result in group {
                            if let r = result { items.append(r) }
                        }
                    }

                    // Mark all as injected
                    await MainActor.run {
                        for it in items { self.injectedSpineIndices.insert(it.idx) }
                    }

                    // Build JSON payload for bulk injection
                    let jsonArray = items.map { item -> [String: Any] in
                        return [
                            "spineIndex": item.idx,
                            "spineHref": item.href,
                            "body": item.body
                        ]
                    }
                    guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonArray),
                          let jsonString = String(data: jsonData, encoding: .utf8) else { return }

                    // Escape for JS string literal (safer than template literal for large payloads)
                    let escaped = jsonString
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "`", with: "\\`")
                        .replacingOccurrences(of: "$", with: "\\$")

                    await MainActor.run {
                        let js = "window.__dualSpine_injectAllChapters(`\(escaped)`)"
                        webView.evaluateJavaScript(js)
                    }
                }
            }
        }

        /// Extract body content from full XHTML document.
        nonisolated static func extractBody(from html: String) -> String {
            // Find <body...> and </body>
            let lowerHtml = html.lowercased()
            guard let bodyStartTag = lowerHtml.range(of: "<body"),
                  let bodyEndTag = lowerHtml.range(of: ">", range: bodyStartTag.upperBound..<lowerHtml.endIndex),
                  let bodyClose = lowerHtml.range(of: "</body>", range: bodyEndTag.upperBound..<lowerHtml.endIndex)
            else {
                return html
            }
            // Convert to original-case indices
            let start = html.index(html.startIndex, offsetBy: lowerHtml.distance(from: lowerHtml.startIndex, to: bodyEndTag.upperBound))
            let end = html.index(html.startIndex, offsetBy: lowerHtml.distance(from: lowerHtml.startIndex, to: bodyClose.lowerBound))
            return String(html[start..<end])
        }

        /// Scroll to a chapter's article WITHOUT reloading the webview.
        /// Returns true if the chapter is already in the DOM and was scrolled to.
        /// Returns false if a full reload is needed.
        func scrollToChapter(spineIndex: Int, in webView: WKWebView) -> Bool {
            guard injectedSpineIndices.contains(spineIndex) else { return false }
            let js = """
            (function() {
                var el = document.getElementById('ds-chapter-\(spineIndex)');
                if (el) {
                    window.__dualSpine_suppressChapterChanged = true;
                    el.scrollIntoView({ block: 'start', behavior: 'smooth' });
                    setTimeout(function() {
                        window.__dualSpine_suppressChapterChanged = false;
                    }, 1000);
                    return true;
                }
                return false;
            })();
            """
            webView.evaluateJavaScript(js)
            currentSpineIndex = spineIndex
            return true
        }

        /// Preload raw bytes for prev/next chapters (2 each direction) so
        /// navigation is instant. Runs on background — reads from ZIP into
        /// the actor's in-memory cache.
        func preloadAdjacentChapters() {
            let document = parent.document
            let resolved = document.package.resolvedSpine
            let current = currentSpineIndex
            let actor = parent.resourceActor

            // Preload 2 before and 2 after (wider window than before)
            let targets = [current - 2, current - 1, current + 1, current + 2]
                .filter { $0 >= 0 && $0 < resolved.count }

            for idx in targets {
                let href = resolved[idx].1.href
                let archivePath = document.contentBasePath + href
                Task.detached(priority: .background) {
                    _ = try? await actor.readResource(at: archivePath)
                }
            }
        }

        /// Show the JS color dot strip below the selection.
        func showColorPicker() {
            guard let webView else { return }
            webView.evaluateJavaScript("window.__dualSpine_showColorPicker()")
        }

        /// Called when user taps a color dot (from JS) or directly with a tint.
        func handleHighlightColorAction(tintHex: String) {
            if let selection = lastSelection {
                parent.onHighlightRequest?(selection, tintHex)
                return
            }
            // Fallback: query selection directly from JS if lastSelection was cleared
            guard let webView else { return }
            webView.evaluateJavaScript("""
                (function() {
                    var sel = window.getSelection();
                    if (!sel || sel.isCollapsed || !sel.rangeCount) return null;
                    var range = sel.getRangeAt(0);
                    var text = sel.toString().trim();
                    if (!text) return null;
                    var rect = range.getBoundingClientRect();
                    var preRange = document.createRange();
                    preRange.selectNodeContents(document.body);
                    preRange.setEnd(range.startContainer, range.startOffset);
                    var rangeStart = preRange.toString().length;
                    return {
                        text: text,
                        rangeStart: rangeStart,
                        rangeEnd: rangeStart + text.length,
                        rectX: rect.x, rectY: rect.y,
                        rectWidth: rect.width, rectHeight: rect.height,
                        spineHref: window.__dualSpine_spineHref || ''
                    };
                })()
                """) { [weak self] result, _ in
                guard let self,
                      let dict = result as? [String: Any],
                      let text = dict["text"] as? String,
                      !text.isEmpty else { return }

                let payload = EPUBBridgeMessage.SelectionPayload(
                    text: text,
                    rangeStart: dict["rangeStart"] as? Int ?? 0,
                    rangeEnd: dict["rangeEnd"] as? Int ?? 0,
                    rectX: dict["rectX"] as? Double ?? 0,
                    rectY: dict["rectY"] as? Double ?? 0,
                    rectWidth: dict["rectWidth"] as? Double ?? 0,
                    rectHeight: dict["rectHeight"] as? Double ?? 0,
                    spineHref: dict["spineHref"] as? String ?? ""
                )
                self.lastSelection = payload
                self.parent.onHighlightRequest?(payload, tintHex)
            }
        }

        /// Called from "Remove Highlight" in the native system edit menu.
        func handleRemoveHighlightMenuAction(highlightID: String) {
            parent.onRemoveHighlightRequest?(highlightID)
            if let webView {
                bridge.removeHighlight(id: highlightID, in: webView)
            }
        }

        func loadSpineItem(at index: Int) {
            lastSelection = nil  // Clear stale selection on navigation
            didAutoAdvance = false  // Reset auto-advance guard for new chapter

            guard let webView,
                  index >= 0,
                  index < parent.document.package.spine.count else { return }

            // In continuous scroll mode, if the chapter is already in the DOM,
            // just scroll to it — no page reload, no lag.
            if !parent.isPaginated && scrollToChapter(spineIndex: index, in: webView) {
                return
            }

            // Otherwise, reset injection set and reload the webview
            injectedSpineIndices.removeAll()

            let resolvedSpine = parent.document.package.resolvedSpine
            guard index < resolvedSpine.count else { return }

            let (_, manifestItem) = resolvedSpine[index]
            let href = manifestItem.href

            let archivePath = parent.document.contentBasePath + href
            guard let url = URL(string: "\(EPUBSchemeHandler.scheme)://book/\(archivePath)") else {
                return
            }

            currentSpineIndex = index
            bridge.setSpineHref(href, in: webView)
            webView.load(URLRequest(url: url))
        }

        private func handleBridgeMessage(_ message: EPUBBridgeMessage) {
            switch message {
            case .contentReady:
                if let css = currentThemeCSS, let webView {
                    bridge.applyTheme(css, in: webView)
                }
                if let webView {
                    let spineHighlights = parent.highlights.filter { $0.spineIndex == currentSpineIndex }
                    appliedHighlights = spineHighlights
                    let commands = spineHighlights.map { record in
                        EPUBBridgeController.HighlightCommand(
                            id: record.id.uuidString,
                            rangeStart: record.rangeStart,
                            rangeEnd: record.rangeEnd,
                            color: HighlightTint.cssColor(hex: record.tintHex)
                        )
                    }
                    if !commands.isEmpty {
                        bridge.applyHighlights(commands, in: webView)
                    }
                }
                if currentPaginated, let webView {
                    let mode = parent.paginationMode
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        self.bridge.enablePagination(mode: mode, in: webView)
                    }
                }
                // In scroll mode: enable continuous scroll (append next chapters inline)
                if !parent.isPaginated, let webView {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        self.enableContinuousScroll(in: webView)
                    }
                }
                // Always preload adjacent chapters into actor cache as a safety net
                preloadAdjacentChapters()

            case .selectionChanged(let payload):
                lastSelection = payload
                // Update highlight overlap state so the menu shows the right items
                webView?.checkSelectionHighlightOverlap()

            case .selectionCleared:
                // Don't clear lastSelection here — it's needed by the Highlight
                // menu action which fires after the selection UI dismisses.
                // lastSelection is cleared on spine navigation instead.
                webView?.selectionOverlapsHighlight = false
                webView?.overlappingHighlightID = nil

            case .highlightRequest(let payload):
                // JS dot strip: user tapped a color dot
                if let selection = lastSelection {
                    parent.onHighlightRequest?(selection, payload.tintHex)
                }

            case .removeHighlightRequest(let payload):
                parent.onRemoveHighlightRequest?(payload.highlightId)
                if let webView {
                    bridge.removeHighlight(id: payload.highlightId, in: webView)
                }

            case .linkTapped(let payload):
                if payload.isInternal {
                    handleInternalLink(payload.href)
                }

            case .paginationAtEnd:
                let nextIndex = currentSpineIndex + 1
                if nextIndex < parent.document.package.spine.count {
                    parent.spineIndex = nextIndex
                    loadSpineItem(at: nextIndex)
                }

            case .paginationAtStart:
                let prevIndex = currentSpineIndex - 1
                if prevIndex >= 0 {
                    parent.spineIndex = prevIndex
                    loadSpineItem(at: prevIndex)
                }

            case .progressUpdated:
                // In continuous scroll mode, scroll-to-end is handled by
                // requestNextChapter message (appended inline, no page reload).
                break

            case .requestNextChapter(let payload):
                // JS wants more content — load next 3 chapters in parallel
                guard let webView else { return }
                let total = parent.document.package.resolvedSpine.count
                for offset in 1...3 {
                    let idx = payload.afterSpineIndex + offset
                    guard idx < total else { break }
                    appendContinuousChapter(spineIndex: idx, in: webView)
                }

            case .requestPrevChapter(let payload):
                // JS wants previous content — prepend prev 3 in parallel
                guard let webView else { return }
                for offset in 1...3 {
                    let idx = payload.beforeSpineIndex - offset
                    guard idx >= 0 else { break }
                    prependContinuousChapter(spineIndex: idx, in: webView)
                }

            case .continuousChapterChanged(let payload):
                // Current chapter changed based on scroll position. Update
                // currentSpineIndex FIRST so updateUIView's diff suppresses reload.
                currentSpineIndex = payload.spineIndex
                if parent.spineIndex != payload.spineIndex {
                    parent.spineIndex = payload.spineIndex
                }

            default:
                break
            }

            parent.onMessage?(message)
        }

        private func handleInternalLink(_ href: String) {
            let parts = href.split(separator: "#", maxSplits: 1)
            let filePart = String(parts.first ?? "")
            let fragment = parts.count > 1 ? String(parts[1]) : nil

            let resolvedSpine = parent.document.package.resolvedSpine
            for (i, (_, manifest)) in resolvedSpine.enumerated() {
                if manifest.href == filePart || manifest.href.hasSuffix(filePart) {
                    if i != currentSpineIndex {
                        parent.spineIndex = i
                        loadSpineItem(at: i)
                    }
                    if let fragment, let webView {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            self.bridge.scrollToFragment(fragment, in: webView)
                        }
                    }
                    return
                }
            }
        }

        // MARK: - WKNavigationDelegate

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if url.scheme == EPUBSchemeHandler.scheme || url.scheme == "about" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
#endif
