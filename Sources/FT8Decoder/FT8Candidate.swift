import Foundation

public struct FT8Candidate: Equatable, Sendable {
    public let startTime: Double
    public let frequency: Float
    public let driftHzPerSecond: Float
    public let symbolOffset: Double
    public let syncScore: Float
    public let snrDB: Float
    public let confidence: Float

    public init(
        startTime: Double,
        frequency: Float,
        driftHzPerSecond: Float = 0,
        symbolOffset: Double = 0,
        syncScore: Float,
        snrDB: Float,
        confidence: Float
    ) {
        self.startTime = startTime
        self.frequency = frequency
        self.driftHzPerSecond = driftHzPerSecond
        self.symbolOffset = symbolOffset
        self.syncScore = syncScore
        self.snrDB = snrDB
        self.confidence = confidence
    }
}
