import XCTest
@testable import FT8Decoder

final class CostasSequenceTests: XCTestCase {
    func testCanonicalSequence() {
        XCTAssertEqual(CostasSequence.tones, [3, 1, 4, 0, 6, 5, 2])
    }

    func testSyncBlockStarts() {
        XCTAssertEqual(CostasSequence.blockStarts, [0, 36, 72])
    }

    func testRecognisesSyncSymbols() {
        XCTAssertTrue(CostasSequence.isSyncSymbol(0))
        XCTAssertTrue(CostasSequence.isSyncSymbol(42))
        XCTAssertTrue(CostasSequence.isSyncSymbol(78))
        XCTAssertFalse(CostasSequence.isSyncSymbol(7))
        XCTAssertFalse(CostasSequence.isSyncSymbol(43))
    }

    func testExpectedToneForAllBlocks() {
        for start in CostasSequence.blockStarts {
            for index in 0..<7 {
                XCTAssertEqual(
                    CostasSequence.expectedTone(forSymbol: start + index),
                    CostasSequence.tones[index]
                )
            }
        }
    }

    func testDataSymbolHasNoExpectedTone() {
        XCTAssertNil(CostasSequence.expectedTone(forSymbol: 20))
    }
}
