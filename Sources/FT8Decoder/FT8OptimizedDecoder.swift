import Foundation
import FT8DSP

public struct FT8OptimizedDecoderConfiguration: Equatable, Sendable {
    public var maximumCandidatesToDecode: Int
    public var minimumCandidateConfidence: Float
    public var minimumSoftSymbolConfidence: Float
    public var decodeUnsupportedMessages: Bool
    public var deduplicationTime: Double
    public var deduplicationFrequency: Float
    public var captureCandidateTraces: Bool

    public init(maximumCandidatesToDecode: Int = 140,
    minimumCandidateConfidence: Float = 0.10,
    minimumSoftSymbolConfidence: Float = 0.08,
    decodeUnsupportedMessages: Bool = true,
    deduplicationTime: Double = 0.160,
    deduplicationFrequency: Float = 12.5,
    captureCandidateTraces: Bool = false) {
        self.maximumCandidatesToDecode = maximumCandidatesToDecode
        self.minimumCandidateConfidence = minimumCandidateConfidence
        self.minimumSoftSymbolConfidence = minimumSoftSymbolConfidence
        self.decodeUnsupportedMessages = decodeUnsupportedMessages
        self.deduplicationTime = deduplicationTime
        self.deduplicationFrequency = deduplicationFrequency
        self.captureCandidateTraces = captureCandidateTraces
    }

    func validate() throws {
        guard maximumCandidatesToDecode > 0,
        (0 ... 1).contains(minimumCandidateConfidence),
        (0 ... 1).contains(minimumSoftSymbolConfidence),
        deduplicationTime >= 0,
        deduplicationFrequency >= 0 else {
            throw FT8OptimizedDecoderError.invalidConfiguration
        }
    }
}

public enum FT8OptimizedDecoderError: Error, Equatable, Sendable {
    case invalidConfiguration
}

public struct FT8DecodeMetrics: Equatable, Sendable {
    public let candidatesFound: Int
    public let candidatesScheduled: Int
    public let softSymbolsExtracted: Int
    public let ldpcAttempts: Int
    public let parityPassed: Int
    public let crcPassed: Int
    public let messagesReturned: Int
    public let elapsedSeconds: Double

    public init(candidatesFound: Int,
    candidatesScheduled: Int,
    softSymbolsExtracted: Int,
    ldpcAttempts: Int,
    parityPassed: Int,
    crcPassed: Int,
    messagesReturned: Int,
    elapsedSeconds: Double) {
        self.candidatesFound = candidatesFound
        self.candidatesScheduled = candidatesScheduled
        self.softSymbolsExtracted = softSymbolsExtracted
        self.ldpcAttempts = ldpcAttempts
        self.parityPassed = parityPassed
        self.crcPassed = crcPassed
        self.messagesReturned = messagesReturned
        self.elapsedSeconds = elapsedSeconds
    }
}

public struct FT8DecodeBatch: Equatable, Sendable {
    public let messages: [FT8CompleteDecode]
    public let metrics: FT8DecodeMetrics
    public let candidateTraces: [FT8CandidateTrace]

    public init(
        messages: [FT8CompleteDecode],
        metrics: FT8DecodeMetrics,
        candidateTraces: [FT8CandidateTrace] = []
    ) {
        self.messages = messages
        self.metrics = metrics
        self.candidateTraces = candidateTraces
    }
}

public struct FT8OptimizedDecoder: Sendable {
    public var configuration: FT8OptimizedDecoderConfiguration
    public var synchronizer: FT8Synchronizer
    public var extractor: SoftSymbolExtractor
    public var ldpcDecoder: FT8LDPCDecoder
    public var messageDecoder: FT8MessageDecoder

    public init(configuration: FT8OptimizedDecoderConfiguration = .init(),
    synchronizer: FT8Synchronizer = .init(),
    extractor: SoftSymbolExtractor = .init(),
    ldpcDecoder: FT8LDPCDecoder = .init(),
    messageDecoder: FT8MessageDecoder = .init()) {
        self.configuration = configuration
        self.synchronizer = synchronizer
        self.extractor = extractor
        self.ldpcDecoder = ldpcDecoder
        self.messageDecoder = messageDecoder
    }

