import Foundation
import FT8Decoder
import FT8DSP
import FT8Encoder
import FT8Protocol
@testable import FT8Validation

enum RealWAVGroundTruthSurfaceError: Error, Equatable {
    case noCandidateForReference(Int)
    case invalidToneCount(Int)
    case invalidMetricCount(Int)
}

enum RealWAVGroundTruthSurfaceDiagnostics {
    static func buildReport(
        recording: String,
        spectrogram: Spectrogram,
        extractor: SoftSymbolExtractor,
        synchronizer: FT8Synchronizer,
        records: [FT8PipelineRecord],
        references: [WSJTXExpectedDecode],
        associationReport: RealWAVReferenceAssociationReport,
        configuration: RealWAVGroundTruthSurfaceConfiguration = .default,
        generatedAt: Date = Date()
    ) throws -> RealWAVGroundTruthSurfaceReport {
        let foundCandidates = try synchronizer.search(in: spectrogram)
        let candidateByRecordIndex = mapCandidates(
            records: records,
            foundCandidates: foundCandidates
        )

        var surfaceRows: [RealWAVGroundTruthSurfacePoint] = []
        var refinedRows: [RealWAVGroundTruthRefinedHypothesis] = []

        for (referenceIndex, reference) in references.enumerated() {
            guard let seedDistance = nearestDistance(
                for: referenceIndex,
                in: associationReport
            ),
            let seed = candidateByRecordIndex[seedDistance.candidateIndex] else {
                throw RealWAVGroundTruthSurfaceError.noCandidateForReference(
                    referenceIndex
                )
            }

            let expectedTones = try FT8Encoder.encode(
                protocolMessage(reference.message)
            )

            guard expectedTones.count == 79 else {
                throw RealWAVGroundTruthSurfaceError.invalidToneCount(
                    expectedTones.count
                )
            }

            let coarse = try surface(
                referenceIndex: referenceIndex,
                reference: reference,
                seedCandidateIndex: seedDistance.candidateIndex,
                seed: seed,
                expectedTones: expectedTones,
                spectrogram: spectrogram,
                extractor: extractor,
                configuration: configuration
            )

            surfaceRows.append(contentsOf: coarse)

            let finalists = coarse.sorted(by: surfaceOrdering)
                .prefix(max(1, configuration.finalistsPerReference))

            var refinedForReference: [RealWAVGroundTruthRefinedHypothesis] = []
            refinedForReference.reserveCapacity(finalists.count)

            for finalist in finalists {
                let trialCandidate = candidate(
                    basedOn: seed,
                    startTime: finalist.trialStartTime,
                    frequency: finalist.trialFrequencyHz
                )

                refinedForReference.append(
                    try evaluateFullHypothesis(
                        referenceIndex: referenceIndex,
                        reference: reference,
                        seedCandidateIndex: seedDistance.candidateIndex,
                        seed: seed,
                        trial: trialCandidate,
                        expectedTones: expectedTones,
                        spectrogram: spectrogram,
                        extractor: extractor
                    )
                )
            }

            if let best = refinedForReference.sorted(
                by: refinedOrdering
            ).first {
                refinedRows.append(best)
            }
        }

        return RealWAVGroundTruthSurfaceReport(
            recording: recording,
            generatedAt: generatedAt,
            configuration: configuration,
            surfaces: surfaceRows,
            refinedHypotheses: refinedRows.sorted {
                $0.referenceIndex < $1.referenceIndex
            }
        )
    }

    private static let costasIndices: [Int] =
        Array(0..<7) + Array(36..<43) + Array(72..<79)

    private static let dataIndices: [Int] =
        (0..<79).filter { !costasIndices.contains($0) }

