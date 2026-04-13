import Foundation

/// A persistent highlight record with stable anchoring.
///
/// Uses a three-part anchor strategy for re-identification:
/// 1. `rangeStart`/`rangeEnd` character offsets (fast, but fragile to content changes)
/// 2. `selectedText` exact match (reliable, but may have duplicates)
/// 3. `textBefore`/`textAfter` context (disambiguates duplicates)
///
/// On restore, try offset-based lookup first; if the text at that offset doesn't
/// match `selectedText`, fall back to context-based fuzzy search.
public struct HighlightRecord: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID

    /// Zero-based spine item index.
    public let spineIndex: Int

    /// Spine item href for validation.
    public let spineHref: String

    /// The exact highlighted text.
    public let selectedText: String

    /// ~50 characters of text immediately before the selection (for re-identification).
    public let textBefore: String

    /// ~50 characters of text immediately after the selection (for re-identification).
    public let textAfter: String

    /// Character offset from the start of the spine item's text content.
    public let rangeStart: Int

    /// Character offset of the end of the selection.
    public let rangeEnd: Int

    /// Highlight color as hex (e.g. `"#F7C948"`).
    public let tintHex: String

    /// Optional user note attached to the highlight.
    public let note: String?

    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        spineIndex: Int,
        spineHref: String,
        selectedText: String,
        textBefore: String = "",
        textAfter: String = "",
        rangeStart: Int,
        rangeEnd: Int,
        tintHex: String = HighlightTint.defaultHex,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.spineIndex = spineIndex
        self.spineHref = spineHref
        self.selectedText = selectedText
        self.textBefore = textBefore
        self.textAfter = textAfter
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.tintHex = tintHex
        self.note = note
        self.createdAt = createdAt
    }
}

// MARK: - Highlight Colors

/// Standard highlight tint palette matching ReBabel's existing colors.
public enum HighlightTint: Sendable {
    public static let defaultHex = "#F7C948"

    public static let palette: [(name: String, hex: String)] = [
        ("Amber", "#F7C948"),
        ("Coral", "#FF8A65"),
        ("Teal", "#4DB6AC"),
        ("Blue", "#64B5F6"),
        ("Purple", "#BA68C8"),
    ]

    /// CSS rgba color with alpha for overlay rendering.
    public static func cssColor(hex: String, alpha: Double = 0.45) -> String {
        guard hex.count >= 7, hex.hasPrefix("#") else {
            return "rgba(247, 201, 72, \(alpha))"
        }
        let r = Int(hex.dropFirst().prefix(2), radix: 16) ?? 247
        let g = Int(hex.dropFirst(3).prefix(2), radix: 16) ?? 201
        let b = Int(hex.dropFirst(5).prefix(2), radix: 16) ?? 72
        return "rgba(\(r), \(g), \(b), \(alpha))"
    }
}
