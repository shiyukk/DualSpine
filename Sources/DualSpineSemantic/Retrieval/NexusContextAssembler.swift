import Foundation

/// Assembles the three-tier prompt context for LLM queries about a book.
///
/// **Tier 1: Book Repomap** (always included, ~500-1500 tokens)
/// Structural overview — TOC with summaries, global entities, classification.
///
/// **Tier 2: Retrieved Chunks** (query-dependent, ~2000-4000 tokens)
/// Top-K semantically relevant passages from hybrid retrieval.
///
/// **Tier 3: Local Context** (selection-dependent, ~500-1000 tokens)
/// Current paragraph and surrounding context from the reading position.
public enum NexusContextAssembler {

    /// The assembled context ready for prompt injection.
    public struct AssembledContext: Sendable {
        /// Tier 1: Structural overview.
        public let repomap: String
        /// Tier 2: Retrieved evidence passages.
        public let retrievedEvidence: String
        /// Tier 3: Current reading context.
        public let localContext: String?
        /// Combined token estimate for all tiers.
        public let estimatedTokens: Int

        /// Full context string ready for prompt insertion.
        public func combined() -> String {
            var parts: [String] = []

            parts.append("<book_repomap>\n\(repomap)\n</book_repomap>")

            if !retrievedEvidence.isEmpty {
                parts.append("<retrieved_evidence>\n\(retrievedEvidence)\n</retrieved_evidence>")
            }

            if let local = localContext, !local.isEmpty {
                parts.append("<current_context>\n\(local)\n</current_context>")
            }

            return parts.joined(separator: "\n\n")
        }
    }

    /// Assemble the full context for an LLM query.
    ///
    /// - Parameters:
    ///   - query: The user's question.
    ///   - repomap: The book's structural repomap.
    ///   - chunks: All semantic chunks for the book.
    ///   - vectorIndex: Vector index for semantic retrieval (optional).
    ///   - queryEmbedding: The query's embedding (optional).
    ///   - localContext: Text around the user's current reading position.
    ///   - maxRetrievedChunks: Maximum number of retrieved chunks to include.
    ///   - maxTotalTokens: Token budget for the assembled context.
    public static func assemble(
        query: String,
        repomap: BookRepomap,
        chunks: [SemanticChunk],
        vectorIndex: LocalVectorIndex? = nil,
        queryEmbedding: [Float]? = nil,
        localContext: String? = nil,
        maxRetrievedChunks: Int = 8,
        maxTotalTokens: Int = 6000
    ) -> AssembledContext {
        // Tier 1: Repomap (always included)
        let repomapText = repomap.promptSerialization()
        let repomapTokens = estimateTokens(repomapText)

        // Tier 3: Local context (included if available)
        let localTokens = localContext.map { estimateTokens($0) } ?? 0

        // Tier 2: Retrieved chunks (fill remaining budget)
        let retrievalBudget = maxTotalTokens - repomapTokens - localTokens
        let retrieved = HybridRetriever.retrieve(
            query: query,
            chunks: chunks,
            vectorIndex: vectorIndex,
            queryEmbedding: queryEmbedding,
            topK: maxRetrievedChunks
        )

        // Pack chunks into the budget
        var evidenceLines: [String] = []
        var usedTokens = 0

        for result in retrieved {
            let chunkTokens = result.chunk.estimatedTokens
            if usedTokens + chunkTokens > retrievalBudget { break }

            let ancestry = result.chunk.headingAncestry.joined(separator: " > ")
            let scoreStr = String(format: "%.3f", result.score)
            evidenceLines.append(
                "<chunk section=\"\(ancestry)\" relevance=\"\(scoreStr)\">\n\(result.chunk.text)\n</chunk>"
            )
            usedTokens += chunkTokens
        }

        let evidenceText = evidenceLines.joined(separator: "\n\n")

        return AssembledContext(
            repomap: repomapText,
            retrievedEvidence: evidenceText,
            localContext: localContext,
            estimatedTokens: repomapTokens + usedTokens + localTokens
        )
    }

    // MARK: - Token Estimation

    private static func estimateTokens(_ text: String) -> Int {
        let wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return max(Int(Double(wordCount) * 1.3), 1)
    }
}
