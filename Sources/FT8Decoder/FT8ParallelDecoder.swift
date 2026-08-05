import Foundation
import FT8DSP

public enum FT8ParallelDecoderError: Error, Equatable, Sendable {
    case invalidConfiguration
}

public struct FT8ParallelDecoderConfiguration: Equatable, Sendable {
    public var maximumConcurrentTasks: Int

    public init(
        maximumConcurrentTasks: Int = max(
            1,
            ProcessInfo.processInfo.activeProcessorCount
        )
    ) {
        self.maximumConcurrentTasks = maximumConcurrentTasks
    }

    func validate() throws {
        guard maximumConcurrentTasks > 0 else {
            throw FT8ParallelDecoderError.invalidConfiguration
        }
    }
}

public struct FT8ParallelMetrics: Equatable, Sendable {
    public let maximumConcurrentTasks: Int
    public let peakConcurrentTasks: Int
    public let candidateTasksCompleted: Int
    public let averageCandidateLatencySeconds: Double
    public let elapsedSeconds: Double

    public init(
        maximumConcurrentTasks: Int,
        peakConcurrentTasks: Int,
        candidateTasksCompleted: Int,
        averageCandidateLatencySeconds: Double,
        elapsedSeconds: Double
    ) {
        self.maximumConcurrentTasks = maximumConcurrentTasks
        self.peakConcurrentTasks = peakConcurrentTasks
        self.candidateTasksCompleted = candidateTasksCompleted
        self.averageCandidateLatencySeconds = averageCandidateLatencySeconds
        self.elapsedSeconds = elapsedSeconds
    }
}

public struct FT8ParallelDecodeBatch: Equatable, Sendable {
    public let messages: [FT8CompleteDecode]
    public let metrics: FT8DecodeMetrics
    public let parallelMetrics: FT8ParallelMetrics

    public init(
        messages: [FT8CompleteDecode],
        metrics: FT8DecodeMetrics,
        parallelMetrics: FT8ParallelMetrics
    ) {
        self.messages = messages
        self.metrics = metrics
        self.parallelMetrics = parallelMetrics
    }
}

public struct FT8ParallelDecoder: Sendable {
    public var configuration: FT8ParallelDecoderConfiguration
    public var optimizedConfiguration: FT8OptimizedDecoderConfiguration
    public var synchronizer: FT8Synchronizer
    public var extractor: SoftSymbolExtractor
    public var ldpcDecoder: FT8LDPCDecoder
    public var messageDecoder: FT8MessageDecoder

    public init(
        configuration: FT8ParallelDecoderConfiguration = .init(),
        optimizedConfiguration: FT8OptimizedDecoderConfiguration = .init(),
        synchronizer: FT8Synchronizer = .init(),
        extractor: SoftSymbolExtractor = .init(),
        ldpcDecoder: FT8LDPCDecoder = .init(),
        messageDecoder: FT8MessageDecoder = .init()
    ) {
        self.configuration = configuration
        self.optimizedConfiguration = optimizedConfiguration
        self.synchronizer = synchronizer
        self.extractor = extractor
        self.ldpcDecoder = ldpcDecoder
        self.messageDecoder = messageDecoder
    }

    public func decode(
        spectrogram: Spectrogram
    ) async throws -> FT8ParallelDecodeBatch {
        try configuration.validate()
        try optimizedConfiguration.validate()

        let started = ContinuousClock.now
        let candidates = try synchronizer.search(in: spectrogram)
        let scheduled = schedule(candidates)

        let outcomes = await decodeScheduled(
            scheduled,
            spectrogram: spectrogram
        )

        var decoded = outcomes.compactMap(\.decode)

        if decoded.count < 2 {
            decoded.append(
                contentsOf: recoverNearbyHypotheses(
                    outcomes: outcomes,
                    spectrogram: spectrogram,
                    existing: decoded
                )
            )
        }

        let messages = deduplicate(decoded)

        let softCount = outcomes.filter(\.softSymbolsExtracted).count
        let ldpcAttempts = outcomes.filter(\.ldpcAttempted).count
        let parityPassed = outcomes.filter(\.parityPassed).count
        let crcPassed = outcomes.filter(\.crcPassed).count
        let candidateLatency = outcomes.reduce(0) {
            $0 + $1.elapsedSeconds
        }
        let averageLatency = outcomes.isEmpty
            ? 0
            : candidateLatency / Double(outcomes.count)

        let elapsed = Self.seconds(
            from: ContinuousClock.now - started
        )

        return FT8ParallelDecodeBatch(
            messages: messages,
            metrics: FT8DecodeMetrics(
                candidatesFound: candidates.count,
                candidatesScheduled: scheduled.count,
                softSymbolsExtracted: softCount,
                ldpcAttempts: ldpcAttempts,
                parityPassed: parityPassed,
                crcPassed: crcPassed,
                messagesReturned: messages.count,
                elapsedSeconds: elapsed
            ),
            parallelMetrics: FT8ParallelMetrics(
                maximumConcurrentTasks:
                    configuration.maximumConcurrentTasks,
                peakConcurrentTasks: min(
                    configuration.maximumConcurrentTasks,
                    scheduled.count
                ),
                candidateTasksCompleted: outcomes.count,
                averageCandidateLatencySeconds: averageLatency,
                elapsedSeconds: elapsed
            )
        )
    }

