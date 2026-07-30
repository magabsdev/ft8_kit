import XCTest
@testable import FT8Decoder

final class PCMFloatRingBufferTests: XCTestCase {
    func testAppendPeekAndRemove() throws {
        var buffer = try PCMFloatRingBuffer(capacity: 5)

        XCTAssertEqual(buffer.append([1, 2, 3]), 3)
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.peek(count: 2), [1, 2])
        XCTAssertEqual(buffer.removeFirst(2), [1, 2])
        XCTAssertEqual(buffer.peek(count: 5), [3])
    }

    func testOverflowKeepsNewestSamples() throws {
        var buffer = try PCMFloatRingBuffer(capacity: 4)

        buffer.append([1, 2, 3, 4, 5, 6])

        XCTAssertEqual(buffer.count, 4)
        XCTAssertEqual(buffer.peek(count: 10), [3, 4, 5, 6])
        XCTAssertEqual(buffer.suffix(count: 2), [5, 6])
    }

    func testWrapAroundPreservesOrdering() throws {
        var buffer = try PCMFloatRingBuffer(capacity: 5)

        buffer.append([1, 2, 3, 4])
        XCTAssertEqual(buffer.removeFirst(3), [1, 2, 3])
        buffer.append([5, 6, 7])

        XCTAssertEqual(buffer.peek(count: 5), [4, 5, 6, 7])
    }

    func testInvalidCapacityThrows() {
        XCTAssertThrowsError(
            try PCMFloatRingBuffer(capacity: 0)
        ) {
            XCTAssertEqual(
                $0 as? PCMFloatRingBufferError,
                .invalidCapacity
            )
        }
    }
}