    public func decode(spectrogram: Spectrogram) throws -> FT8DecodeBatch {
        try configuration.validate()
        let started = ContinuousClock.now

        trace("[Optimized] Starting synchronizer search")

        let found = try synchronizer.search(
            in: spectrogram
        )

        trace("[Optimized] Synchronizer returned \(found.count) candidates")

        let scheduled = schedule(found)

        trace("[Optimized] Scheduled \(scheduled.count) candidates")

        var softCount = 0
        var ldpcAttempts = 0
        var parityPassed = 0
        var crcPassed = 0
        var decoded: [FT8CompleteDecode] = []
        var candidateTraces: [FT8CandidateTrace] = []
        var retryCandidates: [
            (
                candidate: FT8Candidate,
                softConfidence: Float,
                parityPassed: Bool,
                syndromeWeight: Int
            )
        ] = []

        for (index, candidate) in scheduled.enumerated() {
            trace(
                "[Optimized] Candidate \(index + 1)/\(scheduled.count) " + "time=\(candidate.startTime) " + "frequency=\(candidate.frequency) " + "confidence=\(candidate.confidence)"
            )

            trace("[Optimized] Extracting soft symbols")

            let extraction: FT8SoftSymbolExtraction
            do {
                extraction = try extractor.extractWithTrace(
                    from: spectrogram,
                    candidate: candidate
                )
            } catch {
                trace("[Optimized] Soft-symbol extraction failed: \(error)")
                if configuration.captureCandidateTraces {
                    candidateTraces.append(
                        makeTrace(
                            candidate: candidate,
                            candidateIndex: index,
                            extraction: nil,
                            ldpc: nil,
                            decodedText: nil,
                            failure: "softSymbolExtraction: \(error)"
                        )
                    )
                }
                continue
            }

            let soft = extraction.softSymbols
            softCount += 1

            trace(
                "[Optimized] Soft symbols extracted, " + "average confidence=\(soft.averageConfidence)"
            )

            guard soft.averageConfidence >= configuration.minimumSoftSymbolConfidence else {
                trace("[Optimized] Soft-symbol confidence below threshold")
                if configuration.captureCandidateTraces {
                    candidateTraces.append(
                        makeTrace(
                            candidate: candidate,
                            candidateIndex: index,
                            extraction: extraction,
                            ldpc: nil,
                            decodedText: nil,
                            failure: "softSymbolConfidenceBelowThreshold"
                        )
                    )
                }
                continue
            }

            ldpcAttempts += 1

            trace("[Optimized] Starting LDPC decode")

            let ldpc = try ldpcDecoder.decode(soft)

            trace(
                "[Optimized] LDPC decode returned, " + "parity=\(ldpc.parityPassed), " + "crc=\(ldpc.crcPassed)"
            )

            if ldpc.parityPassed {
                parityPassed += 1
            }

            if ldpc.crcPassed {
                crcPassed += 1
            }

            trace("[Optimized] Starting message decode")

            let primaryMessage = try? messageDecoder.decode(
                ldpc,
                softSymbols: soft
            )
            let primaryText = primaryMessage?.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""

            if let message = primaryMessage,
               !primaryText.isEmpty {
                trace("[Optimized] Message decode returned: \(message.text)")

                if !configuration.decodeUnsupportedMessages,
                   case .unsupported = message.message {
                    trace("[Optimized] Unsupported message skipped")
                    continue
                }

                decoded.append(
                    FT8CompleteDecode(
                        candidate: candidate,
                        softSymbols: soft,
                        ldpc: ldpc,
                        decoded: message
                    )
                )
            } else {
                if candidate.confidence >= 0.68,
                   soft.averageConfidence >= 0.12,
                   soft.averageConfidence <= 0.65,
                   !ldpc.crcPassed {
                    retryCandidates.append(
                        (
                            candidate: candidate,
                            softConfidence:
                                soft.averageConfidence,
                            parityPassed:
                                ldpc.parityPassed,
                            syndromeWeight:
                                ldpc.syndromeWeight
                        )
                    )
                }
                if primaryMessage != nil {
                    trace("[Optimized] Empty decoded message rejected")
                } else {
                    trace("[Optimized] Message decode failed")
                }

                if configuration.captureCandidateTraces {
                    candidateTraces.append(
                        makeTrace(
                            candidate: candidate,
                            candidateIndex: index,
                            extraction: extraction,
                            ldpc: ldpc,
                            decodedText: nil,
                            failure: primaryMessage == nil
                                ? "messageDecodeFailed"
                                : "emptyMessageRejected"
                        )
                    )
                }
                continue
            }

            if configuration.captureCandidateTraces,
               let accepted = decoded.last {
                candidateTraces.append(
                    makeTrace(
                        candidate: accepted.candidate,
                        candidateIndex: index,
                        extraction: extraction,
                        ldpc: accepted.ldpc,
                        decodedText: accepted.decoded.text,
                        failure: nil
                    )
                )
            }
        }

        if decoded.isEmpty,
           !retryCandidates.isEmpty {
            let orderedRetries = retryCandidates.sorted {
                if $0.parityPassed != $1.parityPassed {
                    return $0.parityPassed
                }

                if $0.syndromeWeight != $1.syndromeWeight {
                    return $0.syndromeWeight
                        < $1.syndromeWeight
                }

                let lhsDistance = abs(
                    $0.softConfidence - 0.35
                )
                let rhsDistance = abs(
                    $1.softConfidence - 0.35
                )

                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }

                return $0.candidate.confidence
                    > $1.candidate.confidence
            }

            var retriedFrequencies: [Float] = []
            var retryCount = 0

            for entry in orderedRetries {
                let overlapsEarlierRetry =
                    retriedFrequencies.contains {
                        abs(
                            $0 - entry.candidate.frequency
                        ) < 18.75
                    }

                if overlapsEarlierRetry {
                    continue
                }

                retriedFrequencies.append(
                    entry.candidate.frequency
                )
                retryCount += 1
                trace(
                    "[Optimized] Retrying bounded nearby "
                    + "hypotheses for time="
                    + "\(entry.candidate.startTime) "
                    + "frequency="
                    + "\(entry.candidate.frequency)"
                )

                if let retry = retryStrongCandidate(
                    in: spectrogram,
                    candidate: entry.candidate
                ) {
                    trace(
                        "[Optimized] Nearby hypothesis decoded: "
                        + retry.decode.decoded.text
                    )
                    decoded.append(retry.decode)

                    if decoded.count >= 2 {
                        break
                    }
                }

                if retryCount >= 6 {
                    break
                }
            }
        }

