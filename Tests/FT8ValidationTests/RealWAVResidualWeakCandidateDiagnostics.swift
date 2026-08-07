import Foundation
import FT8Decoder

enum RealWAVResidualWeakCandidateDiagnostics {
    struct Configuration: Equatable, Sendable {
        var tightTimeTolerance: Double = 0.25
        var tightFrequencyToleranceHz: Double = 100
        var nearbyTimeTolerance: Double = 0.60
        var nearbyFrequencyToleranceHz: Double = 300
        var maximumNearbyCandidates: Int = 8
        var timeWeight: Double = 0.25
        var frequencyWeightHz: Double = 100
    }

    static func build(
        recording: String,
        pass: Int,
        expected: [WSJTXExpectedDecode],
        decodedMessages: [String],
        traces: [FT8CandidateTrace],
        configuration: Configuration = .init()
    ) -> RealWAVResidualWeakCandidateReport {
        let decodedNormalized = Set(
            decodedMessages.map(normalizedProtocolMessage)
        )

        let passTraces = traces
            .filter { $0.pass == pass }

        let references = expected.enumerated().map {
            referenceIndex,
            reference -> RealWAVResidualReferenceDiagnostic in

            let protocolMessage =
                normalizedProtocolMessage(reference.message)

            let alreadyDecoded =
                decodedNormalized.contains(protocolMessage)

            let ranked = passTraces
                .map {
                    diagnostic(
                        trace: $0,
                        reference: reference,
                        configuration: configuration
                    )
                }
                .sorted {
                    if $0.normalizedDistance
                        == $1.normalizedDistance {
                        return $0.candidateConfidence
                            > $1.candidateConfidence
                    }
                    return $0.normalizedDistance
                        < $1.normalizedDistance
                }

            let nearest = ranked.first

            let nearby = ranked
                .filter {
                    $0.timeDelta
                        <= configuration.nearbyTimeTolerance
                    && $0.frequencyDeltaHz
                        <= configuration.nearbyFrequencyToleranceHz
                }
                .prefix(
                    configuration.maximumNearbyCandidates
                )

            let nearbyArray = Array(nearby)

            let tightCandidatePresent =
                nearbyArray.contains {
                    $0.timeDelta
                        <= configuration.tightTimeTolerance
                    && $0.frequencyDeltaHz
                        <= configuration.tightFrequencyToleranceHz
                }

            let bestSyndromeWeight =
                nearbyArray
                    .compactMap(\.syndromeWeight)
                    .min()

            let bestSoftSymbolConfidence =
                nearbyArray
                    .compactMap(
                        \.averageSoftSymbolConfidence
                    )
                    .max()

            let parityCount =
                nearbyArray.count {
                    $0.parityPassed == true
                }

            let crcCount =
                nearbyArray.count {
                    $0.crcPassed == true
                }

            return RealWAVResidualReferenceDiagnostic(
                referenceIndex: referenceIndex,
                referenceMessage: protocolMessage,
                referenceSNRDB: reference.snrDB,
                referenceTimeOffset:
                    reference.timeOffset,
                referenceFrequencyHz:
                    reference.frequencyHz,
                alreadyDecoded: alreadyDecoded,
                failureStage:
                    classify(
                        alreadyDecoded: alreadyDecoded,
                        nearest: nearest,
                        nearby: nearbyArray,
                        tightCandidatePresent:
                            tightCandidatePresent,
                        configuration: configuration
                    ),
                nearestCandidate: nearest,
                nearbyCandidates: nearbyArray,
                tightCandidatePresent:
                    tightCandidatePresent,
                bestSyndromeWeight:
                    bestSyndromeWeight,
                bestSoftSymbolConfidence:
                    bestSoftSymbolConfidence,
                parityCandidateCount: parityCount,
                crcCandidateCount: crcCount
            )
        }

        return RealWAVResidualWeakCandidateReport(
            recording: recording,
            passAnalysed: pass,
            expectedReferenceCount: expected.count,
            decodedMessages:
                decodedMessages.map(
                    normalizedProtocolMessage
                ),
            remainingReferenceCount:
                references.count {
                    !$0.alreadyDecoded
                },
            passCandidateCount: passTraces.count,
            references: references
        )
    }

