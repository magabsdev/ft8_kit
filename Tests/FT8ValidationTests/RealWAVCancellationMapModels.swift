import Foundation

enum RealWAVCancellationImplementation: String, Codable, Sendable {
    case experimental
    case production
}

struct RealWAVCancellationTouch: Codable, Equatable, Sendable {
    let implementation: RealWAVCancellationImplementation
    let symbolIndex: Int
    let tone: UInt8
    let symbolStartTime: Double
    let frameIndex: Int
    let frameTime: Double
    let frameCentreTime: Double
    let frameTimingOffset: Double
    let toneFrequencyHz: Float
    let centreBin: Int
    let bin: Int
    let binOffset: Int
    let originalMagnitude: Float
    let originalDecibels: Float
    let frameNoiseFloorDB: Float
    let timeTaper: Float
    let frequencyWeight: Float
    let appliedStrength: Float
}

struct RealWAVCancellationSymbolMap: Codable, Equatable, Sendable {
    let symbolIndex: Int
    let tone: UInt8
    let symbolStartTime: Double
    let experimentalFrameIndices: [Int]
    let productionFrameIndices: [Int]
    let experimentalTouchCount: Int
    let productionTouchCount: Int
    let commonFrameCount: Int
    let experimentalOnlyFrameCount: Int
    let productionOnlyFrameCount: Int
    let productionToExperimentalTouchRatio: Double
}

struct RealWAVCancellationMapReport: Codable, Equatable, Sendable {
    let recording: String
    let decodedMessage: String
    let decodedStartTime: Double
    let decodedFrequencyHz: Float
    let symbolCount: Int
    let experimentalTouchCount: Int
    let productionTouchCount: Int
    let productionToExperimentalTouchRatio: Double
    let experimentalUniqueCells: Int
    let productionUniqueCells: Int
    let commonUniqueCells: Int
    let experimentalOnlyUniqueCells: Int
    let productionOnlyUniqueCells: Int
    let experimentalUniqueFrames: Int
    let productionUniqueFrames: Int
    let maximumProductionFramesPerSymbol: Int
    let meanProductionFramesPerSymbol: Double
    let symbols: [RealWAVCancellationSymbolMap]
    let experimentalTouches: [RealWAVCancellationTouch]
    let productionTouches: [RealWAVCancellationTouch]
}
