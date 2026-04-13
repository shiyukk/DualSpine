import Foundation

/// Fast in-memory search across all spine items of an EPUB.
/// Uses pre-extracted text from `EPUBParser.extractFullText` or semantic chunks.
public enum BookSearchEngine {

    /// A single search result with its location in the book.
    public struct SearchResult: Sendable, Identifiable {
        public let id: UUID
        /// The spine item index where the match was found.
        public let spineIndex: Int
        /// The spine item href.
        public let spineHref: String
        /// Character offset of the match within the spine item's text.
        public let characterOffset: Int
        /// The matched text (may be slightly expanded for context).
        public let matchedText: String
        /// Surrounding context (~40 chars before and after).
        public let context: String
        /// The heading ancestry at this location (if chunks are available).
        public let sectionTitle: String?

        public init(
            spineIndex: Int,
            spineHref: String,
            characterOffset: Int,
            matchedText: String,
            context: String,
            sectionTitle: String? = nil
        ) {
            self.id = UUID()
            self.spineIndex = spineIndex
            self.spineHref = spineHref
            self.characterOffset = characterOffset
            self.matchedText = matchedText
            self.context = context
            self.sectionTitle = sectionTitle
        }
    }

    /// Search across all spine items by reading XHTML and doing text search.
    /// - Parameters:
    ///   - query: The search string (case-insensitive).
    ///   - document: The parsed EPUB document.
    ///   - archive: The EPUB archive for reading spine item content.
    ///   - maxResults: Maximum number of results to return.
    public static func search(
        query: String,
        in document: EPUBDocument,
        archive: EPUBArchive,
        maxResults: Int = 50
    ) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        let lowercaseQuery = query.lowercased()
        var results: [SearchResult] = []

        let resolved = document.package.resolvedSpine
        let flatTOC = document.flatTableOfContents

        for (spineIdx, (_, manifest)) in resolved.enumerated() {
            guard manifest.isContentDocument else { continue }

            let archivePath = document.archivePath(forHref: manifest.href)
            guard let xhtml = try? archive.readString(at: archivePath) else { continue }

            let text = stripTags(xhtml)
            let lowercaseText = text.lowercased()

            var searchStart = lowercaseText.startIndex
            while let range = lowercaseText.range(of: lowercaseQuery, range: searchStart..<lowercaseText.endIndex) {
                let charOffset = lowercaseText.distance(from: lowercaseText.startIndex, to: range.lowerBound)
                let matchedText = String(text[range])

                // Build context
                let contextStart = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
                let contextEnd = text.index(range.upperBound, offsetBy: 40, limitedBy: text.endIndex) ?? text.endIndex
                let context = String(text[contextStart..<contextEnd])
                    .replacingOccurrences(of: "\n", with: " ")

                // Find section title from TOC
                let sectionTitle = flatTOC.last(where: { entry in
                    guard let href = entry.href else { return false }
                    return manifest.href == href || manifest.href.hasSuffix(href)
                })?.title

                results.append(SearchResult(
                    spineIndex: spineIdx,
                    spineHref: manifest.href,
                    characterOffset: charOffset,
                    matchedText: matchedText,
                    context: context,
                    sectionTitle: sectionTitle
                ))

                if results.count >= maxResults { return results }

                searchStart = range.upperBound
            }
        }

        return results
    }

    /// Fast tag stripping for search indexing.
    private static func stripTags(_ html: String) -> String {
        var result = ""
        result.reserveCapacity(html.count / 2)
        var insideTag = false
        var insideHead = false
        var insideScript = false
        var insideStyle = false
        var tagBuffer = ""

        for char in html {
            if char == "<" {
                insideTag = true
                tagBuffer = ""
                continue
            }
            if insideTag {
                if char == ">" {
                    insideTag = false
                    let tag = tagBuffer.lowercased()
                    if tag.hasPrefix("head") && !tag.hasPrefix("header") { insideHead = true }
                    if tag.hasPrefix("/head") { insideHead = false }
                    if tag.hasPrefix("script") { insideScript = true }
                    if tag.hasPrefix("/script") { insideScript = false }
                    if tag.hasPrefix("style") { insideStyle = true }
                    if tag.hasPrefix("/style") { insideStyle = false }
                } else {
                    tagBuffer.append(char)
                }
                continue
            }
            if !insideScript && !insideHead && !insideStyle {
                result.append(char)
            }
        }

        return result
    }
}
