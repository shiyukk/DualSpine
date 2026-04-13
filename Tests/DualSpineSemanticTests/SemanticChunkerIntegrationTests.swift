import Foundation
import Testing
@testable import DualSpineCore
@testable import DualSpineSemantic

/// Integration tests for semantic chunking against real EPUB files.
@Suite("Semantic Chunking Integration")
struct SemanticChunkerIntegrationTests {

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
        return entries.first { $0.pathExtension == "epub" && $0.lastPathComponent.contains(substring) }
    }

    @Test("Chunk First Love into semantic blocks")
    func chunkFirstLove() throws {
        guard let url = Self.findEPUB(containing: "First Love") else {
            Issue.record("First Love EPUB not found")
            return
        }

        let doc = try EPUBParser.parse(at: url)
        let archive = try EPUBArchive(at: url)

        let chunkStore = try SemanticChunker.chunkDocument(
            doc,
            readContent: { archivePath in
                try archive.readString(at: archivePath)
            },
            flatTOC: doc.flatTableOfContents
        )

        print("📖 First Love — Semantic Chunks")
        print("  Total chunks: \(chunkStore.chunks.count)")
        print("  Total characters: \(chunkStore.totalCharacters)")
        print("  Total estimated tokens: \(chunkStore.totalEstimatedTokens)")

        // Print first 5 chunks
        for chunk in chunkStore.chunks.prefix(5) {
            print("  [\(chunk.globalIndex)] \(chunk.blockType.rawValue) (\(chunk.estimatedTokens) tokens)")
            print("    Ancestry: \(chunk.headingAncestry.joined(separator: " > "))")
            print("    Text: \(String(chunk.text.prefix(100)))...")
        }

        #expect(chunkStore.chunks.count > 10, "Should produce meaningful number of chunks")
        #expect(chunkStore.totalCharacters > 1000, "Should have substantial text")

        // Verify chunk types
        let types = Set(chunkStore.chunks.map(\.blockType))
        print("  Block types: \(types.map(\.rawValue).sorted())")
        #expect(types.contains(.paragraph) || types.contains(.mergedParagraphs),
                "Should contain paragraph-type chunks")
    }

    @Test("Chunk Measure of All Things — rich nonfiction TOC")
    func chunkMeasure() throws {
        guard let url = Self.findEPUB(containing: "Measure-of-All-Things") else {
            Issue.record("Measure EPUB not found")
            return
        }

        let doc = try EPUBParser.parse(at: url)
        let archive = try EPUBArchive(at: url)

        let chunkStore = try SemanticChunker.chunkDocument(
            doc,
            readContent: { archivePath in
                try archive.readString(at: archivePath)
            },
            flatTOC: doc.flatTableOfContents
        )

        print("\n📖 Measure of All Things — Semantic Chunks")
        print("  Total chunks: \(chunkStore.chunks.count)")
        print("  Total characters: \(chunkStore.totalCharacters)")
        print("  Total estimated tokens: \(chunkStore.totalEstimatedTokens)")

        // Check heading ancestry is populated
        let withAncestry = chunkStore.chunks.filter { !$0.headingAncestry.isEmpty }
        print("  Chunks with heading ancestry: \(withAncestry.count)/\(chunkStore.chunks.count)")

        #expect(chunkStore.chunks.count > 50, "Full nonfiction book should have many chunks")
        #expect(withAncestry.count > 10, "Most chunks should have heading ancestry")

        // Verify chunks are spread across spine items
        let spineIndices = Set(chunkStore.chunks.map(\.spineIndex))
        print("  Spine items covered: \(spineIndices.count)/\(doc.spineCount)")
        #expect(spineIndices.count > 5, "Chunks should span multiple spine items")
    }

    @Test("Chunk Chinese novel — CJK text handling")
    func chunkChinese() throws {
        guard let url = Self.findEPUB(containing: "一日情人") else {
            Issue.record("Chinese EPUB not found")
            return
        }

        let doc = try EPUBParser.parse(at: url)
        let archive = try EPUBArchive(at: url)

        let chunkStore = try SemanticChunker.chunkDocument(
            doc,
            readContent: { archivePath in
                try archive.readString(at: archivePath)
            },
            flatTOC: doc.flatTableOfContents
        )

        print("\n📖 一日情人 — Semantic Chunks")
        print("  Total chunks: \(chunkStore.chunks.count)")
        print("  Total characters: \(chunkStore.totalCharacters)")

        // Verify CJK text is preserved
        let hasCJK = chunkStore.chunks.contains { chunk in
            chunk.text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        }
        #expect(hasCJK, "Chunks should contain Chinese characters")
        #expect(chunkStore.chunks.count > 5, "Should produce meaningful chunks")
    }

    @Test("Hybrid retrieval on chunked book")
    func hybridRetrievalOnRealBook() throws {
        guard let url = Self.findEPUB(containing: "Measure-of-All-Things") else { return }

        let doc = try EPUBParser.parse(at: url)
        let archive = try EPUBArchive(at: url)

        let chunkStore = try SemanticChunker.chunkDocument(
            doc,
            readContent: { try archive.readString(at: $0) },
            flatTOC: doc.flatTableOfContents
        )

        // BM25-only retrieval (no vector index)
        let results = HybridRetriever.retrieve(
            query: "measurement of the earth meridian",
            chunks: chunkStore.chunks,
            topK: 5
        )

        print("\n📖 Measure — Retrieval for 'measurement of the earth meridian'")
        for result in results {
            let ancestry = result.chunk.headingAncestry.joined(separator: " > ")
            print("  [score=\(String(format: "%.4f", result.score))] \(ancestry)")
            print("    \(String(result.chunk.text.prefix(120)))...")
        }

        #expect(results.count > 0, "Should find relevant chunks")
        #expect(results.count <= 5, "Should respect topK limit")
    }
}
