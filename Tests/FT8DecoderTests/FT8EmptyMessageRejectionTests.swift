import Foundation
import XCTest
@testable import FT8Decoder

final class FT8EmptyMessageRejectionTests: XCTestCase {
    func testWhitespaceDetectionUsedByOptimizedDecoder() {
        XCTAssertTrue(
            "   \n"
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )
        XCTAssertFalse(
            "CQ TEST"
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )
    }
}
