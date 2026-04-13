import Foundation
import WebKit
import DualSpineCore

/// Manages the JavaScript bridge between WKWebView and the EPUB content.
/// Handles message routing, theme injection, highlight commands, and navigation.
@MainActor
public final class EPUBBridgeController: NSObject, WKScriptMessageHandler {

    /// Callback for bridge messages from the EPUB content.
    public var onMessage: ((EPUBBridgeMessage) -> Void)?

    /// The message handler name registered in WKWebView configuration.
    nonisolated public static let handlerName = "dualSpine"

    // MARK: - Configuration

    /// Register this bridge with a WKWebView configuration before creating the web view.
    public func register(in configuration: WKWebViewConfiguration) {
        let userContentController = configuration.userContentController

        // Register message handler
        userContentController.add(self, name: Self.handlerName)

        // Inject the bridge JavaScript
        if let bridgeJS = Self.loadBridgeScript() {
            let script = WKUserScript(
                source: bridgeJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            userContentController.addUserScript(script)
        }
    }

    /// Unregister the bridge (call on deinit or when closing the reader).
    public func unregister(from configuration: WKWebViewConfiguration) {
        configuration.userContentController.removeScriptMessageHandler(forName: Self.handlerName)
        configuration.userContentController.removeAllUserScripts()
    }

    // MARK: - WKScriptMessageHandler

    nonisolated public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let handlerName = Self.handlerName
        MainActor.assumeIsolated {
            guard message.name == handlerName else { return }

            if let bridgeMessage = EPUBBridgeMessage.parse(from: message.body) {
                self.onMessage?(bridgeMessage)
            }
        }
    }

    // MARK: - Commands (Swift → JavaScript)

    /// Apply a CSS theme to the EPUB content.
    public func applyTheme(_ css: String, in webView: WKWebView) {
        let escapedCSS = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        webView.evaluateJavaScript("window.__dualSpine_applyTheme('\(escapedCSS)')")
    }

    /// Set a CSS custom property on the document root.
    public func setCSSVariable(_ name: String, value: String, in webView: WKWebView) {
        webView.evaluateJavaScript("window.__dualSpine_setCSSVar('\(name)', '\(value)')")
    }

    /// Apply highlight overlays to the content.
    public func applyHighlights(_ highlights: [HighlightCommand], in webView: WKWebView) {
        guard let data = try? JSONEncoder().encode(highlights),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__dualSpine_applyHighlights(\(json))")
    }

    /// Remove a specific highlight by ID.
    public func removeHighlight(id: String, in webView: WKWebView) {
        webView.evaluateJavaScript("window.__dualSpine_removeHighlight('\(id)')")
    }

    /// Scroll to a character offset in the document.
    public func scrollToOffset(_ offset: Int, in webView: WKWebView) {
        webView.evaluateJavaScript("window.__dualSpine_scrollToOffset(\(offset))")
    }

    /// Scroll to a DOM element by its fragment identifier.
    public func scrollToFragment(_ fragmentID: String, in webView: WKWebView) {
        webView.evaluateJavaScript("window.__dualSpine_scrollToFragment('\(fragmentID)')")
    }

    /// Set the current spine href for selection tracking context.
    public func setSpineHref(_ href: String, in webView: WKWebView) {
        webView.evaluateJavaScript("window.__dualSpine_spineHref = '\(href)'")
    }

    // MARK: - Types

    public struct HighlightCommand: Codable, Sendable {
        public let id: String
        public let rangeStart: Int
        public let rangeEnd: Int
        public let color: String

        public init(id: String, rangeStart: Int, rangeEnd: Int, color: String) {
            self.id = id
            self.rangeStart = rangeStart
            self.rangeEnd = rangeEnd
            self.color = color
        }
    }

    // MARK: - Private

    private static func loadBridgeScript() -> String? {
        guard let url = Bundle.module.url(forResource: "epub-bridge", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("[DualSpine] Failed to load epub-bridge.js from bundle")
            return nil
        }
        return script
    }
}
