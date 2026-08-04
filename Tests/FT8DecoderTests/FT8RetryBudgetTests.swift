import XCTest
@testable import FT8Decoder

final class FT8RetryBudgetTests: XCTestCase {
    func testRetryCandidateOrderingPrefersMidConfidenceSoftSymbols() {
        let values: [(confidence: Float, candidate: Float)] = [
            (0.70, 1),
            (0.36, 2),
            (0.20, 3),
        ]

        let ordered = values.sorted {
            abs($0.confidence - 0.35)
                < abs($1.confidence - 0.35)
        }

        XCTAssertEqual(ordered.first?.candidate, 2)
    }
}
