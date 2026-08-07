import Foundation
import FT8DSP

public enum SoftSymbolError: Error, Equatable, Sendable {
    case emptySpectrogram
    case invalidConfiguration
    case invalidCandidateFrequency(Float)
    case insufficientObservations(symbol: Int)
}

public struct SoftSymbolConfiguration: Equatable, Sendable {
    public var symbolPeriod: Double
    public var toneSpacing: Float

    /// Number of neighbouring frequency bins included on each side of the
    /// interpolated tone frequency. A value of zero still uses fractional-bin
    /// interpolation between the two nearest FFT bins.
    public var integrationRadius: Int

    /// Number of neighbouring waterfall frames included on each side of the
    /// frame nearest the symbol start. FT8Kit's waterfall frame timestamp is
    /// the FFT-window start, so the default ±1 frames samples the same symbol
    /// at three overlapping FFT windows when the normal 40 ms hop is used.
    public var timeIntegrationRadius: Int

    public var minimumObservationsPerSymbol: Int
    public var llrScale: Float
    public var llrLimit: Float

    public init(
        symbolPeriod: Double = 0.160,
        toneSpacing: Float = 6.25,
        integrationRadius: Int = 0,
        timeIntegrationRadius: Int = 1,
        minimumObservationsPerSymbol: Int = 1,
        llrScale: Float = 1,
        llrLimit: Float = 24
    ) {
        self.symbolPeriod = symbolPeriod
        self.toneSpacing = toneSpacing
        self.integrationRadius = integrationRadius
        self.timeIntegrationRadius = timeIntegrationRadius
        self.minimumObservationsPerSymbol = minimumObservationsPerSymbol
        self.llrScale = llrScale
        self.llrLimit = llrLimit
    }

    fileprivate func validate() throws {
        guard symbolPeriod > 0,
              toneSpacing > 0,
              integrationRadius >= 0,
              timeIntegrationRadius >= 0,
              minimumObservationsPerSymbol > 0,
              llrScale > 0,
              llrLimit > 0 else {
            throw SoftSymbolError.invalidConfiguration
        }
    }
}

public struct SoftSymbolExtractor: Sendable {
    public var configuration: SoftSymbolConfiguration

    public init(configuration: SoftSymbolConfiguration = .init()) {
        self.configuration = configuration
    }

    public func extract(
        from spectrogram: Spectrogram,
        candidate: FT8Candidate
    ) throws -> FT8SoftSymbols {
        try extractWithTrace(
            from: spectrogram,
            candidate: candidate
        ).softSymbols
    }

    public func extractWithTrace(
        from spectrogram: Spectrogram,
        candidate: FT8Candidate
    ) throws -> FT8SoftSymbolExtraction {
        try configuration.validate()
        guard !spectrogram.frames.isEmpty else {
            throw SoftSymbolError.emptySpectrogram
        }
        guard candidate.frequency >= spectrogram.minimumFrequency,
              candidate.frequency + 7 * configuration.toneSpacing <= spectrogram.maximumFrequency else {
            throw SoftSymbolError.invalidCandidateFrequency(candidate.frequency)
        }

        var llrs: [Float] = []
        var confidences: [Float] = []
        var traces: [FT8SymbolTrace] = []
        llrs.reserveCapacity(174)
        confidences.reserveCapacity(58)
        traces.reserveCapacity(58)

        for symbolIndex in FT8ToneMapping.dataSymbolIndices {
            let metrics = try toneMetrics(
                symbolIndex: symbolIndex,
                spectrogram: spectrogram,
                candidate: candidate
            )

            let ordered = metrics.sorted(by: >)
            let confidence = min(max((ordered[0] - ordered[1]) / 6, 0), 1)
            confidences.append(confidence)

            traces.append(
                FT8SymbolTrace(
                    symbolIndex: symbolIndex,
                    toneMetrics: metrics,
                    confidence: confidence
                )
            )

            // Max-log bit likelihoods. There are 58 data symbols × 3 bits =
            // 174 channel LLRs, exactly one value per LDPC codeword bit.
            for bitIndex in 0..<3 {
                var zero = -Float.infinity
                var one = -Float.infinity

                for tone in 0..<8 {
                    let bits = FT8ToneMapping.bits(forTone: tone)
                    let bit = bitIndex == 0
                        ? bits.0
                        : (bitIndex == 1 ? bits.1 : bits.2)

                    if bit == 0 {
                        zero = max(zero, metrics[tone])
                    } else {
                        one = max(one, metrics[tone])
                    }
                }

                // FT8LDPCDecoder uses negative LLR values for hard bit 1.
                // Preserve the raw relative reliability here; the LDPC decoder
                // performs whole-vector variance normalisation before BP.
                llrs.append((zero - one) * configuration.llrScale)
            }
        }

        return FT8SoftSymbolExtraction(
            softSymbols: FT8SoftSymbols(
                logLikelihoodRatios: llrs,
                symbolConfidences: confidences
            ),
            symbols: traces
        )
    }