    public func schedule(
        _ candidates: [FT8Candidate]
    ) -> [FT8Candidate] {
        candidates
            .filter {
                $0.confidence >=
                    optimizedConfiguration.minimumCandidateConfidence
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
            .prefix(
                optimizedConfiguration.maximumCandidatesToDecode
            )
            .map { $0 }
    }

    private func decodeScheduled(
        _ candidates: [FT8Candidate],
        spectrogram: Spectrogram
    ) async -> [CandidateOutcome] {
        guard !candidates.isEmpty else { return [] }

        let limit = min(
            configuration.maximumConcurrentTasks,
            candidates.count
        )

        return await withTaskGroup(
            of: CandidateOutcome.self,
            returning: [CandidateOutcome].self
        ) { group in
            var nextIndex = 0
            var outcomes: [CandidateOutcome] = []
            outcomes.reserveCapacity(candidates.count)

            for _ in 0..<limit {
                addTask(
                    to: &group,
                    candidate: candidates[nextIndex],
                    index: nextIndex,
                    spectrogram: spectrogram
                )
                nextIndex += 1
            }

            while let outcome = await group.next() {
                outcomes.append(outcome)

                if nextIndex < candidates.count {
                    addTask(
                        to: &group,
                        candidate: candidates[nextIndex],
                        index: nextIndex,
                        spectrogram: spectrogram
                    )
                    nextIndex += 1
                }
            }

            return outcomes.sorted { $0.index < $1.index }
        }
    }

    private func addTask(
        to group: inout TaskGroup<CandidateOutcome>,
        candidate: FT8Candidate,
        index: Int,
        spectrogram: Spectrogram
    ) {
        let extractor = self.extractor
        let ldpcDecoder = self.ldpcDecoder
        let messageDecoder = self.messageDecoder
        let optimizedConfiguration = self.optimizedConfiguration

        group.addTask {
            let started = ContinuousClock.now

            guard let soft = try? extractor.extract(
                from: spectrogram,
                candidate: candidate
            ) else {
                return CandidateOutcome(
                    index: index,
                    candidate: candidate,
                    elapsedSeconds: Self.seconds(
                        from: ContinuousClock.now - started
                    )
                )
            }

            guard soft.averageConfidence >=
                    optimizedConfiguration.minimumSoftSymbolConfidence
            else {
                return CandidateOutcome(
                    index: index,
                    candidate: candidate,
                    softConfidence: soft.averageConfidence,
                    softSymbolsExtracted: true,
                    elapsedSeconds: Self.seconds(
                        from: ContinuousClock.now - started
                    )
                )
            }

            guard let ldpc = try? ldpcDecoder.decode(soft) else {
                return CandidateOutcome(
                    index: index,
                    candidate: candidate,
                    softConfidence: soft.averageConfidence,
                    softSymbolsExtracted: true,
                    ldpcAttempted: true,
                    elapsedSeconds: Self.seconds(
                        from: ContinuousClock.now - started
                    )
                )
            }

            let message = try? messageDecoder.decode(
                ldpc,
                softSymbols: soft
            )
            let messageText = message?.text
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""

            guard let message,
                  !messageText.isEmpty else {
                return CandidateOutcome(
                    index: index,
                    candidate: candidate,
                    softConfidence: soft.averageConfidence,
                    softSymbolsExtracted: true,
                    ldpcAttempted: true,
                    parityPassed: ldpc.parityPassed,
                    crcPassed: ldpc.crcPassed,
                    syndromeWeight: ldpc.syndromeWeight,
                    elapsedSeconds: Self.seconds(
                        from: ContinuousClock.now - started
                    )
                )
            }

            if !optimizedConfiguration.decodeUnsupportedMessages,
               case .unsupported = message.message {
                return CandidateOutcome(
                    index: index,
                    candidate: candidate,
                    softConfidence: soft.averageConfidence,
                    softSymbolsExtracted: true,
                    ldpcAttempted: true,
                    parityPassed: ldpc.parityPassed,
                    crcPassed: ldpc.crcPassed,
                    syndromeWeight: ldpc.syndromeWeight,
                    elapsedSeconds: Self.seconds(
                        from: ContinuousClock.now - started
                    )
                )
            }

            return CandidateOutcome(
                index: index,
                candidate: candidate,
                softConfidence: soft.averageConfidence,
                softSymbolsExtracted: true,
                ldpcAttempted: true,
                parityPassed: ldpc.parityPassed,
                crcPassed: ldpc.crcPassed,
                syndromeWeight: ldpc.syndromeWeight,
                decode: FT8CompleteDecode(
                    candidate: candidate,
                    softSymbols: soft,
                    ldpc: ldpc,
                    decoded: message
                ),
                elapsedSeconds: Self.seconds(
                    from: ContinuousClock.now - started
                )
            )
        }
    }

    private func recoverNearbyHypotheses(
        outcomes: [CandidateOutcome],
        spectrogram: Spectrogram,
        existing: [FT8CompleteDecode]
    ) -> [FT8CompleteDecode] {
        let optimized = FT8OptimizedDecoder(
            configuration: optimizedConfiguration,
            synchronizer: synchronizer,
            extractor: extractor,
            ldpcDecoder: ldpcDecoder,
            messageDecoder: messageDecoder
        )

        let ordered = outcomes
            .filter {
                $0.decode == nil
                    && !$0.crcPassed
                    && $0.candidate.confidence >= 0.68
                    && $0.softConfidence >= 0.12
                    && $0.softConfidence <= 0.65
            }
            .sorted {
                if $0.parityPassed != $1.parityPassed {
                    return $0.parityPassed
                }
                if $0.syndromeWeight != $1.syndromeWeight {
                    return $0.syndromeWeight < $1.syndromeWeight
                }
                let lhs = abs($0.softConfidence - 0.35)
                let rhs = abs($1.softConfidence - 0.35)
                if lhs != rhs {
                    return lhs < rhs
                }
                return $0.candidate.confidence
                    > $1.candidate.confidence
            }

        var recovered: [FT8CompleteDecode] = []
        var frequencies: [Float] = []

        for outcome in ordered {
            if frequencies.contains(where: {
                abs($0 - outcome.candidate.frequency) < 18.75
            }) {
                continue
            }

            frequencies.append(outcome.candidate.frequency)

            if let result = optimized.retryStrongCandidate(
                in: spectrogram,
                candidate: outcome.candidate
            ) {
                let duplicate = (existing + recovered).contains {
                    $0.decoded.payload
                        == result.decode.decoded.payload
                }
                if !duplicate {
                    recovered.append(result.decode)
                }
            }

            if existing.count + recovered.count >= 2 {
                break
            }
            if frequencies.count >= 6 {
                break
            }
        }

        return recovered
    }

    private func deduplicate(
        _ decodes: [FT8CompleteDecode]
    ) -> [FT8CompleteDecode] {
        var accepted: [FT8CompleteDecode] = []

        for decode in decodes.sorted(by: {
            $0.decoded.confidence > $1.decoded.confidence
        }) {
            let isDuplicate = accepted.contains {
                $0.decoded.payload == decode.decoded.payload &&
                abs(
                    $0.candidate.startTime -
                    decode.candidate.startTime
                ) <= optimizedConfiguration.deduplicationTime &&
                abs(
                    $0.candidate.frequency -
                    decode.candidate.frequency
                ) <= optimizedConfiguration.deduplicationFrequency
            }

            if !isDuplicate {
                accepted.append(decode)
            }
        }

        return accepted.sorted {
            if $0.candidate.startTime == $1.candidate.startTime {
                return $0.candidate.frequency <
                    $1.candidate.frequency
            }
            return $0.candidate.startTime <
                $1.candidate.startTime
        }
    }

    private static func seconds(
        from duration: Duration
    ) -> Double {
        let components = duration.components
        return Double(components.seconds) +
            Double(components.attoseconds) /
            1_000_000_000_000_000_000
    }
}

private struct CandidateOutcome: Sendable {
    let index: Int
    let candidate: FT8Candidate
    let softConfidence: Float
    let softSymbolsExtracted: Bool
    let ldpcAttempted: Bool
    let parityPassed: Bool
    let crcPassed: Bool
    let syndromeWeight: Int
    let decode: FT8CompleteDecode?
    let elapsedSeconds: Double

    init(
        index: Int,
        candidate: FT8Candidate,
        softConfidence: Float = 0,
        softSymbolsExtracted: Bool = false,
        ldpcAttempted: Bool = false,
        parityPassed: Bool = false,
        crcPassed: Bool = false,
        syndromeWeight: Int = .max,
        decode: FT8CompleteDecode? = nil,
        elapsedSeconds: Double
    ) {
        self.index = index
        self.candidate = candidate
        self.softConfidence = softConfidence
        self.softSymbolsExtracted = softSymbolsExtracted
        self.ldpcAttempted = ldpcAttempted
        self.parityPassed = parityPassed
        self.crcPassed = crcPassed
        self.syndromeWeight = syndromeWeight
        self.decode = decode
        self.elapsedSeconds = elapsedSeconds
    }
}
