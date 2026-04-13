import Testing
@testable import DualSpineCore

@Suite("EPUB Container Parser")
struct ContainerParserTests {

    @Test("Extracts OPF path from standard container.xml")
    func standardContainerXML() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let path = try EPUBContainerParser.parseOPFPath(from: xml)
        #expect(path == "OEBPS/content.opf")
    }

    @Test("Extracts OPF path at root level")
    func rootLevelOPF() throws {
        let xml = """
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="package.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let path = try EPUBContainerParser.parseOPFPath(from: xml)
        #expect(path == "package.opf")
    }

    @Test("Throws on missing rootfile")
    func missingRootfile() {
        let xml = """
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles/>
        </container>
        """
        #expect(throws: EPUBError.self) {
            try EPUBContainerParser.parseOPFPath(from: xml)
        }
    }
}

@Suite("EPUB Package Parser")
struct PackageParserTests {

    static let sampleOPF = """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>Test Book</dc:title>
        <dc:creator>Test Author</dc:creator>
        <dc:language>en</dc:language>
        <dc:identifier id="uid">urn:uuid:12345</dc:identifier>
        <dc:subject>Fiction</dc:subject>
        <dc:subject>Science</dc:subject>
      </metadata>
      <manifest>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
        <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
        <item id="css" href="style.css" media-type="text/css"/>
        <item id="cover" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
      </manifest>
      <spine>
        <itemref idref="ch1"/>
        <itemref idref="ch2"/>
      </spine>
    </package>
    """

    @Test("Parses metadata correctly")
    func metadata() throws {
        let package = try EPUBPackageParser.parse(opfString: Self.sampleOPF)
        #expect(package.metadata.title == "Test Book")
        #expect(package.metadata.creators == ["Test Author"])
        #expect(package.metadata.language == "en")
        #expect(package.metadata.identifier == "urn:uuid:12345")
        #expect(package.metadata.subjects == ["Fiction", "Science"])
    }

    @Test("Parses manifest items")
    func manifest() throws {
        let package = try EPUBPackageParser.parse(opfString: Self.sampleOPF)
        #expect(package.manifest.count == 5)
        #expect(package.manifest["ch1"]?.href == "chapter1.xhtml")
        #expect(package.manifest["nav"]?.isNavDocument == true)
        #expect(package.manifest["cover"]?.isCoverImage == true)
        #expect(package.manifest["css"]?.isStylesheet == true)
    }

    @Test("Parses spine in order")
    func spine() throws {
        let package = try EPUBPackageParser.parse(opfString: Self.sampleOPF)
        #expect(package.spine.count == 2)
        #expect(package.spine[0].manifestRef == "ch1")
        #expect(package.spine[1].manifestRef == "ch2")
        #expect(package.spine[0].index == 0)
        #expect(package.spine[1].index == 1)
    }

    @Test("Detects EPUB 3 version")
    func version() throws {
        let package = try EPUBPackageParser.parse(opfString: Self.sampleOPF)
        #expect(package.version == .epub3)
        #expect(package.version.isEPUB3OrLater)
    }

    @Test("Resolves spine against manifest")
    func resolvedSpine() throws {
        let package = try EPUBPackageParser.parse(opfString: Self.sampleOPF)
        let resolved = package.resolvedSpine
        #expect(resolved.count == 2)
        #expect(resolved[0].manifest.href == "chapter1.xhtml")
        #expect(resolved[1].manifest.href == "chapter2.xhtml")
    }

    @Test("Identifies navigation document")
    func navDocument() throws {
        let package = try EPUBPackageParser.parse(opfString: Self.sampleOPF)
        #expect(package.navDocument?.href == "nav.xhtml")
    }

    @Test("Identifies cover image")
    func coverImage() throws {
        let package = try EPUBPackageParser.parse(opfString: Self.sampleOPF)
        #expect(package.coverImage?.href == "cover.jpg")
    }
}

@Suite("EPUB 2 Package Parser")
struct EPUB2PackageParserTests {

    @Test("Parses EPUB 2 OPF with NCX toc reference")
    func epub2WithNCX() throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Legacy Book</dc:title>
            <meta name="cover" content="cover-img"/>
          </metadata>
          <manifest>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="ch1" href="text/chapter1.html" media-type="application/xhtml+xml"/>
            <item id="cover-img" href="images/cover.png" media-type="image/png"/>
          </manifest>
          <spine toc="ncx">
            <itemref idref="ch1"/>
          </spine>
        </package>
        """
        let package = try EPUBPackageParser.parse(opfString: opf)
        #expect(package.version == .epub2)
        #expect(!package.version.isEPUB3OrLater)
        #expect(package.ncxHref == "toc.ncx")
        #expect(package.metadata.coverMetaID == "cover-img")
        #expect(package.coverImage?.href == "images/cover.png")
    }
}

@Suite("TOC Node")
struct TOCNodeTests {

    @Test("Flattens hierarchical TOC")
    func flatten() {
        let toc = TOCNode(
            title: "Part I",
            href: "part1.xhtml",
            children: [
                TOCNode(title: "Chapter 1", href: "ch1.xhtml", level: 1),
                TOCNode(title: "Chapter 2", href: "ch2.xhtml", level: 1),
            ],
            level: 0
        )

        let flat = toc.flattened()
        #expect(flat.count == 3)
        #expect(flat[0].title == "Part I")
        #expect(flat[0].level == 0)
        #expect(flat[1].title == "Chapter 1")
        #expect(flat[1].level == 1)
        #expect(flat[2].title == "Chapter 2")
        #expect(flat[2].index == 2)
    }
}

@Suite("MIME Type Detection")
struct MIMETypeTests {

    @Test("Detects common EPUB content types")
    func commonTypes() {
        #expect(EPUBArchive.mimeType(for: "chapter.xhtml") == "application/xhtml+xml")
        #expect(EPUBArchive.mimeType(for: "style.css") == "text/css")
        #expect(EPUBArchive.mimeType(for: "cover.jpg") == "image/jpeg")
        #expect(EPUBArchive.mimeType(for: "font.woff2") == "font/woff2")
        #expect(EPUBArchive.mimeType(for: "illustration.svg") == "image/svg+xml")
    }

    @Test("Returns octet-stream for unknown extensions")
    func unknownType() {
        #expect(EPUBArchive.mimeType(for: "data.xyz") == "application/octet-stream")
    }
}