        trace("[Optimized] Deduplicating \(decoded.count) decoded messages")

        let messages = deduplicate(decoded)
        let duration = ContinuousClock.now - started
        let components = duration.components
        let elapsed = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000

        trace(
            "[Optimized] Complete: \(messages.count) messages " + "in \(elapsed) seconds"
        )

        return FT8DecodeBatch(
            messages: messages,
            metrics: FT8DecodeMetrics(
                candidatesFound: found.count,
                candidatesScheduled: scheduled.count,
                softSymbolsExtracted: softCount,
                ldpcAttempts: ldpcAttempts,
                parityPassed: parityPassed,
                crcPassed: crcPassed,
                messagesReturned: messages.count,
                elapsedSeconds: elapsed
            ),
            candidateTraces: candidateTraces
        )
    }

    private func makeTrace(
        candidate: FT8Candidate,
        candidateIndex: Int,
        extraction: FT8SoftSymbolExtraction?,
        ldpc: FT8LDPCResult?,
        decodedText: String?,
        failure: String?
    ) -> FT8CandidateTrace {
        FT8CandidateTrace(
            pass: 0,
            candidateIndex: candidateIndex,
            startTime: candidate.startTime,
            frequency: candidate.frequency,
            driftHzPerSecond: candidate.driftHzPerSecond,
            syncScore: candidate.syncScore,
            snrDB: candidate.snrDB,
            candidateConfidence: candidate.confidence,
            averageSoftSymbolConfidence: extraction?.softSymbols.averageConfidence,
            symbols: extraction?.symbols ?? [],
            logLikelihoodRatios: extraction?.softSymbols.logLikelihoodRatios ?? [],
            ldpcIterations: ldpc?.iterations,
            syndromeWeight: ldpc?.syndromeWeight,
            parityPassed: ldpc?.parityPassed,
            crcPassed: ldpc?.crcPassed,
            decodedText: decodedText,
            failure: failure
        )
    }

    public func schedule(_ candidates: [FT8Candidate]) -> [FT8Candidate] {
        candidates
        .filter {
            $0.confidence >= configuration.minimumCandidateConfidence
        }
        .sorted {
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            if $0.syncScore != $1.syncScore {
                return $0.syncScore > $1.syncScore
            }
            if $0.snrDB != $1.snrDB {
                return $0.snrDB > $1.snrDB
            }
            if $0.startTime != $1.startTime {
                return $0.startTime < $1.startTime
            }
            return $0.frequency < $1.frequency
        }
        .prefix(configuration.maximumCandidatesToDecode)
        .map { $0 }
    }

    private func deduplicate(_ decodes: [FT8CompleteDecode]) -> [FT8CompleteDecode] {
        var accepted: [FT8CompleteDecode] = []

        for decode in decodes.sorted(by: {
            $0.decoded.confidence > $1.decoded.confidence
        }) {
            let isDuplicate = accepted.contains {
                $0.decoded.payload == decode.decoded.payload && abs($0.candidate.startTime - decode.candidate.startTime) <= configuration.deduplicationTime && abs($0.candidate.frequency - decode.candidate.frequency) <= configuration.deduplicationFrequency
            }

            if !isDuplicate {
                accepted.append(decode)
            }
        }

        return accepted.sorted {
            if $0.candidate.startTime == $1.candidate.startTime {
                return $0.candidate.frequency < $1.candidate.frequency
            }
            return $0.candidate.startTime < $1.candidate.startTime
        }
    }

    private func trace(_ message: String) {
        FileHandle.standardError.write(
            Data("\(message)\n".utf8)
        )
    }

}
