import Foundation
import FT8DSP

public struct CostasCorrelation: Equatable, Sendable {
    public let score: Float
    public let snrDB: Float
    public let matchedEnergyDB: Float
    public let competingEnergyDB: Float
    public let observations: Int
}

public enum CostasCorrelator {
    public static func correlate(
        spectrogram: Spectrogram,
        startTime: Double,
        baseFrequency: Float,
        driftHzPerSecond: Float = 0,
        symbolPeriod: Double = 0.160,
        toneSpacing: Float = 6.25
    ) -> CostasCorrelation {
        guard !spectrogram.frames.isEmpty else {
            return emptyCorrelation()
        }

        var matchedLinear: Float = 0
        var competingLinear: Float = 0
        var observations = 0

        for blockStart in CostasSequence.blockStarts {
            for localIndex in CostasSequence.tones.indices {
                let symbol = blockStart + localIndex

                // WaterfallFrame.time is the FFT WINDOW START, not its centre.
                //
                // With the normal FT8 waterfall (≈160–171 ms FFT window), a
                // frame whose window starts at the FT8 symbol start naturally
                // integrates energy across the body of that symbol. Sampling
                // at startTime + 0.5 symbolPeriod incorrectly shifts the FFT
                // window by ~80 ms and caused the synchronizer to report
                // candidate.startTime about half a symbol too early.
                //
                // candidate.startTime is therefore consistently defined as:
                //     start of the first FT8 symbol.
                let time = startTime
                    + Double(symbol) * symbolPeriod

                guard let frame = spectrogram.frame(nearestTime: time) else {
                    continue
                }

                // Drift is referenced to the candidate's first-symbol start.
                // Use the requested symbol-window start, rather than frame.time,
                // so rounding to the nearest waterfall hop cannot bias drift.
                let elapsed = Float(time - startTime)
                let expectedTone = Int(
                    CostasSequence.tones[localIndex]
                )

                var toneDB: [Float] = []
                var matchedIndex: Int?
                toneDB.reserveCapacity(8)

                for tone in 0..<8 {
                    let frequency = baseFrequency
                        + Float(tone) * toneSpacing
                        + driftHzPerSecond * elapsed
                    let bin = nearestBin(
                        in: frame,
                        frequency: frequency
                    )

                    guard frame.decibels.indices.contains(bin) else {
                        continue
                    }

                    if tone == expectedTone {
                        matchedIndex = toneDB.count
                    }

                    toneDB.append(frame.decibels[bin])
                }

                let powers = VectorMath.linearPower(
                    fromDecibels: toneDB
                )

                guard let matchedIndex,
                      powers.indices.contains(matchedIndex) else {
                    continue
                }

                let matched = powers[matchedIndex]
                let competitors = VectorMath.sum(powers) - matched
                let competitorCount = powers.count - 1

                matchedLinear += matched

                if competitorCount > 0 {
                    competingLinear += competitors
                        / Float(competitorCount)
                }

                observations += 1
            }
        }

        guard observations > 0 else {
            return emptyCorrelation()
        }

        let matchedMean = matchedLinear / Float(observations)
        let competingMean = max(
            competingLinear / Float(observations),
            Float.leastNonzeroMagnitude
        )
        let ratio = matchedMean / competingMean
        let score = ratio / (1 + ratio)
        let snrDB = 10 * log10f(
            max(ratio, Float.leastNonzeroMagnitude)
        )

        return CostasCorrelation(
            score: score,
            snrDB: snrDB,
            matchedEnergyDB: 10 * log10f(
                max(matchedMean, Float.leastNonzeroMagnitude)
            ),
            competingEnergyDB: 10 * log10f(competingMean),
            observations: observations
        )
    }

    private static func emptyCorrelation() -> CostasCorrelation {
        CostasCorrelation(
            score: 0,
            snrDB: -.infinity,
            matchedEnergyDB: -.infinity,
            competingEnergyDB: -.infinity,
            observations: 0
        )
    }

    private static func nearestBin(
        in frame: WaterfallFrame,
        frequency: Float
    ) -> Int {
        Int(
            (
                (frequency - frame.minimumFrequency)
                    / frame.binWidth
            ).rounded()
        )
    }
}
