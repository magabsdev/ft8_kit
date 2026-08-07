import Foundation

struct RealWAVCancellerCandidateSummary: Codable, Equatable, Sendable {
    let startTime: Double
    let frequencyHz: Float
    let confidence: Float
    let syncScore: Float
    let snrDB: Float
}

struct RealWAVCancellerCellDifference: Codable, Equatable, Sendable {
    let frameIndex: Int
    let bin: Int
    let originalMagnitude: Float
    let experimentalMagnitude: Float
    let productionMagnitude: Float
    let absoluteDifference: Float
}

struct RealWAVCancellerEquivalenceReport: Codable, Equatable, Sendable {
    let recording: String
    let decodedMessage: String
    let decodedStartTime: Double
    let decodedFrequencyHz: Float
    let experimentalAffectedBins: Int
    let productionAffectedBins: Int
    let commonAffectedBins: Int
    let experimentalOnlyBins: Int
    let productionOnlyBins: Int
    let maximumMagnitudeDifference: Float
    let meanMagnitudeDifference: Double
    let rmsMagnitudeDifference: Double
    let relativeRMSError: Double
    let experimentalReductionFraction: Double
    let productionReductionFraction: Double
    let maximumNoiseFloorDifferenceDB: Float
    let meanNoiseFloorDifferenceDB: Double
    let experimentalCandidates: [RealWAVCancellerCandidateSummary]
    let productionCandidates: [RealWAVCancellerCandidateSummary]
    let largestCellDifferences: [RealWAVCancellerCellDifference]
}
