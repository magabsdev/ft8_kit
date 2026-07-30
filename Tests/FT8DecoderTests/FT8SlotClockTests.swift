import Foundation
import XCTest
@testable import FT8Decoder

final class FT8SlotClockTests: XCTestCase {
    func testRoundsDownToFifteenSecondBoundary() {
        let clock = FT8SlotClock()
        let date = Date(timeIntervalSince1970: 1_000.9)

        XCTAssertEqual(
            clock.slotStart(containing: date)
                .timeIntervalSince1970,
            990,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            clock.nextSlotStart(after: date)
                .timeIntervalSince1970,
            1_005,
            accuracy: 0.000_001
        )
    }

    func testProgressAndIndex() {
        let clock = FT8SlotClock()
        let date = Date(timeIntervalSince1970: 37.5)

        XCTAssertEqual(
            clock.progress(at: date),
            0.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            clock.slotIndex(containing: date),
            2
        )
    }
}
