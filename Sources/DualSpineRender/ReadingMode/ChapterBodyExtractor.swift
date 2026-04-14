import Foundation
import SwiftSoup

/// Extracts the `<body>` contents of a chapter's XHTML document using
/// SwiftSoup. Gracefully handles malformed markup, CDATA sections, and
/// unusual framing that the old regex-based extractor could not parse.
enum ChapterBodyExtractor {
    /// Parse `html` and return the serialized inner HTML of the document's
    /// `<body>`. If parsing fails, returns the original string unchanged — the
    /// JS layer is tolerant of full documents but works best with body
    /// fragments.
    static func extractBody(from html: String) -> String {
        guard let document = try? SwiftSoup.parse(html),
              let body = document.body() else {
            return html
        }
        return (try? body.html()) ?? html
    }
}
