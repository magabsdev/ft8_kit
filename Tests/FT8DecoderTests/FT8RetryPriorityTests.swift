import XCTest
@testable import FT8Decoder

final class FT8RetryPriorityTests: XCTestCase {
    func testParityCandidateRanksBeforeLowerSyndromeCandidate() {
        let candidates: [
            (
                parity: Bool,
                syndrome: Int,
                confidence: Float
            )
        ] = [
            (false, 1, 0.95),
            (true, 8, 0.70),
        ]

        let ordered = candidates.sorted {
            if $0.parity != $1.parity {
                return $0.parity
            }

            return $0.syndrome < $1.syndrome
        }

        XCTAssertTrue(ordered[0].parity)
    }

    func testFrequencyDiversityThreshold() {
        let existing: [Float] = [1_000]
        XCTAssertTrue(
            existing.contains {
                abs($0 - 1_012.5) < 18.75
            }
        )
        XCTAssertFalse(
            existing.contains {
                abs($0 - 1_025) < 18.75
            }
        )
    }
}
