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
        let safeReference = max(reference, Float.leastNonzeroMagnitude)
        return magnitudes.map { magnitude in
            let safeMagnitude = max(magnitude, Float.leastNonzeroMagnitude)
            return max(20 * log10f(safeMagnitude / safeReference), floor)
        }
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
            let mean = prepared.reduce(0, +) / Float(prepared.count)
            for i in prepared.indices { prepared[i] -= mean }
        }
        if prepared.count < size {
            prepared += Array(repeating: 0, count: size - prepared.count)
        }

        let coefficients = window.coefficients(count: size)
        var windowed = Array(repeating: Float.zero, count: size)
        for i in 0..<size {
            windowed[i] = prepared[i] * coefficients[i]
        }

        let transformed = try FFT(size: size).forward(windowed)
        let oneSidedCount = size / 2 + 1
        let coherentGain = max(coefficients.reduce(0, +), Float.leastNonzeroMagnitude)
        var magnitudes = Array(repeating: Float.zero, count: oneSidedCount)
        var powers = Array(repeating: Float.zero, count: oneSidedCount)

        for i in 0..<oneSidedCount {
            let raw = sqrtf(
                transformed.real[i] * transformed.real[i] +
                transformed.imaginary[i] * transformed.imaginary[i]
            )
            let edge = i == 0 || i == oneSidedCount - 1
            let scale: Float = edge ? 1 : 2
            let magnitude = scale * raw / coherentGain
            magnitudes[i] = magnitude
            powers[i] = magnitude * magnitude
        }

        return Spectrum(
            sampleRate: sampleRate,
            fftSize: size,
            magnitudes: magnitudes,
            powers: powers
        )
    }
}
