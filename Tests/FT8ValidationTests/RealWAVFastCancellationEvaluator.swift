import Foundation
import FT8Decoder
import FT8DSP
import FT8Encoder

enum RealWAVFastCancellationEvaluator {
    struct CancellationResult {
        let spectrogram: Spectrogram
        let affectedBins: Int
        let reductionFraction: Double
    }

    static func evaluate(
        decode: FT8CompleteDecode,
        spectrogram: Spectrogram,
        profiles: [RealWAVFastCancellationProfile]
    ) throws -> (
        scores: [RealWAVFastCancellationScore],
        best: RealWAVFastCancellationScore
    ) {
        let baseline = try signalMetrics(
            decode: decode,
            spectrogram: spectrogram
        )

        var scores: [RealWAVFastCancellationScore] = []
        scores.reserveCapacity(profiles.count)

        for profile in profiles {
            let cancellation = try cancel(
                decode,
                from: spectrogram,
                profile: profile
            )

            let residual = try signalMetrics(
                decode: decode,
                spectrogram: cancellation.spectrogram
            )

            let suppression =
                baseline.signalPowerDB - residual.signalPowerDB

            let neighbourLoss =
                baseline.neighbourPowerDB - residual.neighbourPowerDB

            // Prefer strong suppression of the decoded signal while penalizing
            // damage to adjacent one-tone-away energy. The penalty is weighted
            // heavily enough that a huge radius cannot win merely by flattening
            // the whole local spectrum.
            let objective =
                suppression - max(neighbourLoss, 0) * 1.5

            scores.append(
                RealWAVFastCancellationScore(
                    profile: profile,
                    affectedBins: cancellation.affectedBins,
                    reductionFraction: cancellation.reductionFraction,
                    residualSignalPowerDB: residual.signalPowerDB,
                    residualNeighbourPowerDB: residual.neighbourPowerDB,
                    suppressionDB: suppression,
                    collateralPenaltyDB: max(neighbourLoss, 0),
                    objective: objective
                )
            )
        }

        let best = scores.max {
            if $0.objective != $1.objective {
                return $0.objective < $1.objective
            }

            if $0.profile.radiusBins != $1.profile.radiusBins {
                return $0.profile.radiusBins > $1.profile.radiusBins
            }

            return $0.profile.strength > $1.profile.strength
        }!

        return (scores, best)
    }

    static func cancel(
        _ decode: FT8CompleteDecode,
        from spectrogram: Spectrogram,
        profile: RealWAVFastCancellationProfile
    ) throws -> CancellationResult {
        let tones = try FT8Encoder.encode(
            text: decode.decoded.text
        )

        var frames = spectrogram.frames
        var affectedBins = 0
        var powerBefore: Double = 0
        var powerAfter: Double = 0

        let symbolPeriod = 0.160
        let radius = max(profile.radiusBins, 0)
        let sigma = max(Float(radius) / 2, 0.75)

        for symbolIndex in 0..<min(79, tones.count) {
            let symbolStart =
                decode.candidate.startTime
                + Double(symbolIndex) * symbolPeriod

            guard let frameIndex = nearestFrameIndex(
                in: frames,
                time: symbolStart
            ) else {
                continue
            }

            let elapsed = Float(
                symbolStart - decode.candidate.startTime
            )

            let toneFrequency =
                decode.candidate.frequency
                + Float(tones[symbolIndex]) * 6.25
                + decode.candidate.driftHzPerSecond * elapsed

            let frame = frames[frameIndex]
            let centreBin = Int(
                (
                    (toneFrequency - frame.minimumFrequency)
                    / frame.binWidth
                ).rounded()
            )

            let x =
                abs(Float(symbolIndex) - 39) / 39
            let taper =
                max(
                    profile.timeTaperFloor,
                    1 - x * x
                )

            var decibels = frame.decibels

            for offset in -radius...radius {
                let bin = centreBin + offset
                guard decibels.indices.contains(bin) else {
                    continue
                }

                let weight = expf(
                    -Float(offset * offset)
                    / (2 * sigma * sigma)
                )

                let strength = min(
                    max(
                        profile.strength
                            * taper
                            * weight,
                        0
                    ),
                    1
                )

                let originalDB = decibels[bin]
                let originalPower =
                    pow(10.0, Double(originalDB) / 10.0)
                let noisePower =
                    pow(
                        10.0,
                        Double(frame.noiseFloorDB) / 10.0
                    )

                let removable =
                    max(originalPower - noisePower, 0)
                let remaining =
                    max(
                        originalPower
                            - removable * Double(strength),
                        noisePower
                    )

                powerBefore += originalPower
                powerAfter += remaining

                decibels[bin] =
                    Float(10.0 * log10(remaining))
                affectedBins += 1
            }

            frames[frameIndex] = WaterfallFrame(
                index: frame.index,
                sampleOffset: frame.sampleOffset,
                time: frame.time,
                minimumFrequency: frame.minimumFrequency,
                binWidth: frame.binWidth,
                magnitudes:
                    decibels.map { powf(10, $0 / 20) },
                decibels: decibels,
                intensities:
                    decibels.map {
                        min(
                            max(
                                ($0 - frame.noiseFloorDB) / 70,
                                0
                            ),
                            1
                        )
                    },
                noiseFloorDB: frame.noiseFloorDB
            )
        }

        let reduction =
            powerBefore > 0
            ? min(
                max(
                    1 - powerAfter / powerBefore,
                    0
                ),
                1
            )
            : 0

        return CancellationResult(
            spectrogram: Spectrogram(
                frames: frames,
                sampleRate: spectrogram.sampleRate,
                fftSize: spectrogram.fftSize,
                hopSize: spectrogram.hopSize,
                minimumFrequency: spectrogram.minimumFrequency,
                maximumFrequency: spectrogram.maximumFrequency
            ),
            affectedBins: affectedBins,
            reductionFraction: reduction
        )
    }

