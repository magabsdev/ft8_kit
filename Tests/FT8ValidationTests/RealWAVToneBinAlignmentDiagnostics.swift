import Foundation
import FT8Decoder
import FT8DSP

enum RealWAVToneBinAlignmentError: Error, Equatable {
    case missingCandidate(Int)
    case missingFrame(candidate: Int, symbol: Int)
    case invalidExpectedTone(candidate: Int, symbol: Int, tone: Int)
}

enum RealWAVToneBinAlignmentDiagnostics {
    static func buildReport(
        recording: String,
        spectrogram: Spectrogram,
        extractor: SoftSymbolExtractor,
        synchronizer: FT8Synchronizer,
        records: [FT8PipelineRecord],
        symbolReport: RealWAVSymbolComparisonReport,
        neighbourhoodRadius: Int = 2,
        generatedAt: Date = Date()
    ) throws -> RealWAVToneBinAlignmentReport {
        let candidates = try synchronizer.search(in: spectrogram)
        let rowsByCandidate = Dictionary(
            grouping: symbolReport.rows,
            by: \.candidateIndex
        )

        var output: [RealWAVToneBinAlignmentRow] = []

        for record in records.sorted(by: {
            $0.candidateIndex < $1.candidateIndex
        }) {
            guard let symbolRows = rowsByCandidate[record.candidateIndex],
                  !symbolRows.isEmpty else {
                continue
            }

            guard let candidate = nearestCandidate(
                to: record,
                candidates: candidates
            ) else {
                throw RealWAVToneBinAlignmentError.missingCandidate(
                    record.candidateIndex
                )
            }

            for symbolRow in symbolRows.sorted(by: {
                $0.dataSymbolIndex < $1.dataSymbolIndex
            }) {
                let receivedSymbolIndex = symbolRow.receivedSymbolIndex
                let requestedSymbolTime =
                    candidate.startTime
                    + Double(receivedSymbolIndex)
                    * extractor.configuration.symbolPeriod

                guard let frame = spectrogram.frame(
                    nearestTime: requestedSymbolTime
                ) else {
                    throw RealWAVToneBinAlignmentError.missingFrame(
                        candidate: record.candidateIndex,
                        symbol: receivedSymbolIndex
                    )
                }

                let elapsed = Float(
                    frame.time - candidate.startTime
                )
                let appliedDrift =
                    candidate.driftHzPerSecond * elapsed

                let toneSamples = (0..<8).map { tone in
                    toneSample(
                        tone: tone,
                        frame: frame,
                        candidateFrequency: candidate.frequency,
                        appliedDriftHz: appliedDrift,
                        toneSpacingHz: extractor.configuration.toneSpacing,
                        neighbourhoodRadius: neighbourhoodRadius
                    )
                }

                let expectedTone = Int(symbolRow.expectedTone)
                guard toneSamples.indices.contains(expectedTone) else {
                    throw RealWAVToneBinAlignmentError.invalidExpectedTone(
                        candidate: record.candidateIndex,
                        symbol: receivedSymbolIndex,
                        tone: expectedTone
                    )
                }

                let frameTimeError =
                    frame.time - requestedSymbolTime

                output.append(
                    RealWAVToneBinAlignmentRow(
                        candidateIndex: record.candidateIndex,
                        referenceMessage: symbolRow.referenceMessage,
                        dataSymbolIndex: symbolRow.dataSymbolIndex,
                        receivedSymbolIndex: receivedSymbolIndex,
                        expectedTone: symbolRow.expectedTone,
                        detectedTone: symbolRow.detectedTone,
                        candidateStartTime: candidate.startTime,
                        requestedSymbolTime: requestedSymbolTime,
                        selectedFrameIndex: frame.index,
                        selectedFrameSampleOffset: frame.sampleOffset,
                        selectedFrameTime: frame.time,
                        frameTimeErrorSeconds: frameTimeError,
                        frameTimeErrorSamples:
                            frameTimeError
                            * Double(spectrogram.sampleRate),
                        candidateBaseFrequencyHz: candidate.frequency,
                        candidateDriftHzPerSecond:
                            candidate.driftHzPerSecond,
                        elapsedSeconds: elapsed,
                        appliedDriftHz: appliedDrift,
                        binWidthHz: frame.binWidth,
                        toneSpacingHz:
                            extractor.configuration.toneSpacing,
                        tones: toneSamples
                    )
                )
            }
        }

        return RealWAVToneBinAlignmentReport(
            recording: recording,
            generatedAt: generatedAt,
            sampleRate: spectrogram.sampleRate,
            fftSize: spectrogram.fftSize,
            hopSize: spectrogram.hopSize,
            rows: output
        )
    }

    private static func toneSample(
        tone: Int,
        frame: WaterfallFrame,
        candidateFrequency: Float,
        appliedDriftHz: Float,
        toneSpacingHz: Float,
        neighbourhoodRadius: Int
    ) -> RealWAVToneBinSample {
        let requestedFrequency =
            candidateFrequency
            + Float(tone) * toneSpacingHz
            + appliedDriftHz

        let fractionalBin =
            (requestedFrequency - frame.minimumFrequency)
            / frame.binWidth

        let roundedBin = Int(fractionalBin.rounded())
        let roundedFrequency = frame.frequency(at: roundedBin)
        let frequencyError =
            roundedFrequency - requestedFrequency

        var offsets: [Int] = []
        var neighbourhood: [Float] = []

        if neighbourhoodRadius >= 0 {
            for offset in -neighbourhoodRadius...neighbourhoodRadius {
                let bin = roundedBin + offset
                guard frame.decibels.indices.contains(bin) else {
                    continue
                }

                offsets.append(offset)
                neighbourhood.append(frame.decibels[bin])
            }
        }

        return RealWAVToneBinSample(
            tone: UInt8(tone),
            requestedFrequencyHz: requestedFrequency,
            fractionalBin: fractionalBin,
            roundedBin: roundedBin,
            roundedBinFrequencyHz: roundedFrequency,
            frequencyErrorHz: frequencyError,
            neighbourhoodDB: neighbourhood,
            neighbourhoodOffsets: offsets
        )
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
