import Foundation
import FT8Decoder
import FT8DSP

struct RealWAVAdaptiveFineDecodeAttempt: Codable, Equatable {
    let candidateIndex: Int
    let referenceMessage: String
    let trialTime: Double
    let trialFrequencyHz: Double
    let timeOffset: Double
    let frequencyOffsetHz: Double
    let averageSoftConfidence: Double
    let syndromeWeight: Int
    let parityPassed: Bool
    let crcPassed: Bool
    let decodedMessage: String?
    let failure: String?
}

struct RealWAVAdaptiveFineDecodeWinner: Codable, Equatable {
    let candidateIndex: Int
    let referenceMessage: String
    let decodedMessage: String
    let trialTime: Double
    let trialFrequencyHz: Double
    let timeOffset: Double
    let frequencyOffsetHz: Double
    let averageSoftConfidence: Double
    let iterations: Int
}

struct RealWAVAdaptiveFineDecodeReport: Codable, Equatable {
    let recording: String
    let generatedAt: Date
    let candidateCount: Int
    let plannedAttemptCount: Int
    let completedAttemptCount: Int
    let crcPassingAttemptCount: Int
    let winners: [RealWAVAdaptiveFineDecodeWinner]
    let attempts: [RealWAVAdaptiveFineDecodeAttempt]
}