    private static func signalMetrics(
        decode: FT8CompleteDecode,
        spectrogram: Spectrogram
    ) throws -> (
        signalPowerDB: Double,
        neighbourPowerDB: Double
    ) {
        let tones = try FT8Encoder.encode(
            text: decode.decoded.text
        )

        var signalPower: Double = 0
        var neighbourPower: Double = 0
        var count = 0

        for symbolIndex in 0..<min(79, tones.count) {
            let time =
                decode.candidate.startTime
                + Double(symbolIndex) * 0.160

            guard let frame = spectrogram.frame(
                nearestTime: time
            ) else {
                continue
            }

            let elapsed = Float(
                time - decode.candidate.startTime
            )

            let toneFrequency =
                decode.candidate.frequency
                + Float(tones[symbolIndex]) * 6.25
                + decode.candidate.driftHzPerSecond * elapsed

            let centreBin = Int(
                (
                    (toneFrequency - frame.minimumFrequency)
                    / frame.binWidth
                ).rounded()
            )

            guard frame.decibels.indices.contains(centreBin) else {
                continue
            }

            signalPower += pow(
                10.0,
                Double(frame.decibels[centreBin]) / 10.0
            )

            var neighbours: [Double] = []

            for offset in [-1, 1] {
                let bin = centreBin + offset
                if frame.decibels.indices.contains(bin) {
                    neighbours.append(
                        pow(
                            10.0,
                            Double(frame.decibels[bin]) / 10.0
                        )
                    )
                }
            }

            if !neighbours.isEmpty {
                neighbourPower +=
                    neighbours.reduce(0, +)
                    / Double(neighbours.count)
            }

            count += 1
        }

        guard count > 0 else {
            return (-.infinity, -.infinity)
        }

        let signalMean =
            signalPower / Double(count)
        let neighbourMean =
            neighbourPower / Double(count)

        return (
            10 * log10(max(signalMean, Double.leastNonzeroMagnitude)),
            10 * log10(max(neighbourMean, Double.leastNonzeroMagnitude))
        )
    }

    private static func nearestFrameIndex(
        in frames: [WaterfallFrame],
        time: Double
    ) -> Int? {
        guard !frames.isEmpty else { return nil }

        var best = 0
        var distance = abs(frames[0].time - time)

        for index in 1..<frames.count {
            let candidate =
                abs(frames[index].time - time)

            if candidate < distance {
                best = index
                distance = candidate
            }
        }

        return best
    }
}
