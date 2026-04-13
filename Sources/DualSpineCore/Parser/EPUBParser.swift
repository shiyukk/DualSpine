import Foundation

/// Top-level EPUB parser. Opens a `.epub` file and produces a fully-parsed `EPUBDocument`.
///
/// Usage:
/// ```swift
/// let document = try EPUBParser.parse(at: epubURL)
/// print(document.title)
/// print(document.flatTableOfContents.map(\.title))
/// ```
public enum EPUBParser {

    /// Parse an EPUB file at the given URL into a fully-resolved `EPUBDocument`.
    public static func parse(at url: URL) throws -> EPUBDocument {
        let archive = try EPUBArchive(at: url)

        // 1. Parse container.xml → locate OPF path
        let containerXML = try archive.readString(at: "META-INF/container.xml")
        let opfRelativePath = try EPUBContainerParser.parseOPFPath(from: containerXML)

        // 2. Determine content base path (directory containing the OPF)
        let contentBasePath: String
        if let lastSlash = opfRelativePath.lastIndex(of: "/") {
            contentBasePath = String(opfRelativePath[...lastSlash])
        } else {
            contentBasePath = ""
        }

        // 3. Parse the OPF package document
        let opfString = try archive.readString(at: opfRelativePath)
        let package = try EPUBPackageParser.parse(opfString: opfString)

        // 4. Parse table of contents
        let toc = try EPUBTOCParser.parse(
            from: package,
            readingContent: { href in
                let archivePath = contentBasePath + href
                return try archive.readString(at: archivePath)
            },
            contentBasePath: contentBasePath
        )

        return EPUBDocument(
            package: package,
            tableOfContents: toc,
            contentBasePath: contentBasePath,
            sourceURL: url
        )
    }

    /// Parse only the metadata and manifest (skips TOC parsing).
    /// Faster for import-time metadata extraction when you don't need the full TOC yet.
    public static func parseMetadata(at url: URL) throws -> (EPUBMetadata, EPUBVersion) {
        let archive = try EPUBArchive(at: url)
        let containerXML = try archive.readString(at: "META-INF/container.xml")
        let opfRelativePath = try EPUBContainerParser.parseOPFPath(from: containerXML)
        let opfString = try archive.readString(at: opfRelativePath)
        let package = try EPUBPackageParser.parse(opfString: opfString)
        return (package.metadata, package.version)
    }

    /// Extract cover image data from the EPUB, if a cover image is declared.
    public static func extractCoverImage(at url: URL) throws -> Data? {
        let archive = try EPUBArchive(at: url)
        let containerXML = try archive.readString(at: "META-INF/container.xml")
        let opfRelativePath = try EPUBContainerParser.parseOPFPath(from: containerXML)

        let contentBasePath: String
        if let lastSlash = opfRelativePath.lastIndex(of: "/") {
            contentBasePath = String(opfRelativePath[...lastSlash])
        } else {
            contentBasePath = ""
        }

        let opfString = try archive.readString(at: opfRelativePath)
        let package = try EPUBPackageParser.parse(opfString: opfString)

        guard let coverItem = package.coverImage else { return nil }
        let archivePath = contentBasePath + coverItem.href
        return try archive.readData(at: archivePath)
    }

    /// Extract the full text content of all spine documents, concatenated in reading order.
    /// Used for AI features (macro analysis, search indexing).
    public static func extractFullText(
        at url: URL,
        maxCharacters: Int = 200_000
    ) throws -> String {
        let archive = try EPUBArchive(at: url)
        let containerXML = try archive.readString(at: "META-INF/container.xml")
        let opfRelativePath = try EPUBContainerParser.parseOPFPath(from: containerXML)

        let contentBasePath: String
        if let lastSlash = opfRelativePath.lastIndex(of: "/") {
            contentBasePath = String(opfRelativePath[...lastSlash])
        } else {
            contentBasePath = ""
        }

        let opfString = try archive.readString(at: opfRelativePath)
        let package = try EPUBPackageParser.parse(opfString: opfString)

        var fullText = ""

        for (_, manifestItem) in package.resolvedSpine {
            guard manifestItem.isContentDocument else { continue }
            let archivePath = contentBasePath + manifestItem.href

            guard let xhtml = try? archive.readString(at: archivePath) else { continue }
            let text = Self.stripHTMLTags(xhtml)
            fullText += text + "\n\n"

            if fullText.count >= maxCharacters {
                return String(fullText.prefix(maxCharacters))
            }
        }

        return fullText
    }

