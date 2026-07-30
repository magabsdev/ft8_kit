import FT8DSP
import FT8Protocol

public struct FT8CompleteDecode: Equatable, Sendable {
    public let candidate: FT8Candidate
    public let softSymbols: FT8SoftSymbols
    public let ldpc: FT8LDPCResult
    public let decoded: FT8DecodedMessage

    public init(
        candidate: FT8Candidate,
        softSymbols: FT8SoftSymbols,
        ldpc: FT8LDPCResult,
        decoded: FT8DecodedMessage
    ) {
        self.candidate = candidate
        self.softSymbols = softSymbols
        self.ldpc = ldpc
        self.decoded = decoded
    }

    public var message: FT8Message { decoded.message }
    public var text: String { decoded.text }
}

public struct FT8CompleteDecoder: Sendable {
    public var synchronizer: FT8Synchronizer
    public var extractor: SoftSymbolExtractor
    public var ldpcDecoder: FT8LDPCDecoder
    public var messageDecoder: FT8MessageDecoder
    public var includeUnsupportedMessages: Bool

    public init(
        synchronizer: FT8Synchronizer = .init(),
        extractor: SoftSymbolExtractor = .init(),
        ldpcDecoder: FT8LDPCDecoder = .init(),
        messageDecoder: FT8MessageDecoder = .init(),
        includeUnsupportedMessages: Bool = true
    ) {
        self.synchronizer = synchronizer
        self.extractor = extractor
        self.ldpcDecoder = ldpcDecoder
        self.messageDecoder = messageDecoder
        self.includeUnsupportedMessages = includeUnsupportedMessages
    }

    public func decode(spectrogram: Spectrogram) throws -> [FT8CompleteDecode] {
        var output: [FT8CompleteDecode] = []

        for candidate in try synchronizer.search(in: spectrogram) {
            guard let soft = try? extractor.extract(
                from: spectrogram,
                candidate: candidate
            ) else {
                continue
            }

            let ldpc = try ldpcDecoder.decode(soft)
            guard let decoded = try? messageDecoder.decode(
                ldpc,
                softSymbols: soft
            ) else {
                continue
            }

            if !includeUnsupportedMessages,
               case .unsupported = decoded.message {
                continue
            }

            output.append(
                FT8CompleteDecode(
                    candidate: candidate,
                    softSymbols: soft,
                    ldpc: ldpc,
                    decoded: decoded
                )
            )
        }

        return deduplicate(output)
    }

    private func deduplicate(
        _ decodes: [FT8CompleteDecode]
    ) -> [FT8CompleteDecode] {
        var accepted: [FT8CompleteDecode] = []

        for decode in decodes.sorted(by: {
            $0.decoded.confidence > $1.decoded.confidence
        }) {
            let duplicate = accepted.contains {
                $0.decoded.payload == decode.decoded.payload &&
                abs($0.candidate.startTime - decode.candidate.startTime) <= 0.160 &&
                abs($0.candidate.frequency - decode.candidate.frequency) <= 12.5
            }
            if !duplicate {
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
}
