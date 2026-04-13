import Foundation

/// A semantically-bounded text chunk extracted from EPUB content.
/// Unlike naive fixed-size chunks, these respect document structure:
/// paragraphs, headings, blockquotes, and tables are never split mid-element.
public struct SemanticChunk: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID

    /// Zero-based index of the spine item (XHTML file) this chunk came from.
    public let spineIndex: Int

    /// The spine item href (e.g. `"chapter3.xhtml"`).
    public let spineHref: String

    /// Which TOC section this chunk falls under (index into flat TOC), if resolved.
    public let tocSectionIndex: Int?

    /// The structural type of this chunk's primary content.
    public let blockType: BlockType

    /// Cleaned text content (HTML tags stripped, whitespace normalized).
    public let text: String

    /// Approximate token count (word-based estimate: `wordCount * 1.3`).
    public let estimatedTokens: Int

    /// The heading hierarchy above this chunk (e.g. `["Part II", "Chapter 5", "The Confession"]`).
    public let headingAncestry: [String]

    /// Character offset from the start of the spine item where this chunk begins.
    public let characterOffsetInSpine: Int

    /// Sequential chunk index across the entire book (for ordering and range queries).
    public let globalIndex: Int

    public init(
        id: UUID = UUID(),
        spineIndex: Int,
        spineHref: String,
        tocSectionIndex: Int? = nil,
        blockType: BlockType,
        text: String,
        estimatedTokens: Int,
        headingAncestry: [String] = [],
        characterOffsetInSpine: Int = 0,
        globalIndex: Int = 0
    ) {
        self.id = id
        self.spineIndex = spineIndex
        self.spineHref = spineHref
        self.tocSectionIndex = tocSectionIndex
        self.blockType = blockType
        self.text = text
        self.estimatedTokens = estimatedTokens
        self.headingAncestry = headingAncestry
        self.characterOffsetInSpine = characterOffsetInSpine
        self.globalIndex = globalIndex
    }

    /// The structural type of a chunk's primary content block.
    public enum BlockType: String, Codable, Sendable, Hashable {
        case heading
        case paragraph
        case blockquote
        case table
        case figure
        case listItem
        case codeBlock
        case preformatted
        /// Multiple short paragraphs merged into one chunk.
        case mergedParagraphs
    }
}

// MARK: - Chunk Store

/// A complete set of semantic chunks for one book, ready for indexing and retrieval.
public struct BookChunkStore: Sendable, Codable {
    /// Schema version for cache invalidation on format changes.
    public static let schemaVersion = 1

    public let bookIdentifier: String
    public let chunks: [SemanticChunk]
    public let totalCharacters: Int
    public let totalEstimatedTokens: Int
    public let schemaVersion: Int

    public init(bookIdentifier: String, chunks: [SemanticChunk]) {
        self.bookIdentifier = bookIdentifier
        self.chunks = chunks
        self.totalCharacters = chunks.reduce(0) { $0 + $1.text.count }
        self.totalEstimatedTokens = chunks.reduce(0) { $0 + $1.estimatedTokens }
        self.schemaVersion = Self.schemaVersion
    }

    /// Look up chunks within a specific TOC section.
    public func chunks(forTOCSection index: Int) -> [SemanticChunk] {
        chunks.filter { $0.tocSectionIndex == index }
    }

    /// Look up chunks from a specific spine item.
    public func chunks(forSpineIndex index: Int) -> [SemanticChunk] {
        chunks.filter { $0.spineIndex == index }
    }
}
