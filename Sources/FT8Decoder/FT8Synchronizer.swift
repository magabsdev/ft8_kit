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

        let frameStep = Double(spectrogram.hopSize)
            / Double(spectrogram.sampleRate)
        guard frameStep > 0,
              frameStep <= configuration.symbolPeriod else {
            throw SynchronizerError.incompatibleFrameSpacing
        }

        let signalDuration = Double(CostasSequence.symbolCount)
            * configuration.symbolPeriod
        let latestStart = max(0, spectrogram.duration - signalDuration)
        let coarseFrequencyStep = configuration.frequencyStep
            ?? max(firstFrame.binWidth, configuration.toneSpacing / 2)

        let lowFrequency = max(
            configuration.minimumFrequency,
            spectrogram.minimumFrequency
        )
        let highFrequency = min(
            configuration.maximumFrequency,
            spectrogram.maximumFrequency - 7 * configuration.toneSpacing
        )
        guard highFrequency > lowFrequency else { return [] }

        var coarse: [FT8Candidate] = []
        var start = max(
            0,
            firstFrame.time - configuration.symbolPeriod
        )

        while start <= latestStart + frameStep / 2 {
            var frequency = lowFrequency

            while frequency <= highFrequency {
                if let candidate = evaluate(
                    spectrogram: spectrogram,
                    startTime: start,
                    frequency: frequency
                ) {
                    coarse.append(candidate)
                }

                frequency += coarseFrequencyStep
            }

            start += frameStep
        }

        let clusterer = FT8CandidateClusterer(
            timeRadius: configuration.deduplicationTime,
            frequencyRadius: configuration.deduplicationFrequency,
            maximumCandidates: configuration.maximumCandidates
        )

        let seedLimit = min(
            max(configuration.maximumCandidates * 3, 32),
            coarse.count
        )
        let seeds = Array(
            coarse.sorted(by: isPreferred).prefix(seedLimit)
        )

        let refined: [FT8Candidate]
        if configuration.enableFineSearch {
            refined = seeds.map {
                refine(
                    $0,
                    in: spectrogram,
                    latestStart: latestStart,
                    lowFrequency: lowFrequency,
                    highFrequency: highFrequency,
                    frameStep: frameStep,
                    coarseFrequencyStep: coarseFrequencyStep
                )
            }
        } else {
            refined = seeds
        }

        let clustered = clusterer.cluster(refined)

        guard configuration.enableAdaptivePruning else {
            return clustered
        }

        let pruner = FT8CandidatePruner(
            minimumRelativeConfidence:
                configuration.minimumRelativeConfidence,
            minimumPeakIsolation:
                configuration.minimumPeakIsolation,
            timeRadius: configuration.pruningTimeRadius,
            frequencyRadius: configuration.pruningFrequencyRadius,
            minimumCandidates:
                configuration.minimumCandidatesAfterPruning,
            maximumCandidates:
                min(
                    configuration.maximumCandidatesAfterPruning,
                    configuration.maximumCandidates
                )
        )

        return pruner.prune(clustered)
    }

    private func refine(
        _ seed: FT8Candidate,
        in spectrogram: Spectrogram,
        latestStart: Double,
        lowFrequency: Float,
        highFrequency: Float,
        frameStep: Double,
        coarseFrequencyStep: Float
    ) -> FT8Candidate {
        let timeStep = min(frameStep, configuration.symbolPeriod)
            / Double(configuration.fineTimeSubdivisions)
        let frequencyStep = min(
            coarseFrequencyStep,
            configuration.toneSpacing
        ) / Float(configuration.fineFrequencySubdivisions)

        let minimumTime = max(
            0,
            seed.startTime - configuration.fineTimeRadius
        )
        let maximumTime = min(
            latestStart,
            seed.startTime + configuration.fineTimeRadius
        )
        let minimumFrequency = max(
            lowFrequency,
            seed.frequency - configuration.fineFrequencyRadius
        )
        let maximumFrequency = min(
            highFrequency,
            seed.frequency + configuration.fineFrequencyRadius
        )

        var best = seed
        var time = minimumTime

        while time <= maximumTime + timeStep / 2 {
            var frequency = minimumFrequency

            while frequency <= maximumFrequency + frequencyStep / 2 {
                if let candidate = evaluate(
                    spectrogram: spectrogram,
                    startTime: time,
                    frequency: frequency
                ), isPreferred(candidate, best) {
                    best = candidate
                }

                frequency += frequencyStep
            }

            time += timeStep
        }

        return best
    }

    private func evaluate(
        spectrogram: Spectrogram,
        startTime: Double,
        frequency: Float
    ) -> FT8Candidate? {
        let drift = configuration.estimateDrift
            ? estimateDrift(
                spectrogram: spectrogram,
                startTime: startTime,
                baseFrequency: frequency
            )
            : 0

        let correlation = CostasCorrelator.correlate(
            spectrogram: spectrogram,
            startTime: startTime,
            baseFrequency: frequency,
            driftHzPerSecond: drift,
            symbolPeriod: configuration.symbolPeriod,
            toneSpacing: configuration.toneSpacing
        )

        guard correlation.score >= configuration.minimumSyncScore,
              correlation.snrDB >= configuration.minimumSNRDB else {
            return nil
        }

        return FT8Candidate(
            startTime: startTime,
            frequency: frequency,
            driftHzPerSecond: drift,
            symbolOffset: startTime / configuration.symbolPeriod,
            syncScore: correlation.score,
            snrDB: correlation.snrDB,
            confidence: confidence(
                score: correlation.score,
                snrDB: correlation.snrDB,
                observations: correlation.observations
            )
        )
    }

    private func estimateDrift(
        spectrogram: Spectrogram,
        startTime: Double,
        baseFrequency: Float
    ) -> Float {
        guard configuration.maximumAbsoluteDrift > 0 else { return 0 }

        let maximum = configuration.maximumAbsoluteDrift
        let driftCandidates: [Float] = [
            -maximum,
            -maximum / 2,
            0,
            maximum / 2,
            maximum
        ]

        var bestDrift: Float = 0
        var bestScore: Float = -.greatestFiniteMagnitude

        for drift in driftCandidates {
            let score = CostasCorrelator.correlate(
                spectrogram: spectrogram,
                startTime: startTime,
                baseFrequency: baseFrequency,
                driftHzPerSecond: drift,
                symbolPeriod: configuration.symbolPeriod,
                toneSpacing: configuration.toneSpacing
            ).score

            if score > bestScore {
                bestScore = score
                bestDrift = drift
            }
        }

        return bestDrift
    }

    private func confidence(
        score: Float,
        snrDB: Float,
        observations: Int
    ) -> Float {
        let snrComponent = min(max((snrDB + 3) / 18, 0), 1)
        let observationComponent = min(Float(observations) / 21, 1)

        return min(
            max(
                0.65 * score +
                0.25 * snrComponent +
                0.10 * observationComponent,
                0
            ),
            1
        )
    }

    private func isPreferred(
        _ lhs: FT8Candidate,
        _ rhs: FT8Candidate
    ) -> Bool {
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }
        if lhs.syncScore != rhs.syncScore {
            return lhs.syncScore > rhs.syncScore
        }
        if lhs.snrDB != rhs.snrDB {
            return lhs.snrDB > rhs.snrDB
        }
        if abs(lhs.driftHzPerSecond) != abs(rhs.driftHzPerSecond) {
            return abs(lhs.driftHzPerSecond)
                < abs(rhs.driftHzPerSecond)
        }
        if lhs.startTime != rhs.startTime {
            return lhs.startTime < rhs.startTime
        }
        return lhs.frequency < rhs.frequency
    }
}
