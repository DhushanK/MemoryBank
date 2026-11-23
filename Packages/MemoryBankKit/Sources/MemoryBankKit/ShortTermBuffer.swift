import Foundation

/// Rolling text buffer of the last N words of committed conversation.
public final class ShortTermBuffer: @unchecked Sendable {
    public let capacityWords: Int
    private var words: [String] = []
    private let lock = NSLock()

    public init(capacityWords: Int = 500) {
        self.capacityWords = capacityWords
    }

    public var text: String {
        lock.lock(); defer { lock.unlock() }
        return words.joined(separator: " ")
    }

    public func append(_ string: String) {
        let incoming = string.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        lock.lock()
        words.append(contentsOf: incoming)
        if words.count > capacityWords {
            words.removeFirst(words.count - capacityWords)
        }
        lock.unlock()
    }

    public func clear() {
        lock.lock()
        words.removeAll()
        lock.unlock()
    }
}
