import Foundation

#if canImport(Accelerate)
import Accelerate
#endif

public enum VectorMath {
    public static func sum(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        #if canImport(Accelerate)
        var result: Float = 0
        vDSP_sve(values, 1, &result, vDSP_Length(values.count))
        return result
        #else
        return simdSum(values)
        #endif
    }

    public static func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return sum(values) / Float(values.count)
    }

    public static func subtract(
        scalar: Float,
        from values: inout [Float]
    ) {
        guard !values.isEmpty else { return }
        #if canImport(Accelerate)
        var offset = -scalar
        vDSP_vsadd(
            values, 1,
            &offset,
            &values, 1,
            vDSP_Length(values.count)
        )
        #else
        var index = 0
        let scalarVector = SIMD8<Float>(repeating: scalar)
        while index + 8 <= values.count {
            let vector = SIMD8<Float>(
                values[index], values[index + 1],
                values[index + 2], values[index + 3],
                values[index + 4], values[index + 5],
                values[index + 6], values[index + 7]
            ) - scalarVector
            for lane in 0..<8 {
                values[index + lane] = vector[lane]
            }
            index += 8
        }
        while index < values.count {
            values[index] -= scalar
            index += 1
        }
        #endif
    }

    public static func multiply(
        _ lhs: [Float],
        _ rhs: [Float]
    ) -> [Float] {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return [] }
        var output = Array(repeating: Float.zero, count: count)

        #if canImport(Accelerate)
        vDSP_vmul(
            lhs, 1,
            rhs, 1,
            &output, 1,
            vDSP_Length(count)
        )
        #else
        var index = 0
        while index + 8 <= count {
            let a = SIMD8<Float>(
                lhs[index], lhs[index + 1],
                lhs[index + 2], lhs[index + 3],
                lhs[index + 4], lhs[index + 5],
                lhs[index + 6], lhs[index + 7]
            )
            let b = SIMD8<Float>(
                rhs[index], rhs[index + 1],
                rhs[index + 2], rhs[index + 3],
                rhs[index + 4], rhs[index + 5],
                rhs[index + 6], rhs[index + 7]
            )
            let product = a * b
            for lane in 0..<8 {
                output[index + lane] = product[lane]
            }
            index += 8
        }
        while index < count {
            output[index] = lhs[index] * rhs[index]
            index += 1
        }
        #endif
        return output
    }

    public static func magnitudes(
        real: [Float],
        imaginary: [Float]
    ) -> [Float] {
        let count = min(real.count, imaginary.count)
        guard count > 0 else { return [] }
        var output = Array(repeating: Float.zero, count: count)

        #if canImport(Accelerate)
        var realCopy = real
        var imaginaryCopy = imaginary
        realCopy.withUnsafeMutableBufferPointer { realBuffer in
            imaginaryCopy.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imaginaryBuffer.baseAddress!
                )
                vDSP_zvabs(
                    &split, 1,
                    &output, 1,
                    vDSP_Length(count)
                )
            }
        }
        #else
        var index = 0
        while index + 8 <= count {
            let re = SIMD8<Float>(
                real[index], real[index + 1],
                real[index + 2], real[index + 3],
                real[index + 4], real[index + 5],
                real[index + 6], real[index + 7]
            )
            let im = SIMD8<Float>(
                imaginary[index], imaginary[index + 1],
                imaginary[index + 2], imaginary[index + 3],
                imaginary[index + 4], imaginary[index + 5],
                imaginary[index + 6], imaginary[index + 7]
            )
            let squared = re * re + im * im
            for lane in 0..<8 {
                output[index + lane] = sqrtf(squared[lane])
            }
            index += 8
        }
        while index < count {
            output[index] = hypotf(real[index], imaginary[index])
            index += 1
        }
        #endif
        return output
    }

    public static func linearPower(
        fromDecibels values: [Float]
    ) -> [Float] {
        guard !values.isEmpty else { return [] }
        var output = Array(repeating: Float.zero, count: values.count)

        #if canImport(Accelerate)
        var scaled = values
        var divisor: Float = 10
        vDSP_vsdiv(
            scaled, 1,
            &divisor,
            &scaled, 1,
            vDSP_Length(scaled.count)
        )
        let base = Array(repeating: Float(10), count: scaled.count)
        var count = Int32(scaled.count)
        vvpowf(&output, scaled, base, &count)
        #else
        for index in values.indices {
            output[index] = powf(10, values[index] / 10)
        }
        #endif
        return output
    }

    public static func decibels(
        magnitudes: [Float],
        reference: Float = 1,
        floor: Float = -160
    ) -> [Float] {
        guard !magnitudes.isEmpty else { return [] }
        let safeReference = max(reference, Float.leastNonzeroMagnitude)
        var output = Array(repeating: Float.zero, count: magnitudes.count)

        #if canImport(Accelerate)
        let safe = magnitudes.map {
            max($0, Float.leastNonzeroMagnitude)
        }
        var count = Int32(safe.count)
        vvlog10f(&output, safe, &count)
        var scale: Float = 20
        vDSP_vsmul(
            output, 1,
            &scale,
            &output, 1,
            vDSP_Length(output.count)
        )
        var offset = -20 * log10f(safeReference)
        vDSP_vsadd(
            output, 1,
            &offset,
            &output, 1,
            vDSP_Length(output.count)
        )
        #else
        for index in magnitudes.indices {
            output[index] = 20 * log10f(
                max(magnitudes[index], Float.leastNonzeroMagnitude)
                / safeReference
            )
        }
        #endif

        for index in output.indices {
            output[index] = max(output[index], floor)
        }
        return output
    }

    private static func simdSum(_ values: [Float]) -> Float {
        var vectorTotal = SIMD8<Float>(repeating: 0)
        var index = 0
        while index + 8 <= values.count {
            vectorTotal += SIMD8<Float>(
                values[index], values[index + 1],
                values[index + 2], values[index + 3],
                values[index + 4], values[index + 5],
                values[index + 6], values[index + 7]
            )
            index += 8
        }

        var total: Float = 0
        for lane in 0..<8 {
            total += vectorTotal[lane]
        }
        while index < values.count {
            total += values[index]
            index += 1
        }
        return total
    }
}
