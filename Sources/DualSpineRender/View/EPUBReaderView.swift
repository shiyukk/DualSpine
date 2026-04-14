#if canImport(UIKit)
import SwiftUI
import UIKit
import WebKit
import DualSpineCore

/// The primary EPUB rendering surface — a SwiftUI wrapper around `WKWebView`
/// that delegates all reading-mode logic to ``ReadingModeController``.
///
/// The public API is intentionally stable. Host applications see the same
/// bindings and callbacks as before; all architectural churn is encapsulated
/// behind ``ReadingModeController`` and the typed bridge.
@MainActor
public struct EPUBReaderView: UIViewRepresentable {
    let document: EPUBDocument
    let resourceActor: EPUBResourceActor
    @Binding var spineIndex: Int
    var themeCSS: String?
    var isPaginated: Bool
    /// Pagination transition mode: `"slide"` or `"fade"`.
    var paginationMode: String
    var highlights: [HighlightRecord]
    var onMessage: ((EPUBBridgeMessage) -> Void)?
    var onHighlightRequest: ((_ selection: EPUBBridgeMessage.SelectionPayload, _ tintHex: String) -> Void)?
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

        webView.registerMenuItems()

        let coordinator = context.coordinator
        webView.onHighlightAction = { [weak coordinator] in
            coordinator?.showColorPicker()
        }
        webView.onRemoveHighlight = { [weak coordinator] highlightID in
            coordinator?.handleRemoveHighlightMenuAction(highlightID: highlightID)
        }

        coordinator.attach(webView: webView, schemeHandler: schemeHandler)
        coordinator.loadInitialSpine(at: spineIndex)

