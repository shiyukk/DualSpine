import Foundation
import Accelerate

/// Brute-force cosine similarity vector index for book chunk embeddings.
///
/// At book scale (~5,000 chunks × 384 dimensions = 7.5MB), brute-force cosine
/// similarity with vDSP runs in ~2ms on A15. No need for ANN (FAISS, Annoy, etc.).
public struct LocalVectorIndex: Sendable {
    /// Flat embedding matrix: `vectors[i]` is the embedding for chunk `i`.
    public let vectors: [[Float]]

    /// Chunk IDs corresponding to each vector, in the same order.
    public let chunkIDs: [UUID]

    /// Embedding dimension (e.g. 384 for multilingual-e5-small).
    public let dimension: Int

    public init(vectors: [[Float]], chunkIDs: [UUID]) {
        precondition(vectors.count == chunkIDs.count,
                     "Vector count must match chunk ID count")
        self.vectors = vectors
        self.chunkIDs = chunkIDs
        self.dimension = vectors.first?.count ?? 0
    }

    /// Find the top-K most similar chunks to a query vector.
    /// Returns results sorted by descending cosine similarity.
    public func topK(_ query: [Float], k: Int = 8) -> [SearchResult] {
        guard !vectors.isEmpty else { return [] }

        precondition(query.count == dimension,
                     "Query dimension (\(query.count)) must match index dimension (\(dimension))")

        let queryNorm = l2Norm(query)
        guard queryNorm > 0 else { return [] }

        var scores: [(index: Int, score: Float)] = []
        scores.reserveCapacity(vectors.count)

        for (i, vector) in vectors.enumerated() {
            let similarity = cosineSimilarity(query, vector, queryNorm: queryNorm)
            scores.append((i, similarity))
        }

        // Partial sort for top-K (O(n + k log k) instead of O(n log n))
        let topK = scores.sorted { $0.score > $1.score }.prefix(k)

        return topK.map { item in
            SearchResult(chunkID: chunkIDs[item.index], score: item.score, index: item.index)
        }
    }

    /// Search result from a vector similarity query.
    public struct SearchResult: Sendable {
        public let chunkID: UUID
        /// Cosine similarity score (0.0–1.0 for normalized embeddings).
        public let score: Float
        /// Index into the chunk store.
        public let index: Int
    }

    // MARK: - Persistence

    /// Serialize to a flat binary format for disk storage.
    /// Format: [dimension: UInt32][count: UInt32][vectors: Float×dim×count][chunkIDs: UUID×count]
    public func serialize() -> Data {
        var data = Data()
        var dim = UInt32(dimension)
        var count = UInt32(vectors.count)
        data.append(Data(bytes: &dim, count: 4))
        data.append(Data(bytes: &count, count: 4))

        for vector in vectors {
            vector.withUnsafeBufferPointer { buf in
                data.append(Data(buffer: buf))
            }
        }

        for id in chunkIDs {
            let uuid = id.uuid
            withUnsafeBytes(of: uuid) { data.append(contentsOf: $0) }
        }

        return data
    }

    /// Deserialize from the flat binary format.
    public static func deserialize(from data: Data) -> LocalVectorIndex? {
        guard data.count >= 8 else { return nil }

        let dim = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        let count = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }

        let vectorBytes = Int(dim) * MemoryLayout<Float>.size
        let expectedSize = 8 + Int(count) * vectorBytes + Int(count) * 16
        guard data.count >= expectedSize else { return nil }

        var vectors: [[Float]] = []
        var offset = 8

        for _ in 0..<count {
            let vector = data[offset..<(offset + vectorBytes)].withUnsafeBytes { buf in
                Array(buf.bindMemory(to: Float.self))
            }
            vectors.append(vector)
            offset += vectorBytes
        }

        var chunkIDs: [UUID] = []
        for _ in 0..<count {
            let uuid = data[offset..<(offset + 16)].withUnsafeBytes { buf in
                buf.load(as: uuid_t.self)
            }
            chunkIDs.append(UUID(uuid: uuid))
            offset += 16
        }

        return LocalVectorIndex(vectors: vectors, chunkIDs: chunkIDs)
    }

    // MARK: - SIMD Math (Accelerate)

    private func cosineSimilarity(_ a: [Float], _ b: [Float], queryNorm: Float) -> Float {
        var dot: Float = 0
        var bNormSq: Float = 0

        a.withUnsafeBufferPointer { aBuf in
            b.withUnsafeBufferPointer { bBuf in
                vDSP_dotpr(aBuf.baseAddress!, 1, bBuf.baseAddress!, 1, &dot, vDSP_Length(a.count))
                vDSP_svesq(bBuf.baseAddress!, 1, &bNormSq, vDSP_Length(b.count))
            }
        }

        let bNorm = sqrt(bNormSq)
        guard bNorm > 0 else { return 0 }
        return dot / (queryNorm * bNorm)
    }

    private func l2Norm(_ v: [Float]) -> Float {
        var sumSq: Float = 0
        v.withUnsafeBufferPointer { buf in
            vDSP_svesq(buf.baseAddress!, 1, &sumSq, vDSP_Length(v.count))
        }
        return sqrt(sumSq)
    }
}
