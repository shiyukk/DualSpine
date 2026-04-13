#if canImport(UIKit)
import UIKit
import WebKit

/// WKWebView subclass that injects "Highlight" and "Remove" into the native
/// text selection edit menu (the horizontal callout bar).
///
/// Color selection is handled separately by the JS dot strip below the selection.
/// The system menu provides "Highlight" (default color) and "Remove" (for existing highlights).
@MainActor
public final class DualSpineWebView: WKWebView {

    /// Called when the user taps "Highlight" in the system callout.
    public var onHighlightAction: (() -> Void)?

    /// Called when the user taps "Remove" in the system callout. Passes highlight ID.
    public var onRemoveHighlight: ((String) -> Void)?

    /// Whether the current selection overlaps an existing highlight.
    public var selectionOverlapsHighlight: Bool = false

    /// The highlight ID that the selection overlaps with (if any).
    public var overlappingHighlightID: String?

    // MARK: - Menu Integration

    override public func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(highlightSelection(_:)) {
            return !selectionOverlapsHighlight
        }
        if action == #selector(removeHighlight(_:)) {
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
            UIMenuItem(title: "Remove", action: #selector(removeHighlight(_:))),
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
}
#endif
