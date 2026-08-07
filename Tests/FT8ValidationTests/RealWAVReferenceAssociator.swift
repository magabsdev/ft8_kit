import Foundation
import FT8Decoder
@testable import FT8Validation

enum RealWAVReferenceAssociator {
    static func buildReport(
        recording: String,
        records: [FT8PipelineRecord],
        expected: [WSJTXExpectedDecode],
        configuration: RealWAVReferenceAssociationConfiguration = .default,
        generatedAt: Date = Date()
    ) -> RealWAVReferenceAssociationReport {
        let references = expected.enumerated().map { index, reference in
            RealWAVReferenceDescriptor(
                referenceIndex: index,
                time: reference.time,
                snrDB: reference.snrDB,
                timeOffset: reference.timeOffset,
                frequencyHz: reference.frequencyHz,
                mode: reference.mode,
                message: reference.message
            )
        }

        let candidates = records
            .sorted { $0.candidateIndex < $1.candidateIndex }
            .map {
                RealWAVCandidateDescriptor(
                    candidateIndex: $0.candidateIndex,
                    startTime: $0.startTime,
                    frequencyHz: $0.frequency,
                    synchronizerScore: $0.synchronizerScore
                )
            }

        let matrix = makeDistanceMatrix(
            references: references,
            candidates: candidates,
            configuration: configuration
        )

        let primary = selectPrimaryAssociations(
            matrix: matrix
        )

        let primaryByCandidate = Dictionary(
            uniqueKeysWithValues: primary.map {
                ($0.candidateIndex, $0)
            }
        )

        let nearestByCandidate = nearestDistancesByCandidate(
            matrix: matrix
        )

        let candidateAssociations = candidates.map { candidate in
            if let match = primaryByCandidate[candidate.candidateIndex] {
                return RealWAVCandidateAssociation(
                    candidateIndex: candidate.candidateIndex,
                    classification: .matched,
                    primaryReferenceIndex: match.referenceIndex,
                    nearestReferenceIndex: match.referenceIndex,
                    nearestReferenceMessage: match.referenceMessage,
                    timeDelta: match.timeDelta,
                    frequencyDeltaHz: match.frequencyDeltaHz,
                    synchronizerScore: candidate.synchronizerScore
                )
            }

            guard let nearest = nearestByCandidate[candidate.candidateIndex] else {
                return RealWAVCandidateAssociation(
                    candidateIndex: candidate.candidateIndex,
                    classification: .unassociated,
                    primaryReferenceIndex: nil,
                    nearestReferenceIndex: nil,
                    nearestReferenceMessage: nil,
                    timeDelta: nil,
                    frequencyDeltaHz: nil,
                    synchronizerScore: candidate.synchronizerScore
                )
            }

            let classification: RealWAVCandidateAssociationClassification =
                nearest.eligibleForNearMatch ? .nearMatch : .unassociated

            return RealWAVCandidateAssociation(
                candidateIndex: candidate.candidateIndex,
                classification: classification,
                primaryReferenceIndex: nil,
                nearestReferenceIndex: nearest.referenceIndex,
                nearestReferenceMessage: nearest.referenceMessage,
                timeDelta: nearest.timeDelta,
                frequencyDeltaHz: nearest.frequencyDeltaHz,
                synchronizerScore: candidate.synchronizerScore
            )
        }

        return RealWAVReferenceAssociationReport(
            recording: recording,
            generatedAt: generatedAt,
            configuration: configuration,
            references: references,
            candidates: candidates,
            distanceMatrix: matrix,
            primaryAssociations: primary.sorted {
                $0.referenceIndex < $1.referenceIndex
            },
            candidateAssociations: candidateAssociations
        )
    }

    static func matchedRecords(
        from records: [FT8PipelineRecord],
        report: RealWAVReferenceAssociationReport
    ) -> [FT8PipelineRecord] {
        let matched = report.matchedCandidateIndices
        return records
            .filter { matched.contains($0.candidateIndex) }
            .sorted { $0.candidateIndex < $1.candidateIndex }
    }