    private static func surface(
        referenceIndex: Int,
        reference: WSJTXExpectedDecode,
        seedCandidateIndex: Int,
        seed: FT8Candidate,
        expectedTones: [UInt8],
        spectrogram: Spectrogram,
        extractor: SoftSymbolExtractor,
        configuration: RealWAVGroundTruthSurfaceConfiguration
    ) throws -> [RealWAVGroundTruthSurfacePoint] {
        let timeOffsets = symmetricOffsets(
            radius: configuration.timeRadiusSeconds,
            step: configuration.timeStepSeconds
        )
        let frequencyOffsets = symmetricOffsets(
            radius: configuration.frequencyRadiusHz,
            step: configuration.frequencyStepHz
        )

        var rows: [RealWAVGroundTruthSurfacePoint] = []
        rows.reserveCapacity(timeOffsets.count * frequencyOffsets.count)

        for dt in timeOffsets {
            for df in frequencyOffsets {
                let trial = candidate(
                    basedOn: seed,
                    startTime: seed.startTime + dt,
                    frequency: seed.frequency + Float(df)
                )

                var correct = 0
                var margin: Float = 0
                var expectedMetric: Float = 0

                for symbolIndex in costasIndices {
                    let metrics = try extractor.toneMetrics(
                        symbolIndex: symbolIndex,
                        spectrogram: spectrogram,
                        candidate: trial
                    )

                    guard metrics.count == 8 else {
                        throw RealWAVGroundTruthSurfaceError.invalidMetricCount(
                            metrics.count
                        )
                    }

                    let expectedTone = Int(expectedTones[symbolIndex])
                    let winningTone = metrics.indices.max {
                        metrics[$0] < metrics[$1]
                    } ?? 0

                    if winningTone == expectedTone {
                        correct += 1
                    }

                    expectedMetric += metrics[expectedTone]

                    let bestOther = metrics.enumerated()
                        .filter { $0.offset != expectedTone }
                        .map(\.element)
                        .max() ?? metrics[expectedTone]

                    margin += metrics[expectedTone] - bestOther
                }

                rows.append(
                    RealWAVGroundTruthSurfacePoint(
                        referenceIndex: referenceIndex,
                        referenceMessage: reference.message,
                        seedCandidateIndex: seedCandidateIndex,
                        trialStartTime: trial.startTime,
                        trialFrequencyHz: trial.frequency,
                        timeOffsetFromSeed: dt,
                        frequencyOffsetFromSeedHz: df,
                        costasCorrect: correct,
                        costasTotal: costasIndices.count,
                        costasMarginDB: margin,
                        costasExpectedMetricDB: expectedMetric
                    )
                )
            }
        }

        return rows
    }

    private static func evaluateFullHypothesis(
        referenceIndex: Int,
        reference: WSJTXExpectedDecode,
        seedCandidateIndex: Int,
        seed: FT8Candidate,
        trial: FT8Candidate,
        expectedTones: [UInt8],
        spectrogram: Spectrogram,
        extractor: SoftSymbolExtractor
    ) throws -> RealWAVGroundTruthRefinedHypothesis {
        var allCorrect = 0
        var dataCorrect = 0
        var costasCorrect = 0
        var totalMargin: Float = 0
        var expectedMetric: Float = 0

        for symbolIndex in 0..<expectedTones.count {
            let metrics = try extractor.toneMetrics(
                symbolIndex: symbolIndex,
                spectrogram: spectrogram,
                candidate: trial
            )

            guard metrics.count == 8 else {
                throw RealWAVGroundTruthSurfaceError.invalidMetricCount(
                    metrics.count
                )
            }

            let expectedTone = Int(expectedTones[symbolIndex])
            let winner = metrics.indices.max {
                metrics[$0] < metrics[$1]
            } ?? 0

            if winner == expectedTone {
                allCorrect += 1
                if costasIndices.contains(symbolIndex) {
                    costasCorrect += 1
                } else {
                    dataCorrect += 1
                }
            }

            expectedMetric += metrics[expectedTone]

            let bestOther = metrics.enumerated()
                .filter { $0.offset != expectedTone }
                .map(\.element)
                .max() ?? metrics[expectedTone]

            totalMargin += metrics[expectedTone] - bestOther
        }

        return RealWAVGroundTruthRefinedHypothesis(
            referenceIndex: referenceIndex,
            referenceMessage: reference.message,
            seedCandidateIndex: seedCandidateIndex,
            seedStartTime: seed.startTime,
            seedFrequencyHz: seed.frequency,
            referenceTimeOffset: reference.timeOffset,
            referenceFrequencyHz: reference.frequencyHz,
            refinedStartTime: trial.startTime,
            refinedFrequencyHz: trial.frequency,
            refinedTimeDelta: abs(
                reference.timeOffset - trial.startTime
            ),
            refinedFrequencyDeltaHz: abs(
                Double(reference.frequencyHz)
                    - Double(trial.frequency)
            ),
            costasCorrect: costasCorrect,
            costasTotal: costasIndices.count,
            allSymbolsCorrect: allCorrect,
            allSymbolsTotal: expectedTones.count,
            dataSymbolsCorrect: dataCorrect,
            dataSymbolsTotal: dataIndices.count,
            aggregateMarginDB: totalMargin,
            aggregateExpectedMetricDB: expectedMetric
        )
    }

