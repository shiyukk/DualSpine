import Foundation

/// Parses the OPF package document into `EPUBPackage` (metadata + manifest + spine).
enum EPUBPackageParser {

    static func parse(opfString: String) throws -> EPUBPackage {
        let delegate = OPFParserDelegate()
        let parser = XMLParser(data: Data(opfString.utf8))
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.parse()

        if let error = delegate.parseError {
            throw EPUBError.opfMalformed(error.localizedDescription)
        }

        let metadata = EPUBMetadata(
            title: delegate.title ?? "Untitled",
            creators: delegate.creators,
            language: delegate.language,
            identifier: delegate.identifier,
            publisher: delegate.publisher,
            date: delegate.date,
            description: delegate.description_,
            rights: delegate.rights,
            subjects: delegate.subjects,
            coverMetaID: delegate.coverMetaID
        )

        let manifestDict = Dictionary(
            delegate.manifestItems.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        if delegate.spineItems.isEmpty {
            throw EPUBError.spineEmpty
        }

        let version = EPUBVersion(versionString: delegate.packageVersion ?? "")

        // Resolve NCX href from the toc attribute on <spine>
        var ncxHref: String?
        if let ncxID = delegate.spineTocRef {
            ncxHref = manifestDict[ncxID]?.href
        }

        return EPUBPackage(
            metadata: metadata,
            manifest: manifestDict,
            spine: delegate.spineItems,
            version: version,
            ncxHref: ncxHref
        )
    }
}

// MARK: - SAX Delegate

private final class OPFParserDelegate: NSObject, XMLParserDelegate {
    // Metadata
    var title: String?
    var creators: [String] = []
    var language: String?
    var identifier: String?
    var publisher: String?
    var date: String?
    var description_: String?
    var rights: String?
    var subjects: [String] = []
    var coverMetaID: String?
    var packageVersion: String?

    // Manifest
    var manifestItems: [EPUBManifestItem] = []

    // Spine
    var spineItems: [EPUBSpineItem] = []
    var spineTocRef: String?

    // Parse state
    var parseError: (any Error)?
    private var currentElement: String = ""
    private var currentText: String = ""
    private var insideMetadata = false
    private var spineIndex = 0

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
        case "package":
            packageVersion = attributes["version"]

        case "metadata":
            insideMetadata = true

        case "meta":
            // EPUB 2 cover declaration: <meta name="cover" content="cover-image-id"/>
            if insideMetadata,
               attributes["name"] == "cover",
               let content = attributes["content"] {
                coverMetaID = content
            }

        case "item":
            if let id = attributes["id"], let href = attributes["href"] {
                let mediaType = attributes["media-type"] ?? "application/octet-stream"
                let properties: Set<String>
                if let props = attributes["properties"] {
                    properties = Set(props.split(separator: " ").map(String.init))
                } else {
                    properties = []
                }
                let item = EPUBManifestItem(
                    id: id,
                    href: href,
                    mediaType: mediaType,
                    properties: properties
                )
                manifestItems.append(item)
            }

        case "spine":
            spineTocRef = attributes["toc"]

        case "itemref":
            if let idref = attributes["idref"] {
                let linear = attributes["linear"] != "no"
                let item = EPUBSpineItem(
                    manifestRef: idref,
                    linear: linear,
                    index: spineIndex
                )
                spineItems.append(item)
                spineIndex += 1
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

        if insideMetadata && !text.isEmpty {
            switch elementName {
            case "title", "dc:title":
                if title == nil { title = text }
            case "creator", "dc:creator":
                creators.append(text)
            case "language", "dc:language":
                if language == nil { language = text }
            case "identifier", "dc:identifier":
                if identifier == nil { identifier = text }
            case "publisher", "dc:publisher":
                if publisher == nil { publisher = text }
            case "date", "dc:date":
                if date == nil { date = text }
            case "description", "dc:description":
                if description_ == nil { description_ = text }
            case "rights", "dc:rights":
                if rights == nil { rights = text }
            case "subject", "dc:subject":
                subjects.append(text)
            default:
                break
            }
        }

        if elementName == "metadata" {
            insideMetadata = false
        }

        currentElement = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
        self.parseError = parseError
    }
}
