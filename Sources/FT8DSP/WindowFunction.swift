import Foundation

public enum WindowFunction: Equatable, Sendable {
    case rectangular
    case hann
    case hamming
    case blackman
    case blackmanHarris

    public func coefficients(count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [1] }

        let denominator = Double(count - 1)
        var output = Array(repeating: Float.zero, count: count)

        for index in 0..<count {
            let phase = 2.0 * Double.pi * Double(index) / denominator
            let value: Double

            switch self {
            case .rectangular:
                value = 1.0
            case .hann:
                value = 0.5 - 0.5 * cos(phase)
            case .hamming:
                value = 0.54 - 0.46 * cos(phase)
            case .blackman:
                value = 0.42 - 0.5 * cos(phase) + 0.08 * cos(2.0 * phase)
            case .blackmanHarris:
                let a0 = 0.35875
                let a1 = 0.48829
                let a2 = 0.14128
                let a3 = 0.01168
                value = a0 - a1 * cos(phase) + a2 * cos(2.0 * phase) - a3 * cos(3.0 * phase)
            }
            output[index] = Float(value)
        }

        return output
    }

    public func apply(to samples: [Float]) -> [Float] {
        let window = coefficients(count: samples.count)
        var output = Array(repeating: Float.zero, count: samples.count)
        for index in samples.indices {
            output[index] = samples[index] * window[index]
        }
        return output
    }
}
