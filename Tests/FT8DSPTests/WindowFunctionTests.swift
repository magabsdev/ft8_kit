import XCTest
@testable import FT8DSP

final class WindowFunctionTests: XCTestCase {
    func testRectangularWindow() {
        XCTAssertEqual(WindowFunction.rectangular.coefficients(count: 4), [1, 1, 1, 1])
    }

    func testHannEndpointsAndCentre() {
        let values = WindowFunction.hann.coefficients(count: 9)
        XCTAssertEqual(values.first ?? -1, 0, accuracy: 0.000001)
        XCTAssertEqual(values.last ?? -1, 0, accuracy: 0.000001)
        XCTAssertEqual(values[4], 1, accuracy: 0.000001)
    }

    func testHammingEndpoints() {
        let values = WindowFunction.hamming.coefficients(count: 9)
        XCTAssertEqual(values.first ?? -1, 0.08, accuracy: 0.000001)
        XCTAssertEqual(values.last ?? -1, 0.08, accuracy: 0.000001)
    }

    func testApplyPreservesCount() {
        XCTAssertEqual(
            WindowFunction.blackmanHarris.apply(to: Array(repeating: 1, count: 64)).count,
            64
        )
    }
}
