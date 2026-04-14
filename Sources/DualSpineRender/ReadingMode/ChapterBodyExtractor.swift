import Foundation
import SwiftSoup

/// Extracts the `<body>` contents of a chapter's XHTML document using
/// SwiftSoup. Gracefully handles malformed markup, CDATA sections, and
/// unusual framing that the old regex-based extractor could not parse.
///
/// Relative resource URLs (`src`, `href`, `poster`, `srcset`) inside the body
/// are rewritten so they resolve against the chapter's own archive location
/// rather than the host page, which may be a different spine item.
enum ChapterBodyExtractor {
    /// Parse `html` and return the serialized inner HTML of the document's
    /// `<body>` with relative URLs rewritten against `baseURL`. If parsing
    /// fails, returns the original string unchanged.
    static func extractBody(from html: String, baseURL: URL?) -> String {
        guard let document = try? SwiftSoup.parse(html, baseURL?.absoluteString ?? "") else {
            return html
        }
        if let base = baseURL {
            rewriteURLs(in: document, base: base)
        }
        guard let body = document.body(),
              let serialized = try? body.html() else {
            return html
        }
        return serialized
    }

    private static let urlAttributes: [String] = ["src", "href", "poster"]

    private static func rewriteURLs(in document: SwiftSoup.Document, base: URL) {
        for attribute in urlAttributes {
            guard let elements = try? document.select("[\(attribute)]") else { continue }
            for element in elements.array() {
                guard let raw = try? element.attr(attribute), !raw.isEmpty else { continue }
                if isAbsoluteOrScheme(raw) { continue }
                if let resolved = URL(string: raw, relativeTo: base)?.absoluteURL {
                    _ = try? element.attr(attribute, resolved.absoluteString)
                }
            }
        }
        // srcset — each candidate needs rewriting independently.
        if let elements = try? document.select("[srcset]") {
            for element in elements.array() {
                guard let raw = try? element.attr("srcset"), !raw.isEmpty else { continue }
                let rewritten = rewriteSrcSet(raw, base: base)
                _ = try? element.attr("srcset", rewritten)
            }
        }
    }

    private static func rewriteSrcSet(_ value: String, base: URL) -> String {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let mapped = parts.map { candidate -> String in
            let tokens = candidate.split(separator: " ", maxSplits: 1)
            guard let urlToken = tokens.first else { return candidate }
            let urlString = String(urlToken)
            let descriptor = tokens.count > 1 ? " " + String(tokens[1]) : ""
            if isAbsoluteOrScheme(urlString) { return candidate }
            if let resolved = URL(string: urlString, relativeTo: base)?.absoluteURL {
                return resolved.absoluteString + descriptor
            }
            return candidate
        }
        return mapped.joined(separator: ", ")
    }

    private static func isAbsoluteOrScheme(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { return true }
        if trimmed.hasPrefix("data:") || trimmed.hasPrefix("blob:") { return true }
        if trimmed.contains("://") { return true }
        if trimmed.hasPrefix("//") { return true }
        return false
    }
}
