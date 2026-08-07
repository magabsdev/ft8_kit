import Foundation

struct RealWAVToneMetricRow: Codable, Equatable, Sendable {
    let candidateIndex: Int
    let referenceMessage: String
    let dataSymbolIndex: Int
    let receivedSymbolIndex: Int
    let symbolStartTime: Double
    let symbolStartSample: Int
    let frameTime: Double
    let expectedTone: UInt8
    let detectedTone: UInt8
    let winningTone: UInt8
    let runnerUpTone: UInt8
    let toneMetricsDB: [Float]
    let expectedToneMetricDB: Float
    let detectedToneMetricDB: Float
    let winningMetricDB: Float
    let runnerUpMetricDB: Float
    let winningMarginDB: Float
    let expectedToneBin: Int
    let winningToneBin: Int
    let expectedBinFrequencyHz: Float
    let winningBinFrequencyHz: Float
    let expectedTargetFrequencyHz: Float
    let winningTargetFrequencyHz: Float
}

struct RealWAVToneMetricReport: Codable, Equatable, Sendable {
    let recording: String
    let generatedAt: Date
    let sampleRate: Int
    let rows: [RealWAVToneMetricRow]

    var candidateCount: Int { Set(rows.map(\.candidateIndex)).count }
    var symbolCount: Int { rows.count }
    var expectedToneWins: Int { rows.count { $0.expectedTone == $0.winningTone } }
    var expectedToneLosses: Int { symbolCount - expectedToneWins }
}