    static func printSummary(
        _ report: RealWAVResidualWeakCandidateReport
    ) {
        print("Residual weak-candidate diagnostics:")
        print(
            "  recording: \(report.recording)"
        )
        print(
            "  pass: \(report.passAnalysed)"
                + " candidates=\(report.passCandidateCount)"
                + " expected=\(report.expectedReferenceCount)"
                + " remaining=\(report.remainingReferenceCount)"
        )
        print(
            "  decoded: "
                + report.decodedMessages
                    .joined(separator: " | ")
        )

        for reference in report.references
        where !reference.alreadyDecoded {
            print(
                "  reference #\(reference.referenceIndex)"
                    + " \"\(reference.referenceMessage)\""
                    + " snr=\(reference.referenceSNRDB)"
                    + " time=\(reference.referenceTimeOffset)"
                    + " frequency=\(reference.referenceFrequencyHz)"
            )

            print(
                "    stage=\(reference.failureStage.rawValue)"
                    + " tightCandidate=\(reference.tightCandidatePresent)"
                    + " nearby=\(reference.nearbyCandidates.count)"
                    + " bestSyndrome="
                    + optional(reference.bestSyndromeWeight)
                    + " bestSoft="
                    + optional(reference.bestSoftSymbolConfidence)
            )

            if let nearest =
                reference.nearestCandidate {
                print(
                    "    nearest:"
                        + " candidate=\(nearest.candidateIndex)"
                        + " dt=\(String(format: "%.3f", nearest.timeDelta))"
                        + " df=\(String(format: "%.3f", nearest.frequencyDeltaHz))"
                        + " confidence=\(nearest.candidateConfidence)"
                        + " soft="
                        + optional(
                            nearest.averageSoftSymbolConfidence
                        )
                        + " syndrome="
                        + optional(nearest.syndromeWeight)
                        + " parity="
                        + optional(nearest.parityPassed)
                        + " crc="
                        + optional(nearest.crcPassed)
                        + " failure="
                        + (nearest.failure ?? "none")
                )
            }

            for candidate
            in reference.nearbyCandidates.prefix(4) {
                print(
                    "      #\(candidate.candidateIndex)"
                        + " dt=\(String(format: "%.3f", candidate.timeDelta))"
                        + " df=\(String(format: "%.3f", candidate.frequencyDeltaHz))"
                        + " soft="
                        + optional(
                            candidate.averageSoftSymbolConfidence
                        )
                        + " syndrome="
                        + optional(candidate.syndromeWeight)
                        + " parity="
                        + optional(candidate.parityPassed)
                        + " crc="
                        + optional(candidate.crcPassed)
                )
            }
        }
    }

    static func normalizedProtocolMessage(
        _ message: String
    ) -> String {
        let trimmed = message
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let protocolPart: String

        if let annotationRange = trimmed.range(
            of: #"\s{2,}"#,
            options: .regularExpression
        ) {
            protocolPart = String(
                trimmed[..<annotationRange.lowerBound]
            )
        } else {
            protocolPart = trimmed
        }

        return protocolPart
            .uppercased()
            .split(
                whereSeparator: {
                    $0.isWhitespace
                }
            )
            .joined(separator: " ")
    }

    private static func diagnostic(
        trace: FT8CandidateTrace,
        reference: WSJTXExpectedDecode,
        configuration: Configuration
    ) -> RealWAVResidualCandidateDiagnostic {
        let dt = abs(
            trace.startTime
                - reference.timeOffset
        )
        let df = abs(
            Double(trace.frequency)
                - Double(reference.frequencyHz)
        )

        let distance =
            dt / configuration.timeWeight
            + df / configuration.frequencyWeightHz

        return RealWAVResidualCandidateDiagnostic(
            pass: trace.pass,
            candidateIndex: trace.candidateIndex,
            startTime: trace.startTime,
            frequencyHz: trace.frequency,
            timeDelta: dt,
            frequencyDeltaHz: df,
            normalizedDistance: distance,
            syncScore: trace.syncScore,
            snrDB: trace.snrDB,
            candidateConfidence:
                trace.candidateConfidence,
            averageSoftSymbolConfidence:
                trace.averageSoftSymbolConfidence,
            ldpcIterations: trace.ldpcIterations,
            syndromeWeight: trace.syndromeWeight,
            parityPassed: trace.parityPassed,
            crcPassed: trace.crcPassed,
            decodedText: trace.decodedText,
            failure: trace.failure
        )
    }

    private static func classify(
        alreadyDecoded: Bool,
        nearest:
            RealWAVResidualCandidateDiagnostic?,
        nearby:
            [RealWAVResidualCandidateDiagnostic],
        tightCandidatePresent: Bool,
        configuration: Configuration
    ) -> RealWAVResidualFailureStage {
        if alreadyDecoded {
            return .decoded
        }

        guard let nearest else {
            return .noCandidate
        }

        guard tightCandidatePresent else {
            if nearest.timeDelta
                > configuration.nearbyTimeTolerance
                || nearest.frequencyDeltaHz
                > configuration.nearbyFrequencyToleranceHz {
                return .noCandidate
            }

            return .candidateAssociation
        }

        if nearby.contains(
            where: {
                $0.crcPassed == true
            }
        ) {
            return .decoded
        }

        if nearby.contains(
            where: {
                $0.parityPassed == true
            }
        ) {
            return .crc
        }

        if nearby.contains(
            where: {
                $0.syndromeWeight != nil
            }
        ) {
            return .ldpc
        }

        if nearby.contains(
            where: {
                $0.averageSoftSymbolConfidence != nil
            }
        ) {
            return .softSymbols
        }

        if nearby.contains(
            where: {
                $0.failure == "messageDecodeFailed"
            }
        ) {
            return .messageDecode
        }

        return .unknown
    }

    private static func optional<T>(
        _ value: T?
    ) -> String {
        value.map { String(describing: $0) }
            ?? "nil"
    }
}
