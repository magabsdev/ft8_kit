import Foundation

struct RealWAVFastCancellationProfile: Codable, Equatable, Sendable {
    let radiusBins: Int
    let strength: Float
    let timeTaperFloor: Float

    var label: String {
        "r\(radiusBins)-s\(String(format: "%.2f", strength))-t\(String(format: "%.2f", timeTaperFloor))"
    }
}

struct RealWAVFastCancellationScore: Codable, Equatable, Sendable {
    let profile: RealWAVFastCancellationProfile
    let affectedBins: Int
    let reductionFraction: Double
    let residualSignalPowerDB: Double
    let residualNeighbourPowerDB: Double
    let suppressionDB: Double
    let collateralPenaltyDB: Double
    let objective: Double
}

struct RealWAVFastCancellationReport: Codable, Equatable, Sendable {
    let recording: String
    let cancelledMessage: String
    let cancelledFrequencyHz: Float
    let cancelledStartTime: Double
    let selectedProfile: RealWAVFastCancellationProfile
    let scores: [RealWAVFastCancellationScore]
    let residualCandidates: Int
    let residualCRCPassed: Int
    let residualMessages: [String]
    let cancelledMessageReappeared: Bool
    let residualElapsedSeconds: Double
}
