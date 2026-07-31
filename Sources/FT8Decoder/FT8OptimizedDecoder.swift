import Foundation
import FT8DSP

public struct FT8OptimizedDecoderConfiguration: Equatable, Sendable {
    public var maximumCandidatesToDecode: Int
    public var minimumCandidateConfidence: Float
    public var minimumSoftSymbolConfidence: Float
    public var decodeUnsupportedMessages: Bool
    public var deduplicationTime: Double
    public var deduplicationFrequency: Float

    public init(maximumCandidatesToDecode: Int = 50,
    minimumCandidateConfidence: Float = 0.10,
    minimumSoftSymbolConfidence: Float = 0.08,
    decodeUnsupportedMessages: Bool = true,
    deduplicationTime: Double = 0.160,
    deduplicationFrequency: Float = 12.5) {
        self.maximumCandidatesToDecode = maximumCandidatesToDecode
        self.minimumCandidateConfidence = minimumCandidateConfidence
        self.minimumSoftSymbolConfidence = minimumSoftSymbolConfidence
        self.decodeUnsupportedMessages = decodeUnsupportedMessages
        self.deduplicationTime = deduplicationTime
        self.deduplicationFrequency = deduplicationFrequency
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

    public init(messages: [FT8CompleteDecode],
    metrics: FT8DecodeMetrics) {
        self.messages = messages
        self.metrics = metrics
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

        for (index, candidate) in scheduled.enumerated() {
            trace(
                "[Optimized] Candidate \(index + 1)/\(scheduled.count) " + "time=\(candidate.startTime) " + "frequency=\(candidate.frequency) " + "confidence=\(candidate.confidence)"
            )

            trace("[Optimized] Extracting soft symbols")

            guard let soft = try? extractor.extract(
                from: spectrogram,
                candidate: candidate
            ) else {
                trace("[Optimized] Soft-symbol extraction failed")
                continue
            }

            softCount += 1

            trace(
                "[Optimized] Soft symbols extracted, " + "average confidence=\(soft.averageConfidence)"
            )

            guard soft.averageConfidence >= configuration.minimumSoftSymbolConfidence else {
                trace("[Optimized] Soft-symbol confidence below threshold")
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

            guard let message = try? messageDecoder.decode(
                ldpc,
                softSymbols: soft
            ) else {
                trace("[Optimized] Message decode failed")
                continue
            }

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
            )
        )
    }

    public func schedule(_ candidates: [FT8Candidate]) -> [FT8Candidate] {
        let ordered = candidates
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

        // Avoid spending most LDPC attempts on adjacent representations of
        // the same Costas peak. The synchronizer already performs a first
        // non-maximum-suppression pass, but cancellation and coarse grid
        // searches can still return dense local clusters.
        let timeRadius = max(configuration.deduplicationTime, 0.240)
        let frequencyRadius = max(configuration.deduplicationFrequency, 18.75)

        var scheduled: [FT8Candidate] = []
        scheduled.reserveCapacity(
            min(configuration.maximumCandidatesToDecode, ordered.count)
        )

        for candidate in ordered {
            let overlapsExistingPeak = scheduled.contains {
                abs($0.startTime - candidate.startTime) <= timeRadius &&
                abs($0.frequency - candidate.frequency) <= frequencyRadius
            }

            guard !overlapsExistingPeak else {
                continue
            }

            scheduled.append(candidate)

            if scheduled.count >= configuration.maximumCandidatesToDecode {
                break
            }
        }

        return scheduled
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