    public func toneMetrics(
        symbolIndex: Int,
        spectrogram: Spectrogram,
        candidate: FT8Candidate
    ) throws -> [Float] {
        try configuration.validate()

        guard !spectrogram.frames.isEmpty else {
            throw SoftSymbolError.emptySpectrogram
        }

        let symbolStart =
            candidate.startTime
            + Double(symbolIndex) * configuration.symbolPeriod

        let frameStep =
            Double(spectrogram.hopSize) / Double(spectrogram.sampleRate)

        let centreFrameIndex = Int((symbolStart / frameStep).rounded())

        let firstFrameIndex = max(
            0,
            centreFrameIndex - configuration.timeIntegrationRadius
        )
        let lastFrameIndex = min(
            spectrogram.frames.count - 1,
            centreFrameIndex + configuration.timeIntegrationRadius
        )

        guard firstFrameIndex <= lastFrameIndex else {
            throw SoftSymbolError.insufficientObservations(symbol: symbolIndex)
        }

        var accumulatedPower = Array(repeating: Float.zero, count: 8)
        var accumulatedWeight = Array(repeating: Float.zero, count: 8)
        var observationCount = 0

        for frameIndex in firstFrameIndex...lastFrameIndex {
            let frame = spectrogram.frames[frameIndex]

            // Triangular temporal weighting keeps the original nearest-frame
            // observation dominant while using overlapping neighbouring FFTs
            // to reduce a single-frame fade/noise spike.
            let frameDistance = abs(frameIndex - centreFrameIndex)
            let timeWeight = Float(
                configuration.timeIntegrationRadius + 1 - frameDistance
            )

            let elapsed = Float(frame.time - candidate.startTime)

            for tone in 0..<8 {
                let frequency =
                    candidate.frequency
                    + Float(tone) * configuration.toneSpacing
                    + candidate.driftHzPerSecond * elapsed

                let power = interpolatedLinearPower(
                    at: frequency,
                    in: frame
                )

                guard power.isFinite, power > 0 else {
                    continue
                }

                accumulatedPower[tone] += power * timeWeight
                accumulatedWeight[tone] += timeWeight
            }

            observationCount += 1
        }

        guard observationCount >= configuration.minimumObservationsPerSymbol else {
            throw SoftSymbolError.insufficientObservations(symbol: symbolIndex)
        }

        return accumulatedPower.indices.map { tone in
            let weight = accumulatedWeight[tone]
            let meanPower = weight > 0
                ? accumulatedPower[tone] / weight
                : Float.leastNonzeroMagnitude

            return 10 * log10f(
                max(meanPower, Float.leastNonzeroMagnitude)
            )
        }
    }

    private func interpolatedLinearPower(
        at frequency: Float,
        in frame: WaterfallFrame
    ) -> Float {
        let exactBin =
            (frequency - frame.minimumFrequency) / frame.binWidth

        guard exactBin.isFinite else {
            return 0
        }

        let lowerCentre = Int(floor(exactBin))
        let fraction = exactBin - Float(lowerCentre)

        var weightedPower: Float = 0
        var totalWeight: Float = 0

        // integrationRadius = 0 still performs two-bin linear interpolation.
        // Larger radii add symmetric neighbouring interpolated samples.
        for offset in -configuration.integrationRadius...configuration.integrationRadius {
            let lower = lowerCentre + offset
            let upper = lower + 1

            guard frame.decibels.indices.contains(lower),
                  frame.decibels.indices.contains(upper) else {
                continue
            }

            let lowerPower = powf(10, frame.decibels[lower] / 10)
            let upperPower = powf(10, frame.decibels[upper] / 10)

            let interpolated =
                lowerPower * (1 - fraction)
                + upperPower * fraction

            // Frequency neighbours use a triangular weight so the bins closest
            // to the requested tone remain dominant.
            let frequencyWeight = Float(
                configuration.integrationRadius + 1 - abs(offset)
            )

            weightedPower += interpolated * frequencyWeight
            totalWeight += frequencyWeight
        }

        guard totalWeight > 0 else {
            return 0
        }

        return weightedPower / totalWeight
    }
}