enum RealWAVAdaptiveFineDecoder {
    static func decode(
        recording: String,
        spectrogram: Spectrogram,
        refinementReport: RealWAVFineHypothesisReport,
        extractor: SoftSymbolExtractor,
        ldpcDecoder: FT8LDPCDecoder,
        messageDecoder: FT8MessageDecoder,
        generatedAt: Date = Date()
    ) -> RealWAVAdaptiveFineDecodeReport {
        var attempts: [RealWAVAdaptiveFineDecodeAttempt] = []
        var winners: [RealWAVAdaptiveFineDecodeWinner] = []

        attempts.reserveCapacity(refinementReport.totalPointCount)
        winners.reserveCapacity(refinementReport.candidates.count)

        for refinementCandidate in refinementReport.candidates {
            let orderedPoints = refinementCandidate.points.sorted {
                let lhsDistance =
                    abs($0.timeOffset) / max(refinementReport.timeStep, 0.000_001)
                    + abs($0.frequencyOffsetHz)
                        / max(refinementReport.frequencyStepHz, 0.000_001)
                let rhsDistance =
                    abs($1.timeOffset) / max(refinementReport.timeStep, 0.000_001)
                    + abs($1.frequencyOffsetHz)
                        / max(refinementReport.frequencyStepHz, 0.000_001)

                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                if abs($0.timeOffset) != abs($1.timeOffset) {
                    return abs($0.timeOffset) < abs($1.timeOffset)
                }
                if abs($0.frequencyOffsetHz) != abs($1.frequencyOffsetHz) {
                    return abs($0.frequencyOffsetHz)
                        < abs($1.frequencyOffsetHz)
                }
                if $0.timeOffset != $1.timeOffset {
                    return $0.timeOffset < $1.timeOffset
                }
                return $0.frequencyOffsetHz < $1.frequencyOffsetHz
            }

            for point in orderedPoints {
                let trialCandidate = FT8Candidate(
                    startTime: point.trialTime,
                    frequency: Float(point.trialFrequencyHz),
                    driftHzPerSecond: 0,
                    symbolOffset: 0,
                    syncScore: 0,
                    snrDB: 0,
                    confidence: 0
                )

                do {
                    let softSymbols = try extractor.extract(
                        from: spectrogram,
                        candidate: trialCandidate
                    )
                    let ldpcResult = try ldpcDecoder.decode(softSymbols)

                    if ldpcResult.crcPassed {
                        do {
                            let decoded = try messageDecoder.decode(
                                ldpcResult,
                                softSymbols: softSymbols
                            )
                            let message = decoded.text.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )

                            attempts.append(
                                RealWAVAdaptiveFineDecodeAttempt(
                                    candidateIndex: point.candidateIndex,
                                    referenceMessage: point.referenceMessage,
                                    trialTime: point.trialTime,
                                    trialFrequencyHz: point.trialFrequencyHz,
                                    timeOffset: point.timeOffset,
                                    frequencyOffsetHz: point.frequencyOffsetHz,
                                    averageSoftConfidence:
                                        Double(softSymbols.averageConfidence),
                                    syndromeWeight: ldpcResult.syndromeWeight,
                                    parityPassed: ldpcResult.parityPassed,
                                    crcPassed: true,
                                    decodedMessage: message,
                                    failure: message.isEmpty
                                        ? "emptyDecodedMessage"
                                        : nil
                                )
                            )

                            if !message.isEmpty {
                                winners.append(
                                    RealWAVAdaptiveFineDecodeWinner(
                                        candidateIndex: point.candidateIndex,
                                        referenceMessage:
                                            point.referenceMessage,
                                        decodedMessage: message,
                                        trialTime: point.trialTime,
                                        trialFrequencyHz:
                                            point.trialFrequencyHz,
                                        timeOffset: point.timeOffset,
                                        frequencyOffsetHz:
                                            point.frequencyOffsetHz,
                                        averageSoftConfidence:
                                            Double(
                                                softSymbols.averageConfidence
                                            ),
                                        iterations: ldpcResult.iterations
                                    )
                                )
                                break
                            }
                        } catch {
                            attempts.append(
                                RealWAVAdaptiveFineDecodeAttempt(
                                    candidateIndex: point.candidateIndex,
                                    referenceMessage: point.referenceMessage,
                                    trialTime: point.trialTime,
                                    trialFrequencyHz: point.trialFrequencyHz,
                                    timeOffset: point.timeOffset,
                                    frequencyOffsetHz: point.frequencyOffsetHz,
                                    averageSoftConfidence:
                                        Double(softSymbols.averageConfidence),
                                    syndromeWeight: ldpcResult.syndromeWeight,
                                    parityPassed: ldpcResult.parityPassed,
                                    crcPassed: ldpcResult.crcPassed,
                                    decodedMessage: nil,
                                    failure:
                                        "messageDecode:\(String(describing: error))"
                                )
                            )
                        }
                    } else {
                        attempts.append(
                            RealWAVAdaptiveFineDecodeAttempt(
                                candidateIndex: point.candidateIndex,
                                referenceMessage: point.referenceMessage,
                                trialTime: point.trialTime,
                                trialFrequencyHz: point.trialFrequencyHz,
                                timeOffset: point.timeOffset,
                                frequencyOffsetHz: point.frequencyOffsetHz,
                                averageSoftConfidence:
                                    Double(softSymbols.averageConfidence),
                                syndromeWeight: ldpcResult.syndromeWeight,
                                parityPassed: ldpcResult.parityPassed,
                                crcPassed: false,
                                decodedMessage: nil,
                                failure: ldpcResult.parityPassed
                                    ? "crcFailed"
                                    : "parityFailed"
                            )
                        )
                    }
                } catch {
                    attempts.append(
                        RealWAVAdaptiveFineDecodeAttempt(
                            candidateIndex: point.candidateIndex,
                            referenceMessage: point.referenceMessage,
                            trialTime: point.trialTime,
                            trialFrequencyHz: point.trialFrequencyHz,
                            timeOffset: point.timeOffset,
                            frequencyOffsetHz: point.frequencyOffsetHz,
                            averageSoftConfidence: 0,
                            syndromeWeight: .max,
                            parityPassed: false,
                            crcPassed: false,
                            decodedMessage: nil,
                            failure: "trialDecode:\(String(describing: error))"
                        )
                    )
                }
            }
        }

