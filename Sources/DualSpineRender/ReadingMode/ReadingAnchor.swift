import Foundation

/// A stable position within the EPUB reading surface.
///
/// Anchors are resolvable across mode changes (scroll ↔ paginated) and across
/// chapter window shifts. They identify a logical point in the content, not a
/// numeric scroll offset (which is layout-dependent and breaks under font or
/// mode changes).
///
/// ### Identification strategy
///
/// The JS layer resolves an anchor in priority order:
///
/// 1. `elementID` — if the anchor pins to an element with a stable ID (e.g.
///    a fragment target from a TOC link or an `<article>` container), use
///    `getElementById`.
/// 2. `characterOffset` — character offset into the spine item's text content.
///    Stable across layout changes within the same chapter.
/// 3. `progress` — fractional progress `0...1` through the spine item. Used
///    only when neither ID nor character offset is available.
public struct ReadingAnchor: Codable, Sendable, Hashable {
    /// Zero-based spine item index.
    public let spineIndex: Int

    /// Optional DOM element ID to scroll to (fragment identifier).
    public let elementID: String?

    /// Character offset into the spine item's text content.
    public let characterOffset: Int?

    /// Fractional progress `0.0 ... 1.0` through the spine item.
    public let progress: Double?

    public init(
        spineIndex: Int,
        elementID: String? = nil,
        characterOffset: Int? = nil,
        progress: Double? = nil
    ) {
        self.spineIndex = spineIndex
        self.elementID = elementID
        self.characterOffset = characterOffset
        self.progress = progress
    }

    /// Anchor to the start of a spine item.
    public static func startOfSpine(_ index: Int) -> ReadingAnchor {
        ReadingAnchor(spineIndex: index, progress: 0)
    }
}
