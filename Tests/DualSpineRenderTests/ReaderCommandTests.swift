import Testing
import Foundation
@testable import DualSpineRender

@Suite("ReaderCommand encoding")
struct ReaderCommandTests {

    @Test("setMode emits {type, payload:{mode, anchor}}")
    func setModeEncoding() throws {
        let command = ReaderCommand.setMode(
            mode: .paginatedSlide,
            anchor: .startOfSpine(3)
        )
        let json = try command.jsonString()
        let object = try parse(json)
        #expect(object["type"] as? String == "setMode")
        let payload = try #require(object["payload"] as? [String: Any])
        let mode = try #require(payload["mode"] as? [String: Any])
        #expect(mode["mode"] as? String == "paginated")
        #expect(mode["transition"] as? String == "slide")
        let anchor = try #require(payload["anchor"] as? [String: Any])
        #expect(anchor["spineIndex"] as? Int == 3)
    }

    @Test("mountChapters carries chapter array with bodyHTML")
    func mountChaptersEncoding() throws {
        let command = ReaderCommand.mountChapters(
            chapters: [
                ChapterContent(spineIndex: 0, spineHref: "c1.xhtml", bodyHTML: "<p>Hi</p>"),
                ChapterContent(spineIndex: 1, spineHref: "c2.xhtml", bodyHTML: "<p>There</p>")
            ],
            anchor: ReadingAnchor(spineIndex: 1, progress: 0.5)
        )
        let json = try command.jsonString()
        let object = try parse(json)
        #expect(object["type"] as? String == "mountChapters")
        let payload = try #require(object["payload"] as? [String: Any])
        let chapters = try #require(payload["chapters"] as? [[String: Any]])
        #expect(chapters.count == 2)
        #expect(chapters[0]["spineIndex"] as? Int == 0)
        #expect(chapters[1]["bodyHTML"] as? String == "<p>There</p>")
    }

    @Test("navigate payload contains anchor only")
    func navigateEncoding() throws {
        let command = ReaderCommand.navigate(anchor: ReadingAnchor(spineIndex: 2, elementID: "ch2-top"))
        let json = try command.jsonString()
        let object = try parse(json)
        #expect(object["type"] as? String == "navigate")
        let payload = try #require(object["payload"] as? [String: Any])
        let anchor = try #require(payload["anchor"] as? [String: Any])
        #expect(anchor["elementID"] as? String == "ch2-top")
    }

    @Test("nextPage and prevPage encode with empty payload")
    func pageCommandsEncoding() throws {
        for (command, type) in [
            (ReaderCommand.nextPage, "nextPage"),
            (ReaderCommand.prevPage, "prevPage")
        ] {
            let object = try parse(try command.jsonString())
            #expect(object["type"] as? String == type)
            #expect(object["payload"] is [String: Any])
        }
    }

    @Test("applyHighlights carries full HighlightCommand list")
    func applyHighlightsEncoding() throws {
        let command = ReaderCommand.applyHighlights([
            ReaderCommand.HighlightCommand(
                id: "abc",
                spineIndex: 0,
                rangeStart: 10,
                rangeEnd: 20,
                color: "rgba(247, 201, 72, 0.45)"
            )
        ])
        let json = try command.jsonString()
        let object = try parse(json)
        let payload = try #require(object["payload"] as? [String: Any])
        let list = try #require(payload["highlights"] as? [[String: Any]])
        #expect(list.count == 1)
        #expect(list[0]["id"] as? String == "abc")
        #expect(list[0]["color"] as? String == "rgba(247, 201, 72, 0.45)")
    }

    @Test("applyTheme ships the CSS string verbatim")
    func applyThemeEncoding() throws {
        let css = "#ds-reader { color: red; }"
        let command = ReaderCommand.applyTheme(css: css)
        let object = try parse(try command.jsonString())
        let payload = try #require(object["payload"] as? [String: Any])
        #expect(payload["css"] as? String == css)
    }

    @Test("ModeDescriptor static helpers build expected shapes")
    func modeDescriptorHelpers() {
        #expect(ReaderCommand.ModeDescriptor.scroll.mode == "scroll")
        #expect(ReaderCommand.ModeDescriptor.scroll.transition == nil)
        #expect(ReaderCommand.ModeDescriptor.paginatedSlide.mode == "paginated")
        #expect(ReaderCommand.ModeDescriptor.paginatedSlide.transition == "slide")
        #expect(ReaderCommand.ModeDescriptor.paginatedFade.transition == "fade")
    }

    private func parse(_ json: String) throws -> [String: Any] {
        let data = try #require(json.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
