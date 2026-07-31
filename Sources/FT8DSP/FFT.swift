import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

public final class FFT: @unchecked Sendable {
    public let size: Int

    #if canImport(Accelerate)
    private let forwardTransform: vDSP.DFT<Float>
    private let inverseTransform: vDSP.DFT<Float>
    #endif

    public init(size: Int) throws {
        guard size >= 2 else { throw FFTError.sizeMustBeAtLeastTwo(size) }

        #if !canImport(Accelerate)
        guard (size & (size - 1)) == 0 else {
            throw FFTError.sizeMustBePowerOfTwo(size)
        }
        #endif

        self.size = size

        #if canImport(Accelerate)
        guard let forward = vDSP.DFT(
            count: size,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        ), let inverse = vDSP.DFT(
            count: size,
            direction: .inverse,
            transformType: .complexComplex,
            ofType: Float.self
        ) else {
            throw FFTError.unavailable
        }
        self.forwardTransform = forward
        self.inverseTransform = inverse
        #endif
    }

    public func forward(_ samples: [Float]) throws -> FFTResult {
        try forward(real: samples, imaginary: Array(repeating: 0, count: size))
    }

    public func forward(real: [Float], imaginary: [Float]) throws -> FFTResult {
        try validate(real, imaginary)

        #if canImport(Accelerate)
        var outputReal = Array(repeating: Float.zero, count: size)
        var outputImaginary = Array(repeating: Float.zero, count: size)
        forwardTransform.transform(
            inputReal: real,
            inputImaginary: imaginary,
            outputReal: &outputReal,
            outputImaginary: &outputImaginary
        )
        return FFTResult(real: outputReal, imaginary: outputImaginary)
        #else
        return Self.radix2(real: real, imaginary: imaginary, inverse: false)
        #endif
    }

    public func inverse(_ spectrum: FFTResult) throws -> [Float] {
        try inverseComplex(spectrum).real
    }

    public func inverseComplex(_ spectrum: FFTResult) throws -> FFTResult {
        try validate(spectrum.real, spectrum.imaginary)

        #if canImport(Accelerate)
        var outputReal = Array(repeating: Float.zero, count: size)
        var outputImaginary = Array(repeating: Float.zero, count: size)
        inverseTransform.transform(
            inputReal: spectrum.real,
            inputImaginary: spectrum.imaginary,
            outputReal: &outputReal,
            outputImaginary: &outputImaginary
        )
        let scale = Float(size)
        for i in outputReal.indices {
            outputReal[i] /= scale
            outputImaginary[i] /= scale
        }
        return FFTResult(real: outputReal, imaginary: outputImaginary)
        #else
        return Self.radix2(
            real: spectrum.real,
            imaginary: spectrum.imaginary,
            inverse: true
        )
        #endif
    }

    private func validate(_ real: [Float], _ imaginary: [Float]) throws {
        guard real.count == size else {
            throw FFTError.incorrectInputCount(expected: size, actual: real.count)
        }
        guard imaginary.count == size else {
            throw FFTError.incorrectInputCount(expected: size, actual: imaginary.count)
        }
    }

    #if !canImport(Accelerate)
    private static func radix2(
        real inputReal: [Float],
        imaginary inputImaginary: [Float],
        inverse: Bool
    ) -> FFTResult {
        let n = inputReal.count
        var real = inputReal
        var imag = inputImaginary
        var j = 0

        if n > 2 {
            for i in 1..<(n - 1) {
                var bit = n >> 1
                while (j & bit) != 0 {
                    j ^= bit
                    bit >>= 1
                }
                j ^= bit
                if i < j {
                    real.swapAt(i, j)
                    imag.swapAt(i, j)
                }
            }
        }

        var length = 2
        while length <= n {
            let angle = (inverse ? 2.0 : -2.0) * Double.pi / Double(length)
            let stepR = Float(cos(angle))
            let stepI = Float(sin(angle))
            let half = length / 2
            var start = 0

            while start < n {
                var wr: Float = 1
                var wi: Float = 0

                for offset in 0..<half {
                    let even = start + offset
                    let odd = even + half
                    let oddR = real[odd] * wr - imag[odd] * wi
                    let oddI = real[odd] * wi + imag[odd] * wr
                    let evenR = real[even]
                    let evenI = imag[even]

                    real[even] = evenR + oddR
                    imag[even] = evenI + oddI
                    real[odd] = evenR - oddR
                    imag[odd] = evenI - oddI

                    let nextWR = wr * stepR - wi * stepI
                    wi = wr * stepI + wi * stepR
                    wr = nextWR
                }
                start += length
            }
            length <<= 1
        }

        if inverse {
            let scale = Float(n)
            for i in real.indices {
                real[i] /= scale
                imag[i] /= scale
            }
        }

        return FFTResult(real: real, imaginary: imag)
    }
    #endif
}
