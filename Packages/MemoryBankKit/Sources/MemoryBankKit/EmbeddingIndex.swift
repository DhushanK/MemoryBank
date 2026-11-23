import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public struct RetrievalHit: Sendable, Equatable {
    public let document: ContextDocument
    public let score: Double
}

/// Local embedding index using NaturalLanguage when available, else hashed bag-of-words.
public final class EmbeddingIndex: @unchecked Sendable {
    private var docs: [ContextDocument] = []
    private var vectors: [[Double]] = []
    private let dimension = 128
    private let lock = NSLock()

#if canImport(NaturalLanguage)
    private let embedding = NLEmbedding.wordEmbedding(for: .english)
#endif

    public init() {}

    public var documents: [ContextDocument] {
        lock.lock(); defer { lock.unlock() }
        return docs
    }

    public func upsert(_ document: ContextDocument) {
        let vector = embed(document.body)
        lock.lock()
        if let idx = docs.firstIndex(where: { $0.id == document.id }) {
            docs[idx] = document
            vectors[idx] = vector
        } else {
            docs.append(document)
            vectors.append(vector)
        }
        lock.unlock()
    }

    public func load(_ documents: [ContextDocument]) {
        for doc in documents { upsert(doc) }
    }

    public func reinforce(id: UUID, factor: Double = 1.15) {
        lock.lock()
        if let idx = docs.firstIndex(where: { $0.id == id }) {
            docs[idx].weight *= factor
        }
        lock.unlock()
    }

    public func downweight(id: UUID, factor: Double = 0.85) {
        lock.lock()
        if let idx = docs.firstIndex(where: { $0.id == id }) {
            docs[idx].weight *= factor
        }
        lock.unlock()
    }

    public func search(query: String, topK: Int = 3) -> [RetrievalHit] {
        let q = embed(query)
        lock.lock()
        let snapshotDocs = docs
        let snapshotVecs = vectors
        lock.unlock()

        var hits: [RetrievalHit] = []
        for (doc, vec) in zip(snapshotDocs, snapshotVecs) {
            let score = cosine(q, vec) * doc.weight
            hits.append(RetrievalHit(document: doc, score: score))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(topK))
    }

    private func embed(_ text: String) -> [Double] {
#if canImport(NaturalLanguage)
        if let embedding {
            var acc = [Double](repeating: 0, count: dimension)
            let tokens = text.lowercased().split { !$0.isLetter && !$0.isNumber }
            var count = 0
            for token in tokens {
                if let v = embedding.vector(for: String(token)) {
                    for i in 0..<min(dimension, v.count) {
                        acc[i] += v[i]
                    }
                    count += 1
                }
            }
            if count > 0 {
                let inv = 1.0 / Double(count)
                return acc.map { $0 * inv }
            }
        }
#endif
        return hashedEmbed(text)
    }

    private func hashedEmbed(_ text: String) -> [Double] {
        var vec = [Double](repeating: 0, count: dimension)
        let tokens = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        for token in tokens {
            var hash: UInt64 = 5381
            for b in token.utf8 { hash = ((hash << 5) &+ hash) &+ UInt64(b) }
            let idx = Int(hash % UInt64(dimension))
            vec[idx] += 1
        }
        let norm = sqrt(vec.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return vec }
        return vec.map { $0 / norm }
    }

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<n {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = sqrt(na) * sqrt(nb)
        return denom > 0 ? dot / denom : 0
    }
}
