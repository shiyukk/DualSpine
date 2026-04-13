#if canImport(UIKit)
import SwiftUI
import UIKit
import WebKit
import DualSpineCore

/// The primary EPUB rendering surface. A SwiftUI wrapper around WKWebView
/// that uses `EPUBSchemeHandler` to serve content directly from the ZIP archive.
///
/// Usage:
/// ```swift
/// EPUBReaderView(
///     document: epubDocument,
///     resourceActor: resourceActor,
///     spineIndex: $currentSpineIndex,
///     onMessage: { message in /* handle bridge messages */ }
/// )
/// ```
@MainActor
public struct EPUBReaderView: UIViewRepresentable {
    let document: EPUBDocument
    let resourceActor: EPUBResourceActor
    @Binding var spineIndex: Int
    var themeCSS: String?
    var isPaginated: Bool
    var onMessage: ((EPUBBridgeMessage) -> Void)?

    public init(
        document: EPUBDocument,
        resourceActor: EPUBResourceActor,
        spineIndex: Binding<Int>,
        themeCSS: String? = nil,
        isPaginated: Bool = false,
        onMessage: ((EPUBBridgeMessage) -> Void)? = nil
    ) {
        self.document = document
        self.resourceActor = resourceActor
        self._spineIndex = spineIndex
        self.themeCSS = themeCSS
        self.isPaginated = isPaginated
        self.onMessage = onMessage
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Register the custom scheme handler
        let schemeHandler = EPUBSchemeHandler(
            resourceActor: resourceActor,
            contentBasePath: document.contentBasePath
        )
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: EPUBSchemeHandler.scheme)

        // Register the JS bridge
        context.coordinator.bridge.register(in: configuration)

        // Configure web view
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator

        // Disable zoom (EPUB content should be styled, not user-zoomed)
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.bouncesZoom = false

        // Store reference for updates
        context.coordinator.webView = webView
        context.coordinator.schemeHandler = schemeHandler

        // Load the first spine item
        context.coordinator.loadSpineItem(at: spineIndex)

        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator

        // Navigate to a different spine item if the index changed
        if coordinator.currentSpineIndex != spineIndex {
            coordinator.loadSpineItem(at: spineIndex)
        }

        // Update theme if changed
        if let css = themeCSS, css != coordinator.currentThemeCSS {
            coordinator.currentThemeCSS = css
            coordinator.bridge.applyTheme(css, in: webView)
        }

        // Toggle pagination mode
        if isPaginated != coordinator.currentPaginated {
            coordinator.currentPaginated = isPaginated
            if isPaginated {
                coordinator.bridge.enablePagination(in: webView)
            } else {
                coordinator.bridge.disablePagination(in: webView)
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: EPUBReaderView
        let bridge = EPUBBridgeController()
        weak var webView: WKWebView?
        var schemeHandler: EPUBSchemeHandler?
        var currentSpineIndex: Int = -1
        var currentThemeCSS: String?
        var currentPaginated: Bool = false

        init(parent: EPUBReaderView) {
            self.parent = parent
            super.init()

            bridge.onMessage = { [weak self] message in
                self?.handleBridgeMessage(message)
            }
        }

        func loadSpineItem(at index: Int) {
            guard let webView,
                  index >= 0,
                  index < parent.document.package.spine.count else { return }

            let resolvedSpine = parent.document.package.resolvedSpine
            guard index < resolvedSpine.count else { return }

            let (_, manifestItem) = resolvedSpine[index]
            let href = manifestItem.href

            // Build the epub-content:// URL
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
                // Apply pagination after theme
                if currentPaginated, let webView {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        self.bridge.enablePagination(in: webView)
                    }
                }

            case .linkTapped(let payload):
                if payload.isInternal {
                    handleInternalLink(payload.href)
                }

            case .paginationAtEnd:
                // Auto-advance to next spine item
                let nextIndex = currentSpineIndex + 1
                if nextIndex < parent.document.package.spine.count {
                    parent.spineIndex = nextIndex
                    loadSpineItem(at: nextIndex)
                }

            case .paginationAtStart:
                // Auto-advance to previous spine item (land on last page)
                let prevIndex = currentSpineIndex - 1
                if prevIndex >= 0 {
                    parent.spineIndex = prevIndex
                    loadSpineItem(at: prevIndex)
                    // TODO: navigate to last page of previous spine item after load
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
