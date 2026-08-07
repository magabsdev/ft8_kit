import Foundation
import FT8Decoder
import FT8DSP
import FT8Encoder
@testable import FT8Validation

enum RealWAVTimingCalibrationError: Error, Equatable {
    case invalidConfiguration
    case invalidExpectedToneCount(Int)
}

enum RealWAVTimingCalibrationDiagnostics {
    static func buildReport(
        recording: String,
        spectrogram: Spectrogram,
        extractor: SoftSymbolExtractor,
        references: [WSJTXExpectedDecode],
        configuration:
            RealWAVTimingCalibrationConfiguration = .init(),
        generatedAt: Date = Date()
    ) throws -> RealWAVTimingCalibrationReport {
        let corrections = configuration.corrections

        guard !corrections.isEmpty else {
            throw RealWAVTimingCalibrationError
                .invalidConfiguration
        }

        var allPoints: [RealWAVTimingCalibrationPoint] = []
        var results:
            [RealWAVTimingCalibrationReferenceResult] = []

        for (referenceIndex, reference) in
            references.enumerated()
        {
            let protocolText = stripWSJTXAnnotation(
                from: reference.message
            )

            let expectedTones = try FT8Encoder.encode(
                text: protocolText
            )

            guard expectedTones.count == 79 else {
                throw RealWAVTimingCalibrationError
                    .invalidExpectedToneCount(
                        expectedTones.count
                    )
            }

            var referencePoints:
                [RealWAVTimingCalibrationPoint] = []
            referencePoints.reserveCapacity(
                corrections.count
            )

            for correction in corrections {
                let point = try score(
                    referenceIndex: referenceIndex,
                    referenceMessage: protocolText,
                    reference:
                        reference,
                    expectedTones:
                        expectedTones,
                    correction:
                        correction,
                    spectrogram:
                        spectrogram,
                    extractor:
                        extractor
                )

                referencePoints.append(point)
            }

            let best = referencePoints.max {
                isBetter($1, than: $0)
            }!

            let baseline =
                referencePoints.min {
                    abs($0.trialCorrectionSeconds)
                        < abs($1.trialCorrectionSeconds)
                }!

            results.append(
                RealWAVTimingCalibrationReferenceResult(
                    referenceIndex: referenceIndex,
                    referenceMessage: protocolText,
                    referenceTimeOffset:
                        reference.timeOffset,
                    referenceFrequencyHz:
                        reference.frequencyHz,
                    bestCorrectionSeconds:
                        best.trialCorrectionSeconds,
                    bestStartTime:
                        best.trialStartTime,
                    bestCorrectToneCount:
                        best.correctToneCount,
                    toneCount:
                        best.toneCount,
                    bestToneAccuracy:
                        best.toneAccuracy,
                    bestCorrectDataToneCount:
                        best.correctDataToneCount,
                    dataToneCount:
                        best.dataToneCount,
                    bestDataToneAccuracy:
                        best.dataToneAccuracy,
                    bestCorrectCostasToneCount:
                        best.correctCostasToneCount,
                    costasToneCount:
                        best.costasToneCount,
                    bestCostasToneAccuracy:
                        best.costasToneAccuracy,
                    bestMeanExpectedToneMarginDB:
                        best.meanExpectedToneMarginDB,
                    baselineCorrectToneCount:
                        baseline.correctToneCount,
                    baselineToneAccuracy:
                        baseline.toneAccuracy,
                    improvementInCorrectTones:
                        best.correctToneCount
                            - baseline.correctToneCount
                )
            )

            allPoints.append(
                contentsOf: referencePoints
            )
        }

        let bestCorrections =
            results.map(\.bestCorrectionSeconds)
                .sorted()

        let consensus =
            median(bestCorrections)

        let spread: Double
        if let first = bestCorrections.first,
           let last = bestCorrections.last {
            spread = last - first
        } else {
            spread = 0
        }

        return RealWAVTimingCalibrationReport(
            recording: recording,
            generatedAt: generatedAt,
            configuration: configuration,
            consensusCorrectionSeconds:
                consensus,
            correctionSpreadSeconds:
                spread,
            references: results,
            points: allPoints
        )
    }

