import Foundation
import FT8DSP
import FT8Protocol

public struct FT8WSJTXSoftMetricExtractor: Sendable {
    public var llrScale: Float
    public var llrLimit: Float

    public init(llrScale: Float = 2.83, llrLimit: Float = 24) {
        self.llrScale = llrScale
        self.llrLimit = llrLimit
    }

    public func extract(
        from spectrogram: Spectrogram,
        candidate: FT8Candidate
    ) throws -> [FT8SoftSymbolVariant] {
        guard !spectrogram.frames.isEmpty else {
            throw SoftSymbolError.emptySpectrogram
        }

        let observations = try complexToneObservations(
            from: spectrogram,
            candidate: candidate
        )

        let a = rawMetrics(observations: observations, nsym: 1, bitNormalized: false)
        let b = rawMetrics(observations: observations, nsym: 2, bitNormalized: false)
        let c = rawMetrics(observations: observations, nsym: 3, bitNormalized: false)
        let d = rawMetrics(observations: observations, nsym: 1, bitNormalized: true)
        let e = zip(zip(a, b), c).map { pair in
            let values = [pair.0.0, pair.0.1, pair.1]
            return values.max(by: { abs($0) < abs($1) }) ?? 0
        }

        let families: [(String, [Float])] = [
            ("wsjtx-nsym1", normalize(a)),
            ("wsjtx-nsym2", normalize(b)),
            ("wsjtx-nsym3", normalize(c)),
            ("wsjtx-bit-normalized", normalize(d)),
            ("wsjtx-best", normalize(e))
        ]

        return families.map { name, llrs in
            FT8SoftSymbolVariant(
                profileName: name,
                softSymbols: FT8SoftSymbols(
                    logLikelihoodRatios: llrs,
                    symbolConfidences: confidences(from: llrs)
                )
            )
        }
    }

    private struct ComplexValue {
        let real: Float
        let imaginary: Float

        static func + (lhs: Self, rhs: Self) -> Self {
            Self(real: lhs.real + rhs.real, imaginary: lhs.imaginary + rhs.imaginary)
        }

        var magnitude: Float { hypotf(real, imaginary) }
    }

    private func complexToneObservations(
        from spectrogram: Spectrogram,
        candidate: FT8Candidate
    ) throws -> [[[ComplexValue]]] {
        let halves = [Array(7...35), Array(43...71)]
        var result: [[[ComplexValue]]] = []
        result.reserveCapacity(2)

        for symbols in halves {
            var half: [[ComplexValue]] = []
            half.reserveCapacity(29)

            for symbolIndex in symbols {
                let symbolStart =
                    candidate.startTime + Double(symbolIndex) * 0.160

                guard let frame = spectrogram.frame(nearestTime: symbolStart) else {
                    throw SoftSymbolError.insufficientObservations(symbol: symbolIndex)
                }

                let elapsed = Float(frame.time - candidate.startTime)
                var tones: [ComplexValue] = []
                tones.reserveCapacity(8)

                for tone in 0..<8 {
                    let frequency =
                        candidate.frequency
                        + Float(tone) * 6.25
                        + candidate.driftHzPerSecond * elapsed
                    tones.append(interpolatedComplex(frequency: frequency, frame: frame))
                }

                half.append(tones)
            }

            result.append(half)
        }

        return result
    }

    private func rawMetrics(
        observations: [[[ComplexValue]]],
        nsym: Int,
        bitNormalized: Bool
    ) -> [Float] {
        var metrics = Array(repeating: Float.zero, count: 174)
        let combinationCount = 1 << (3 * nsym)
        let bitCount = 3 * nsym

        for halfIndex in 0..<2 {
            let half = observations[halfIndex]
            var k = 0

            while k < 29 {
                var amplitudes = Array(repeating: Float.zero, count: combinationCount)

                for pattern in 0..<combinationCount {
                    var sum = ComplexValue(real: 0, imaginary: 0)

                    for symbolOffset in 0..<nsym {
                        let symbol = k + symbolOffset
                        if symbol >= half.count { continue }

                        let shift = 3 * (nsym - 1 - symbolOffset)
                        let binaryTone = (pattern >> shift) & 0x7
                        let grayTone = Int(FT8Constants.grayMap[binaryTone])
                        sum = sum + half[symbol][grayTone]
                    }

                    amplitudes[pattern] = sum.magnitude
                }

                let startingBit = halfIndex * 87 + k * 3

                for localBit in 0..<bitCount {
                    let outputIndex = startingBit + localBit
                    if outputIndex >= metrics.count { continue }

                    let patternBit = bitCount - 1 - localBit
                    var zeroMaximum = -Float.infinity
                    var oneMaximum = -Float.infinity

                    for pattern in 0..<combinationCount {
                        let value = amplitudes[pattern]
                        if ((pattern >> patternBit) & 1) == 0 {
                            zeroMaximum = max(zeroMaximum, value)
                        } else {
                            oneMaximum = max(oneMaximum, value)
                        }
                    }

                    var metric = zeroMaximum - oneMaximum
                    if bitNormalized {
                        let denominator = max(zeroMaximum, oneMaximum)
                        metric = denominator > 0 && denominator.isFinite
                            ? metric / denominator
                            : 0
                    }
                    metrics[outputIndex] = metric
                }

                k += nsym
            }
        }

        return metrics
    }

    private func normalize(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return values }

        let count = Float(values.count)
        let mean = values.reduce(Float.zero, +) / count
        let meanSquare = values.reduce(Float.zero) { $0 + $1 * $1 } / count
        let variance = meanSquare - mean * mean
        let sigma = variance > 0
            ? sqrtf(variance)
            : sqrtf(max(meanSquare, 0))

        guard sigma.isFinite, sigma > Float.leastNonzeroMagnitude else {
            return values.map { _ in 0 }
        }

        return values.map {
            min(max(($0 / sigma) * llrScale, -llrLimit), llrLimit)
        }
    }

    private func confidences(from llrs: [Float]) -> [Float] {
        stride(from: 0, to: llrs.count, by: 3).map { start in
            let end = min(start + 3, llrs.count)
            let mean = llrs[start..<end].map(abs).reduce(Float.zero, +)
                / Float(end - start)
            return min(max(mean / 6, 0), 1)
        }
    }

    private func interpolatedComplex(
        frequency: Float,
        frame: WaterfallFrame
    ) -> ComplexValue {
        let exactBin = (frequency - frame.minimumFrequency) / frame.binWidth
        guard exactBin.isFinite else {
            return .init(real: 0, imaginary: 0)
        }

        let lower = Int(floor(exactBin))
        let upper = lower + 1
        let fraction = exactBin - Float(lower)

        guard frame.magnitudes.indices.contains(lower),
              frame.magnitudes.indices.contains(upper) else {
            return .init(real: 0, imaginary: 0)
        }

        if frame.real.indices.contains(lower),
           frame.real.indices.contains(upper),
           frame.imaginary.indices.contains(lower),
           frame.imaginary.indices.contains(upper) {
            return .init(
                real: frame.real[lower] * (1 - fraction) + frame.real[upper] * fraction,
                imaginary: frame.imaginary[lower] * (1 - fraction)
                    + frame.imaginary[upper] * fraction
            )
        }

        return .init(
            real: frame.magnitudes[lower] * (1 - fraction)
                + frame.magnitudes[upper] * fraction,
            imaginary: 0
        )
    }
}
