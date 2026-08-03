import Foundation
import FT8DSP

public struct FT8Synchronizer: Sendable {
    public var configuration: SynchronizerConfiguration

    public init(configuration: SynchronizerConfiguration = .init()) {
        self.configuration = configuration
    }

    public func search(in spectrogram: Spectrogram) throws -> [FT8Candidate] {
        try configuration.validate()
        guard let firstFrame = spectrogram.frames.first else {
            throw SynchronizerError.emptySpectrogram
        }

        let frameStep = Double(spectrogram.hopSize) / Double(spectrogram.sampleRate)
        guard frameStep > 0, frameStep <= configuration.symbolPeriod else {
            throw SynchronizerError.incompatibleFrameSpacing
        }

        let signalDuration = Double(CostasSequence.symbolCount) * configuration.symbolPeriod
        let latestStart = max(0, spectrogram.duration - signalDuration)
        let frequencyStep = configuration.frequencyStep ?? max(firstFrame.binWidth, configuration.toneSpacing / 2)

        let lowFrequency = max(configuration.minimumFrequency, spectrogram.minimumFrequency)
        let highFrequency = min(
            configuration.maximumFrequency,
            spectrogram.maximumFrequency - 7 * configuration.toneSpacing
        )
        guard highFrequency > lowFrequency else { return [] }

        var raw: [FT8Candidate] = []
        var start = max(0, firstFrame.time - configuration.symbolPeriod)

        while start <= latestStart + frameStep / 2 {
            var frequency = lowFrequency
            while frequency <= highFrequency {
                let drift = configuration.estimateDrift
                    ? estimateDrift(
                        spectrogram: spectrogram,
                        startTime: start,
                        baseFrequency: frequency
                    )
                    : 0

                let correlation = CostasCorrelator.correlate(
                    spectrogram: spectrogram,
                    startTime: start,
                    baseFrequency: frequency,
                    driftHzPerSecond: drift,
                    symbolPeriod: configuration.symbolPeriod,
                    toneSpacing: configuration.toneSpacing
                )

                if correlation.score >= configuration.minimumSyncScore,
                   correlation.snrDB >= configuration.minimumSNRDB {
                    let confidence = confidence(
                        score: correlation.score,
                        snrDB: correlation.snrDB,
                        observations: correlation.observations
                    )
                    raw.append(
                        FT8Candidate(
                            startTime: start,
                            frequency: frequency,
                            driftHzPerSecond: drift,
                            symbolOffset: start / configuration.symbolPeriod,
                            syncScore: correlation.score,
                            snrDB: correlation.snrDB,
                            confidence: confidence
                        )
                    )
                }

                frequency += frequencyStep
            }
            start += frameStep
        }

        return deduplicate(raw)
    }

    private func estimateDrift(
        spectrogram: Spectrogram,
        startTime: Double,
        baseFrequency: Float
    ) -> Float {
        guard configuration.maximumAbsoluteDrift > 0 else { return 0 }

        let candidates: [Float] = [
            -configuration.maximumAbsoluteDrift,
            -configuration.maximumAbsoluteDrift / 2,
            0,
            configuration.maximumAbsoluteDrift / 2,
            configuration.maximumAbsoluteDrift
        ]

        return candidates.max { lhs, rhs in
            CostasCorrelator.correlate(
                spectrogram: spectrogram,
                startTime: startTime,
                baseFrequency: baseFrequency,
                driftHzPerSecond: lhs,
                symbolPeriod: configuration.symbolPeriod,
                toneSpacing: configuration.toneSpacing
            ).score
            <
            CostasCorrelator.correlate(
                spectrogram: spectrogram,
                startTime: startTime,
                baseFrequency: baseFrequency,
                driftHzPerSecond: rhs,
                symbolPeriod: configuration.symbolPeriod,
                toneSpacing: configuration.toneSpacing
            ).score
        } ?? 0
    }

    private func confidence(score: Float, snrDB: Float, observations: Int) -> Float {
        let snrComponent = min(max((snrDB + 3) / 18, 0), 1)
        let observationComponent = min(Float(observations) / 21, 1)
        return min(max(0.65 * score + 0.25 * snrComponent + 0.10 * observationComponent, 0), 1)
    }

    private func deduplicate(_ candidates: [FT8Candidate]) -> [FT8Candidate] {
        let ordered = candidates.sorted {
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            if $0.syncScore != $1.syncScore {
                return $0.syncScore > $1.syncScore
            }
            if $0.snrDB != $1.snrDB {
                return $0.snrDB > $1.snrDB
            }
            if $0.startTime != $1.startTime {
                return $0.startTime < $1.startTime
            }
            return $0.frequency < $1.frequency
        }

        // Suppress neighbouring points from the same Costas peak. The old
        // radii were small enough that a single broad signal ridge could
        // consume a large fraction of maximumCandidates.
        let timeRadius = configuration.deduplicationTime
        let frequencyRadius = configuration.deduplicationFrequency

        var accepted: [FT8Candidate] = []
        accepted.reserveCapacity(
            min(configuration.maximumCandidates, ordered.count)
        )

        for candidate in ordered {
            let duplicate = accepted.contains {
                abs($0.frequency - candidate.frequency) <= frequencyRadius &&
                abs($0.startTime - candidate.startTime) <= timeRadius
            }

            guard !duplicate else {
                continue
            }

            accepted.append(candidate)

            if accepted.count >= configuration.maximumCandidates {
                break
            }
        }

        return accepted.sorted {
            if $0.startTime == $1.startTime {
                return $0.frequency < $1.frequency
            }
            return $0.startTime < $1.startTime
        }
    }
}
