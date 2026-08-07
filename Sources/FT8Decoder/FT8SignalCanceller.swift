import Foundation
import FT8DSP

public enum FT8SignalCancellationError: Error, Equatable, Sendable {
    case invalidConfiguration
}

public struct FT8SignalCancellationConfiguration:
    Equatable,
    Sendable
{
    public var symbolPeriod: Double
    public var toneSpacing: Float
    public var cancellationStrength: Float
    public var binRadius: Int

    /// Minimum time-domain cancellation multiplier at the first/last symbols.
    ///
    /// The real-WAV cancellation calibration selected 0.50. The centre of the
    /// FT8 transmission still receives full configured cancellation strength.
    public var timeTaperFloor: Float

    /// Preserve the measured frame noise floor while removing signal power.
    ///
    /// This is the production default because the calibrated real-WAV
    /// cancellation path subtracts only power above the existing noise floor.
    public var preserveNoiseFloor: Bool

    public var minimumResidualMagnitude: Float

    public init(
        symbolPeriod: Double = 0.160,
        toneSpacing: Float = 6.25,
        cancellationStrength: Float = 1.00,
        binRadius: Int = 1,
        timeTaperFloor: Float = 0.50,
        preserveNoiseFloor: Bool = true,
        minimumResidualMagnitude: Float =
            Float.leastNonzeroMagnitude
    ) {
        self.symbolPeriod = symbolPeriod
        self.toneSpacing = toneSpacing
        self.cancellationStrength = cancellationStrength
        self.binRadius = binRadius
        self.timeTaperFloor = timeTaperFloor
        self.preserveNoiseFloor = preserveNoiseFloor
        self.minimumResidualMagnitude =
            minimumResidualMagnitude
    }

    func validate() throws {
        guard symbolPeriod > 0,
              toneSpacing > 0,
              (0...1).contains(cancellationStrength),
              binRadius >= 0,
              (0...1).contains(timeTaperFloor),
              minimumResidualMagnitude > 0 else {
            throw FT8SignalCancellationError.invalidConfiguration
        }
    }
}

public struct FT8CancellationResult: Equatable, Sendable {
    public let spectrogram: Spectrogram
    public let energyBefore: Double
    public let energyAfter: Double
    public let affectedBins: Int

    public init(
        spectrogram: Spectrogram,
        energyBefore: Double,
        energyAfter: Double,
        affectedBins: Int
    ) {
        self.spectrogram = spectrogram
        self.energyBefore = energyBefore
        self.energyAfter = energyAfter
        self.affectedBins = affectedBins
    }

    public var removedEnergy: Double {
        max(energyBefore - energyAfter, 0)
    }

    public var reductionFraction: Double {
        guard energyBefore > 0 else { return 0 }
        return min(
            max(1 - energyAfter / energyBefore, 0),
            1
        )
    }
}

public struct FT8SignalCanceller: Sendable {
    public var configuration:
        FT8SignalCancellationConfiguration
    public var synthesizer: FT8SignalSynthesizer

    public init(
        configuration:
            FT8SignalCancellationConfiguration = .init(),
        synthesizer: FT8SignalSynthesizer = .init()
    ) {
        self.configuration = configuration
        self.synthesizer = synthesizer
    }

