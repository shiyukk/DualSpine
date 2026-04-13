import Foundation

/// Parses `META-INF/container.xml` to locate the OPF package document path.
///
/// The container.xml structure is:
/// ```xml
/// <?xml version="1.0"?>
/// <container version="1.0" xmlns="...">
///   <rootfiles>
///     <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
///   </rootfiles>
/// </container>
/// ```
enum EPUBContainerParser {

    /// Extract the OPF path from container.xml content.
    /// Returns the `full-path` attribute of the first `<rootfile>` element.
    static func parseOPFPath(from containerXML: String) throws -> String {
        let delegate = ContainerXMLDelegate()
        let parser = XMLParser(data: Data(containerXML.utf8))
        parser.delegate = delegate
        parser.parse()

        guard let opfPath = delegate.opfPath else {
            throw EPUBError.containerXMLMalformed(
                "No <rootfile> with full-path found in container.xml"
            )
        }
        return opfPath
    }
}

// MARK: - SAX Delegate

private final class ContainerXMLDelegate: NSObject, XMLParserDelegate {
    var opfPath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        if elementName == "rootfile" || elementName.hasSuffix(":rootfile") {
            if let path = attributes["full-path"] {
                // Take the first rootfile only (multi-rendition EPUBs are rare)
                if opfPath == nil {
                    opfPath = path
                }
            }
        }
    }
}
