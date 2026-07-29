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
            return CostasCorrelation(
                score: 0, snrDB: -.infinity,
                matchedEnergyDB: -.infinity,
                competingEnergyDB: -.infinity,
                observations: 0
            )
        }

        var matchedLinear: Float = 0
        var competingLinear: Float = 0
        var observations = 0

        for blockStart in CostasSequence.blockStarts {
            for localIndex in CostasSequence.tones.indices {
                let symbol = blockStart + localIndex
                let time = startTime + Double(symbol) * symbolPeriod + symbolPeriod / 2
                guard let frame = spectrogram.frame(nearestTime: time) else { continue }

                let elapsed = Float(time - startTime)
                let centre = baseFrequency
                    + Float(CostasSequence.tones[localIndex]) * toneSpacing
                    + driftHzPerSecond * elapsed

                let expectedBin = nearestBin(in: frame, frequency: centre)
                guard expectedBin >= 0 && expectedBin < frame.count else { continue }

                let matched = linearPower(fromDecibels: frame.decibels[expectedBin])
                var competitors: Float = 0
                var count = 0
                for tone in 0..<8 where tone != Int(CostasSequence.tones[localIndex]) {
                    let frequency = baseFrequency
                        + Float(tone) * toneSpacing
                        + driftHzPerSecond * elapsed
                    let bin = nearestBin(in: frame, frequency: frequency)
                    if bin >= 0 && bin < frame.count {
                        competitors += linearPower(fromDecibels: frame.decibels[bin])
                        count += 1
                    }
                }

                matchedLinear += matched
                if count > 0 {
                    competingLinear += competitors / Float(count)
                }
                observations += 1
            }
        }

        guard observations > 0 else {
            return CostasCorrelation(
                score: 0, snrDB: -.infinity,
                matchedEnergyDB: -.infinity,
                competingEnergyDB: -.infinity,
                observations: 0
            )
        }

        let matchedMean = matchedLinear / Float(observations)
        let competingMean = max(competingLinear / Float(observations), Float.leastNonzeroMagnitude)
        let ratio = matchedMean / competingMean
        let score = ratio / (1 + ratio)
        let snrDB = 10 * log10f(max(ratio, Float.leastNonzeroMagnitude))

        return CostasCorrelation(
            score: score,
            snrDB: snrDB,
            matchedEnergyDB: 10 * log10f(max(matchedMean, Float.leastNonzeroMagnitude)),
            competingEnergyDB: 10 * log10f(competingMean),
            observations: observations
        )
    }

    private static func nearestBin(in frame: WaterfallFrame, frequency: Float) -> Int {
        Int(((frequency - frame.minimumFrequency) / frame.binWidth).rounded())
    }

    private static func linearPower(fromDecibels value: Float) -> Float {
        powf(10, value / 10)
    }
}
