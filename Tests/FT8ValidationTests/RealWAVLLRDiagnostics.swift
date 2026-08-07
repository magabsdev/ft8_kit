import Foundation
import FT8Decoder
import FT8DSP

enum RealWAVLLRDiagnosticError: Error, Equatable {
    case missingPipelineRecord(Int)
    case missingCandidate(Int)
    case invalidExpectedBits(candidate: Int, symbol: Int, actual: Int)
    case invalidDecodedBits(candidate: Int, actual: Int)
    case invalidRecordedLLRs(candidate: Int, actual: Int)
    case invalidToneMetricCount(candidate: Int, symbol: Int, actual: Int)
}

enum RealWAVLLRDiagnostics {
    static func buildReport(
        recording: String,
        spectrogram: Spectrogram,
        extractor: SoftSymbolExtractor,
        synchronizer: FT8Synchronizer,
        records: [FT8PipelineRecord],
        symbolReport: RealWAVSymbolComparisonReport,
        generatedAt: Date = Date()
    ) throws -> RealWAVLLRReport {
        let candidates = try synchronizer.search(in: spectrogram)
        let recordsByIndex = Dictionary(
            uniqueKeysWithValues: records.map {
                ($0.candidateIndex, $0)
            }
        )
        let symbolRowsByCandidate = Dictionary(
            grouping: symbolReport.rows,
            by: \.candidateIndex
        )

        var output: [RealWAVLLRRow] = []
        output.reserveCapacity(
            symbolReport.rows.count * 3
        )

        for candidateIndex in symbolRowsByCandidate.keys.sorted() {
            guard let record = recordsByIndex[candidateIndex] else {
                throw RealWAVLLRDiagnosticError.missingPipelineRecord(
                    candidateIndex
                )
            }

            guard record.interleavedBits.count
                    == FT8PipelineRecord.channelBitCount else {
                throw RealWAVLLRDiagnosticError.invalidDecodedBits(
                    candidate: candidateIndex,
                    actual: record.interleavedBits.count
                )
            }

            guard record.logLikelihoodRatios.count
                    == FT8PipelineRecord.llrCount else {
                throw RealWAVLLRDiagnosticError.invalidRecordedLLRs(
                    candidate: candidateIndex,
                    actual: record.logLikelihoodRatios.count
                )
            }

            guard let candidate = nearestCandidate(
                to: record,
                candidates: candidates
            ) else {
                throw RealWAVLLRDiagnosticError.missingCandidate(
                    candidateIndex
                )
            }

            guard let symbolRows = symbolRowsByCandidate[candidateIndex] else {
                continue
            }

            for symbolRow in symbolRows.sorted(by: {
                $0.dataSymbolIndex < $1.dataSymbolIndex
            }) {
                guard symbolRow.expectedGrayBits.count == 3 else {
                    throw RealWAVLLRDiagnosticError.invalidExpectedBits(
                        candidate: candidateIndex,
                        symbol: symbolRow.receivedSymbolIndex,
                        actual: symbolRow.expectedGrayBits.count
                    )
                }

                let metrics = try extractor.toneMetrics(
                    symbolIndex: symbolRow.receivedSymbolIndex,
                    spectrogram: spectrogram,
                    candidate: candidate
                )

                guard metrics.count == 8 else {
                    throw RealWAVLLRDiagnosticError.invalidToneMetricCount(
                        candidate: candidateIndex,
                        symbol: symbolRow.receivedSymbolIndex,
                        actual: metrics.count
                    )
                }

                let ranked = metrics.enumerated().sorted {
                    if $0.element == $1.element {
                        return $0.offset < $1.offset
                    }
                    return $0.element > $1.element
                }

                let winner = ranked[0]
                let runnerUp = ranked[1]

                for bitIndex in 0..<3 {
                    let globalBitIndex =
                        symbolRow.dataSymbolIndex * 3 + bitIndex

                    let extrema = bestMetrics(
                        forBitIndex: bitIndex,
                        metrics: metrics
                    )

                    let rawDifference =
                        extrema.zero - extrema.one
                    let recomputedLLR =
                        rawDifference
                        * extractor.configuration.llrScale
                    let recordedLLR =
                        record.logLikelihoodRatios[globalBitIndex]

                    let expectedBit =
                        symbolRow.expectedGrayBits[bitIndex]
                    let decodedBit =
                        record.interleavedBits[globalBitIndex]
                    let llrHardBit: UInt8 =
                        recordedLLR < 0 ? 1 : 0

                    output.append(
                        RealWAVLLRRow(
                            candidateIndex: candidateIndex,
                            referenceMessage:
                                symbolRow.referenceMessage,
                            globalBitIndex: globalBitIndex,
                            dataSymbolIndex:
                                symbolRow.dataSymbolIndex,
                            receivedSymbolIndex:
                                symbolRow.receivedSymbolIndex,
                            bitIndexInSymbol: bitIndex,
                            expectedTone:
                                symbolRow.expectedTone,
                            detectedTone:
                                symbolRow.detectedTone,
                            winningTone:
                                UInt8(winner.offset),
                            runnerUpTone:
                                UInt8(runnerUp.offset),
                            toneMetricsDB: metrics,
                            winningMetricDB:
                                winner.element,
                            runnerUpMetricDB:
                                runnerUp.element,
                            winningMarginDB:
                                winner.element - runnerUp.element,
                            bestZeroMetricDB:
                                extrema.zero,
                            bestOneMetricDB:
                                extrema.one,
                            rawMetricDifference:
                                rawDifference,
                            recomputedLLR:
                                recomputedLLR,
                            recordedLLR:
                                recordedLLR,
                            llrDelta:
                                recordedLLR - recomputedLLR,
                            expectedBit:
                                expectedBit,
                            decodedBit:
                                decodedBit,
                            llrHardBit:
                                llrHardBit,
                            llrSignMatchesExpected:
                                llrHardBit == expectedBit,
                            decodedBitMatchesExpected:
                                decodedBit == expectedBit,
                            llrMagnitude:
                                abs(recordedLLR)
                        )
                    )
                }
            }
        }

        return RealWAVLLRReport(
            recording: recording,
            generatedAt: generatedAt,
            rows: output,
            summary: makeSummary(rows: output)
        )
    }

