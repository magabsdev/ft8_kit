import Foundation

public struct FFTResult: Equatable, Sendable {
    public let real: [Float]
    public let imaginary: [Float]

    public init(real: [Float], imaginary: [Float]) {
        precondition(real.count == imaginary.count)
        self.real = real
        self.imaginary = imaginary
    }

    public var count: Int { real.count }

    public var magnitudes: [Float] {
        zip(real, imaginary).map { pair in
            sqrtf(pair.0 * pair.0 + pair.1 * pair.1)
        }
    }

    public var powers: [Float] {
        zip(real, imaginary).map { pair in
            pair.0 * pair.0 + pair.1 * pair.1
        }
    }
}
