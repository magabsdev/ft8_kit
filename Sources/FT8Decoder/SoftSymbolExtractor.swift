import Foundation
import FT8DSP

public enum SoftSymbolError: Error, Equatable, Sendable {
    case emptySpectrogram
    case invalidConfiguration
    case invalidCandidateFrequency(Float)
    case insufficientObservations(symbol: Int)
}

public enum SoftSymbolMetricMode: String, Equatable, Sendable {
    case maxLog
    case logMAP

    // WSJT-X FT8 pass-1 metric: max compatible tone amplitude
    // difference, normalized across all 174 metrics.
    case wsjtxNormalizedMaxAmplitude
}

public struct SoftSymbolConfiguration: Equatable, Sendable {
    public var symbolPeriod: Double
    public var toneSpacing: Float
    public var integrationRadius: Int
    public var timeIntegrationRadius: Int
    public var minimumObservationsPerSymbol: Int
    public var llrScale: Float
    public var llrLimit: Float
    public var metricMode: SoftSymbolMetricMode

    public init(
        symbolPeriod: Double = 0.160,
        toneSpacing: Float = 6.25,
        integrationRadius: Int = 0,
        timeIntegrationRadius: Int = 1,
        minimumObservationsPerSymbol: Int = 1,
        llrScale: Float = 1,
        llrLimit: Float = 24,
        metricMode: SoftSymbolMetricMode = .maxLog
    ) {
        self.symbolPeriod = symbolPeriod
        self.toneSpacing = toneSpacing
        self.integrationRadius = integrationRadius
        self.timeIntegrationRadius = timeIntegrationRadius
        self.minimumObservationsPerSymbol = minimumObservationsPerSymbol
        self.llrScale = llrScale
        self.llrLimit = llrLimit
        self.metricMode = metricMode
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

            for bitIndex in 0..<3 {
                let llr = bitLLR(
                    bitIndex: bitIndex,
                    toneMetricsDB: metrics
                )

                let scaledLLR: Float
                if configuration.metricMode == .wsjtxNormalizedMaxAmplitude {
                    scaledLLR = llr
                } else {
                    scaledLLR = llr * configuration.llrScale
                }

                llrs.append(
                    min(
                        max(
                            scaledLLR,
                            -configuration.llrLimit
                        ),
                        configuration.llrLimit
                    )
                )
            }
        }

        if configuration.metricMode == .wsjtxNormalizedMaxAmplitude {
            llrs = normalizeWSJTXBitMetrics(llrs)
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

    private func bitLLR(
        bitIndex: Int,
        toneMetricsDB: [Float]
    ) -> Float {
        switch configuration.metricMode {
        case .maxLog:
            var zero = -Float.infinity
            var one = -Float.infinity

            for tone in 0..<8 {
                let bits = FT8ToneMapping.bits(forTone: tone)
                let bit = bitIndex == 0
                    ? bits.0
                    : (bitIndex == 1 ? bits.1 : bits.2)

                if bit == 0 {
                    zero = max(zero, toneMetricsDB[tone])
                } else {
                    one = max(one, toneMetricsDB[tone])
                }
            }

            return zero - one

        case .wsjtxNormalizedMaxAmplitude:
            // WSJT-X ft8b.f90 uses abs(FFT) amplitudes for its nsym=1
            // bit metric. FT8Kit stores interpolated dB power here, so
            // convert back to amplitude before taking compatible maxima.
            //
            // WSJT-X uses positive => bit 1. FT8Kit uses positive => bit 0,
            // hence the deliberately reversed sign below.
            var zero = -Float.infinity
            var one = -Float.infinity

            for tone in 0..<8 {
                let bits = FT8ToneMapping.bits(forTone: tone)
                let bit = bitIndex == 0
                    ? bits.0
                    : (bitIndex == 1 ? bits.1 : bits.2)
                let amplitude = powf(10, toneMetricsDB[tone] / 20)

                if bit == 0 {
                    zero = max(zero, amplitude)
                } else {
                    one = max(one, amplitude)
                }
            }

            return zero - one

        case .logMAP:
            // Preserve likelihood contribution from every compatible tone.
            // dB power is converted to natural-log space before log-sum-exp.
            let dbToNaturalLog = Float(log(10.0) / 10.0)
            var zero: [Float] = []
            var one: [Float] = []
            zero.reserveCapacity(4)
            one.reserveCapacity(4)

            for tone in 0..<8 {
                let bits = FT8ToneMapping.bits(forTone: tone)
                let bit = bitIndex == 0
                    ? bits.0
                    : (bitIndex == 1 ? bits.1 : bits.2)

                let value = toneMetricsDB[tone] * dbToNaturalLog

                if bit == 0 {
                    zero.append(value)
                } else {
                    one.append(value)
                }
            }

            return logSumExp(zero) - logSumExp(one)
        }
    }

    // Port of WSJT-X normalizebmet(), followed by its FT8
    // scalefac=2.83. Unlike ordinary profiles this scaling is global
    // across the complete 174-bit metric vector.
    private func normalizeWSJTXBitMetrics(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else {
            return values
        }

        let count = Float(values.count)
        let mean = values.reduce(Float.zero, +) / count
        let meanSquare = values.reduce(Float.zero) {
            $0 + $1 * $1
        } / count
        let variance = meanSquare - mean * mean

        let sigma: Float
        if variance > 0 {
            sigma = sqrtf(variance)
        } else {
            sigma = sqrtf(max(meanSquare, 0))
        }

        guard sigma.isFinite, sigma > Float.leastNonzeroMagnitude else {
            return values.map { _ in 0 }
        }

        return values.map {
            min(
                max(($0 / sigma) * 2.83, -configuration.llrLimit),
                configuration.llrLimit
            )
        }
    }

    private func logSumExp(_ values: [Float]) -> Float {
        guard let maximum = values.max(), maximum.isFinite else {
            return -Float.infinity
        }

        var sum: Float = 0
        for value in values {
            sum += expf(value - maximum)
        }

        return maximum + logf(max(sum, Float.leastNonzeroMagnitude))
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
