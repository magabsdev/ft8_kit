#!/usr/bin/env python3
from pathlib import Path
import sys

path = Path("Sources/FT8Decoder/FT8OptimizedDecoder.swift")
if not path.exists():
    sys.exit(f"Missing {path}")

source = path.read_text()

old_state = '''        var retryCandidates: [
            (
                candidate: FT8Candidate,
                softConfidence: Float
            )
        ] = []
'''

new_state = '''        var retryCandidates: [
            (
                candidate: FT8Candidate,
                softConfidence: Float,
                parityPassed: Bool,
                syndromeWeight: Int
            )
        ] = []
'''

if old_state not in source:
    sys.exit("Could not find Checkpoint 5.2 retry state.")
source = source.replace(old_state, new_state, 1)

old_collect = '''                if index < 12,
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

new_collect = '''                if candidate.confidence >= 0.68,
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
'''

if old_collect not in source:
    sys.exit("Could not find Checkpoint 5.2 retry collection block.")
source = source.replace(old_collect, new_collect, 1)

old_sort = '''            let orderedRetries = retryCandidates.sorted {
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
'''

new_sort = '''            let orderedRetries = retryCandidates.sorted {
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
'''

if old_sort not in source:
    sys.exit("Could not find Checkpoint 5.2 retry ordering block.")
source = source.replace(old_sort, new_sort, 1)

old_end = '''                    decoded.append(retry.decode)
                    break
                }
            }
        }
'''

new_end = '''                    decoded.append(retry.decode)

                    if decoded.count >= 2 {
                        break
                    }
                }

                if retryCount >= 6 {
                    break
                }
            }
        }
'''

if old_end not in source:
    sys.exit("Could not find Checkpoint 5.2 retry loop ending.")
source = source.replace(old_end, new_end, 1)

path.write_text(source)
print(f"Patched {path}")
