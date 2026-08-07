import Foundation
import FT8Decoder
import FT8DSP

enum RealWAVToneMetricDiagnosticError: Error, Equatable {
    case missingCandidate(Int)
    case missingFrame(candidate: Int, symbol: Int)
    case invalidMetricCount(candidate: Int, symbol: Int, actual: Int)
}

enum RealWAVToneMetricDiagnostics {
    static func buildReport(
        recording: String,
        sampleRate: Int,
        spectrogram: Spectrogram,
        extractor: SoftSymbolExtractor,
        synchronizer: FT8Synchronizer,
        records: [FT8PipelineRecord],
        symbolReport: RealWAVSymbolComparisonReport,
        generatedAt: Date = Date()
    ) throws -> RealWAVToneMetricReport {
        let foundCandidates = try synchronizer.search(in: spectrogram)
        let symbolRowsByCandidate = Dictionary(
            grouping: symbolReport.rows,
            by: \.candidateIndex
        )

        var rows: [RealWAVToneMetricRow] = []

        for record in records.sorted(by: {
            $0.candidateIndex < $1.candidateIndex
        }) {
            guard let symbolRows = symbolRowsByCandidate[record.candidateIndex],
                  !symbolRows.isEmpty else {
                continue
            }

            guard let candidate = nearestCandidate(
                to: record,
                candidates: foundCandidates
            ) else {
                throw RealWAVToneMetricDiagnosticError.missingCandidate(
                    record.candidateIndex
                )
            }

            for symbolRow in symbolRows.sorted(by: {
                $0.dataSymbolIndex < $1.dataSymbolIndex
            }) {
                let receivedSymbolIndex = symbolRow.receivedSymbolIndex
                let symbolStartTime = candidate.startTime
                    + Double(receivedSymbolIndex)
                    * extractor.configuration.symbolPeriod

                guard let frame = spectrogram.frame(
                    nearestTime: symbolStartTime
                ) else {
                    throw RealWAVToneMetricDiagnosticError.missingFrame(
                        candidate: record.candidateIndex,
                        symbol: receivedSymbolIndex
                    )
                }

                let metrics = try extractor.toneMetrics(
                    symbolIndex: receivedSymbolIndex,
                    spectrogram: spectrogram,
                    candidate: candidate
                )

                guard metrics.count == 8 else {
                    throw RealWAVToneMetricDiagnosticError.invalidMetricCount(
                        candidate: record.candidateIndex,
                        symbol: receivedSymbolIndex,
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
                let expectedTone = Int(symbolRow.expectedTone)
                let detectedTone = Int(symbolRow.detectedTone)

                let elapsed = Float(frame.time - candidate.startTime)
                let drift = candidate.driftHzPerSecond * elapsed

                let expectedTargetFrequency =
                    candidate.frequency
                    + Float(expectedTone) * extractor.configuration.toneSpacing
                    + drift

                let winningTargetFrequency =
                    candidate.frequency
                    + Float(winner.offset) * extractor.configuration.toneSpacing
                    + drift

                let expectedBin = Int(
                    (
                        (expectedTargetFrequency - frame.minimumFrequency)
                        / frame.binWidth
                    ).rounded()
                )

                let winningBin = Int(
                    (
                        (winningTargetFrequency - frame.minimumFrequency)
                        / frame.binWidth
                    ).rounded()
                )

                let expectedBinFrequency =
                    frame.minimumFrequency
                    + Float(expectedBin) * frame.binWidth

                let winningBinFrequency =
                    frame.minimumFrequency
                    + Float(winningBin) * frame.binWidth

                rows.append(
                    RealWAVToneMetricRow(
                        candidateIndex: record.candidateIndex,
                        referenceMessage: symbolRow.referenceMessage,
                        dataSymbolIndex: symbolRow.dataSymbolIndex,
                        receivedSymbolIndex: receivedSymbolIndex,
                        symbolStartTime: symbolStartTime,
                        symbolStartSample: Int(
                            (symbolStartTime * Double(sampleRate)).rounded()
                        ),
                        frameTime: frame.time,
                        expectedTone: symbolRow.expectedTone,
                        detectedTone: symbolRow.detectedTone,
                        winningTone: UInt8(winner.offset),
                        runnerUpTone: UInt8(runnerUp.offset),
                        toneMetricsDB: metrics,
                        expectedToneMetricDB: metrics[expectedTone],
                        detectedToneMetricDB: metrics[detectedTone],
                        winningMetricDB: winner.element,
                        runnerUpMetricDB: runnerUp.element,
                        winningMarginDB: winner.element - runnerUp.element,
                        expectedToneBin: expectedBin,
                        winningToneBin: winningBin,
                        expectedBinFrequencyHz: expectedBinFrequency,
                        winningBinFrequencyHz: winningBinFrequency,
                        expectedTargetFrequencyHz: expectedTargetFrequency,
                        winningTargetFrequencyHz: winningTargetFrequency
                    )
                )
            }
        }

        return RealWAVToneMetricReport(
            recording: recording,
            generatedAt: generatedAt,
            sampleRate: sampleRate,
            rows: rows
        )
    }

    private static func nearestCandidate(
        to record: FT8PipelineRecord,
        candidates: [FT8Candidate]
    ) -> FT8Candidate? {
        candidates.min { lhs, rhs in
            candidateDistance(lhs, record: record)
                < candidateDistance(rhs, record: record)
        }
    }

    private static func candidateDistance(
        _ candidate: FT8Candidate,
        record: FT8PipelineRecord
    ) -> Double {
        abs(candidate.startTime - record.startTime)
            + Double(abs(candidate.frequency - record.frequency)) / 50
    }
}
