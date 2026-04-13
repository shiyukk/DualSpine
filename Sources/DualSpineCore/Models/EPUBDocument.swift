import Foundation

/// The fully parsed, immutable representation of an EPUB file.
/// This is the primary output of `EPUBParser.parse(at:)` — a Sendable value type
/// containing all structural information needed by both the visual and semantic tracks.
public struct EPUBDocument: Sendable {
    /// The parsed OPF package (metadata, manifest, spine).
    public let package: EPUBPackage

    /// The hierarchical table of contents.
    public let tableOfContents: [TOCNode]

    /// The directory prefix within the archive where the OPF lives
    /// (e.g. `"OEBPS/"` or `""`). All manifest hrefs are relative to this.
    public let contentBasePath: String

    /// The URL of the source EPUB file on disk.
    public let sourceURL: URL

    public init(
        package: EPUBPackage,
        tableOfContents: [TOCNode],
        contentBasePath: String,
        sourceURL: URL
    ) {
        self.package = package
        self.tableOfContents = tableOfContents
        self.contentBasePath = contentBasePath
        self.sourceURL = sourceURL
    }

    // MARK: - Convenience

    public var title: String { package.metadata.title }
    public var author: String? { package.metadata.primaryAuthor }
    public var language: String? { package.metadata.language }
    public var spineCount: Int { package.spine.count }

    /// Flattened TOC entries for list display.
    public var flatTableOfContents: [FlatTOCEntry] {
        tableOfContents.flatMap { $0.flattened() }
    }

    /// Resolve a manifest-relative href to the full archive path.
    /// For example, if `contentBasePath` is `"OEBPS/"` and href is `"chapter1.xhtml"`,
    /// this returns `"OEBPS/chapter1.xhtml"`.
    public func archivePath(forHref href: String) -> String {
        if href.hasPrefix("/") {
            return String(href.dropFirst())
        }
        return contentBasePath + href
    }

    /// All content document archive paths in reading order.
    public var readingOrderArchivePaths: [String] {
        package.readingOrderHrefs.map { archivePath(forHref: $0) }
    }
}
