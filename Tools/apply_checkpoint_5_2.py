#!/usr/bin/env python3
from pathlib import Path
import sys

path = Path("Sources/FT8Decoder/FT8OptimizedDecoder.swift")
if not path.exists():
    sys.exit(f"Missing {path}")

source = path.read_text()

old_state = '''        var decoded: [FT8CompleteDecode] = []
        var candidateTraces: [FT8CandidateTrace] = []
'''

new_state = '''        var decoded: [FT8CompleteDecode] = []
        var candidateTraces: [FT8CandidateTrace] = []
        var retryCandidates: [
            (
                candidate: FT8Candidate,
                softConfidence: Float
            )
        ] = []
'''

if old_state not in source:
    sys.exit("Could not find decoder state block.")
source = source.replace(old_state, new_state, 1)

old_branch = '''            } else if index < 12,
                      candidate.confidence >= 0.70,
                      let retry = retryStrongCandidate(
                        in: spectrogram,
                        candidate: candidate
                      ) {
                trace(
                    "[Optimized] Nearby hypothesis decoded: "
                    + retry.decode.decoded.text
                )
                decoded.append(retry.decode)
            } else {
'''

new_branch = '''            } else {
                if index < 12,
                   candidate.confidence >= 0.85,
                   soft.averageConfidence >= 0.12,
                   soft.averageConfidence <= 0.55,
                   !ldpc.parityPassed,
                   !ldpc.crcPassed {
                    retryCandidates.append(
                        (
                            candidate: candidate,
                            softConfidence:
                                soft.averageConfidence
                        )
                    )
                }
'''

if old_branch not in source:
    sys.exit("Could not find inline retry block.")
source = source.replace(old_branch, new_branch, 1)

old_after_loop = '''        trace("[Optimized] Deduplicating \\(decoded.count) decoded messages")

        let messages = deduplicate(decoded)
'''

new_after_loop = '''        if decoded.isEmpty,
           !retryCandidates.isEmpty {
            let orderedRetries = retryCandidates.sorted {
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

            for entry in orderedRetries.prefix(2) {
                trace(
                    "[Optimized] Retrying bounded nearby "
                    + "hypotheses for time="
                    + "\\(entry.candidate.startTime) "
                    + "frequency="
                    + "\\(entry.candidate.frequency)"
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
                    break
                }
            }
        }

        trace("[Optimized] Deduplicating \\(decoded.count) decoded messages")

        let messages = deduplicate(decoded)
'''

if old_after_loop not in source:
    sys.exit("Could not find decoder post-loop block.")
source = source.replace(old_after_loop, new_after_loop, 1)

path.write_text(source)
print(f"Patched {path}")
