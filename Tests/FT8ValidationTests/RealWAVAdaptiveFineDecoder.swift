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
    private struct PointKey: Hashable {
        let timeIndex: Int
        let frequencyIndex: Int
    }

    private struct TrialResult {
        let point: RealWAVFineHypothesisPoint
        let attempt: RealWAVAdaptiveFineDecodeAttempt
        let winner: RealWAVAdaptiveFineDecodeWinner?
    }

    private static let maximumAttemptsPerCandidate = 32
    private static let maximumIterationsPerCandidate = 6
    private static let maximumStagnantIterations = 2

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

        let boundedCapacity = min(
            refinementReport.totalPointCount,
            refinementReport.candidates.count * maximumAttemptsPerCandidate
        )
        attempts.reserveCapacity(boundedCapacity)
        winners.reserveCapacity(refinementReport.candidates.count)

        for refinementCandidate in refinementReport.candidates {
            let result = decodeCandidate(
                refinementCandidate,
                report: refinementReport,
                spectrogram: spectrogram,
                extractor: extractor,
                ldpcDecoder: ldpcDecoder,
                messageDecoder: messageDecoder
            )

            attempts.append(contentsOf: result.attempts)
            if let winner = result.winner {
                winners.append(winner)
            }
        }

        return RealWAVAdaptiveFineDecodeReport(
            recording: recording,
            generatedAt: generatedAt,
            candidateCount: refinementReport.candidates.count,
            plannedAttemptCount: boundedCapacity,
            completedAttemptCount: attempts.count,
            crcPassingAttemptCount: attempts.count { $0.crcPassed },
            winners: winners,
            attempts: attempts
        )
    }

    private static func decodeCandidate(
        _ candidate: RealWAVFineHypothesisCandidate,
        report: RealWAVFineHypothesisReport,
        spectrogram: Spectrogram,
        extractor: SoftSymbolExtractor,
        ldpcDecoder: FT8LDPCDecoder,
        messageDecoder: FT8MessageDecoder
    ) -> (
        attempts: [RealWAVAdaptiveFineDecodeAttempt],
        winner: RealWAVAdaptiveFineDecodeWinner?
    ) {
        let timeStep = max(report.timeStep, 0.000_001)
        let frequencyStep = max(report.frequencyStepHz, 0.000_001)

        let pointsByKey = Dictionary(
            uniqueKeysWithValues: candidate.points.map { point in
                (
                    key(
                        for: point,
                        timeStep: timeStep,
                        frequencyStep: frequencyStep
                    ),
                    point
                )
            }
        )

        guard let origin = nearestOrigin(in: candidate.points) else {
            return ([], nil)
        }

        var attempts: [RealWAVAdaptiveFineDecodeAttempt] = []
        attempts.reserveCapacity(
            min(maximumAttemptsPerCandidate, candidate.points.count)
        )

        var visited: Set<PointKey> = []
        var centre = origin
        var bestResult: TrialResult?
        var stagnantIterations = 0

        for iteration in 0..<maximumIterationsPerCandidate {
            let centreKey = key(
                for: centre,
                timeStep: timeStep,
                frequencyStep: frequencyStep
            )

            let radius = iteration + 1
            let keys = neighbourhoodKeys(
                around: centreKey,
                radius: radius
            )

            var iterationResults: [TrialResult] = []

            for pointKey in keys {
                guard attempts.count < maximumAttemptsPerCandidate else {
                    break
                }
                guard visited.insert(pointKey).inserted,
                      let point = pointsByKey[pointKey]
                else {
                    continue
                }

                let result = evaluate(
                    point,
                    spectrogram: spectrogram,
                    extractor: extractor,
                    ldpcDecoder: ldpcDecoder,
                    messageDecoder: messageDecoder
                )
                attempts.append(result.attempt)
                iterationResults.append(result)

                if let winner = result.winner {
                    return (attempts, winner)
                }
            }

            guard !iterationResults.isEmpty else {
                break
            }

            let iterationBest = iterationResults.min {
                isBetter($0.attempt, than: $1.attempt)
            }

            guard let iterationBest else {
                break
            }

            if let currentBest = bestResult {
                if isBetter(
                    iterationBest.attempt,
                    than: currentBest.attempt
                ) {
                    bestResult = iterationBest
                    centre = iterationBest.point
                    stagnantIterations = 0
                } else {
                    stagnantIterations += 1
                }
            } else {
                bestResult = iterationBest
                centre = iterationBest.point
                stagnantIterations = 0
            }

            if stagnantIterations >= maximumStagnantIterations {
                break
            }
        }

        return (attempts, nil)
    }

    private static func evaluate(
        _ point: RealWAVFineHypothesisPoint,
        spectrogram: Spectrogram,
        extractor: SoftSymbolExtractor,
        ldpcDecoder: FT8LDPCDecoder,
        messageDecoder: FT8MessageDecoder
    ) -> TrialResult {
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
            let softConfidence = Double(softSymbols.averageConfidence)

            guard ldpcResult.crcPassed else {
                return TrialResult(
                    point: point,
                    attempt: RealWAVAdaptiveFineDecodeAttempt(
                        candidateIndex: point.candidateIndex,
                        referenceMessage: point.referenceMessage,
                        trialTime: point.trialTime,
                        trialFrequencyHz: point.trialFrequencyHz,
                        timeOffset: point.timeOffset,
                        frequencyOffsetHz: point.frequencyOffsetHz,
                        averageSoftConfidence: softConfidence,
                        syndromeWeight: ldpcResult.syndromeWeight,
                        parityPassed: ldpcResult.parityPassed,
                        crcPassed: false,
                        decodedMessage: nil,
                        failure: ldpcResult.parityPassed
                            ? "crcFailed"
                            : "parityFailed"
                    ),
                    winner: nil
                )
            }

            do {
                let decoded = try messageDecoder.decode(
                    ldpcResult,
                    softSymbols: softSymbols
                )
                let message = decoded.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                let attempt = RealWAVAdaptiveFineDecodeAttempt(
                    candidateIndex: point.candidateIndex,
                    referenceMessage: point.referenceMessage,
                    trialTime: point.trialTime,
                    trialFrequencyHz: point.trialFrequencyHz,
                    timeOffset: point.timeOffset,
                    frequencyOffsetHz: point.frequencyOffsetHz,
                    averageSoftConfidence: softConfidence,
                    syndromeWeight: ldpcResult.syndromeWeight,
                    parityPassed: ldpcResult.parityPassed,
                    crcPassed: true,
                    decodedMessage: message,
                    failure: message.isEmpty
                        ? "emptyDecodedMessage"
                        : nil
                )

                guard !message.isEmpty else {
                    return TrialResult(
                        point: point,
                        attempt: attempt,
                        winner: nil
                    )
                }

                return TrialResult(
                    point: point,
                    attempt: attempt,
                    winner: RealWAVAdaptiveFineDecodeWinner(
                        candidateIndex: point.candidateIndex,
                        referenceMessage: point.referenceMessage,
                        decodedMessage: message,
                        trialTime: point.trialTime,
                        trialFrequencyHz: point.trialFrequencyHz,
                        timeOffset: point.timeOffset,
                        frequencyOffsetHz: point.frequencyOffsetHz,
                        averageSoftConfidence: softConfidence,
                        iterations: ldpcResult.iterations
                    )
                )
            } catch {
                return TrialResult(
                    point: point,
                    attempt: RealWAVAdaptiveFineDecodeAttempt(
                        candidateIndex: point.candidateIndex,
                        referenceMessage: point.referenceMessage,
                        trialTime: point.trialTime,
                        trialFrequencyHz: point.trialFrequencyHz,
                        timeOffset: point.timeOffset,
                        frequencyOffsetHz: point.frequencyOffsetHz,
                        averageSoftConfidence: softConfidence,
                        syndromeWeight: ldpcResult.syndromeWeight,
                        parityPassed: ldpcResult.parityPassed,
                        crcPassed: ldpcResult.crcPassed,
                        decodedMessage: nil,
                        failure:
                            "messageDecode:\(String(describing: error))"
                    ),
                    winner: nil
                )
            }
        } catch {
            return TrialResult(
                point: point,
                attempt: RealWAVAdaptiveFineDecodeAttempt(
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
                ),
                winner: nil
            )
        }
    }

    private static func nearestOrigin(
        in points: [RealWAVFineHypothesisPoint]
    ) -> RealWAVFineHypothesisPoint? {
        points.min { lhs, rhs in
            let lhsDistance =
                abs(lhs.timeOffset) + abs(lhs.frequencyOffsetHz)
            let rhsDistance =
                abs(rhs.timeOffset) + abs(rhs.frequencyOffsetHz)

            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            if abs(lhs.timeOffset) != abs(rhs.timeOffset) {
                return abs(lhs.timeOffset) < abs(rhs.timeOffset)
            }
            return abs(lhs.frequencyOffsetHz)
                < abs(rhs.frequencyOffsetHz)
        }
    }

    private static func key(
        for point: RealWAVFineHypothesisPoint,
        timeStep: Double,
        frequencyStep: Double
    ) -> PointKey {
        PointKey(
            timeIndex: Int((point.timeOffset / timeStep).rounded()),
            frequencyIndex: Int(
                (point.frequencyOffsetHz / frequencyStep).rounded()
            )
        )
    }

    private static func neighbourhoodKeys(
        around centre: PointKey,
        radius: Int
    ) -> [PointKey] {
        guard radius > 0 else {
            return [centre]
        }

        var keys: [PointKey] = []
        keys.reserveCapacity(radius == 1 ? 9 : radius * 8)

        if radius == 1 {
            keys.append(centre)
        }

        for timeDelta in -radius...radius {
            for frequencyDelta in -radius...radius {
                guard max(abs(timeDelta), abs(frequencyDelta)) == radius else {
                    continue
                }

                keys.append(
                    PointKey(
                        timeIndex: centre.timeIndex + timeDelta,
                        frequencyIndex:
                            centre.frequencyIndex + frequencyDelta
                    )
                )
            }
        }

        return keys.sorted { lhs, rhs in
            let lhsDistance =
                abs(lhs.timeIndex - centre.timeIndex)
                + abs(lhs.frequencyIndex - centre.frequencyIndex)
            let rhsDistance =
                abs(rhs.timeIndex - centre.timeIndex)
                + abs(rhs.frequencyIndex - centre.frequencyIndex)

            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            if lhs.timeIndex != rhs.timeIndex {
                return lhs.timeIndex < rhs.timeIndex
            }
            return lhs.frequencyIndex < rhs.frequencyIndex
        }
    }

    private static func isBetter(
        _ lhs: RealWAVAdaptiveFineDecodeAttempt,
        than rhs: RealWAVAdaptiveFineDecodeAttempt
    ) -> Bool {
        if lhs.crcPassed != rhs.crcPassed {
            return lhs.crcPassed
        }
        if lhs.parityPassed != rhs.parityPassed {
            return lhs.parityPassed
        }
        if lhs.syndromeWeight != rhs.syndromeWeight {
            return lhs.syndromeWeight < rhs.syndromeWeight
        }
        if lhs.averageSoftConfidence != rhs.averageSoftConfidence {
            return lhs.averageSoftConfidence
                > rhs.averageSoftConfidence
        }

        let lhsDistance =
            abs(lhs.timeOffset) + abs(lhs.frequencyOffsetHz)
        let rhsDistance =
            abs(rhs.timeOffset) + abs(rhs.frequencyOffsetHz)

        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }
        if lhs.timeOffset != rhs.timeOffset {
            return lhs.timeOffset < rhs.timeOffset
        }
        return lhs.frequencyOffsetHz < rhs.frequencyOffsetHz
    }

    static func printSummary(_ report: RealWAVAdaptiveFineDecodeReport) {
        print("Real WAV adaptive fine decode:")
        print("  recording: \(report.recording)")
        print("  candidates: \(report.candidateCount)")
        print("  bounded attempts planned: \(report.plannedAttemptCount)")
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
                isBetter($0, than: $1)
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
