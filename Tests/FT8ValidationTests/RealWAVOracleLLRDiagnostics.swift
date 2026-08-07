import Foundation
import FT8Decoder
import FT8DSP
import FT8Encoder
import FT8Protocol
@testable import FT8Validation

enum RealWAVOracleLLRDiagnosticsError: Error, Equatable {
    case invalidExpectedToneCount(Int)
    case missingSymbolTrace(Int)
    case invalidLLRCount(Int)
}

enum RealWAVOracleLLRDiagnostics {
    static func buildReport(
        recording: String,
        spectrogram: Spectrogram,
        extractor: SoftSymbolExtractor,
        ldpcDecoder: FT8LDPCDecoder,
        references: [WSJTXExpectedDecode],
        generatedAt: Date = Date()
    ) throws -> RealWAVOracleLLRReport {
        var allBits: [RealWAVOracleLLRBitRow] = []
        var summaries: [RealWAVOracleLLRReferenceSummary] = []

        for (referenceIndex, reference) in references.enumerated() {
            let protocolText = stripWSJTXAnnotation(
                from: reference.message
            )

            let expectedTones = try FT8Encoder.encode(
                text: protocolText
            )

            guard expectedTones.count == 79 else {
                throw RealWAVOracleLLRDiagnosticsError
                    .invalidExpectedToneCount(expectedTones.count)
            }

            let payload = try FT8MessageCodec.pack(protocolText)
            let protected = try FT8CRC.append(to: payload)
            let expectedCodeword = try FT8Encoder.encodeLDPC(protected)

            // This checkpoint intentionally bypasses synchronizer uncertainty.
            // Use the WSJT-X reference time/frequency as an oracle and ask:
            // can FT8Kit's extractor + LLR + LDPC path decode the known signal?
            let candidate = FT8Candidate(
                startTime: reference.timeOffset,
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

            let rawLLRs =
                extraction.softSymbols.logLikelihoodRatios

            guard rawLLRs.count == 174 else {
                throw RealWAVOracleLLRDiagnosticsError
                    .invalidLLRCount(rawLLRs.count)
            }

            let normalizedLLRs =
                normalizeLogLikelihoodRatios(rawLLRs)

            let tracesBySymbol = Dictionary(
                uniqueKeysWithValues:
                    extraction.symbols.map {
                        ($0.symbolIndex, $0)
                    }
            )

            var referenceRows: [RealWAVOracleLLRBitRow] = []
            referenceRows.reserveCapacity(174)

            var correctSymbols = 0

            for (dataOrdinal, symbolIndex) in
                FT8ToneMapping.dataSymbolIndices.enumerated()
            {
                guard let trace = tracesBySymbol[symbolIndex] else {
                    throw RealWAVOracleLLRDiagnosticsError
                        .missingSymbolTrace(symbolIndex)
                }

                let metrics = trace.toneMetrics
                let expectedTone = Int(expectedTones[symbolIndex])

                let winningTone = metrics.indices.max {
                    metrics[$0] < metrics[$1]
                } ?? 0

                if winningTone == expectedTone {
                    correctSymbols += 1
                }

                let ordered = metrics.sorted(by: >)
                let winningMetric =
                    ordered.first ?? -Float.infinity
                let runnerUpMetric =
                    ordered.dropFirst().first ?? -Float.infinity

                for bitWithinSymbol in 0..<3 {
                    let bitIndex =
                        dataOrdinal * 3 + bitWithinSymbol
                    let expectedBit =
                        expectedCodeword[bitIndex]
                    let hardBit: UInt8 =
                        rawLLRs[bitIndex] < 0 ? 1 : 0

                    referenceRows.append(
                        RealWAVOracleLLRBitRow(
                            referenceIndex: referenceIndex,
                            referenceMessage: protocolText,
                            bitIndex: bitIndex,
                            dataSymbolOrdinal: dataOrdinal,
                            symbolIndex: symbolIndex,
                            bitWithinSymbol: bitWithinSymbol,
                            expectedTone: expectedTone,
                            winningTone: winningTone,
                            expectedBit: expectedBit,
                            hardBit: hardBit,
                            hardBitCorrect:
                                hardBit == expectedBit,
                            rawLLR: rawLLRs[bitIndex],
                            normalizedLLR:
                                normalizedLLRs[bitIndex],
                            absoluteRawLLR:
                                abs(rawLLRs[bitIndex]),
                            symbolConfidence:
                                trace.confidence,
                            expectedToneMetricDB:
                                trace.toneMetrics[expectedTone],
                            winningToneMetricDB:
                                winningMetric,
                            runnerUpToneMetricDB:
                                runnerUpMetric,
                            toneMetricsDB:
                                trace.toneMetrics
                        )
                    )
                }
            }

            let ldpc = try ldpcDecoder.decode(
                logLikelihoodRatios: rawLLRs
            )

            let correctBits = referenceRows.count {
                $0.hardBitCorrect
            }
            let incorrectBits =
                referenceRows.count - correctBits

            let averageAbsoluteRawLLR =
                referenceRows.isEmpty
                ? 0
                : referenceRows.reduce(0.0) {
                    $0 + Double($1.absoluteRawLLR)
                } / Double(referenceRows.count)

            let averageConfidence =
                extraction.softSymbols.symbolConfidences.isEmpty
                ? 0
                : extraction.softSymbols.symbolConfidences
                    .reduce(0.0) {
                        $0 + Double($1)
                    }
                    / Double(
                        extraction.softSymbols
                            .symbolConfidences.count
                    )

            summaries.append(
                RealWAVOracleLLRReferenceSummary(
                    referenceIndex: referenceIndex,
                    referenceMessage: protocolText,
                    referenceTimeOffset:
                        reference.timeOffset,
                    referenceFrequencyHz:
                        reference.frequencyHz,
                    bitCount: referenceRows.count,
                    correctHardBits: correctBits,
                    incorrectHardBits: incorrectBits,
                    bitAccuracy:
                        Double(correctBits)
                        / Double(referenceRows.count),
                    correctDataSymbols: correctSymbols,
                    dataSymbolCount:
                        FT8ToneMapping
                            .dataSymbolIndices.count,
                    dataSymbolAccuracy:
                        Double(correctSymbols)
                        / Double(
                            FT8ToneMapping
                                .dataSymbolIndices.count
                        ),
                    averageAbsoluteRawLLR:
                        averageAbsoluteRawLLR,
                    averageSymbolConfidence:
                        averageConfidence,
                    ldpcParityPassed:
                        ldpc.parityPassed,
                    ldpcCRCPassed:
                        ldpc.crcPassed,
                    ldpcSyndromeWeight:
                        ldpc.syndromeWeight,
                    ldpcIterations:
                        ldpc.iterations
                )
            )

            allBits.append(contentsOf: referenceRows)
        }

        return RealWAVOracleLLRReport(
            recording: recording,
            generatedAt: generatedAt,
            references: summaries,
            bits: allBits
        )
    }

    private static func normalizeLogLikelihoodRatios(
        _ values: [Float]
    ) -> [Float] {
        guard !values.isEmpty else {
            return values
        }

        var sum: Float = 0
        var sumOfSquares: Float = 0

        for value in values {
            guard value.isFinite else {
                return values
            }

            sum += value
            sumOfSquares += value * value
        }

        let count = Float(values.count)
        let mean = sum / count
        let variance =
            (sumOfSquares / count) - (mean * mean)

        guard variance.isFinite,
              variance > Float.leastNonzeroMagnitude else {
            return values
        }

        let factor = sqrtf(24 / variance)

        guard factor.isFinite else {
            return values
        }

        return values.map { $0 * factor }
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
