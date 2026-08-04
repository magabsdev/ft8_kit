import Foundation
import FT8DSP

public struct FT8CandidateRetryResult: Sendable {
    public let decode: FT8CompleteDecode
    public let extraction: FT8SoftSymbolExtraction

    public init(
        decode: FT8CompleteDecode,
        extraction: FT8SoftSymbolExtraction
    ) {
        self.decode = decode
        self.extraction = extraction
    }
}

public extension FT8OptimizedDecoder {
    func retryStrongCandidate(
        in spectrogram: Spectrogram,
        candidate: FT8Candidate
    ) -> FT8CandidateRetryResult? {
        let hypotheses: [(time: Double, frequency: Float)] = [
            (-0.040, 0),
            (0.040, 0),
            (0, -1.5625),
            (0, 1.5625),
            (-0.040, -1.5625),
            (-0.040, 1.5625),
            (0.040, -1.5625),
            (0.040, 1.5625),
        ]

        for hypothesis in hypotheses {
            let adjustedTime = max(0, candidate.startTime + hypothesis.time)
            let adjustedFrequency = max(0, candidate.frequency + hypothesis.frequency)

            let adjusted = FT8Candidate(
                startTime: adjustedTime,
                frequency: adjustedFrequency,
                driftHzPerSecond: candidate.driftHzPerSecond,
                symbolOffset: adjustedTime / 0.160,
                syncScore: candidate.syncScore,
                snrDB: candidate.snrDB,
                confidence: candidate.confidence
            )

            guard let extraction = try? extractor.extractWithTrace(
                from: spectrogram,
                candidate: adjusted
            ) else {
                continue
            }

            guard let ldpc = try? ldpcDecoder.decode(extraction.softSymbols),
                  ldpc.parityPassed,
                  ldpc.crcPassed,
                  let message = try? messageDecoder.decode(
                    ldpc,
                    softSymbols: extraction.softSymbols
                  ),
                  !message.text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty else {
                continue
            }

            if !configuration.decodeUnsupportedMessages,
               case .unsupported = message.message {
                continue
            }

            return FT8CandidateRetryResult(
                decode: FT8CompleteDecode(
                    candidate: adjusted,
                    softSymbols: extraction.softSymbols,
                    ldpc: ldpc,
                    decoded: message
                ),
                extraction: extraction
            )
        }

        return nil
    }
}
