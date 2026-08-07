import Foundation
import FT8Decoder
import FT8DSP
import FT8Encoder
import FT8Protocol
@testable import FT8Validation

enum RealWAVTimingCorrectedDecodeError: Error, Equatable {
    case invalidExpectedToneCount(Int)
    case invalidLLRCount(Int)
}

enum RealWAVTimingCorrectedDecodeDiagnostics {
    static func buildReport(
        recording: String,
        spectrogram: Spectrogram,
        extractor: SoftSymbolExtractor,
        ldpcDecoder: FT8LDPCDecoder,
        references: [WSJTXExpectedDecode],
        timingCorrectionSeconds: Double,
        generatedAt: Date = Date()
    ) throws -> RealWAVTimingCorrectedDecodeReport {
        var rows: [RealWAVTimingCorrectedDecodeReference] = []

        for (referenceIndex, reference) in references.enumerated() {
            let protocolText = stripWSJTXAnnotation(
                from: reference.message
            )

            let expectedTones = try FT8Encoder.encode(
                text: protocolText
            )

            guard expectedTones.count == 79 else {
                throw RealWAVTimingCorrectedDecodeError
                    .invalidExpectedToneCount(expectedTones.count)
            }

            let payload = try FT8MessageCodec.pack(protocolText)
            let protected = try FT8CRC.append(to: payload)
            let expectedCodeword = try FT8Encoder.encodeLDPC(protected)

            let correctedStart =
                reference.timeOffset + timingCorrectionSeconds

            let candidate = FT8Candidate(
                startTime: correctedStart,
                frequency: Float(reference.frequencyHz),
                driftHzPerSecond: 0,
                symbolOffset: 0,
                syncScore: 1,
                snrDB: Float(reference.snrDB),
                confidence: 1
            )

            let extraction = try extractor.extractWithTrace(
                from: spectrogram,
                candidate: candidate
            )

            let llrs = extraction.softSymbols.logLikelihoodRatios

            guard llrs.count == 174 else {
                throw RealWAVTimingCorrectedDecodeError
                    .invalidLLRCount(llrs.count)
            }

            let hardBits = extraction.softSymbols.hardBits

            let correctHardBits = zip(
                hardBits.bits,
                expectedCodeword.bits
            ).reduce(into: 0) { count, pair in
                if pair.0 == pair.1 {
                    count += 1
                }
            }

            let tracesBySymbol = Dictionary(
                uniqueKeysWithValues:
                    extraction.symbols.map {
                        ($0.symbolIndex, $0)
                    }
            )

            var correctDataSymbols = 0

            for symbolIndex in FT8ToneMapping.dataSymbolIndices {
                guard let trace = tracesBySymbol[symbolIndex] else {
                    continue
                }

                let winningTone = trace.toneMetrics.indices.max {
                    trace.toneMetrics[$0] < trace.toneMetrics[$1]
                } ?? 0

                if winningTone == Int(expectedTones[symbolIndex]) {
                    correctDataSymbols += 1
                }
            }

            let ldpc = try ldpcDecoder.decode(
                logLikelihoodRatios: llrs
            )

            rows.append(
                RealWAVTimingCorrectedDecodeReference(
                    referenceIndex: referenceIndex,
                    referenceMessage: protocolText,
                    referenceTimeOffset: reference.timeOffset,
                    correctedStartTime: correctedStart,
                    referenceFrequencyHz: reference.frequencyHz,
                    correctHardBits: correctHardBits,
                    bitCount: expectedCodeword.count,
                    bitAccuracy:
                        Double(correctHardBits)
                        / Double(expectedCodeword.count),
                    correctDataSymbols: correctDataSymbols,
                    dataSymbolCount:
                        FT8ToneMapping.dataSymbolIndices.count,
                    dataSymbolAccuracy:
                        Double(correctDataSymbols)
                        / Double(
                            FT8ToneMapping.dataSymbolIndices.count
                        ),
                    parityPassed: ldpc.parityPassed,
                    crcPassed: ldpc.crcPassed,
                    syndromeWeight: ldpc.syndromeWeight,
                    iterations: ldpc.iterations
                )
            )
        }

        return RealWAVTimingCorrectedDecodeReport(
            recording: recording,
            generatedAt: generatedAt,
            timingCorrectionSeconds: timingCorrectionSeconds,
            parityPassingReferences:
                rows.count { $0.parityPassed },
            crcPassingReferences:
                rows.count { $0.crcPassed },
            references: rows
        )
    }

    private static func stripWSJTXAnnotation(
        from message: String
    ) -> String {
        let trimmed = message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard let range = trimmed.range(
            of: #"\s{2,}"#,
            options: .regularExpression
        ) else {
            return trimmed
        }

        return String(trimmed[..<range.lowerBound])
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }
}
