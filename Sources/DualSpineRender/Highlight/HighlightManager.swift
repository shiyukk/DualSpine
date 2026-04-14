#if canImport(UIKit)
import Foundation
import DualSpineCore

/// Manages highlight state for an active reader session.
/// Bridges between persisted ``HighlightRecord`` storage and the new
/// ``ReadingModeController`` rendering layer.
@MainActor
public final class HighlightManager {
    private weak var controller: ReadingModeController?

    /// All highlights for the current book (caller manages persistence).
    public private(set) var highlights: [HighlightRecord] = []

    /// The spine index currently being displayed.
    public private(set) var currentSpineIndex: Int = -1

    public init(controller: ReadingModeController) {
        self.controller = controller
    }

    /// Load highlights from persisted storage (call once on reader open).
    public func loadHighlights(_ records: [HighlightRecord]) {
        self.highlights = records
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
        textBefore: String = "",
        textAfter: String = "",
        tintHex: String = HighlightTint.defaultHex
    ) -> HighlightRecord {
        let record = HighlightRecord(
            spineIndex: currentSpineIndex,
            spineHref: selection.spineHref,
            selectedText: selection.text,
            textBefore: textBefore,
            textAfter: textAfter,
            rangeStart: selection.rangeStart,
            rangeEnd: selection.rangeEnd,
            tintHex: tintHex
        )
        highlights.append(record)
        applyHighlightsForCurrentSpine()
        return record
    }

    /// Remove a highlight by ID.
    @discardableResult
    public func removeHighlight(id: UUID) -> HighlightRecord? {
        guard let index = highlights.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = highlights.remove(at: index)
        let controller = self.controller
        Task { await controller?.removeHighlight(id: id.uuidString) }
        return removed
    }

    /// Re-apply highlights for the current spine item.
    public func applyHighlightsForCurrentSpine() {
        let spineHighlights = highlights.filter { $0.spineIndex == currentSpineIndex }
        let commands = spineHighlights.map { record in
            ReaderCommand.HighlightCommand(
                id: record.id.uuidString,
                spineIndex: record.spineIndex,
                rangeStart: record.rangeStart,
                rangeEnd: record.rangeEnd,
                color: HighlightTint.cssColor(hex: record.tintHex)
            )
        }
        let controller = self.controller
        Task { await controller?.applyHighlights(commands) }
    }

    /// Get all highlights for a specific spine index.
    public func highlights(forSpine index: Int) -> [HighlightRecord] {
        highlights.filter { $0.spineIndex == index }
    }
}
#endif