    // MARK: - Private

    /// Fast, regex-free HTML tag stripping for text extraction.
    private static func stripHTMLTags(_ html: String) -> String {
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
                        .trimmingCharacters(in: .whitespaces)

                    // Track <head>...</head> to skip metadata, styles, links
                    if tag.hasPrefix("head") && !tag.hasPrefix("header") { insideHead = true }
                    if tag.hasPrefix("/head") { insideHead = false; continue }

                    if tag.hasPrefix("script") { insideScript = true }
                    if tag.hasPrefix("/script") { insideScript = false }
                    if tag.hasPrefix("style") { insideStyle = true }
                    if tag.hasPrefix("/style") { insideStyle = false }

                    // Block elements get a newline
                    let isBlock = tag.hasPrefix("p") || tag.hasPrefix("/p")
                        || tag.hasPrefix("br") || tag.hasPrefix("div")
                        || tag.hasPrefix("/div") || tag.hasPrefix("h")
                        || tag.hasPrefix("/h") || tag.hasPrefix("li")
                        || tag.hasPrefix("/li") || tag.hasPrefix("tr")
                        || tag.hasPrefix("/tr") || tag.hasPrefix("blockquote")
                        || tag.hasPrefix("/blockquote") || tag.hasPrefix("section")
                        || tag.hasPrefix("/section")

                    if isBlock && !insideHead {
                        result += "\n"
                    }
                } else {
                    tagBuffer.append(char)
                }
                continue
            }

            if !insideScript && !insideStyle && !insideHead {
                result.append(char)
            }
        }

        // Decode HTML entities
        var decoded = result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&hellip;", with: "…")
            .replacingOccurrences(of: "&lsquo;", with: "\u{2018}")
            .replacingOccurrences(of: "&rsquo;", with: "\u{2019}")
            .replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
            .replacingOccurrences(of: "&rdquo;", with: "\u{201D}")

        // Decode numeric character references (&#13; &#160; &#x20; etc.)
        decoded = decodeNumericEntities(decoded)

        // Collapse multiple blank lines into one, trim leading/trailing whitespace per line
        let lines = decoded.components(separatedBy: .newlines)
        var cleaned: [String] = []
        var lastWasEmpty = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !lastWasEmpty && !cleaned.isEmpty {
                    cleaned.append("")
                    lastWasEmpty = true
                }
            } else {
                cleaned.append(trimmed)
                lastWasEmpty = false
            }
        }

        return cleaned.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decode `&#123;` and `&#x1F;` style numeric entities.
    private static func decodeNumericEntities(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var i = text.startIndex

        while i < text.endIndex {
            if text[i] == "&", text.index(after: i) < text.endIndex, text[text.index(after: i)] == "#" {
                // Found &#...;
                let start = i
                i = text.index(i, offsetBy: 2) // skip &#
                var numStr = ""
                let isHex = i < text.endIndex && (text[i] == "x" || text[i] == "X")
                if isHex { i = text.index(after: i) }

                while i < text.endIndex && text[i] != ";" {
                    numStr.append(text[i])
                    i = text.index(after: i)
                }

                if i < text.endIndex && text[i] == ";" {
                    i = text.index(after: i) // skip ;
                    let codePoint = isHex
                        ? UInt32(numStr, radix: 16)
                        : UInt32(numStr, radix: 10)

                    if let cp = codePoint, let scalar = Unicode.Scalar(cp) {
                        // Skip control characters (&#13; = CR, &#10; = LF treated as space)
                        if cp == 13 || cp == 10 {
                            result.append("\n")
                        } else if cp < 32 {
                            // skip other control chars
                        } else {
                            result.append(Character(scalar))
                        }
                    } else {
                        result.append(contentsOf: text[start..<i])
                    }
                } else {
                    result.append(contentsOf: text[start..<i])
                }
            } else {
                result.append(text[i])
                i = text.index(after: i)
            }
        }

        return result
    }
}
