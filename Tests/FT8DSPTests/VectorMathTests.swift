import XCTest
@testable import FT8DSP

final class VectorMathTests: XCTestCase {
    func testSumAndMeanMatchScalarReference() {
        let values = (0..<37).map { Float($0) * 0.25 - 2 }
        XCTAssertEqual(
            VectorMath.sum(values),
            values.reduce(0, +),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VectorMath.mean(values),
            values.reduce(0, +) / Float(values.count),
            accuracy: 0.0001
        )
    }

    func testSubtractScalarInPlace() {
        var values: [Float] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        VectorMath.subtract(scalar: 2, from: &values)
        XCTAssertEqual(values, [-1, 0, 1, 2, 3, 4, 5, 6, 7])
    }

    func testMultiplyMatchesScalarReference() {
        let lhs = (0..<19).map(Float.init)
        let rhs = (0..<19).map { Float($0) / 3 }
        let expected = zip(lhs, rhs).map { $0 * $1 }
        let actual = VectorMath.multiply(lhs, rhs)

        for index in expected.indices {
            XCTAssertEqual(actual[index], expected[index], accuracy: 0.0001)
        }
    }

    func testComplexMagnitudes() {
        let result = VectorMath.magnitudes(
            real: [3, 5, 0, -8, 1],
            imaginary: [4, 12, 0, 15, 0]
        )
        XCTAssertEqual(result[0], 5, accuracy: 0.0001)
        XCTAssertEqual(result[1], 13, accuracy: 0.0001)
        XCTAssertEqual(result[2], 0, accuracy: 0.0001)
        XCTAssertEqual(result[3], 17, accuracy: 0.0001)
        XCTAssertEqual(result[4], 1, accuracy: 0.0001)
    }

    func testDecibelPowerRoundTrip() {
        let decibels: [Float] = [-40, -10, 0, 3, 12]
        let powers = VectorMath.linearPower(fromDecibels: decibels)

        for index in decibels.indices {
            XCTAssertEqual(
                10 * log10f(powers[index]),
                decibels[index],
                accuracy: 0.0005
            )
        }
    }

    func testDecibelsHonourFloor() {
        let result = VectorMath.decibels(
            magnitudes: [1, 0.1, 0],
            floor: -80
        )
        XCTAssertEqual(result[0], 0, accuracy: 0.0001)
        XCTAssertEqual(result[1], -20, accuracy: 0.0001)
        XCTAssertEqual(result[2], -80, accuracy: 0.0001)
    }
}