    static func matchedReferences(
        from expected: [WSJTXExpectedDecode],
        report: RealWAVReferenceAssociationReport
    ) -> [WSJTXExpectedDecode] {
        report.primaryAssociations
            .sorted { $0.referenceIndex < $1.referenceIndex }
            .compactMap { association in
                guard expected.indices.contains(
                    association.referenceIndex
                ) else {
                    return nil
                }
                return expected[association.referenceIndex]
            }
    }

    private static func makeDistanceMatrix(
        references: [RealWAVReferenceDescriptor],
        candidates: [RealWAVCandidateDescriptor],
        configuration: RealWAVReferenceAssociationConfiguration
    ) -> [RealWAVReferenceCandidateDistance] {
        var rows: [RealWAVReferenceCandidateDistance] = []
        rows.reserveCapacity(references.count * candidates.count)

        for reference in references {
            for candidate in candidates {
                let dt = abs(
                    reference.timeOffset - candidate.startTime
                )
                let df = abs(
                    Double(reference.frequencyHz)
                        - Double(candidate.frequencyHz)
                )

                let confidencePenalty =
                    max(0, 1 - Double(candidate.synchronizerScore))
                    * configuration.confidenceWeight

                let normalised =
                    dt / configuration.matchedTimeTolerance
                    + df / configuration.matchedFrequencyToleranceHz
                    + confidencePenalty

                rows.append(
                    RealWAVReferenceCandidateDistance(
                        referenceIndex: reference.referenceIndex,
                        candidateIndex: candidate.candidateIndex,
                        referenceMessage: reference.message,
                        referenceTimeOffset: reference.timeOffset,
                        referenceFrequencyHz: reference.frequencyHz,
                        candidateStartTime: candidate.startTime,
                        candidateFrequencyHz: candidate.frequencyHz,
                        synchronizerScore: candidate.synchronizerScore,
                        timeDelta: dt,
                        frequencyDeltaHz: df,
                        normalisedDistance: normalised,
                        eligibleForMatched:
                            dt <= configuration.matchedTimeTolerance
                            && df <= configuration.matchedFrequencyToleranceHz,
                        eligibleForNearMatch:
                            dt <= configuration.nearTimeTolerance
                            && df <= configuration.nearFrequencyToleranceHz
                    )
                )
            }
        }

        return rows
    }

    private static func selectPrimaryAssociations(
        matrix: [RealWAVReferenceCandidateDistance]
    ) -> [RealWAVPrimaryAssociation] {
        let eligible = matrix
            .filter(\.eligibleForMatched)
            .sorted {
                if $0.normalisedDistance == $1.normalisedDistance {
                    if $0.synchronizerScore == $1.synchronizerScore {
                        if $0.referenceIndex == $1.referenceIndex {
                            return $0.candidateIndex < $1.candidateIndex
                        }
                        return $0.referenceIndex < $1.referenceIndex
                    }
                    return $0.synchronizerScore > $1.synchronizerScore
                }
                return $0.normalisedDistance < $1.normalisedDistance
            }

        var usedReferences = Set<Int>()
        var usedCandidates = Set<Int>()
        var result: [RealWAVPrimaryAssociation] = []

        for row in eligible {
            guard !usedReferences.contains(row.referenceIndex),
                  !usedCandidates.contains(row.candidateIndex) else {
                continue
            }

            usedReferences.insert(row.referenceIndex)
            usedCandidates.insert(row.candidateIndex)

            result.append(
                RealWAVPrimaryAssociation(
                    referenceIndex: row.referenceIndex,
                    candidateIndex: row.candidateIndex,
                    referenceMessage: row.referenceMessage,
                    timeDelta: row.timeDelta,
                    frequencyDeltaHz: row.frequencyDeltaHz,
                    synchronizerScore: row.synchronizerScore,
                    normalisedDistance: row.normalisedDistance
                )
            )
        }

        return result
    }

    private static func nearestDistancesByCandidate(
        matrix: [RealWAVReferenceCandidateDistance]
    ) -> [Int: RealWAVReferenceCandidateDistance] {
        let grouped = Dictionary(
            grouping: matrix,
            by: \.candidateIndex
        )

        return grouped.compactMapValues { rows in
            rows.min {
                if $0.normalisedDistance == $1.normalisedDistance {
                    return $0.referenceIndex < $1.referenceIndex
                }
                return $0.normalisedDistance < $1.normalisedDistance
            }
        }
    }
}
