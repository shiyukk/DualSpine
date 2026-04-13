import Foundation

/// A transparent, debuggable reading position — replaces Readium's opaque locator JSON.
///
/// Encodes everything needed to restore the reader to an exact position:
/// spine item + scroll progress + optional character offset for precision.
public struct ReadingPosition: Codable, Sendable, Hashable {
    /// Zero-based index of the spine item.
    public let spineIndex: Int

    /// The spine item href (e.g. `"chapter3.xhtml"`), for validation after re-parse.
    public let spineHref: String

    /// 0.0–1.0 scroll progress within the current spine item.
    public let chapterProgress: Double

    /// 0.0–1.0 progress through the entire book (computed from spine position + chapter progress).
    public let overallProgress: Double

    /// Character offset from the start of the spine item's text content.
    /// Used for precise restoration; falls back to `chapterProgress` if unavailable.
    public let characterOffset: Int?

    /// When this position was recorded.
    public let timestamp: Date

    public init(
        spineIndex: Int,
        spineHref: String,
        chapterProgress: Double,
        overallProgress: Double,
        characterOffset: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.spineIndex = spineIndex
        self.spineHref = spineHref
        self.chapterProgress = min(max(chapterProgress, 0), 1)
        self.overallProgress = min(max(overallProgress, 0), 1)
        self.characterOffset = characterOffset
        self.timestamp = timestamp
    }

    /// Compute overall progress from spine position.
    /// - Parameters:
    ///   - spineIndex: Current spine index.
    ///   - chapterProgress: Progress within current chapter.
    ///   - totalSpineItems: Total number of spine items in the book.
    public static func computeOverallProgress(
        spineIndex: Int,
        chapterProgress: Double,
        totalSpineItems: Int
    ) -> Double {
        guard totalSpineItems > 0 else { return 0 }
        let baseProgress = Double(spineIndex) / Double(totalSpineItems)
        let chapterContribution = chapterProgress / Double(totalSpineItems)
        return min(baseProgress + chapterContribution, 1.0)
    }

    /// A short human-readable summary (e.g. "Ch 5 · 42%").
    public var displaySummary: String {
        let pct = Int(overallProgress * 100)
        return "Ch \(spineIndex + 1) · \(pct)%"
    }
}
