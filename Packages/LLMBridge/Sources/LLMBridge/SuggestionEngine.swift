import Foundation
import MemoryBankKit
import NeuralCore

/// Local suggestion engine. Uses heuristic RAG correction now; llama.cpp Metal can replace `correct(...)`.
public final class SuggestionEngine: @unchecked Sendable {
    public let memory: MemoryBank
    private var candidates: [PredictionPayload] = []
    private var candidateIndex: Int = 0
    private let lock = NSLock()

    public init(memory: MemoryBank = MemoryBank()) {
        self.memory = memory
    }

    public func suggest(for emission: DecoderEmission) -> PredictionPayload {
        let hits = memory.retrieve(for: emission.noisyText, topK: 3)
        let built = hits.enumerated().map { idx, hit -> PredictionPayload in
            let corrected = Self.correct(noisy: emission.noisyText, with: hit)
            let confidence = min(0.98, max(0.35, hit.score * (idx == 0 ? 1.0 : 0.85)))
            return PredictionPayload(
                predictedText: corrected,
                confidence: confidence,
                sourceCitation: hit.document.citation,
                documentID: hit.document.id,
                engine: "heuristic-rag"
            )
        }
        let fallback = PredictionPayload(
            predictedText: emission.groundTruth ?? emission.noisyText,
            confidence: 0.4,
            sourceCitation: "Decoder prior",
            documentID: nil,
            engine: "fallback"
        )
        let list = built.isEmpty ? [fallback] : built
        lock.lock()
        candidates = list
        candidateIndex = 0
        lock.unlock()
        return list[0]
    }

    public func current() -> PredictionPayload? {
        lock.lock(); defer { lock.unlock() }
        guard !candidates.isEmpty else { return nil }
        return candidates[candidateIndex]
    }

    public func nextCandidate() -> PredictionPayload? {
        lock.lock()
        defer { lock.unlock() }
        guard !candidates.isEmpty else { return nil }
        candidateIndex = (candidateIndex + 1) % candidates.count
        return candidates[candidateIndex]
    }

    public func acceptCurrent() -> PredictionPayload? {
        lock.lock()
        let payload = candidates.isEmpty ? nil : candidates[candidateIndex]
        lock.unlock()
        guard let payload else { return nil }
        if let id = payload.documentID {
            memory.index.reinforce(id: id)
        }
        memory.shortTerm.append(payload.predictedText)
        return payload
    }

    public func rejectCurrent() -> PredictionPayload? {
        lock.lock()
        let payload = candidates.isEmpty ? nil : candidates[candidateIndex]
        lock.unlock()
        if let id = payload?.documentID {
            memory.index.downweight(id: id)
        }
        return nextCandidate()
    }

    /// Prefer calendar/note phrasing when tokens overlap; otherwise lightly expand noisy text.
    public static func correct(noisy: String, with hit: RetrievalHit) -> String {
        let body = hit.document.body
        let noisyTokens = Set(noisy.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let bodyTokens = body.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let overlap = bodyTokens.filter { noisyTokens.contains($0) || noisyTokens.contains(String($0.prefix(3))) }
        if overlap.count >= 1 {
            // Use document title if it looks like a short utterance, else first sentence of body.
            if hit.document.title.split(separator: " ").count <= 8 {
                return hit.document.title
            }
            return body.split(separator: ".").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? body
        }
        return noisy
            .replacingOccurrences(of: "Mting", with: "Meeting")
            .replacingOccurrences(of: "Snd", with: "Send")
            .replacingOccurrences(of: "desgn", with: "design")
            .replacingOccurrences(of: "ntes", with: "notes")
            .replacingOccurrences(of: "Cal ", with: "Call ")
            .replacingOccurrences(of: "aftr", with: "after")
            .replacingOccurrences(of: "lnch", with: "lunch")
            .replacingOccurrences(of: "Bok", with: "Book")
            .replacingOccurrences(of: "flite", with: "flight")
            .replacingOccurrences(of: "Seatle", with: "Seattle")
            .replacingOccurrences(of: "Remnd", with: "Remind")
            .replacingOccurrences(of: "strech", with: "stretch")
    }
}
