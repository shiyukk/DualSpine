import Foundation
import WebKit
import DualSpineCore

/// Manages highlight state for an active reader session.
/// Bridges between persisted `HighlightRecord` storage and the JS rendering layer.
@MainActor
public final class HighlightManager {
    private let bridge: EPUBBridgeController
    private weak var webView: WKWebView?

    /// All highlights for the current book (caller manages persistence).
    public private(set) var highlights: [HighlightRecord] = []

    /// The spine index currently being displayed.
    public private(set) var currentSpineIndex: Int = -1

    public init(bridge: EPUBBridgeController) {
        self.bridge = bridge
    }

    /// Load highlights from persisted storage (call once on reader open).
    public func loadHighlights(_ records: [HighlightRecord]) {
        self.highlights = records
    }

    /// Set the active WebView reference (call from coordinator).
    public func setWebView(_ webView: WKWebView) {
        self.webView = webView
    }

    /// Called when the reader navigates to a new spine item.
    /// Applies all highlights belonging to this spine item.
    public func didNavigateToSpine(index: Int) {
        currentSpineIndex = index
        applyHighlightsForCurrentSpine()
    }

    /// Create a new highlight from a selection event.
    /// Returns the created record for persistence.
    public func createHighlight(
        from selection: EPUBBridgeMessage.SelectionPayload,
        context: EPUBBridgeController.SelectionContext?,
        tintHex: String = HighlightTint.defaultHex
    ) -> HighlightRecord {
        let record = HighlightRecord(
            spineIndex: currentSpineIndex,
            spineHref: selection.spineHref,
            selectedText: selection.text,
            textBefore: context?.textBefore ?? "",
            textAfter: context?.textAfter ?? "",
            rangeStart: context?.rangeStart ?? selection.rangeStart,
            rangeEnd: context?.rangeEnd ?? selection.rangeEnd,
            tintHex: tintHex
        )

        highlights.append(record)
        applyHighlightsForCurrentSpine()
        return record
    }

    /// Remove a highlight by ID.
    /// Returns the removed record (for persistence sync), or nil if not found.
    @discardableResult
    public func removeHighlight(id: UUID) -> HighlightRecord? {
        guard let index = highlights.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = highlights.remove(at: index)

        if let webView {
            bridge.removeHighlight(id: id.uuidString, in: webView)
        }

        return removed
    }

    /// Re-apply highlights for the current spine item.
    public func applyHighlightsForCurrentSpine() {
        guard let webView else { return }

        let spineHighlights = highlights.filter { $0.spineIndex == currentSpineIndex }

        let commands = spineHighlights.map { record in
            EPUBBridgeController.HighlightCommand(
                id: record.id.uuidString,
                rangeStart: record.rangeStart,
                rangeEnd: record.rangeEnd,
                color: HighlightTint.cssColor(hex: record.tintHex)
            )
        }

        bridge.applyHighlights(commands, in: webView)
    }

    /// Get all highlights for a specific spine index.
    public func highlights(forSpine index: Int) -> [HighlightRecord] {
        highlights.filter { $0.spineIndex == index }
    }
}
