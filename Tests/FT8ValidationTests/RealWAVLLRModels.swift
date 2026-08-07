import Foundation

struct RealWAVLLRRow: Codable, Equatable, Sendable {
    let candidateIndex: Int
    let referenceMessage: String

    let globalBitIndex: Int
    let dataSymbolIndex: Int
    let receivedSymbolIndex: Int
    let bitIndexInSymbol: Int

    let expectedTone: UInt8
    let detectedTone: UInt8
    let winningTone: UInt8
    let runnerUpTone: UInt8

    let toneMetricsDB: [Float]
    let winningMetricDB: Float
    let runnerUpMetricDB: Float
    let winningMarginDB: Float

    let bestZeroMetricDB: Float
    let bestOneMetricDB: Float
    let rawMetricDifference: Float
    let recomputedLLR: Float
    let recordedLLR: Float
    let llrDelta: Float

    let expectedBit: UInt8
    let decodedBit: UInt8
    let llrHardBit: UInt8

    let llrSignMatchesExpected: Bool
    let decodedBitMatchesExpected: Bool
    let llrMagnitude: Float
}

struct RealWAVLLRHistogramBucket: Codable, Equatable, Sendable {
    let lowerBound: Float?
    let upperBound: Float?
    let count: Int
}

struct RealWAVLLRSummary: Codable, Equatable, Sendable {
    let bitCount: Int
    let correctDecodedBits: Int
    let incorrectDecodedBits: Int
    let correctLLRSigns: Int
    let incorrectLLRSigns: Int

    let averageAbsoluteLLR: Float
    let averageAbsoluteLLRCorrectBits: Float
    let averageAbsoluteLLRIncorrectBits: Float

    let below025Count: Int
    let below050Count: Int
    let below100Count: Int

    let wrongSignPercentage: Double
    let below025Percentage: Double
    let below050Percentage: Double
    let below100Percentage: Double

    let maximumAbsoluteRecomputedVsRecordedDelta: Float
    let histogram: [RealWAVLLRHistogramBucket]
}

struct RealWAVLLRReport: Codable, Equatable, Sendable {
    let recording: String
    let generatedAt: Date
    let rows: [RealWAVLLRRow]
    let summary: RealWAVLLRSummary

    var candidateCount: Int {
        Set(rows.map(\.candidateIndex)).count
    }
}
