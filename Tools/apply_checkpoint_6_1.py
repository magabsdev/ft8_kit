#!/usr/bin/env python3
from pathlib import Path
import sys

path = Path("Sources/FT8Decoder/FT8ParallelDecoder.swift")
if not path.exists():
    sys.exit(f"Missing {path}")

source = path.read_text()

def replace(old: str, new: str, label: str) -> None:
    global source
    if old not in source:
        sys.exit(f"Could not find {label}.")
    source = source.replace(old, new, 1)

replace(
'''        let decoded = outcomes.compactMap(\\.decode)
        let messages = deduplicate(decoded)
''',
'''        var decoded = outcomes.compactMap(\\.decode)

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
''',
"decoded-message collection block"
)

replace(
'''                return CandidateOutcome(
                    index: index,
                    elapsedSeconds: Self.seconds(
                        from: ContinuousClock.now - started
                    )
                )
''',
'''                return CandidateOutcome(
                    index: index,
                    candidate: candidate,
                    elapsedSeconds: Self.seconds(
                        from: ContinuousClock.now - started
                    )
                )
''',
"extraction-failure outcome"
)

replace(
'''                return CandidateOutcome(
                    index: index,
                    softSymbolsExtracted: true,
                    elapsedSeconds: Self.seconds(
                        from: ContinuousClock.now - started
                    )
                )
''',
'''                return CandidateOutcome(
                    index: index,
                    candidate: candidate,
                    softConfidence: soft.averageConfidence,
                    softSymbolsExtracted: true,
                    elapsedSeconds: Self.seconds(
                        from: ContinuousClock.now - started
                    )
                )
''',
"low-confidence outcome"
)

replace(
'''                return CandidateOutcome(
                    index: index,
                    softSymbolsExtracted: true,
                    ldpcAttempted: true,
                    elapsedSeconds: Self.seconds(
                        from: ContinuousClock.now - started
                    )
                )
''',
'''                return CandidateOutcome(
                    index: index,
                    candidate: candidate,
                    softConfidence: soft.averageConfidence,
                    softSymbolsExtracted: true,
                    ldpcAttempted: true,
                    elapsedSeconds: Self.seconds(
                        from: ContinuousClock.now - started
                    )
                )
''',
"LDPC-failure outcome"
)

replace(
'''            guard let message = try? messageDecoder.decode(
                ldpc,
                softSymbols: soft
            ) else {
                return CandidateOutcome(
                    index: index,
                    softSymbolsExtracted: true,
                    ldpcAttempted: true,
                    parityPassed: ldpc.parityPassed,
                    crcPassed: ldpc.crcPassed,
                    elapsedSeconds: Self.seconds(
                        from: ContinuousClock.now - started
                    )
                )
            }
''',
'''            let message = try? messageDecoder.decode(
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
''',
"message-decode guard"
)

replace(
'''                return CandidateOutcome(
                    index: index,
                    softSymbolsExtracted: true,
                    ldpcAttempted: true,
                    parityPassed: ldpc.parityPassed,
                    crcPassed: ldpc.crcPassed,
                    elapsedSeconds: Self.seconds(
                        from: ContinuousClock.now - started
                    )
                )
''',
'''                return CandidateOutcome(
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
''',
"unsupported-message outcome"
)

replace(
'''            return CandidateOutcome(
                index: index,
                softSymbolsExtracted: true,
                ldpcAttempted: true,
                parityPassed: ldpc.parityPassed,
                crcPassed: ldpc.crcPassed,
                decode: FT8CompleteDecode(
''',
'''            return CandidateOutcome(
                index: index,
                candidate: candidate,
                softConfidence: soft.averageConfidence,
                softSymbolsExtracted: true,
                ldpcAttempted: true,
                parityPassed: ldpc.parityPassed,
                crcPassed: ldpc.crcPassed,
                syndromeWeight: ldpc.syndromeWeight,
                decode: FT8CompleteDecode(
''',
"successful outcome"
)

marker = '''    private func deduplicate(
        _ decodes: [FT8CompleteDecode]
    ) -> [FT8CompleteDecode] {
'''
helper = '''    private func recoverNearbyHypotheses(
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

'''
replace(marker, helper + marker, "deduplicate insertion point")

start = source.find("private struct CandidateOutcome: Sendable {")
if start < 0:
    sys.exit("Could not find CandidateOutcome.")

source = source[:start] + '''private struct CandidateOutcome: Sendable {
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
'''

path.write_text(source)
print(f"Patched {path}")
