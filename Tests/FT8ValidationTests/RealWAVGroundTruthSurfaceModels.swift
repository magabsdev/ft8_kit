import Foundation

struct RealWAVGroundTruthSurfaceConfiguration: Codable, Equatable, Sendable {
    var timeRadiusSeconds: Double = 0.40
    var timeStepSeconds: Double = 0.02
    var frequencyRadiusHz: Double = 50.0
    var frequencyStepHz: Double = 3.125
    var finalistsPerReference: Int = 12

    static let `default` = Self()
}

struct RealWAVGroundTruthSurfacePoint: Codable, Equatable, Sendable {
    let referenceIndex: Int
    let referenceMessage: String
    let seedCandidateIndex: Int
    let trialStartTime: Double
    let trialFrequencyHz: Float
    let timeOffsetFromSeed: Double
    let frequencyOffsetFromSeedHz: Double
    let costasCorrect: Int
    let costasTotal: Int
    let costasMarginDB: Float
    let costasExpectedMetricDB: Float
}

struct RealWAVGroundTruthRefinedHypothesis: Codable, Equatable, Sendable {
    let referenceIndex: Int
    let referenceMessage: String
    let seedCandidateIndex: Int
    let seedStartTime: Double
    let seedFrequencyHz: Float
    let referenceTimeOffset: Double
    let referenceFrequencyHz: Int
    let refinedStartTime: Double
    let refinedFrequencyHz: Float
    let refinedTimeDelta: Double
    let refinedFrequencyDeltaHz: Double
    let costasCorrect: Int
    let costasTotal: Int
    let allSymbolsCorrect: Int
    let allSymbolsTotal: Int
    let dataSymbolsCorrect: Int
    let dataSymbolsTotal: Int
    let aggregateMarginDB: Float
    let aggregateExpectedMetricDB: Float
}

struct RealWAVGroundTruthSurfaceReport: Codable, Equatable, Sendable {
    let recording: String
    let generatedAt: Date
    let configuration: RealWAVGroundTruthSurfaceConfiguration
    let surfaces: [RealWAVGroundTruthSurfacePoint]
    let refinedHypotheses: [RealWAVGroundTruthRefinedHypothesis]

    var referenceCount: Int {
        Set(refinedHypotheses.map(\.referenceIndex)).count
    }
}
