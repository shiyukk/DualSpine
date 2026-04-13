import Foundation
import Testing
@testable import DualSpineCore

/// Integration tests against real EPUB files in /books/.
/// These tests validate the parser against diverse real-world EPUBs.
@Suite("Real EPUB Integration")
struct EPUBIntegrationTests {

    // MARK: - File discovery (substring match to handle Unicode filenames)

    static let booksDir: URL = {
        let fileURL = URL(fileURLWithPath: #filePath)
        return fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("books")
    }()

    static func findEPUB(containing substring: String) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: booksDir, includingPropertiesForKeys: nil
        ) else { return nil }

        return entries.first { url in
            url.pathExtension == "epub" && url.lastPathComponent.contains(substring)
        }
    }

    static let allEPUBURLs: [URL] = {
        (try? FileManager.default.contentsOfDirectory(
            at: booksDir, includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "epub" } ?? []
    }()

    // MARK: - First Love (Turgenev) — Small classic, likely EPUB 2

    @Test("Parse First Love — metadata")
    func firstLoveMetadata() throws {
        guard let url = Self.findEPUB(containing: "First Love") else {
            Issue.record("First Love EPUB not found in \(Self.booksDir.path)")
            return
        }

        let doc = try EPUBParser.parse(at: url)
        print("📖 First Love")
        print("  Title: \(doc.title)")
        print("  Author: \(doc.author ?? "nil")")
        print("  Language: \(doc.language ?? "nil")")
        print("  Version: \(doc.package.version)")
        print("  Spine count: \(doc.spineCount)")
        print("  TOC entries: \(doc.flatTableOfContents.count)")
        print("  Content base: \"\(doc.contentBasePath)\"")

        #expect(!doc.title.isEmpty)
        #expect(doc.spineCount > 0)
    }

    @Test("Parse First Love — TOC structure")
    func firstLoveTOC() throws {
        guard let url = Self.findEPUB(containing: "First Love") else { return }

        let doc = try EPUBParser.parse(at: url)
        let flatTOC = doc.flatTableOfContents

        print("  TOC:")
        for entry in flatTOC.prefix(15) {
            print("    \(entry.displayTitle) → \(entry.href ?? "nil")")
        }

        #expect(!flatTOC.isEmpty, "TOC should have entries")
    }

    @Test("Parse First Love — full text extraction")
    func firstLoveText() throws {
        guard let url = Self.findEPUB(containing: "First Love") else { return }

        let text = try EPUBParser.extractFullText(at: url, maxCharacters: 5000)

        print("  Text length: \(text.count) chars")
        print("  First 200 chars: \(String(text.prefix(200)))")

        #expect(text.count > 100, "Should extract substantial text")
    }

    @Test("Parse First Love — cover image extraction")
    func firstLoveCover() throws {
        guard let url = Self.findEPUB(containing: "First Love") else { return }

        let coverData = try EPUBParser.extractCoverImage(at: url)
        print("  Cover image: \(coverData.map { "\($0.count) bytes" } ?? "none")")
        // Cover may or may not exist — just verify no crash
    }

    @Test("Parse First Love — all spine items resolve")
    func firstLoveSpineResolution() throws {
        guard let url = Self.findEPUB(containing: "First Love") else { return }

        let doc = try EPUBParser.parse(at: url)
        let resolved = doc.package.resolvedSpine

        print("  Resolved spine: \(resolved.count)/\(doc.spineCount)")
        for (i, (_, manifest)) in resolved.prefix(5).enumerated() {
            print("    [\(i)] \(manifest.href) (\(manifest.mediaType))")
        }

        #expect(resolved.count == doc.spineCount, "All spine items should resolve")
    }

    // MARK: - 一日情人 (Chinese novel) — Non-English, CJK content

    @Test("Parse Chinese novel — metadata and CJK text")
    func chineseNovelParse() throws {
        guard let url = Self.findEPUB(containing: "一日情人") else {
            Issue.record("Chinese EPUB not found")
            return
        }

        let doc = try EPUBParser.parse(at: url)
        print("\n📖 一日情人")
        print("  Title: \(doc.title)")
        print("  Author: \(doc.author ?? "nil")")
        print("  Language: \(doc.language ?? "nil")")
        print("  Version: \(doc.package.version)")
        print("  Spine count: \(doc.spineCount)")
        print("  TOC entries: \(doc.flatTableOfContents.count)")

        #expect(!doc.title.isEmpty)
        #expect(doc.spineCount > 0)

        // Verify CJK text extraction
        let text = try EPUBParser.extractFullText(at: url, maxCharacters: 2000)
        print("  Text length: \(text.count) chars")
        print("  First 200 chars: \(String(text.prefix(200)))")

        let hasCJK = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        #expect(hasCJK, "Chinese novel should contain CJK characters")
    }

    // MARK: - The Measure of All Things — Mid-size narrative nonfiction (EPUB 2)

    @Test("Parse Measure of All Things — metadata and TOC")
    func measureMetadata() throws {
        guard let url = Self.findEPUB(containing: "Measure-of-All-Things") else {
            Issue.record("Measure EPUB not found")
            return
        }

        let doc = try EPUBParser.parse(at: url)
        print("\n📖 The Measure of All Things")
        print("  Title: \(doc.title)")
        print("  Author: \(doc.author ?? "nil")")
        print("  Language: \(doc.language ?? "nil")")
        print("  Version: \(doc.package.version)")
        print("  Spine count: \(doc.spineCount)")
        print("  Manifest items: \(doc.package.manifest.count)")
        print("  TOC entries: \(doc.flatTableOfContents.count)")
        print("  Nav document: \(doc.package.navDocument?.href ?? "none")")
        print("  NCX href: \(doc.package.ncxHref ?? "none")")

        #expect(!doc.title.isEmpty)
        #expect(doc.spineCount > 0)
        #expect(doc.flatTableOfContents.count >= 10, "Nonfiction book should have rich TOC")

        print("  TOC:")
        for entry in doc.flatTableOfContents.prefix(20) {
            print("    \(entry.displayTitle)")
        }
    }

    @Test("Parse Measure of All Things — text extraction capped correctly")
    func measureTextExtraction() throws {
        guard let url = Self.findEPUB(containing: "Measure-of-All-Things") else { return }

        let text = try EPUBParser.extractFullText(at: url, maxCharacters: 50_000)
        print("  Full text: \(text.count) chars (capped at 50K)")

        #expect(text.count >= 1000, "Mid-size book should have substantial text")
        #expect(text.count <= 51_000, "Should be capped near limit")
    }

    // MARK: - Advanced Teleoperation (55MB academic) — Stress test

    @Test("Parse large academic EPUB — manifest and resource analysis")
    func largeAcademicParse() throws {
        guard let url = Self.findEPUB(containing: "Advanced Teleoperation") else {
            Issue.record("Large academic EPUB not found")
            return
        }

        let doc = try EPUBParser.parse(at: url)
        print("\n📖 Advanced Teleoperation (55MB)")
        print("  Title: \(doc.title)")
        print("  Author: \(doc.author ?? "nil")")
        print("  Language: \(doc.language ?? "nil")")
        print("  Version: \(doc.package.version)")
        print("  Spine count: \(doc.spineCount)")
        print("  Manifest items: \(doc.package.manifest.count)")
        print("  TOC entries: \(doc.flatTableOfContents.count)")

        let byType = Dictionary(grouping: doc.package.manifest.values, by: \.mediaType)
        print("  Resource types:")
        for (type, items) in byType.sorted(by: { $0.value.count > $1.value.count }).prefix(10) {
            print("    \(type): \(items.count)")
        }

        #expect(!doc.title.isEmpty)
        #expect(doc.spineCount > 0)
        #expect(doc.package.manifest.count > 10, "Academic EPUB should have many resources")
    }

    // MARK: - Developmental Organization (35MB academic, EPUB 3)

    @Test("Parse Developmental Organization — EPUB 3 with many images")
    func devOrgParse() throws {
        guard let url = Self.findEPUB(containing: "Developmental Organization") else {
            Issue.record("DevOrg EPUB not found")
            return
        }

        let doc = try EPUBParser.parse(at: url)
        print("\n📖 Developmental Organization (35MB)")
        print("  Title: \(doc.title)")
        print("  Author: \(doc.author ?? "nil")")
        print("  Language: \(doc.language ?? "nil")")
        print("  Version: \(doc.package.version)")
        print("  Spine count: \(doc.spineCount)")
        print("  Manifest items: \(doc.package.manifest.count)")
        print("  TOC entries: \(doc.flatTableOfContents.count)")

        #expect(!doc.title.isEmpty)
        #expect(doc.spineCount > 0)
    }

    // MARK: - Cross-cutting validation (all EPUBs)

    @Test("All EPUBs — spine items fully resolve against manifest")
    func allSpineResolves() throws {
        for url in Self.allEPUBURLs {
            let doc = try EPUBParser.parse(at: url)
            let resolved = doc.package.resolvedSpine

            #expect(
                resolved.count == doc.spineCount,
                "[\(doc.title)] \(resolved.count)/\(doc.spineCount) spine items resolved"
            )
        }
    }

    @Test("All EPUBs — reading order hrefs are non-empty")
    func allReadingOrderValid() throws {
        for url in Self.allEPUBURLs {
            let doc = try EPUBParser.parse(at: url)

            for href in doc.readingOrderArchivePaths {
                #expect(!href.isEmpty, "[\(doc.title)] empty reading order href")
            }
        }
    }

    @Test("All EPUBs — first spine items are readable from archive")
    func allSpineItemsReadable() throws {
        for url in Self.allEPUBURLs {
            let doc = try EPUBParser.parse(at: url)
            let archive = try EPUBArchive(at: url)

            for path in doc.readingOrderArchivePaths.prefix(3) {
                let exists = archive.containsEntry(at: path)
                #expect(exists, "[\(doc.title)] spine resource missing: \(path)")

                if exists {
                    let content = try archive.readString(at: path)
                    #expect(content.count > 10, "[\(doc.title)] spine resource too small: \(path)")
                }
            }
        }
    }

    @Test("All EPUBs — text extraction produces non-empty output")
    func allTextExtraction() throws {
        for url in Self.allEPUBURLs {
            let text = try EPUBParser.extractFullText(at: url, maxCharacters: 1000)
            let title = (try? EPUBParser.parseMetadata(at: url).0.title) ?? url.lastPathComponent

            #expect(text.count > 50, "[\(title)] text extraction too short: \(text.count) chars")
        }
    }
}
