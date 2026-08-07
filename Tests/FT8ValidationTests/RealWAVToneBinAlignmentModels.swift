import Foundation

struct RealWAVToneBinSample: Codable, Equatable, Sendable {
    let tone: UInt8
    let requestedFrequencyHz: Float
    let fractionalBin: Float
    let roundedBin: Int
    let roundedBinFrequencyHz: Float
    let frequencyErrorHz: Float
    let neighbourhoodDB: [Float]
    let neighbourhoodOffsets: [Int]
}

struct RealWAVToneBinAlignmentRow: Codable, Equatable, Sendable {
    let candidateIndex: Int
    let referenceMessage: String
    let dataSymbolIndex: Int
    let receivedSymbolIndex: Int

    let expectedTone: UInt8
    let detectedTone: UInt8

    let candidateStartTime: Double
    let requestedSymbolTime: Double
    let selectedFrameIndex: Int
    let selectedFrameSampleOffset: Int
    let selectedFrameTime: Double
    let frameTimeErrorSeconds: Double
    let frameTimeErrorSamples: Double

    let candidateBaseFrequencyHz: Float
    let candidateDriftHzPerSecond: Float
    let elapsedSeconds: Float
    let appliedDriftHz: Float

    let binWidthHz: Float
    let toneSpacingHz: Float
    let tones: [RealWAVToneBinSample]
}

struct RealWAVToneBinAlignmentReport: Codable, Equatable, Sendable {
    let recording: String
    let generatedAt: Date
    let sampleRate: Float
    let fftSize: Int
    let hopSize: Int
    let rows: [RealWAVToneBinAlignmentRow]

    var candidateCount: Int {
        Set(rows.map(\.candidateIndex)).count
    }

    var symbolCount: Int {
        rows.count
    }

    var meanAbsoluteFrameTimeErrorSeconds: Double {
        guard !rows.isEmpty else { return 0 }
        return rows.reduce(0) {
            $0 + abs($1.frameTimeErrorSeconds)
        } / Double(rows.count)
    }

    var maximumAbsoluteFrameTimeErrorSeconds: Double {
        rows.map { abs($0.frameTimeErrorSeconds) }.max() ?? 0
    }

    var meanAbsoluteExpectedToneFrequencyErrorHz: Float {
        let values = rows.compactMap { row -> Float? in
            guard row.tones.indices.contains(Int(row.expectedTone)) else {
                return nil
            }
            return abs(row.tones[Int(row.expectedTone)].frequencyErrorHz)
        }

        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    var maximumAbsoluteExpectedToneFrequencyErrorHz: Float {
        rows.compactMap { row -> Float? in
            guard row.tones.indices.contains(Int(row.expectedTone)) else {
                return nil
            }
            return abs(row.tones[Int(row.expectedTone)].frequencyErrorHz)
        }.max() ?? 0
    }
}
