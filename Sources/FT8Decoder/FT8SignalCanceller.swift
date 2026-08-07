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

    /// Prevent cancellation from pushing a bin below the measured frame noise
    /// floor. This avoids creating artificial spectral holes that can damage
    /// neighbouring weak signals.
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
        return removedEnergy / energyBefore
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

        var frameMagnitudes = spectrogram.frames.map(
            \.magnitudes
        )
        var affected = Set<BinAddress>()
        var before: Double = 0
        var after: Double = 0

        for decode in decodes {
            let tones = try synthesizer.tones(for: decode)

            for symbolIndex in tones.indices {
                let symbolStart =
                    decode.candidate.startTime +
                    Double(symbolIndex) *
                    configuration.symbolPeriod
                let symbolEnd =
                    symbolStart +
                    configuration.symbolPeriod

                let timeTaper = symbolTimeTaper(
                    symbolIndex: symbolIndex,
                    symbolCount: tones.count
                )

                for frameIndex in spectrogram.frames.indices {
                    let frame = spectrogram.frames[frameIndex]
                    let frameCentre = frame.time +
                        Double(spectrogram.fftSize) /
                        Double(spectrogram.sampleRate) / 2

                    guard frameCentre >= symbolStart,
                          frameCentre < symbolEnd else {
                        continue
                    }

                    let elapsed = Float(
                        frameCentre -
                        decode.candidate.startTime
                    )
                    let frequency =
                        decode.candidate.frequency +
                        Float(tones[symbolIndex]) *
                        configuration.toneSpacing +
                        decode.candidate.driftHzPerSecond *
                        elapsed

                    let centreBin = Int(
                        (
                            (frequency -
                                frame.minimumFrequency) /
                            frame.binWidth
                        ).rounded()
                    )

                    let lower =
                        centreBin - configuration.binRadius
                    let upper =
                        centreBin + configuration.binRadius

                    for bin in lower...upper
                    where frame.magnitudes.indices.contains(bin) {
                        let address = BinAddress(
                            frame: frameIndex,
                            bin: bin
                        )

                        // A bin can be touched by adjacent symbol windows. Only
                        // charge its energy once, but allow the strongest
                        // requested cancellation to remain applied.
                        let firstTouch =
                            affected.insert(address).inserted

                        let original =
                            frameMagnitudes[frameIndex][bin]

                        if firstTouch {
                            before += Double(original * original)
                        }

                        let frequencyWeight =
                            gaussianFrequencyWeight(
                                bin: bin,
                                centreBin: centreBin
                            )

                        let strength = min(
                            max(
                                configuration.cancellationStrength *
                                timeTaper *
                                frequencyWeight,
                                0
                            ),
                            1
                        )

                        let scale = max(0, 1 - strength)
                        var residual = max(
                            original * scale,
                            configuration.minimumResidualMagnitude
                        )

                        if configuration.preserveNoiseFloor {
                            let noiseMagnitude = powf(
                                10,
                                frame.noiseFloorDB / 20
                            )

                            // Never raise a bin that was already below the
                            // measured noise floor.
                            if original > noiseMagnitude {
                                residual = max(
                                    residual,
                                    noiseMagnitude
                                )
                            }
                        }

                        frameMagnitudes[frameIndex][bin] =
                            min(
                                frameMagnitudes[frameIndex][bin],
                                residual
                            )
                    }
                }
            }
        }

        // Compute after-energy from the final residual values so bins touched
        // more than once are not double-counted.
        for address in affected {
            let value =
                frameMagnitudes[address.frame][address.bin]
            after += Double(value * value)
        }

        let frames = spectrogram.frames.indices.map {
            frameIndex -> WaterfallFrame in
            let source = spectrogram.frames[frameIndex]
            let magnitudes = frameMagnitudes[frameIndex]
            let decibels = VectorMath.decibels(
                magnitudes: magnitudes
            )
            let noise = NoiseFloorEstimator.median(
                of: decibels
            )
            let dynamicRange = max(
                (source.decibels.max() ?? noise) -
                    (source.decibels.min() ?? noise),
                1
            )
            let ceiling = max(
                decibels.max() ?? noise,
                noise + dynamicRange
            )
            let floorDB = ceiling - dynamicRange
            let intensities = decibels.map {
                min(
                    max(($0 - floorDB) / dynamicRange, 0),
                    1
                )
            }

            return WaterfallFrame(
                index: source.index,
                sampleOffset: source.sampleOffset,
                time: source.time,
                minimumFrequency:
                    source.minimumFrequency,
                binWidth: source.binWidth,
                magnitudes: magnitudes,
                decibels: decibels,
                intensities: intensities,
                noiseFloorDB: noise
            )
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
            energyBefore: before,
            energyAfter: after,
            affectedBins: affected.count
        )
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
            abs(Float(symbolIndex) - midpoint)
            / max(midpoint, 1)

        return max(
            configuration.timeTaperFloor,
            1 - distance * distance
        )
    }

    private func gaussianFrequencyWeight(
        bin: Int,
        centreBin: Int
    ) -> Float {
        let distance = bin - centreBin
        let sigma = max(
            Float(configuration.binRadius) / 2,
            0.75
        )

        return expf(
            -Float(distance * distance) /
            (2 * sigma * sigma)
        )
    }
}

private struct BinAddress: Hashable {
    let frame: Int
    let bin: Int
}
