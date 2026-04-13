import Foundation
import SwiftSoup

/// Parses EPUB table of contents from both EPUB 2 (NCX) and EPUB 3 (Navigation Document) formats.
public enum EPUBTOCParser {

    /// Parse the TOC from whichever source is available.
    /// Prefers EPUB 3 Navigation Document; falls back to NCX.
    public static func parse(
        from document: EPUBPackage,
        readingContent: (_ href: String) throws -> String,
        contentBasePath: String
    ) throws -> [TOCNode] {
        // Try EPUB 3 Navigation Document first
        if let navItem = document.navDocument {
            let navContent = try readingContent(navItem.href)
            let nodes = try parseNavigationDocument(navContent, basePath: contentBasePath)
            if !nodes.isEmpty { return nodes }
        }

        // Fall back to NCX (EPUB 2)
        if let ncxHref = document.ncxHref {
            let ncxContent = try readingContent(ncxHref)
            let nodes = try parseNCX(ncxContent, basePath: contentBasePath)
            if !nodes.isEmpty { return nodes }
        }

        return []
    }

    // MARK: - EPUB 3 Navigation Document

    /// Parse an EPUB 3 Navigation Document (XHTML with `<nav epub:type="toc">`).
    static func parseNavigationDocument(_ html: String, basePath: String) throws -> [TOCNode] {
        let doc = try SwiftSoup.parse(html)

        // Find the primary TOC nav element
        guard let tocNav = try doc.select("nav[epub|type=toc]").first()
                ?? doc.select("nav").first() else {
            return []
        }

        // The TOC is an ordered list (<ol>) inside the <nav>
        guard let rootOL = try tocNav.select(":root > ol").first()
                ?? tocNav.getElementsByTag("ol").first() else {
            return []
        }

        return try parseOLChildren(rootOL, level: 0, basePath: basePath)
    }

    private static func parseOLChildren(
        _ ol: Element,
        level: Int,
        basePath: String
    ) throws -> [TOCNode] {
        var nodes: [TOCNode] = []

        for li in ol.children() where li.tagName() == "li" {
            // Each <li> contains an <a> (or <span>) and optionally a nested <ol>
            let anchor = try li.getElementsByTag("a").first()
            let span = try li.getElementsByTag("span").first()

            let title = try (anchor?.text() ?? span?.text() ?? "").trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !title.isEmpty else { continue }

            var href: String?
            var fragmentID: String?

            if let rawHref = try anchor?.attr("href"), !rawHref.isEmpty {
                let parts = rawHref.split(separator: "#", maxSplits: 1)
                href = parts.first.map { resolveHref(String($0), basePath: basePath) }
                fragmentID = parts.count > 1 ? String(parts[1]) : nil
            }

            // Recurse into nested <ol>
            var children: [TOCNode] = []
            if let nestedOL = try li.getElementsByTag("ol").first() {
                children = try parseOLChildren(nestedOL, level: level + 1, basePath: basePath)
            }

            let node = TOCNode(
                title: title,
                href: href,
                fragmentID: fragmentID,
                children: children,
                level: level
            )
            nodes.append(node)
        }

        return nodes
    }

    // MARK: - EPUB 2 NCX

    /// Parse an EPUB 2 NCX (XML with `<navMap>` containing `<navPoint>` elements).
    static func parseNCX(_ xml: String, basePath: String) throws -> [TOCNode] {
        let delegate = NCXParserDelegate(basePath: basePath)
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.parse()

        if let error = delegate.parseError {
            throw EPUBError.tocParsingFailed(error.localizedDescription)
        }

        return delegate.rootNodes
    }

    // MARK: - Helpers

    private static func resolveHref(_ href: String, basePath: String) -> String {
        if href.isEmpty || href.hasPrefix("http://") || href.hasPrefix("https://") {
            return href
        }
        // Already absolute within archive
        if href.hasPrefix(basePath) {
            return href
        }
        return href
    }
}

// MARK: - NCX SAX Delegate

private final class NCXParserDelegate: NSObject, XMLParserDelegate {
    let basePath: String
    var rootNodes: [TOCNode] = []
    var parseError: (any Error)?

    // Stack-based parsing for nested <navPoint> elements
    private var nodeStack: [(title: String?, href: String?, fragmentID: String?, children: [TOCNode])] = []
    private var currentElement = ""
    private var currentText = ""
    private var pendingSrc: String?

    init(basePath: String) {
        self.basePath = basePath
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "navPoint":
            nodeStack.append((title: nil, href: nil, fragmentID: nil, children: []))

        case "content":
            if let src = attributes["src"], !nodeStack.isEmpty {
                let parts = src.split(separator: "#", maxSplits: 1)
                let href = String(parts.first ?? "")
                let fragment = parts.count > 1 ? String(parts[1]) : nil
                nodeStack[nodeStack.count - 1].href = href
                nodeStack[nodeStack.count - 1].fragmentID = fragment
            }

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "text":
            if !text.isEmpty, !nodeStack.isEmpty {
                nodeStack[nodeStack.count - 1].title = text
            }

        case "navPoint":
            guard let finished = nodeStack.popLast() else { break }
            let level = nodeStack.count
            let node = TOCNode(
                title: finished.title ?? "",
                href: finished.href,
                fragmentID: finished.fragmentID,
                children: finished.children,
                level: level
            )
            if nodeStack.isEmpty {
                rootNodes.append(node)
            } else {
                nodeStack[nodeStack.count - 1].children.append(node)
            }

        default:
            break
        }

        currentElement = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, parseErrorOccurred error: any Error) {
        parseError = error
    }
}
