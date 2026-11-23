import Foundation

public struct ContextDocument: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var source: String
    public var title: String
    public var body: String
    public var weight: Double

    public init(
        id: UUID = UUID(),
        source: String,
        title: String,
        body: String,
        weight: Double = 1.0
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.body = body
        self.weight = weight
    }

    public var citation: String { "\(source): \(title)" }
}
