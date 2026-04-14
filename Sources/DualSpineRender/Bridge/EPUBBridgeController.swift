#if canImport(UIKit)
import Foundation
import WebKit
import DualSpineCore

/// Registers the JS reader controller script and the typed event handler
/// on a `WKWebViewConfiguration`. All command dispatch now flows through
/// ``ReadingModeController``; this type exists only to wire up the web view.
@MainActor
public final class EPUBBridgeController: NSObject {

    /// The dedicated event bridge for the new typed channel.
    let eventBridge = ReaderEventBridge()

    /// Forwarded from the event bridge for convenience.
    var onEvent: ((ReaderEvent) -> Void)? {
        get { eventBridge.onEvent }
        set { eventBridge.onEvent = newValue }
    }

    /// Register the reader controller script and event handler in a web view
    /// configuration. Call once, before creating the web view.
    public func register(in configuration: WKWebViewConfiguration) {
        let userContentController = configuration.userContentController
        userContentController.add(eventBridge, name: ReaderEventBridge.handlerName)

        if let script = Self.loadScript() {
            let userScript = WKUserScript(
                source: script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            userContentController.addUserScript(userScript)
        }
    }

    /// Remove registered scripts and handlers. Call when tearing down.
    public func unregister(from configuration: WKWebViewConfiguration) {
        let userContentController = configuration.userContentController
        userContentController.removeScriptMessageHandler(forName: ReaderEventBridge.handlerName)
        userContentController.removeAllUserScripts()
    }

    // MARK: - Private

    private static func loadScript() -> String? {
        guard let url = Bundle.module.url(forResource: "reader-controller", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("[DualSpine] Failed to load reader-controller.js from bundle")
            return nil
        }
        return source
    }
}
#endif
