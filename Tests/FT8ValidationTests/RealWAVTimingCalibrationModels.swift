import Foundation

struct RealWAVTimingCalibrationConfiguration: Codable, Equatable, Sendable {
    let minimumCorrectionSeconds: Double
    let maximumCorrectionSeconds: Double
    let stepSeconds: Double

    init(
        minimumCorrectionSeconds: Double = -0.50,
        maximumCorrectionSeconds: Double = 0.50,
        stepSeconds: Double = 0.01
    ) {
        self.minimumCorrectionSeconds = minimumCorrectionSeconds
        self.maximumCorrectionSeconds = maximumCorrectionSeconds
        self.stepSeconds = stepSeconds
    }

    var corrections: [Double] {
        guard stepSeconds > 0,
              maximumCorrectionSeconds >= minimumCorrectionSeconds else {
            return []
        }

        let count = Int(
            ((maximumCorrectionSeconds - minimumCorrectionSeconds)
             / stepSeconds).rounded()
        )

        return (0...count).map {
            minimumCorrectionSeconds
                + Double($0) * stepSeconds
        }
    }
}

struct RealWAVTimingCalibrationPoint: Codable, Equatable, Sendable {
    let referenceIndex: Int
    let referenceMessage: String
    let referenceTimeOffset: Double
    let trialCorrectionSeconds: Double
    let trialStartTime: Double
    let frequencyHz: Int
    let correctToneCount: Int
    let toneCount: Int
    let toneAccuracy: Double
    let correctDataToneCount: Int
    let dataToneCount: Int
    let dataToneAccuracy: Double
    let correctCostasToneCount: Int
    let costasToneCount: Int
    let costasToneAccuracy: Double
    let meanExpectedToneMarginDB: Double
    let medianExpectedToneMarginDB: Double
    let positiveMarginCount: Int
}

struct RealWAVTimingCalibrationReferenceResult: Codable, Equatable, Sendable {
    let referenceIndex: Int
    let referenceMessage: String
    let referenceTimeOffset: Double
    let referenceFrequencyHz: Int
    let bestCorrectionSeconds: Double
    let bestStartTime: Double
    let bestCorrectToneCount: Int
    let toneCount: Int
    let bestToneAccuracy: Double
    let bestCorrectDataToneCount: Int
    let dataToneCount: Int
    let bestDataToneAccuracy: Double
    let bestCorrectCostasToneCount: Int
    let costasToneCount: Int
    let bestCostasToneAccuracy: Double
    let bestMeanExpectedToneMarginDB: Double
    let baselineCorrectToneCount: Int
    let baselineToneAccuracy: Double
    let improvementInCorrectTones: Int
}

struct RealWAVTimingCalibrationReport: Codable, Equatable, Sendable {
    let recording: String
    let generatedAt: Date
    let configuration: RealWAVTimingCalibrationConfiguration
    let consensusCorrectionSeconds: Double
    let correctionSpreadSeconds: Double
    let references: [RealWAVTimingCalibrationReferenceResult]
    let points: [RealWAVTimingCalibrationPoint]
}
