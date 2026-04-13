import Foundation

/// Metadata extracted from the OPF `<metadata>` block.
public struct EPUBMetadata: Sendable, Hashable {
    public let title: String
    public let creators: [String]
    public let language: String?
    public let identifier: String?
    public let publisher: String?
    public let date: String?
    public let description: String?
    public let rights: String?
    public let subjects: [String]

    /// The manifest item ID referenced by `<meta name="cover" content="...">` (EPUB 2 pattern).
    public let coverMetaID: String?

    public init(
        title: String,
        creators: [String] = [],
        language: String? = nil,
        identifier: String? = nil,
        publisher: String? = nil,
        date: String? = nil,
        description: String? = nil,
        rights: String? = nil,
        subjects: [String] = [],
        coverMetaID: String? = nil
    ) {
        self.title = title
        self.creators = creators
        self.language = language
        self.identifier = identifier
        self.publisher = publisher
        self.date = date
        self.description = description
        self.rights = rights
        self.subjects = subjects
        self.coverMetaID = coverMetaID
    }

    /// The first creator listed, typically the primary author.
    public var primaryAuthor: String? { creators.first }
}
