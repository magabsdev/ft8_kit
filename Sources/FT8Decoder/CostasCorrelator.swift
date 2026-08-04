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

                // Candidate startTime is the start of the first FT8 symbol.
                // Correlation must sample at the centre of each symbol because
                // the waterfall frame represents the analysis window centred
                // on that instant.
                let time = startTime
                    + (Double(symbol) + 0.5) * symbolPeriod

                guard let frame = spectrogram.frame(nearestTime: time) else {
                    continue
                }

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
