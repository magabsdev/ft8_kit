import Foundation

struct RealWAVCancellationSweepProfile: Codable, Equatable, Sendable {
    let radiusBins: Int
    let strength: Float
    let timeTaperFloor: Float

    var label: String {
        "r\(radiusBins)-s\(String(format: "%.2f", strength))-t\(String(format: "%.2f", timeTaperFloor))"
    }
}

struct RealWAVCancellationSweepResult: Codable, Equatable, Sendable {
    let profile: RealWAVCancellationSweepProfile
    let affectedBins: Int
    let reductionFraction: Double
    let residualCandidates: Int
    let residualCRCPassed: Int
    let residualMessages: [String]
    let cancelledMessageReappeared: Bool
    let elapsedSeconds: Double
}

struct RealWAVCancellationSweepReport: Codable, Equatable, Sendable {
    let recording: String
    let cancelledMessage: String
    let cancelledFrequencyHz: Float
    let cancelledStartTime: Double
    let firstPassCRCPassed: Int
    let firstPassMessages: [String]
    let results: [RealWAVCancellationSweepResult]
}
