import Foundation
import FT8Decoder
import FT8DSP
import FT8Encoder

enum RealWAVAdaptiveCanceller {
    struct Result {
        let spectrogram: Spectrogram
        let affectedBins: Int
        let reductionFraction: Double
    }

    static func cancel(
        _ decode: FT8CompleteDecode,
        from spectrogram: Spectrogram,
        profile: RealWAVCancellationSweepProfile
    ) throws -> Result {
        let tones = try FT8Encoder.encode(
            text: decode.decoded.text
        )

        guard tones.count == 79 else {
            return Result(
                spectrogram: spectrogram,
                affectedBins: 0,
                reductionFraction: 0
            )
        }

        var frames = spectrogram.frames
        var affectedBins = 0
        var powerBefore: Double = 0
        var powerAfter: Double = 0

        let symbolPeriod = 0.160
        let radius = max(profile.radiusBins, 0)
        let sigma = max(Float(radius) / 2, 0.75)

        for symbolIndex in 0..<79 {
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
            let exactBin =
                (toneFrequency - frame.minimumFrequency)
                / frame.binWidth
            let centreBin = Int(exactBin.rounded())

            let x =
                abs(Float(symbolIndex) - 39) / 39
            let taper =
                max(
                    profile.timeTaperFloor,
                    1 - x * x
                )

            var newDecibels = frame.decibels

            for offset in -radius...radius {
                let bin = centreBin + offset

                guard newDecibels.indices.contains(bin) else {
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

                let originalDB = newDecibels[bin]
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

                let updatedDB =
                    Float(10.0 * log10(remaining))

                powerBefore += originalPower
                powerAfter += remaining
                newDecibels[bin] = updatedDB
                affectedBins += 1
            }

            let magnitudes =
                newDecibels.map {
                    powf(10, $0 / 20)
                }

            let intensities =
                newDecibels.map {
                    min(
                        max(
                            ($0 - frame.noiseFloorDB) / 70,
                            0
                        ),
                        1
                    )
                }

            frames[frameIndex] = WaterfallFrame(
                index: frame.index,
                sampleOffset: frame.sampleOffset,
                time: frame.time,
                minimumFrequency: frame.minimumFrequency,
                binWidth: frame.binWidth,
                magnitudes: magnitudes,
                decibels: newDecibels,
                intensities: intensities,
                noiseFloorDB: frame.noiseFloorDB
            )
        }

        let reduction: Double
        if powerBefore > 0 {
            reduction = min(
                max(
                    1 - powerAfter / powerBefore,
                    0
                ),
                1
            )
        } else {
            reduction = 0
        }

        return Result(
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

    private static func nearestFrameIndex(
        in frames: [WaterfallFrame],
        time: Double
    ) -> Int? {
        guard !frames.isEmpty else {
            return nil
        }

        var bestIndex = 0
        var bestDistance =
            abs(frames[0].time - time)

        for index in 1..<frames.count {
            let distance =
                abs(frames[index].time - time)

            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }
}