        return RealWAVAdaptiveFineDecodeReport(
            recording: recording,
            generatedAt: generatedAt,
            candidateCount: refinementReport.candidates.count,
            plannedAttemptCount: refinementReport.totalPointCount,
            completedAttemptCount: attempts.count,
            crcPassingAttemptCount: attempts.count { $0.crcPassed },
            winners: winners,
            attempts: attempts
        )
    }

    static func printSummary(_ report: RealWAVAdaptiveFineDecodeReport) {
        print("Real WAV adaptive fine decode:")
        print("  recording: \(report.recording)")
        print("  candidates: \(report.candidateCount)")
        print("  planned attempts: \(report.plannedAttemptCount)")
        print("  completed attempts: \(report.completedAttemptCount)")
        print("  CRC-passing attempts: \(report.crcPassingAttemptCount)")
        print("  recovered messages: \(report.winners.count)")

        for winner in report.winners {
            print(
                "  #\(winner.candidateIndex + 1)"
                    + " decoded=\"\(winner.decodedMessage)\""
                    + " reference=\"\(winner.referenceMessage)\""
                    + " time=\(winner.trialTime)"
                    + " frequency=\(winner.trialFrequencyHz)"
                    + " dt=\(winner.timeOffset)"
                    + " df=\(winner.frequencyOffsetHz)"
                    + " soft=\(winner.averageSoftConfidence)"
                    + " iterations=\(winner.iterations)"
            )
        }

        if report.winners.isEmpty {
            let best = report.attempts.sorted {
                if $0.crcPassed != $1.crcPassed {
                    return $0.crcPassed
                }
                if $0.parityPassed != $1.parityPassed {
                    return $0.parityPassed
                }
                if $0.syndromeWeight != $1.syndromeWeight {
                    return $0.syndromeWeight < $1.syndromeWeight
                }
                return $0.averageSoftConfidence
                    > $1.averageSoftConfidence
            }

            print("  best unsuccessful hypotheses:")
            for attempt in best.prefix(10) {
                print(
                    "    #\(attempt.candidateIndex + 1)"
                        + " time=\(attempt.trialTime)"
                        + " frequency=\(attempt.trialFrequencyHz)"
                        + " dt=\(attempt.timeOffset)"
                        + " df=\(attempt.frequencyOffsetHz)"
                        + " syndrome=\(attempt.syndromeWeight)"
                        + " parity=\(attempt.parityPassed)"
                        + " crc=\(attempt.crcPassed)"
                        + " soft=\(attempt.averageSoftConfidence)"
                        + " failure=\(attempt.failure ?? "none")"
                )
            }
        }
    }

    static func exportIfRequested(
        _ report: RealWAVAdaptiveFineDecodeReport,
        fileManager: FileManager = .default,
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) throws {
        if let jsonURL = exportURL(
            variable: "FT8_REAL_WAV_ADAPTIVE_JSON",
            environment: environment
        ) {
            try prepareParentDirectory(
                for: jsonURL,
                fileManager: fileManager
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(
                to: jsonURL,
                options: .atomic
            )
            print(
                "Real WAV adaptive JSON written to: \(jsonURL.path)"
            )
        }

        if let csvURL = exportURL(
            variable: "FT8_REAL_WAV_ADAPTIVE_CSV",
            environment: environment
        ) {
            try prepareParentDirectory(
                for: csvURL,
                fileManager: fileManager
            )
            try csv(report).write(
                to: csvURL,
                atomically: true,
                encoding: .utf8
            )
            print(
                "Real WAV adaptive CSV written to: \(csvURL.path)"
            )
        }
    }

    private static func exportURL(
        variable: String,
        environment: [String: String]
    ) -> URL? {
        guard let rawPath = environment[variable]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty
        else {
            return nil
        }

        return URL(
            fileURLWithPath:
                NSString(string: rawPath).expandingTildeInPath
        )
    }

    private static func prepareParentDirectory(
        for fileURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private static func csv(
        _ report: RealWAVAdaptiveFineDecodeReport
    ) -> String {
        var rows = [
            [
                "recording",
                "candidate_index",
                "reference_message",
                "trial_time",
                "trial_frequency_hz",
                "time_offset",
                "frequency_offset_hz",
                "average_soft_confidence",
                "syndrome_weight",
                "parity_passed",
                "crc_passed",
                "decoded_message",
                "failure"
            ].joined(separator: ",")
        ]

        for attempt in report.attempts {
            rows.append(
                [
                    csvField(report.recording),
                    String(attempt.candidateIndex),
                    csvField(attempt.referenceMessage),
                    String(attempt.trialTime),
                    String(attempt.trialFrequencyHz),
                    String(attempt.timeOffset),
                    String(attempt.frequencyOffsetHz),
                    String(attempt.averageSoftConfidence),
                    String(attempt.syndromeWeight),
                    String(attempt.parityPassed),
                    String(attempt.crcPassed),
                    csvField(attempt.decodedMessage ?? ""),
                    csvField(attempt.failure ?? "")
                ].joined(separator: ",")
            )
        }

        return rows.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",")
                || value.contains("\"")
                || value.contains("\n")
        else {
            return value
        }

        return "\""
            + value.replacingOccurrences(of: "\"", with: "\"\"")
            + "\""
    }
}
