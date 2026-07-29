import XCTest
@testable import FT8DSP

final class FFTTests: XCTestCase {
    func testRejectsNonPowerOfTwoSize() {
        XCTAssertThrowsError(try FFT(size: 12)) { error in
            XCTAssertEqual(error as? FFTError, .sizeMustBePowerOfTwo(12))
        }
    }

    func testImpulseTransformsToFlatSpectrum() throws {
        let result = try FFT(size: 8).forward([1, 0, 0, 0, 0, 0, 0, 0])
        for value in result.real {
            XCTAssertEqual(value, 1, accuracy: 0.00001)
        }
        for value in result.imaginary {
            XCTAssertEqual(value, 0, accuracy: 0.00001)
        }
    }

    func testForwardInverseRoundTrip() throws {
        let input: [Float] = [0.25, -0.5, 0.75, 1, -1, 0.125, 0.5, -0.25]
        let fft = try FFT(size: 8)
        let reconstructed = try fft.inverse(try fft.forward(input))
        for (actual, expected) in zip(reconstructed, input) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }

    func testComplexSingleBin() throws {
        let n = 32
        let bin = 5
        let real = (0..<n).map {
            Float(cos(2 * Double.pi * Double(bin * $0) / Double(n)))
        }
        let imag = (0..<n).map {
            Float(sin(2 * Double.pi * Double(bin * $0) / Double(n)))
        }
        let result = try FFT(size: n).forward(real: real, imaginary: imag)
        let peak = result.magnitudes.enumerated().max { $0.element < $1.element }
        XCTAssertEqual(peak?.offset, bin)
        XCTAssertEqual(peak?.element ?? 0, Float(n), accuracy: 0.001)
    }
}
