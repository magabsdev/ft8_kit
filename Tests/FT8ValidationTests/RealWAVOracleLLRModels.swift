import Foundation

struct RealWAVOracleLLRBitRow: Codable, Equatable, Sendable {
    let referenceIndex: Int
    let referenceMessage: String
    let bitIndex: Int
    let dataSymbolOrdinal: Int
    let symbolIndex: Int
    let bitWithinSymbol: Int
    let expectedTone: Int
    let winningTone: Int
    let expectedBit: UInt8
    let hardBit: UInt8
    let hardBitCorrect: Bool
    let rawLLR: Float
    let normalizedLLR: Float
    let absoluteRawLLR: Float
    let symbolConfidence: Float
    let expectedToneMetricDB: Float
    let winningToneMetricDB: Float
    let runnerUpToneMetricDB: Float
    let toneMetricsDB: [Float]
}

struct RealWAVOracleLLRReferenceSummary: Codable, Equatable, Sendable {
    let referenceIndex: Int
    let referenceMessage: String
    let referenceTimeOffset: Double
    let referenceFrequencyHz: Int
    let bitCount: Int
    let correctHardBits: Int
    let incorrectHardBits: Int
    let bitAccuracy: Double
    let correctDataSymbols: Int
    let dataSymbolCount: Int
    let dataSymbolAccuracy: Double
    let averageAbsoluteRawLLR: Double
    let averageSymbolConfidence: Double
    let ldpcParityPassed: Bool
    let ldpcCRCPassed: Bool
    let ldpcSyndromeWeight: Int
    let ldpcIterations: Int
}

struct RealWAVOracleLLRReport: Codable, Equatable, Sendable {
    let recording: String
    let generatedAt: Date
    let references: [RealWAVOracleLLRReferenceSummary]
    let bits: [RealWAVOracleLLRBitRow]

    var crcPassingReferences: Int {
        references.count { $0.ldpcCRCPassed }
    }

    var parityPassingReferences: Int {
        references.count { $0.ldpcParityPassed }
    }
}
