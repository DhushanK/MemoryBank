import Foundation

public struct DecoderEmission: Sendable, Equatable {
    public let noisyText: String
    public let groundTruth: String?
    public let hostTimeNs: UInt64
    public let confidence: Double

    public init(noisyText: String, groundTruth: String?, hostTimeNs: UInt64, confidence: Double) {
        self.noisyText = noisyText
        self.groundTruth = groundTruth
        self.hostTimeNs = hostTimeNs
        self.confidence = confidence
    }
}

/// Maps spike-rate features into intentionally noisy text using a confusion model.
public final class NoisyDecoder: @unchecked Sendable {
    private let phrases: [(truth: String, noisy: String)]
    private var cursor: Int = 0
    private let lock = NSLock()

    public init(phrases: [(truth: String, noisy: String)] = NoisyDecoder.defaultPhrases) {
        self.phrases = phrases.isEmpty ? NoisyDecoder.defaultPhrases : phrases
    }

    public static let defaultPhrases: [(truth: String, noisy: String)] = [
        ("Meeting at 4", "Mting a 4"),
        ("Send the design notes", "Snd the desgn ntes"),
        ("Call mom after lunch", "Cal mom aftr lnch"),
        ("Book a flight to Seattle", "Bok a flite to Seatle"),
        ("Remind me to stretch", "Remnd me to strech")
    ]

    public func decode(rates: [Float], hostTimeNs: UInt64) -> DecoderEmission {
        lock.lock()
        defer { lock.unlock() }
        let energy = rates.reduce(0) { $0 + abs($1) }
        let idx: Int
        if energy < 1e-4 {
            idx = cursor % phrases.count
        } else {
            let hash = rates.enumerated().reduce(0) { acc, pair in
                acc &+ Int(pair.element * 1000) &+ pair.offset * 17
            }
            idx = abs(hash) % phrases.count
        }
        cursor += 1
        let phrase = phrases[idx]
        let confidence = min(0.95, max(0.2, Double(energy)))
        return DecoderEmission(
            noisyText: phrase.noisy,
            groundTruth: phrase.truth,
            hostTimeNs: hostTimeNs,
            confidence: confidence
        )
    }

    /// Apply a simple character-confusion noise model to arbitrary ground truth.
    public static func corrupt(_ text: String, seed: UInt64) -> String {
        var rng = SeededGenerator(seed: seed)
        let drops: Set<Character> = ["e", "a", "i", "o", "u"]
        return String(text.map { ch in
            if drops.contains(Character(ch.lowercased())) && Int.random(in: 0...2, using: &rng) == 0 {
                return ""
            }
            if ch.isLetter && Int.random(in: 0...8, using: &rng) == 0 {
                return String(Character(UnicodeScalar(Int.random(in: 97...122, using: &rng))!))
            }
            return String(ch)
        }.joined())
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
