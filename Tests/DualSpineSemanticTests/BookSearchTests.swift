import Foundation
import Testing
@testable import DualSpineCore

@Suite("Book Search Engine")
struct BookSearchTests {

    static let booksDir: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("books")
    }()

    static func findEPUB(containing substring: String) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: booksDir, includingPropertiesForKeys: nil
        ) else { return nil }
        return entries.first { $0.pathExtension == "epub" && $0.lastPathComponent.contains(substring) }
    }

    @Test("Search for 'love' in First Love")
    func searchLove() throws {
        guard let url = Self.findEPUB(containing: "First Love") else {
            Issue.record("EPUB not found"); return
        }

        let doc = try EPUBParser.parse(at: url)
        let archive = try EPUBArchive(at: url)

        let results = BookSearchEngine.search(query: "love", in: doc, archive: archive, maxResults: 10)

        print("Search 'love': \(results.count) results")
        for r in results.prefix(5) {
            print("  [\(r.spineIndex)] ...  \(r.context.prefix(80))...")
        }

        #expect(results.count > 0, "Should find 'love' in First Love")
    }

    @Test("Search for 'garden' in First Love")
    func searchGarden() throws {
        guard let url = Self.findEPUB(containing: "First Love") else { return }

        let doc = try EPUBParser.parse(at: url)
        let archive = try EPUBArchive(at: url)

        let results = BookSearchEngine.search(query: "garden", in: doc, archive: archive, maxResults: 10)

        print("Search 'garden': \(results.count) results")
        for r in results.prefix(3) {
            print("  [\(r.spineIndex)] \(r.context.prefix(80))...")
        }

        #expect(results.count > 0, "Should find 'garden' in First Love")
    }

    @Test("Search is case-insensitive")
    func searchCaseInsensitive() throws {
        guard let url = Self.findEPUB(containing: "First Love") else { return }

        let doc = try EPUBParser.parse(at: url)
        let archive = try EPUBArchive(at: url)

        let lower = BookSearchEngine.search(query: "love", in: doc, archive: archive, maxResults: 50)
        let upper = BookSearchEngine.search(query: "LOVE", in: doc, archive: archive, maxResults: 50)

        #expect(lower.count == upper.count, "Case should not affect result count")
    }

    @Test("Empty query returns no results")
    func searchEmpty() throws {
        guard let url = Self.findEPUB(containing: "First Love") else { return }

        let doc = try EPUBParser.parse(at: url)
        let archive = try EPUBArchive(at: url)

        let results = BookSearchEngine.search(query: "", in: doc, archive: archive)
        #expect(results.isEmpty)
    }
}
