import Foundation
import MemoryBankKit

public struct PredictionPayload: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let predictedText: String
    public let confidence: Double
    public let sourceCitation: String
    public let documentID: UUID?
    public let engine: String

    public init(
        id: UUID = UUID(),
        predictedText: String,
        confidence: Double,
        sourceCitation: String,
        documentID: UUID? = nil,
        engine: String
    ) {
        self.id = id
        self.predictedText = predictedText
        self.confidence = confidence
        self.sourceCitation = sourceCitation
        self.documentID = documentID
        self.engine = engine
    }
}
