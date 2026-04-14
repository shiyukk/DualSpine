import Testing
import Foundation
@testable import DualSpineRender

@Suite("ReadingAnchor")
struct ReadingAnchorTests {

    @Test("Round-trips through JSONEncoder/JSONDecoder with all fields")
    func fullRoundTrip() throws {
        let anchor = ReadingAnchor(
            spineIndex: 7,
            elementID: "section-3",
            characterOffset: 1_234,
            progress: 0.42
        )
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(ReadingAnchor.self, from: data)
        #expect(decoded == anchor)
    }

    @Test("Encodes explicit nulls for optional fields so JS can distinguish")
    func optionalFieldsSurviveRoundTrip() throws {
        let anchor = ReadingAnchor(spineIndex: 2)
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(ReadingAnchor.self, from: data)
        #expect(decoded.spineIndex == 2)
        #expect(decoded.elementID == nil)
        #expect(decoded.characterOffset == nil)
        #expect(decoded.progress == nil)
    }

    @Test("startOfSpine creates progress=0 anchor")
    func startOfSpineAnchor() {
        let anchor = ReadingAnchor.startOfSpine(5)
        #expect(anchor.spineIndex == 5)
        #expect(anchor.progress == 0)
        #expect(anchor.elementID == nil)
        #expect(anchor.characterOffset == nil)
    }
}
