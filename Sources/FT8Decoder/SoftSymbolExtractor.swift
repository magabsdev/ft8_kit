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
    public var integrationRadius: Int
    public var minimumObservationsPerSymbol: Int
    public var llrScale: Float
    public var llrLimit: Float

    public init(
        symbolPeriod: Double = 0.160,
        toneSpacing: Float = 6.25,
        integrationRadius: Int = 0,
        minimumObservationsPerSymbol: Int = 1,
        llrScale: Float = 1,
        llrLimit: Float = 24
    ) {
        self.symbolPeriod = symbolPeriod
        self.toneSpacing = toneSpacing
        self.integrationRadius = integrationRadius
        self.minimumObservationsPerSymbol = minimumObservationsPerSymbol
        self.llrScale = llrScale
        self.llrLimit = llrLimit
    }

    fileprivate func validate() throws {
        guard symbolPeriod > 0,
              toneSpacing > 0,
              integrationRadius >= 0,
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
        llrs.reserveCapacity(174)
        confidences.reserveCapacity(58)

        for symbolIndex in FT8ToneMapping.dataSymbolIndices {
            let metrics = try toneMetrics(
                symbolIndex: symbolIndex,
                spectrogram: spectrogram,
                candidate: candidate
            )
            let ordered = metrics.sorted(by: >)
            let confidence = max(0, ordered[0] - ordered[1])
            confidences.append(min(confidence / 6, 1))

            for bitIndex in 0..<3 {
                var zero = -Float.infinity
                var one = -Float.infinity
                for tone in 0..<8 {
                    let bits = FT8ToneMapping.bits(forTone: tone)
                    let bit = bitIndex == 0 ? bits.0 : (bitIndex == 1 ? bits.1 : bits.2)
                    if bit == 0 {
                        zero = max(zero, metrics[tone])
                    } else {
                        one = max(one, metrics[tone])
                    }
                }
                let value = (zero - one) * configuration.llrScale
                llrs.append(min(max(value, -configuration.llrLimit), configuration.llrLimit))
            }
        }

        return FT8SoftSymbols(
            logLikelihoodRatios: llrs,
            symbolConfidences: confidences
        )
    }

    public func toneMetrics(
    symbolIndex: Int,
    spectrogram: Spectrogram,
    candidate: FT8Candidate
    ) throws -> [Float] {
        try configuration.validate()

        let symbolStart = candidate.startTime
        + Double(symbolIndex) * configuration.symbolPeriod

        guard let frame = spectrogram.frame(nearestTime: symbolStart) else {
            throw SoftSymbolError.insufficientObservations(symbol: symbolIndex)
        }

        var linear = Array(repeating: Float.zero, count: 8)

        for tone in 0..<8 {
            let elapsed = Float(frame.time - candidate.startTime)
            let frequency = candidate.frequency
            + Float(tone) * configuration.toneSpacing
            + candidate.driftHzPerSecond * elapsed

            let centreBin = Int(
                ((frequency - frame.minimumFrequency) / frame.binWidth).rounded()
            )

            var decibelSamples: [Float] = []
            decibelSamples.reserveCapacity(
                configuration.integrationRadius * 2 + 1
            )

            for offset in -configuration.integrationRadius...configuration.integrationRadius {
                let bin = centreBin + offset
                guard frame.decibels.indices.contains(bin) else {
                    continue
                }
                decibelSamples.append(frame.decibels[bin])
            }

            let powers = VectorMath.linearPower(fromDecibels: decibelSamples)
            linear[tone] = powers.isEmpty ? 0 : VectorMath.mean(powers)
        }

        return linear.map { power in
            10 * log10f(
                max(power, Float.leastNonzeroMagnitude)
            )
        }
    }
}
