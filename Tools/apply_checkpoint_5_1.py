#!/usr/bin/env python3
from pathlib import Path
import sys

path = Path("Sources/FT8Decoder/FT8OptimizedDecoder.swift")
if not path.exists():
    sys.exit(f"Missing {path}")

source = path.read_text()

old_guard = '''            guard let message = try? messageDecoder.decode(
                ldpc,
                softSymbols: soft
            ) else {
                trace("[Optimized] Message decode failed")
                if configuration.captureCandidateTraces {
                    candidateTraces.append(
                        makeTrace(
                            candidate: candidate,
                            candidateIndex: index,
                            extraction: extraction,
                            ldpc: ldpc,
                            decodedText: nil,
                            failure: "messageDecodeFailed"
                        )
                    )
                }
                continue
            }

            trace("[Optimized] Message decode returned: \\(message.text)")

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
'''

new_guard = '''            let primaryMessage = try? messageDecoder.decode(
                ldpc,
                softSymbols: soft
            )
            let primaryText = primaryMessage?.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""

            if let message = primaryMessage,
               !primaryText.isEmpty {
                trace("[Optimized] Message decode returned: \\(message.text)")

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
            } else if index < 12,
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
'''

if old_guard not in source:
    sys.exit(
        "Expected FT8OptimizedDecoder message block was not found. "
        "The repository differs from the reviewed main branch."
    )
source = source.replace(old_guard, new_guard, 1)

old_trace = '''            if configuration.captureCandidateTraces {
                candidateTraces.append(
                    makeTrace(
                        candidate: candidate,
                        candidateIndex: index,
                        extraction: extraction,
                        ldpc: ldpc,
                        decodedText: message.text,
                        failure: nil
                    )
                )
            }
'''

new_trace = '''            if configuration.captureCandidateTraces,
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
'''

if old_trace not in source:
    sys.exit("Expected candidate trace block was not found.")
source = source.replace(old_trace, new_trace, 1)

path.write_text(source)
print(f"Patched {path}")