        return webView
    }

    public func updateUIView(_ webView: DualSpineWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if coordinator.currentSpineIndex != spineIndex {
            coordinator.navigateToSpine(index: spineIndex)
        }

        if let css = themeCSS, css != coordinator.currentThemeCSS {
            coordinator.currentThemeCSS = css
            coordinator.applyTheme(css)
        }

        let desiredMode = ReadingModeController.Mode.from(
            isPaginated: isPaginated,
            paginationMode: paginationMode
        )
        if desiredMode != coordinator.currentMode {
            coordinator.currentMode = desiredMode
            coordinator.transitionMode(to: desiredMode)
        }

        let spineHighlights = highlights.filter { $0.spineIndex == coordinator.currentSpineIndex }
        if spineHighlights != coordinator.appliedHighlights {
            coordinator.appliedHighlights = spineHighlights
            coordinator.applyHighlights(allHighlights: highlights)
        }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: EPUBReaderView
        let bridge = EPUBBridgeController()
        private(set) weak var webView: DualSpineWebView?
        private(set) var schemeHandler: EPUBSchemeHandler?

        let chapterCache: ChapterCache
        let readingController: ReadingModeController

        var currentSpineIndex: Int = -1
        var currentSpineHref: String = ""
        var currentThemeCSS: String?
        var currentMode: ReadingModeController.Mode = .scroll
        var appliedHighlights: [HighlightRecord] = []
        var lastSelection: EPUBBridgeMessage.SelectionPayload?
        var lastSelectionHighlightID: String?

        init(parent: EPUBReaderView) {
            self.parent = parent
            self.chapterCache = ChapterCache(
                document: parent.document,
                resourceActor: parent.resourceActor
            )
            self.readingController = ReadingModeController(
                document: parent.document,
                chapterCache: chapterCache,
                initialMode: ReadingModeController.Mode.from(
                    isPaginated: parent.isPaginated,
                    paginationMode: parent.paginationMode
                ),
                initialSpineIndex: max(0, parent.spineIndex)
            )
            super.init()

            bridge.onEvent = { [weak self] event in
                self?.dispatchEvent(event)
            }

            Task.detached(priority: .utility) { [chapterCache] in
                await chapterCache.preloadAll()
            }

            Task { [readingController] in
                await readingController.setEventObserver { [weak self] event in
                    self?.handleControllerEvent(event)
                }
                await readingController.setSpineObserver { [weak self] index in
                    self?.handleSpineChanged(index)
                }
            }
        }

        func attach(webView: DualSpineWebView, schemeHandler: EPUBSchemeHandler) {
            self.webView = webView
            self.schemeHandler = schemeHandler
            let controller = readingController
            Task { await controller.attach(webView: webView) }
        }

        // MARK: - Navigation

        func loadInitialSpine(at index: Int) {
            guard let webView else { return }
            let resolvedSpine = parent.document.package.resolvedSpine
            guard index >= 0, index < resolvedSpine.count else { return }

            currentSpineIndex = index
            currentSpineHref = resolvedSpine[index].manifest.href

            let archivePath = parent.document.contentBasePath + currentSpineHref
            guard let url = URL(string: "\(EPUBSchemeHandler.scheme)://book/\(archivePath)") else { return }
            webView.load(URLRequest(url: url))

            let anchor = ReadingAnchor.startOfSpine(index)
            let controller = readingController
            Task { await controller.start(anchor: anchor) }
        }

        func navigateToSpine(index: Int) {
            let resolvedSpine = parent.document.package.resolvedSpine
            guard index >= 0, index < resolvedSpine.count else { return }
            currentSpineIndex = index
            currentSpineHref = resolvedSpine[index].manifest.href
            let anchor = ReadingAnchor.startOfSpine(index)
            let controller = readingController
            Task { await controller.navigate(to: anchor) }
        }

        func transitionMode(to mode: ReadingModeController.Mode) {
            let anchor = ReadingAnchor.startOfSpine(currentSpineIndex)
            let controller = readingController
            Task { await controller.transition(to: mode, anchor: anchor) }
        }

        func applyTheme(_ css: String) {
            let controller = readingController
            Task { await controller.applyTheme(css: css) }
        }

        func applyHighlights(allHighlights: [HighlightRecord]) {
            let state = Task { [readingController] in
                await readingController.currentState()
            }
            Task {
                let currentState = await state.value
                let mounted = Set(currentState.mountedWindow)
                let commands = allHighlights
                    .filter { mounted.contains($0.spineIndex) }
                    .map { record in
                        ReaderCommand.HighlightCommand(
                            id: record.id.uuidString,
                            spineIndex: record.spineIndex,
                            rangeStart: record.rangeStart,
                            rangeEnd: record.rangeEnd,
                            color: HighlightTint.cssColor(hex: record.tintHex)
                        )
                    }
                await readingController.applyHighlights(commands)
            }
        }

        // MARK: - Highlight picker

        func showColorPicker() {
            let controller = readingController
            Task { await controller.showHighlightPicker() }
        }

        func handleRemoveHighlightMenuAction(highlightID: String) {
            parent.onRemoveHighlightRequest?(highlightID)
            let controller = readingController
            Task { await controller.removeHighlight(id: highlightID) }
        }

        // MARK: - Event handling

        private func dispatchEvent(_ event: ReaderEvent) {
            let controller = readingController
            Task { await controller.handle(event: event) }
        }

        private func handleControllerEvent(_ event: ReaderEvent) {
            switch event {
            case .ready:
                if let css = currentThemeCSS {
                    applyTheme(css)
                }
                applyHighlights(allHighlights: parent.highlights)

            case let .selectionChanged(payload):
                let projected = EPUBBridgeMessage.SelectionPayload(
                    text: payload.text,
                    rangeStart: payload.rangeStart,
                    rangeEnd: payload.rangeEnd,
                    rectX: payload.rectX,
                    rectY: payload.rectY,
                    rectWidth: payload.rectWidth,
                    rectHeight: payload.rectHeight,
                    spineHref: payload.spineHref.isEmpty ? currentSpineHref : payload.spineHref
                )
                lastSelection = projected
                lastSelectionHighlightID = payload.highlightID.isEmpty ? nil : payload.highlightID
                webView?.selectionOverlapsHighlight = !payload.highlightID.isEmpty
                webView?.overlappingHighlightID = lastSelectionHighlightID

            case .selectionCleared:
                webView?.selectionOverlapsHighlight = false
                webView?.overlappingHighlightID = nil

            case let .highlightRequested(payload, tintHex):
                let projected = EPUBBridgeMessage.SelectionPayload(
                    text: payload.text,
                    rangeStart: payload.rangeStart,
                    rangeEnd: payload.rangeEnd,
                    rectX: payload.rectX,
                    rectY: payload.rectY,
                    rectWidth: payload.rectWidth,
                    rectHeight: payload.rectHeight,
                    spineHref: payload.spineHref.isEmpty ? currentSpineHref : payload.spineHref
                )
                parent.onHighlightRequest?(projected, tintHex)

            case let .removeHighlightRequested(highlightID):
                parent.onRemoveHighlightRequest?(highlightID)

            case let .linkTapped(href, isInternal):
                if isInternal { handleInternalLink(href) }

            default:
                break
            }

            if let message = EPUBBridgeMessage.from(event: event, currentSpineHref: currentSpineHref) {
                parent.onMessage?(message)
            }
        }

        private func handleSpineChanged(_ index: Int) {
            currentSpineIndex = index
            if let resolved = parent.document.package.resolvedSpine[safe: index] {
                currentSpineHref = resolved.manifest.href
            }
            if parent.spineIndex != index {
                parent.spineIndex = index
            }
        }

        private func handleInternalLink(_ href: String) {
            let parts = href.split(separator: "#", maxSplits: 1)
            let filePart = String(parts.first ?? "")
            let fragment = parts.count > 1 ? String(parts[1]) : nil

            let resolvedSpine = parent.document.package.resolvedSpine
            for (i, pair) in resolvedSpine.enumerated() {
                if pair.manifest.href == filePart
                    || pair.manifest.href.hasSuffix(filePart)
                    || filePart.hasSuffix(pair.manifest.href) {
                    let anchor = ReadingAnchor(spineIndex: i, elementID: fragment)
                    let controller = readingController
                    Task { await controller.navigate(to: anchor) }
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

// MARK: - Collection safe subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#endif
