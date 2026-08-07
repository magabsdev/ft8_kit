import Foundation

struct RealWAVTimingCorrectedDecodeReference: Codable, Equatable, Sendable {
    let referenceIndex: Int
    let referenceMessage: String
    let referenceTimeOffset: Double
    let correctedStartTime: Double
    let referenceFrequencyHz: Int

    let correctHardBits: Int
    let bitCount: Int
    let bitAccuracy: Double

    let correctDataSymbols: Int
    let dataSymbolCount: Int
    let dataSymbolAccuracy: Double

    let parityPassed: Bool
    let crcPassed: Bool
    let syndromeWeight: Int
    let iterations: Int
}

struct RealWAVTimingCorrectedDecodeReport: Codable, Equatable, Sendable {
    let recording: String
    let generatedAt: Date
    let timingCorrectionSeconds: Double
    let parityPassingReferences: Int
    let crcPassingReferences: Int
    let references: [RealWAVTimingCorrectedDecodeReference]
}
