import Testing
import Foundation
@testable import DualSpineRender

@Suite("ChapterBodyExtractor")
struct ChapterBodyExtractorTests {

    @Test("Extracts inner body content from a full XHTML document")
    func extractsInnerBody() {
        let xhtml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Ch 1</title></head>
        <body><p>Hello</p><p>World</p></body>
        </html>
        """
        let body = ChapterBodyExtractor.extractBody(from: xhtml, baseURL: nil)
        #expect(body.contains("<p>Hello</p>"))
        #expect(body.contains("<p>World</p>"))
        #expect(!body.contains("<title>"))
    }

    @Test("Rewrites relative img src against baseURL")
    func rewritesRelativeImageSrc() throws {
        let xhtml = """
        <html><body><img src="images/cover.jpg" alt="c"/></body></html>
        """
        let base = try #require(URL(string: "dualspine://book/OEBPS/chapter1.xhtml"))
        let body = ChapterBodyExtractor.extractBody(from: xhtml, baseURL: base)
        #expect(body.contains("dualspine://book/OEBPS/images/cover.jpg"))
    }

    @Test("Leaves absolute URLs alone")
    func preservesAbsoluteURLs() throws {
        let xhtml = """
        <html><body>
        <a href="https://example.com/x">x</a>
        <img src="data:image/png;base64,AAA"/>
        <a href="#section">anchor</a>
        </body></html>
        """
        let base = try #require(URL(string: "dualspine://book/OEBPS/c.xhtml"))
        let body = ChapterBodyExtractor.extractBody(from: xhtml, baseURL: base)
        #expect(body.contains("https://example.com/x"))
        #expect(body.contains("data:image/png;base64,AAA"))
        #expect(body.contains("href=\"#section\""))
    }

    @Test("Rewrites each srcset candidate independently")
    func rewritesSrcSet() throws {
        let xhtml = """
        <html><body>
        <img srcset="images/small.jpg 1x, images/large.jpg 2x"/>
        </body></html>
        """
        let base = try #require(URL(string: "dualspine://book/OEBPS/c.xhtml"))
        let body = ChapterBodyExtractor.extractBody(from: xhtml, baseURL: base)
        #expect(body.contains("dualspine://book/OEBPS/images/small.jpg 1x"))
        #expect(body.contains("dualspine://book/OEBPS/images/large.jpg 2x"))
    }

    @Test("Returns original string on parse failure (no body)")
    func unparseable() {
        // SwiftSoup is tolerant — but a purely empty string has no body.
        let body = ChapterBodyExtractor.extractBody(from: "", baseURL: nil)
        #expect(body == "")
    }
}
