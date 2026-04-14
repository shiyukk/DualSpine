#if canImport(UIKit)
import Foundation
import WebKit

/// Dedicated `WKScriptMessageHandler` for typed `ReaderEvent` messages from
/// the JS reader controller. Kept separate from the legacy highlight/selection
/// bridge so the event channel has its own parser and cannot be confused with
/// older message shapes.
@MainActor
final class ReaderEventBridge: NSObject, WKScriptMessageHandler {
    /// Channel name registered on `WKUserContentController`. The JS side
    /// posts via `window.webkit.messageHandlers.dualSpineReader.postMessage(...)`.
    nonisolated static let handlerName = "dualSpineReader"

    /// Called on the main actor whenever a typed event arrives.
    var onEvent: ((ReaderEvent) -> Void)?

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated {
            guard message.name == Self.handlerName else { return }
            if let event = ReaderEvent.parse(from: message.body) {
                self.onEvent?(event)
            }
        }
    }
}
#endif