    public func cancel(
        _ decodes: [FT8CompleteDecode],
        from spectrogram: Spectrogram
    ) throws -> FT8CancellationResult {
        try configuration.validate()

        guard !decodes.isEmpty else {
            return FT8CancellationResult(
                spectrogram: spectrogram,
                energyBefore: 0,
                energyAfter: 0,
                affectedBins: 0
            )
        }

        // IMPORTANT:
        // The calibrated real-WAV cancellation path operates on exactly one
        // nearest waterfall frame per FT8 symbol. Do not expand the 160 ms
        // symbol over every overlapping FFT frame. The previous production
        // implementation did that and touched 948 cells instead of the
        // calibrated 237, suppressing neighbouring weak signals.
        var frames = spectrogram.frames

        var powerBefore: Double = 0
        var powerAfter: Double = 0
        var affectedBins = 0

        for decode in decodes {
            let tones = try synthesizer.tones(for: decode)
            let symbolCount = min(79, tones.count)

            for symbolIndex in 0..<symbolCount {
                let symbolStart =
                    decode.candidate.startTime +
                    Double(symbolIndex) *
                    configuration.symbolPeriod

                guard let frameIndex = nearestFrameIndex(
                    in: frames,
                    time: symbolStart
                ) else {
                    continue
                }

                let frame = frames[frameIndex]

                let elapsed = Float(
                    symbolStart -
                    decode.candidate.startTime
                )

                let toneFrequency =
                    decode.candidate.frequency +
                    Float(tones[symbolIndex]) *
                    configuration.toneSpacing +
                    decode.candidate.driftHzPerSecond *
                    elapsed

                let centreBin = Int(
                    (
                        (toneFrequency -
                            frame.minimumFrequency) /
                        frame.binWidth
                    ).rounded()
                )

                let taper = symbolTimeTaper(
                    symbolIndex: symbolIndex,
                    symbolCount: symbolCount
                )

                var decibels = frame.decibels

                let radius = configuration.binRadius
                let sigma = max(
                    Float(radius) / 2,
                    0.75
                )

                for offset in -radius...radius {
                    let bin = centreBin + offset

                    guard decibels.indices.contains(bin) else {
                        continue
                    }

                    let frequencyWeight = expf(
                        -Float(offset * offset) /
                        (2 * sigma * sigma)
                    )

                    let strength = min(
                        max(
                            configuration.cancellationStrength *
                            taper *
                            frequencyWeight,
                            0
                        ),
                        1
                    )

                    let originalDB = decibels[bin]
                    let originalPower = pow(
                        10.0,
                        Double(originalDB) / 10.0
                    )

                    let minimumPower = pow(
                        Double(
                            configuration.minimumResidualMagnitude
                        ),
                        2
                    )

                    let remainingPower: Double

                    if configuration.preserveNoiseFloor {
                        let noisePower = pow(
                            10.0,
                            Double(frame.noiseFloorDB) / 10.0
                        )

                        let removablePower = max(
                            originalPower - noisePower,
                            0
                        )

                        remainingPower = max(
                            originalPower -
                                removablePower *
                                Double(strength),
                            max(noisePower, minimumPower)
                        )
                    } else {
                        remainingPower = max(
                            originalPower *
                                (1 - Double(strength)),
                            minimumPower
                        )
                    }

                    powerBefore += originalPower
                    powerAfter += remainingPower
                    affectedBins += 1

                    decibels[bin] = Float(
                        10.0 * log10(
                            max(
                                remainingPower,
                                Double.leastNonzeroMagnitude
                            )
                        )
                    )
                }

                // Preserve the original measured frame noise floor. Recomputing
                // it after cancellation changed the residual waterfall and
                // produced extreme diagnostic deltas.
                frames[frameIndex] = WaterfallFrame(
                    index: frame.index,
                    sampleOffset: frame.sampleOffset,
                    time: frame.time,
                    minimumFrequency:
                        frame.minimumFrequency,
                    binWidth: frame.binWidth,
                    magnitudes: decibels.map {
                        powf(10, $0 / 20)
                    },
                    decibels: decibels,
                    intensities: decibels.map {
                        min(
                            max(
                                ($0 -
                                    frame.noiseFloorDB) /
                                    70,
                                0
                            ),
                            1
                        )
                    },
                    noiseFloorDB:
                        frame.noiseFloorDB
                )
            }
        }

        return FT8CancellationResult(
            spectrogram: Spectrogram(
                frames: frames,
                sampleRate: spectrogram.sampleRate,
                fftSize: spectrogram.fftSize,
                hopSize: spectrogram.hopSize,
                minimumFrequency:
                    spectrogram.minimumFrequency,
                maximumFrequency:
                    spectrogram.maximumFrequency
            ),
            energyBefore: powerBefore,
            energyAfter: powerAfter,
            affectedBins: affectedBins
        )
    }

    private func nearestFrameIndex(
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
                bestIndex = index
                bestDistance = distance
            }
        }

        return bestIndex
    }

    private func symbolTimeTaper(
        symbolIndex: Int,
        symbolCount: Int
    ) -> Float {
        guard symbolCount > 1 else {
            return 1
        }

        let midpoint =
            Float(symbolCount - 1) / 2

        let distance =
            abs(
                Float(symbolIndex) -
                midpoint
            ) / max(midpoint, 1)

        return max(
            configuration.timeTaperFloor,
            1 - distance * distance
        )
    }
}