    private static func nearestDistance(
        for referenceIndex: Int,
        in report: RealWAVReferenceAssociationReport
    ) -> RealWAVReferenceCandidateDistance? {
        report.distanceMatrix
            .filter { $0.referenceIndex == referenceIndex }
            .min {
                if $0.normalisedDistance == $1.normalisedDistance {
                    return $0.synchronizerScore > $1.synchronizerScore
                }
                return $0.normalisedDistance < $1.normalisedDistance
            }
    }

    private static func mapCandidates(
        records: [FT8PipelineRecord],
        foundCandidates: [FT8Candidate]
    ) -> [Int: FT8Candidate] {
        var result: [Int: FT8Candidate] = [:]

        for record in records {
            guard let nearest = foundCandidates.min(by: {
                candidateDistance($0, record: record)
                    < candidateDistance($1, record: record)
            }) else {
                continue
            }

            result[record.candidateIndex] = nearest
        }

        return result
    }

    private static func candidateDistance(
        _ candidate: FT8Candidate,
        record: FT8PipelineRecord
    ) -> Double {
        abs(candidate.startTime - record.startTime)
            + Double(abs(candidate.frequency - record.frequency)) / 50
    }

    private static func candidate(
        basedOn seed: FT8Candidate,
        startTime: Double,
        frequency: Float
    ) -> FT8Candidate {
        FT8Candidate(
            startTime: startTime,
            frequency: frequency,
            driftHzPerSecond: seed.driftHzPerSecond,
            symbolOffset: seed.symbolOffset,
            syncScore: seed.syncScore,
            snrDB: seed.snrDB,
            confidence: seed.confidence
        )
    }

    private static func symmetricOffsets(
        radius: Double,
        step: Double
    ) -> [Double] {
        precondition(radius >= 0)
        precondition(step > 0)

        let count = Int((radius / step).rounded(.down))
        return (-count...count).map { Double($0) * step }
    }

    private static func surfaceOrdering(
        _ lhs: RealWAVGroundTruthSurfacePoint,
        _ rhs: RealWAVGroundTruthSurfacePoint
    ) -> Bool {
        if lhs.costasCorrect != rhs.costasCorrect {
            return lhs.costasCorrect > rhs.costasCorrect
        }
        if lhs.costasMarginDB != rhs.costasMarginDB {
            return lhs.costasMarginDB > rhs.costasMarginDB
        }
        if lhs.costasExpectedMetricDB != rhs.costasExpectedMetricDB {
            return lhs.costasExpectedMetricDB > rhs.costasExpectedMetricDB
        }
        if abs(lhs.timeOffsetFromSeed) != abs(rhs.timeOffsetFromSeed) {
            return abs(lhs.timeOffsetFromSeed) < abs(rhs.timeOffsetFromSeed)
        }
        return abs(lhs.frequencyOffsetFromSeedHz)
            < abs(rhs.frequencyOffsetFromSeedHz)
    }

    private static func refinedOrdering(
        _ lhs: RealWAVGroundTruthRefinedHypothesis,
        _ rhs: RealWAVGroundTruthRefinedHypothesis
    ) -> Bool {
        if lhs.dataSymbolsCorrect != rhs.dataSymbolsCorrect {
            return lhs.dataSymbolsCorrect > rhs.dataSymbolsCorrect
        }
        if lhs.allSymbolsCorrect != rhs.allSymbolsCorrect {
            return lhs.allSymbolsCorrect > rhs.allSymbolsCorrect
        }
        if lhs.aggregateMarginDB != rhs.aggregateMarginDB {
            return lhs.aggregateMarginDB > rhs.aggregateMarginDB
        }
        return lhs.aggregateExpectedMetricDB > rhs.aggregateExpectedMetricDB
    }

    private static func protocolMessage(
        _ rawMessage: String
    ) -> FT8Message {
        let protocolText = stripWSJTXAnnotation(from: rawMessage)
        let fields = protocolText
            .uppercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        if fields.count == 3 {
            return .standard(
                to: fields[0],
                from: fields[1],
                extra: fields[2]
            )
        }

        if fields.count == 4, fields[0] == "CQ" {
            return .standard(
                to: "CQ \(fields[1])",
                from: fields[2],
                extra: fields[3]
            )
        }

        return .freeText(fields.joined(separator: " "))
    }

    private static func stripWSJTXAnnotation(
        from message: String
    ) -> String {
        let trimmed = message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard let range = trimmed.range(
            of: #"\s{2,}"#,
            options: .regularExpression
        ) else {
            return trimmed
        }

        return String(trimmed[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