    private static func bestMetrics(
        forBitIndex bitIndex: Int,
        metrics: [Float]
    ) -> (zero: Float, one: Float) {
        var zero = -Float.infinity
        var one = -Float.infinity

        for tone in 0..<8 {
            let bits = FT8ToneMapping.bits(forTone: tone)
            let bit: UInt8

            switch bitIndex {
            case 0:
                bit = bits.0
            case 1:
                bit = bits.1
            default:
                bit = bits.2
            }

            if bit == 0 {
                zero = max(zero, metrics[tone])
            } else {
                one = max(one, metrics[tone])
            }
        }

        return (zero, one)
    }

    private static func makeSummary(
        rows: [RealWAVLLRRow]
    ) -> RealWAVLLRSummary {
        let bitCount = rows.count
        let correctDecoded = rows.count {
            $0.decodedBitMatchesExpected
        }
        let correctSigns = rows.count {
            $0.llrSignMatchesExpected
        }

        let correctRows = rows.filter {
            $0.decodedBitMatchesExpected
        }
        let incorrectRows = rows.filter {
            !$0.decodedBitMatchesExpected
        }

        let below025 = rows.count { $0.llrMagnitude < 0.25 }
        let below050 = rows.count { $0.llrMagnitude < 0.50 }
        let below100 = rows.count { $0.llrMagnitude < 1.00 }

        return RealWAVLLRSummary(
            bitCount: bitCount,
            correctDecodedBits: correctDecoded,
            incorrectDecodedBits: bitCount - correctDecoded,
            correctLLRSigns: correctSigns,
            incorrectLLRSigns: bitCount - correctSigns,
            averageAbsoluteLLR:
                averageMagnitude(rows),
            averageAbsoluteLLRCorrectBits:
                averageMagnitude(correctRows),
            averageAbsoluteLLRIncorrectBits:
                averageMagnitude(incorrectRows),
            below025Count: below025,
            below050Count: below050,
            below100Count: below100,
            wrongSignPercentage:
                percentage(bitCount - correctSigns, total: bitCount),
            below025Percentage:
                percentage(below025, total: bitCount),
            below050Percentage:
                percentage(below050, total: bitCount),
            below100Percentage:
                percentage(below100, total: bitCount),
            maximumAbsoluteRecomputedVsRecordedDelta:
                rows.map { abs($0.llrDelta) }.max() ?? 0,
            histogram: makeHistogram(rows: rows)
        )
    }

    private static func averageMagnitude(
        _ rows: [RealWAVLLRRow]
    ) -> Float {
        guard !rows.isEmpty else { return 0 }
        return rows.reduce(Float.zero) {
            $0 + $1.llrMagnitude
        } / Float(rows.count)
    }

    private static func percentage(
        _ value: Int,
        total: Int
    ) -> Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total) * 100
    }

    private static func makeHistogram(
        rows: [RealWAVLLRRow]
    ) -> [RealWAVLLRHistogramBucket] {
        let edges: [Float] = [
            -24, -12, -8, -4, -2, -1, -0.5, -0.25,
            0,
            0.25, 0.5, 1, 2, 4, 8, 12, 24
        ]

        var buckets: [RealWAVLLRHistogramBucket] = []

        buckets.append(
            RealWAVLLRHistogramBucket(
                lowerBound: nil,
                upperBound: edges[0],
                count: rows.count {
                    $0.recordedLLR < edges[0]
                }
            )
        )

        for index in 0..<(edges.count - 1) {
            let lower = edges[index]
            let upper = edges[index + 1]
            buckets.append(
                RealWAVLLRHistogramBucket(
                    lowerBound: lower,
                    upperBound: upper,
                    count: rows.count {
                        $0.recordedLLR >= lower
                            && $0.recordedLLR < upper
                    }
                )
            )
        }

        if let last = edges.last {
            buckets.append(
                RealWAVLLRHistogramBucket(
                    lowerBound: last,
                    upperBound: nil,
                    count: rows.count {
                        $0.recordedLLR >= last
                    }
                )
            )
        }

        return buckets
    }

    private static func nearestCandidate(
        to record: FT8PipelineRecord,
        candidates: [FT8Candidate]
    ) -> FT8Candidate? {
        candidates.min {
            candidateDistance($0, record: record)
                < candidateDistance($1, record: record)
        }
    }

    private static func candidateDistance(
        _ candidate: FT8Candidate,
        record: FT8PipelineRecord
    ) -> Double {
        abs(candidate.startTime - record.startTime)
            + Double(
                abs(candidate.frequency - record.frequency)
            ) / 50
    }
}
