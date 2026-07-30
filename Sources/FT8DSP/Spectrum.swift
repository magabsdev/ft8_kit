import Foundation

public struct Spectrum: Equatable, Sendable {
    public let sampleRate: Float
    public let fftSize: Int
    public let magnitudes: [Float]
    public let powers: [Float]

    public var binWidth: Float { sampleRate / Float(fftSize) }

    public func frequency(atBin index: Int) -> Float {
        Float(index) * binWidth
    }

    public func nearestBin(to frequency: Float) -> Int {
        guard !magnitudes.isEmpty else { return 0 }
        let candidate = Int((frequency / binWidth).rounded())
        return min(max(candidate, 0), magnitudes.count - 1)
    }

    public func decibels(reference: Float = 1, floor: Float = -160) -> [Float] {
        VectorMath.decibels(
            magnitudes: magnitudes,
            reference: reference,
            floor: floor
        )
    }

    public static func analyse(
        samples: [Float],
        sampleRate: Float,
        fftSize: Int? = nil,
        window: WindowFunction = .hann,
        removeMean: Bool = true
    ) throws -> Spectrum {
        let size = fftSize ?? samples.count
        guard samples.count <= size else {
            throw FFTError.incorrectInputCount(expected: size, actual: samples.count)
        }

        var prepared = samples
        if removeMean && !prepared.isEmpty {
            let mean = VectorMath.mean(prepared)
            VectorMath.subtract(scalar: mean, from: &prepared)
        }
        if prepared.count < size {
            prepared += Array(repeating: 0, count: size - prepared.count)
        }

        let coefficients = window.coefficients(count: size)
        let windowed = VectorMath.multiply(prepared, coefficients)

        let transformed = try FFT(size: size).forward(windowed)
        let oneSidedCount = size / 2 + 1
        let coherentGain = max(coefficients.reduce(0, +), Float.leastNonzeroMagnitude)
        let rawMagnitudes = VectorMath.magnitudes(
            real: Array(transformed.real.prefix(oneSidedCount)),
            imaginary: Array(transformed.imaginary.prefix(oneSidedCount))
        )
        var magnitudes = Array(repeating: Float.zero, count: oneSidedCount)

        for i in 0..<oneSidedCount {
            let edge = i == 0 || i == oneSidedCount - 1
            let scale: Float = edge ? 1 : 2
            magnitudes[i] = scale * rawMagnitudes[i] / coherentGain
        }

        let powers = VectorMath.multiply(magnitudes, magnitudes)

        return Spectrum(
            sampleRate: sampleRate,
            fftSize: size,
            magnitudes: magnitudes,
            powers: powers
        )
    }
}