    private static func score(
        referenceIndex: Int,
        referenceMessage: String,
        reference: WSJTXExpectedDecode,
        expectedTones: [UInt8],
        correction: Double,
        spectrogram: Spectrogram,
        extractor: SoftSymbolExtractor
    ) throws -> RealWAVTimingCalibrationPoint {
        let trialStart =
            reference.timeOffset + correction

        let candidate = FT8Candidate(
            startTime: trialStart,
            frequency: Float(reference.frequencyHz),
            driftHzPerSecond: 0,
            symbolOffset: 0,
            syncScore: 1,
            snrDB: Float(reference.snrDB),
            confidence: 1
        )

        var correct = 0
        var correctData = 0
        var correctCostas = 0
        var margins: [Double] = []
        margins.reserveCapacity(79)

        let dataSymbols =
            Set(FT8ToneMapping.dataSymbolIndices)

        for symbolIndex in 0..<79 {
            let metrics = try extractor.toneMetrics(
                symbolIndex: symbolIndex,
                spectrogram: spectrogram,
                candidate: candidate
            )

            let expectedTone =
                Int(expectedTones[symbolIndex])

            let winningTone =
                metrics.indices.max {
                    metrics[$0] < metrics[$1]
                } ?? 0

            let expectedMetric =
                metrics[expectedTone]

            let strongestOther =
                metrics.enumerated()
                    .filter {
                        $0.offset != expectedTone
                    }
                    .map(\.element)
                    .max()
                    ?? -Float.infinity

            let margin =
                Double(
                    expectedMetric - strongestOther
                )

            margins.append(margin)

            if winningTone == expectedTone {
                correct += 1

                if dataSymbols.contains(symbolIndex) {
                    correctData += 1
                } else {
                    correctCostas += 1
                }
            }
        }

        let dataCount =
            FT8ToneMapping.dataSymbolIndices.count
        let costasCount = 79 - dataCount

        return RealWAVTimingCalibrationPoint(
            referenceIndex: referenceIndex,
            referenceMessage: referenceMessage,
            referenceTimeOffset:
                reference.timeOffset,
            trialCorrectionSeconds: correction,
            trialStartTime: trialStart,
            frequencyHz: reference.frequencyHz,
            correctToneCount: correct,
            toneCount: 79,
            toneAccuracy:
                Double(correct) / 79.0,
            correctDataToneCount: correctData,
            dataToneCount: dataCount,
            dataToneAccuracy:
                Double(correctData)
                    / Double(dataCount),
            correctCostasToneCount: correctCostas,
            costasToneCount: costasCount,
            costasToneAccuracy:
                Double(correctCostas)
                    / Double(costasCount),
            meanExpectedToneMarginDB:
                margins.reduce(0, +)
                    / Double(margins.count),
            medianExpectedToneMarginDB:
                median(margins),
            positiveMarginCount:
                margins.count { $0 > 0 }
        )
    }

    private static func isBetter(
        _ lhs: RealWAVTimingCalibrationPoint,
        than rhs: RealWAVTimingCalibrationPoint
    ) -> Bool {
        if lhs.correctToneCount
            != rhs.correctToneCount {
            return lhs.correctToneCount
                > rhs.correctToneCount
        }

        if lhs.correctDataToneCount
            != rhs.correctDataToneCount {
            return lhs.correctDataToneCount
                > rhs.correctDataToneCount
        }

        if lhs.meanExpectedToneMarginDB
            != rhs.meanExpectedToneMarginDB {
            return lhs.meanExpectedToneMarginDB
                > rhs.meanExpectedToneMarginDB
        }

        return abs(lhs.trialCorrectionSeconds)
            < abs(rhs.trialCorrectionSeconds)
    }

    private static func median(
        _ values: [Double]
    ) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        let sorted = values.sorted()
        let middle = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (
                sorted[middle - 1]
                + sorted[middle]
            ) / 2
        }

        return sorted[middle]
    }

    private static func stripWSJTXAnnotation(
        from message: String
    ) -> String {
        let trimmed =
            message.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard let range = trimmed.range(
            of: #"\s{2,}"#,
            options: .regularExpression
        ) else {
            return trimmed
        }

        return String(
            trimmed[..<range.lowerBound]
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }
}
