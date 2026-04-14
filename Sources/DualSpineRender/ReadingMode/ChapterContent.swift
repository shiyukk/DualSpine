import Foundation

/// The payload for a single chapter injected into the JS layout engine.
///
/// Content is the chapter's `<body>` contents as a string. Parsing and
/// body extraction happen in Swift (via SwiftSoup) before this DTO is built,
/// so the JS layer never parses full XHTML documents.
public struct ChapterContent: Codable, Sendable, Hashable {
    /// Zero-based spine item index.
    public let spineIndex: Int

    /// The original manifest href (used for link resolution and diagnostics).
    public let spineHref: String

    /// The chapter's body HTML — everything between `<body>` and `</body>`,
    /// with no surrounding document framing.
    public let bodyHTML: String

    public init(spineIndex: Int, spineHref: String, bodyHTML: String) {
        self.spineIndex = spineIndex
        self.spineHref = spineHref
        self.bodyHTML = bodyHTML
    }
}
