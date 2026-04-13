import Foundation

/// A bookmark at a specific reading position.
public struct BookmarkRecord: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID

    /// The reading position this bookmark captures.
    public let position: ReadingPosition

    /// Optional user-assigned title (defaults to chapter/section name).
    public let title: String?

    /// A short text excerpt around the bookmarked position for preview display.
    public let excerpt: String?

    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        position: ReadingPosition,
        title: String? = nil,
        excerpt: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.position = position
        self.title = title
        self.excerpt = excerpt
        self.createdAt = createdAt
    }

    /// Display title: user title, falling back to position summary.
    public var displayTitle: String {
        title ?? position.displaySummary
    }
}
