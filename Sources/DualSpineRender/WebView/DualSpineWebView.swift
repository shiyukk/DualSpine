#if canImport(UIKit)
import UIKit
import WebKit

/// WKWebView subclass that adds "Highlight" and "Remove Highlight" to the
/// native system edit menu. These appear in the expanded menu after tapping `>`:
///
///   Copy | Look Up | Translate | Search Web | Share... | **Highlight** | **Remove Highlight**
@MainActor
public final class DualSpineWebView: WKWebView {

    /// Called when the user taps "Highlight" in the expanded system menu.
    public var onHighlightAction: (() -> Void)?

    /// Called when the user taps "Remove Highlight". Passes the highlight ID.
    public var onRemoveHighlight: ((String) -> Void)?

    /// Whether the current selection overlaps an existing highlight.
    public var selectionOverlapsHighlight: Bool = false

    /// The highlight ID that the selection overlaps with (if any).
    public var overlappingHighlightID: String?

    // MARK: - Menu Integration

    override public func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(highlightSelection(_:)) {
            // Show "Highlight" only when text is selected and NOT on existing highlight
            let hasSel = selectedTextLength > 0
            return hasSel && !selectionOverlapsHighlight
        }
        if action == #selector(removeHighlight(_:)) {
            // Show "Remove Highlight" only when on existing highlight
            return selectionOverlapsHighlight
        }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc private func highlightSelection(_ sender: Any?) {
        onHighlightAction?()
    }

    @objc private func removeHighlight(_ sender: Any?) {
        if let id = overlappingHighlightID {
            onRemoveHighlight?(id)
        }
    }

    /// Register the custom menu items. Call once after creating the web view.
    public func registerMenuItems() {
        UIMenuController.shared.menuItems = [
            UIMenuItem(title: "Highlight", action: #selector(highlightSelection(_:))),
            UIMenuItem(title: "Remove Highlight", action: #selector(removeHighlight(_:))),
        ]
    }

    /// Update highlight overlap state from JS. Call when selection changes.
    public func checkSelectionHighlightOverlap() {
        evaluateJavaScript("window.__dualSpine_getSelectionHighlightId()") { [weak self] result, _ in
            Task { @MainActor in
                if let id = result as? String, !id.isEmpty {
                    self?.selectionOverlapsHighlight = true
                    self?.overlappingHighlightID = id
                } else {
                    self?.selectionOverlapsHighlight = false
                    self?.overlappingHighlightID = nil
                }
            }
        }
    }

    // MARK: - Private

    /// Quick check if there's selected text (avoids async JS call for canPerformAction).
    private var selectedTextLength: Int {
        // WKWebView doesn't expose selection directly, but canPerformAction
        // is only called when the system detects a selection, so return 1.
        return 1
    }
}
#endif
