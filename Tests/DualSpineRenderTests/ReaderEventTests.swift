import Testing
import Foundation
@testable import DualSpineRender

@Suite("ReaderEvent parsing")
struct ReaderEventTests {

    @Test("ready parses with empty payload")
    func readyParse() {
        let event = ReaderEvent.parse(from: ["type": "ready", "payload": [:]])
        #expect(event == .ready)
    }

    @Test("chapterChanged requires spineIndex")
    func chapterChangedParse() {
        let event = ReaderEvent.parse(from: [
            "type": "chapterChanged",
            "payload": ["spineIndex": 4]
        ])
        #expect(event == .chapterChanged(spineIndex: 4))
    }

    @Test("chapterChanged rejects missing spineIndex")
    func chapterChangedRejectsMissing() {
        let event = ReaderEvent.parse(from: [
            "type": "chapterChanged",
            "payload": [:]
        ])
        #expect(event == nil)
    }

    @Test("progressUpdated handles scroll-only (overall only) and paginated (with page fields)")
    func progressUpdatedShapes() {
        let scrollEvent = ReaderEvent.parse(from: [
            "type": "progressUpdated",
            "payload": ["overall": 0.25]
        ])
        #expect(scrollEvent == .progressUpdated(overall: 0.25, pageIndex: nil, pageCount: nil))

        let paginatedPayload: [String: Any] = [
            "overall": 0.5,
            "pageIndex": Int(3),
            "pageCount": Int(10)
        ]
        let paginatedEvent = ReaderEvent.parse(from: [
            "type": "progressUpdated",
            "payload": paginatedPayload
        ])
        #expect(paginatedEvent == .progressUpdated(overall: 0.5, pageIndex: 3, pageCount: 10))
    }

    @Test("boundaryReached carries direction and spineIndex")
    func boundaryReachedParse() {
        let event = ReaderEvent.parse(from: [
            "type": "boundaryReached",
            "payload": ["direction": "end", "spineIndex": 12]
        ])
        #expect(event == .boundaryReached(direction: "end", spineIndex: 12))
    }

    @Test("selectionChanged decodes full SelectionPayload including highlightId")
    func selectionChangedParse() throws {
        let payload: [String: Any] = [
            "text": "hello",
            "rangeStart": 10,
            "rangeEnd": 15,
            "rectX": 1.0,
            "rectY": 2.0,
            "rectWidth": 3.0,
            "rectHeight": 4.0,
            "spineIndex": 0,
            "spineHref": "c1.xhtml",
            "highlightId": "abc-123"
        ]
        let event = ReaderEvent.parse(from: ["type": "selectionChanged", "payload": payload])
        guard case let .selectionChanged(selection) = event else {
            Issue.record("expected selectionChanged, got \(String(describing: event))")
            return
        }
        #expect(selection.text == "hello")
        #expect(selection.rangeStart == 10)
        #expect(selection.highlightID == "abc-123")
    }

    @Test("selectionChanged defaults highlightId to empty when absent")
    func selectionChangedMissingHighlightId() throws {
        let payload: [String: Any] = [
            "text": "hello",
            "rangeStart": 0,
            "rangeEnd": 5,
            "rectX": 0, "rectY": 0, "rectWidth": 0, "rectHeight": 0,
            "spineIndex": 0,
            "spineHref": ""
        ]
        let event = ReaderEvent.parse(from: ["type": "selectionChanged", "payload": payload])
        guard case let .selectionChanged(selection) = event else {
            Issue.record("expected selectionChanged")
            return
        }
        #expect(selection.highlightID == "")
    }

    @Test("unknown type returns nil")
    func unknownType() {
        let event = ReaderEvent.parse(from: ["type": "whatever", "payload": [:]])
        #expect(event == nil)
    }

    @Test("linkTapped defaults isInternal to false when absent")
    func linkTappedDefaults() {
        let event = ReaderEvent.parse(from: [
            "type": "linkTapped",
            "payload": ["href": "https://example.com"]
        ])
        #expect(event == .linkTapped(href: "https://example.com", isInternal: false))
    }
}

@Suite("EPUBBridgeMessage projection")
struct EPUBBridgeMessageProjectionTests {

    @Test("progressUpdated without page info → .progressUpdated")
    func progressToProgress() {
        let projected = EPUBBridgeMessage.from(
            event: .progressUpdated(overall: 0.3, pageIndex: nil, pageCount: nil),
            currentSpineHref: "c.xhtml"
        )
        guard case let .progressUpdated(payload) = projected else {
            Issue.record("expected progressUpdated")
            return
        }
        #expect(payload.chapterProgress == 0.3)
    }

    @Test("progressUpdated with page info → .pageChanged")
    func progressToPageChanged() {
        let projected = EPUBBridgeMessage.from(
            event: .progressUpdated(overall: 0.5, pageIndex: 4, pageCount: 10),
            currentSpineHref: "c.xhtml"
        )
        guard case let .pageChanged(payload) = projected else {
            Issue.record("expected pageChanged")
            return
        }
        #expect(payload.currentPage == 4)
        #expect(payload.totalPages == 10)
    }

    @Test("boundaryReached / ready / chapterChanged are internal → nil projection")
    func internalEventsDoNotProject() {
        let events: [ReaderEvent] = [
            .ready,
            .chapterChanged(spineIndex: 0),
            .boundaryReached(direction: "end", spineIndex: 0)
        ]
        for event in events {
            let projected = EPUBBridgeMessage.from(event: event, currentSpineHref: "")
            #expect(projected == nil)
        }
    }
}

