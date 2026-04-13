import Foundation

/// Hybrid retrieval combining vector similarity (semantic) and BM25-like token overlap (lexical).
/// Uses Reciprocal Rank Fusion to merge results from both strategies.
public enum HybridRetriever {

    /// Retrieve the top-K most relevant chunks for a query using hybrid retrieval.
    ///
    /// - Parameters:
    ///   - query: The user's question or search text.
    ///   - chunks: All semantic chunks in the book.
    ///   - vectorIndex: Pre-built vector index for semantic search (optional — degrades to BM25-only).
    ///   - queryEmbedding: The query's embedding vector (required if vectorIndex is provided).
    ///   - topK: Number of results to return.
    ///   - rrf_k: Reciprocal Rank Fusion constant (default 60, standard value from literature).
    public static func retrieve(
        query: String,
        chunks: [SemanticChunk],
        vectorIndex: LocalVectorIndex? = nil,
        queryEmbedding: [Float]? = nil,
        topK: Int = 8,
        rrf_k: Int = 60
    ) -> [RetrievedChunk] {
        // Lexical retrieval (BM25-like token overlap)
        let lexicalResults = bm25Search(query: query, chunks: chunks, topK: topK * 2)

        // Semantic retrieval (vector similarity)
        var semanticResults: [LocalVectorIndex.SearchResult] = []
        if let vectorIndex, let embedding = queryEmbedding {
            semanticResults = vectorIndex.topK(embedding, k: topK * 2)
        }

        // Build chunk ID → index maps for both result sets
        let chunkByID = Dictionary(
            chunks.enumerated().map { ($1.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Reciprocal Rank Fusion
        var rrfScores: [UUID: Double] = [:]

        for (rank, result) in lexicalResults.enumerated() {
            let score = 1.0 / Double(rrf_k + rank + 1)
            rrfScores[result.chunkID, default: 0] += score
        }

        for (rank, result) in semanticResults.enumerated() {
            let score = 1.0 / Double(rrf_k + rank + 1)
            rrfScores[result.chunkID, default: 0] += score
        }

        // Sort by fused score and take top-K
        let sorted = rrfScores.sorted { $0.value > $1.value }.prefix(topK)

        return sorted.compactMap { (chunkID, score) in
            guard let chunkIndex = chunkByID[chunkID] else { return nil }
            let chunk = chunks[chunkIndex]
            return RetrievedChunk(chunk: chunk, score: score)
        }
    }

    // MARK: - BM25-Like Token Overlap

    /// Simple token-overlap scoring (analogous to BM25 but without corpus statistics).
    /// Fast and effective for single-document retrieval.
    private static func bm25Search(
        query: String,
        chunks: [SemanticChunk],
        topK: Int
    ) -> [LexicalResult] {
        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else { return [] }

        var results: [LexicalResult] = []

        for chunk in chunks {
            let chunkTokens = tokenize(chunk.text)
            guard !chunkTokens.isEmpty else { continue }

            // Count matching unique tokens
            let chunkTokenSet = Set(chunkTokens)
            let matchCount = queryTokens.filter { chunkTokenSet.contains($0) }.count

            // Normalize by query length for recall, chunk length for precision
            let score = Double(matchCount) / Double(queryTokens.count)
                * (1.0 / (1.0 + log(Double(chunkTokens.count))))

            if score > 0 {
                results.append(LexicalResult(chunkID: chunk.id, score: score))
            }
        }

        return results.sorted { $0.score > $1.score }.prefix(topK).map { $0 }
    }

    /// Tokenize text into lowercased words of 3+ characters (rough stopword filtering).
    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0.count >= 3 }
            .map(String.init)
    }

    // MARK: - Result Types

    public struct RetrievedChunk: Sendable {
        public let chunk: SemanticChunk
        /// Fused relevance score (higher is more relevant).
        public let score: Double
    }

    private struct LexicalResult {
        let chunkID: UUID
        let score: Double
    }
}
