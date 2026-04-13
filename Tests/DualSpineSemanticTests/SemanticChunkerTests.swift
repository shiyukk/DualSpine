import Foundation
import Testing
@testable import DualSpineSemantic

@Suite("Semantic Chunker")
struct SemanticChunkerTests {

    @Test("Chunks simple XHTML with paragraphs")
    func simpleParagraphs() throws {
        let xhtml = """
        <html>
        <body>
          <h1>Chapter 1</h1>
          <p>This is the first paragraph with enough text to form a meaningful chunk for semantic analysis.</p>
          <p>This is the second paragraph that continues the narrative with additional detail and context.</p>
          <p>This is the third paragraph that wraps up the introduction to the chapter.</p>
        </body>
        </html>
        """

        let chunks = try SemanticChunker.chunkXHTML(
            xhtml,
            spineIndex: 0,
            spineHref: "chapter1.xhtml",
            targetTokens: 512
        )

        #expect(!chunks.isEmpty)
        // Short paragraphs should be merged since they're well under 512 tokens
        #expect(chunks.count <= 2)
    }

    @Test("Preserves heading ancestry")
    func headingAncestry() throws {
        let xhtml = """
        <html>
        <body>
          <h1>Part I: The Beginning</h1>
          <h2>Chapter 1: Introduction</h2>
          <p>This paragraph should inherit headings as ancestry for context.</p>
        </body>
        </html>
        """

        let chunks = try SemanticChunker.chunkXHTML(
            xhtml,
            spineIndex: 0,
            spineHref: "chapter1.xhtml",
            targetTokens: 512
        )

        let paragraphChunk = chunks.first(where: {
            $0.text.contains("inherit headings")
        })
        #expect(paragraphChunk != nil)
        #expect(paragraphChunk?.headingAncestry.contains("Part I: The Beginning") == true)
        #expect(paragraphChunk?.headingAncestry.contains("Chapter 1: Introduction") == true)
    }

    @Test("Keeps blockquotes as single units")
    func blockquoteIntegrity() throws {
        let xhtml = """
        <html>
        <body>
          <p>He then quoted the famous passage:</p>
          <blockquote>To be or not to be, that is the question. Whether tis nobler in the mind to suffer the slings and arrows of outrageous fortune, or to take arms against a sea of troubles.</blockquote>
          <p>The audience was moved.</p>
        </body>
        </html>
        """

        let chunks = try SemanticChunker.chunkXHTML(
            xhtml,
            spineIndex: 0,
            spineHref: "chapter1.xhtml",
            targetTokens: 512
        )

        let hasBlockquote = chunks.contains { $0.blockType == .blockquote }
        #expect(hasBlockquote)
    }

    @Test("Skips script and style elements")
    func skipsNonContent() throws {
        let xhtml = """
        <html>
        <head><style>body { color: red; }</style></head>
        <body>
          <script>alert('hello');</script>
          <p>Real content here.</p>
          <nav>Navigation links</nav>
        </body>
        </html>
        """

        let chunks = try SemanticChunker.chunkXHTML(
            xhtml,
            spineIndex: 0,
            spineHref: "chapter1.xhtml",
            targetTokens: 512
        )

        let allText = chunks.map(\.text).joined()
        #expect(!allText.contains("alert"))
        #expect(allText.contains("Real content"))
    }

    @Test("Assigns sequential global indices")
    func globalIndexing() throws {
        let xhtml = """
        <html>
        <body>
          <h1>Title</h1>
          <p>First paragraph.</p>
          <p>Second paragraph.</p>
          <p>Third paragraph.</p>
        </body>
        </html>
        """

        let chunks = try SemanticChunker.chunkXHTML(
            xhtml,
            spineIndex: 0,
            spineHref: "chapter1.xhtml",
            targetTokens: 20, // Low target to prevent merging
            globalIndexStart: 10
        )

        for (i, chunk) in chunks.enumerated() {
            #expect(chunk.globalIndex == 10 + i)
        }
    }

    @Test("Token estimation is reasonable")
    func tokenEstimation() {
        let shortText = "Hello world"
        let longText = String(repeating: "word ", count: 100)

        let shortTokens = SemanticChunker.estimateTokens(shortText)
        let longTokens = SemanticChunker.estimateTokens(longText)

        #expect(shortTokens >= 2)
        #expect(shortTokens <= 5)
        #expect(longTokens >= 100)
        #expect(longTokens <= 200)
    }
}

@Suite("Local Vector Index")
struct LocalVectorIndexTests {

    @Test("Finds most similar vector")
    func topKSearch() {
        let vectors: [[Float]] = [
            [1.0, 0.0, 0.0],  // chunk 0: points along x-axis
            [0.0, 1.0, 0.0],  // chunk 1: points along y-axis
            [0.7, 0.7, 0.0],  // chunk 2: between x and y
        ]
        let ids = [UUID(), UUID(), UUID()]
        let index = LocalVectorIndex(vectors: vectors, chunkIDs: ids)

        // Query along x-axis — chunk 0 should be most similar
        let results = index.topK([1.0, 0.0, 0.0], k: 2)
        #expect(results.count == 2)
        #expect(results[0].chunkID == ids[0])
        #expect(results[0].score > 0.99)
    }

    @Test("Serialization roundtrip")
    func serializationRoundtrip() {
        let vectors: [[Float]] = [
            [0.1, 0.2, 0.3, 0.4],
            [0.5, 0.6, 0.7, 0.8],
        ]
        let ids = [UUID(), UUID()]
        let original = LocalVectorIndex(vectors: vectors, chunkIDs: ids)

        let data = original.serialize()
        let restored = LocalVectorIndex.deserialize(from: data)

        #expect(restored != nil)
        #expect(restored?.vectors.count == 2)
        #expect(restored?.chunkIDs == ids)
        #expect(restored?.dimension == 4)
    }

    @Test("Empty index returns empty results")
    func emptyIndex() {
        let index = LocalVectorIndex(vectors: [], chunkIDs: [])
        let results = index.topK([1.0, 0.0], k: 5)
        #expect(results.isEmpty)
    }
}

@Suite("Hybrid Retriever")
struct HybridRetrieverTests {

    @Test("BM25-only retrieval finds relevant chunks")
    func lexicalOnly() {
        let chunks = [
            SemanticChunk(
                spineIndex: 0, spineHref: "ch1.xhtml",
                blockType: .paragraph,
                text: "Anna walked through the garden thinking about her marriage",
                estimatedTokens: 12, globalIndex: 0
            ),
            SemanticChunk(
                spineIndex: 0, spineHref: "ch1.xhtml",
                blockType: .paragraph,
                text: "The train arrived at the station in Moscow late that evening",
                estimatedTokens: 14, globalIndex: 1
            ),
            SemanticChunk(
                spineIndex: 1, spineHref: "ch2.xhtml",
                blockType: .paragraph,
                text: "Levin worked in the garden planting seeds for the harvest",
                estimatedTokens: 13, globalIndex: 2
            ),
        ]

        let results = HybridRetriever.retrieve(
            query: "garden",
            chunks: chunks,
            topK: 2
        )

        #expect(results.count == 2)
        // Both garden-containing chunks should rank higher
        let texts = results.map(\.chunk.text)
        #expect(texts.allSatisfy { $0.contains("garden") })
    }
}
