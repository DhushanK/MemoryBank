import Foundation

public final class MemoryBank: @unchecked Sendable {
    public let index = EmbeddingIndex()
    public let shortTerm = ShortTermBuffer(capacityWords: 500)

    public init() {}

    public func seedFromJSON(at url: URL) throws {
        let data = try Data(contentsOf: url)
        let docs = try JSONDecoder().decode([ContextDocument].self, from: data)
        index.load(docs)
    }

    public func seed(_ documents: [ContextDocument]) {
        index.load(documents)
    }

    public func retrieve(for noisyText: String, topK: Int = 3) -> [RetrievalHit] {
        let query = [noisyText, shortTerm.text].filter { !$0.isEmpty }.joined(separator: "\n")
        return index.search(query: query, topK: topK)
    }
}
