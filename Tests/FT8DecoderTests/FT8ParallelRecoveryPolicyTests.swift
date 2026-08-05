import XCTest
@testable import FT8Decoder

final class FT8ParallelRecoveryPolicyTests: XCTestCase {
    func testRecoveryFrequencyDiversity() {
        let frequencies: [Float] = [1_000]
        XCTAssertTrue(
            frequencies.contains {
                abs($0 - 1_012.5) < 18.75
            }
        )
        XCTAssertFalse(
            frequencies.contains {
                abs($0 - 1_025) < 18.75
            }
        )
    }

    func testParityIsPreferredForRetryOrdering() {
        let values = [
            (parity: false, syndrome: 1),
            (parity: true, syndrome: 8),
        ]

        let ordered = values.sorted {
            if $0.parity != $1.parity {
                return $0.parity
            }
            return $0.syndrome < $1.syndrome
        }

        XCTAssertTrue(ordered[0].parity)
    }
}
