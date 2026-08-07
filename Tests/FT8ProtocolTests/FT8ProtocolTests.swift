import XCTest
@testable import FT8Protocol

final class FT8ProtocolTests: XCTestCase {
    func testFreeTextRoundTrip() throws {
        let payload = try FT8MessageCodec.pack(.freeText("SIGNAL8 CORE"))
        XCTAssertEqual(payload.count, 77)
        XCTAssertEqual(try FT8MessageCodec.unpack(payload), .freeText("SIGNAL8 CORE"))
    }

    func testStandardMessageRoundTrips() throws {
        let messages: [FT8Message] = [
            .standard(to: "CQ", from: "G0ABC", extra: "IO91"),
            .standard(to: "M0XYZ", from: "G0ABC", extra: "-10"),
            .standard(to: "G0ABC", from: "M0XYZ", extra: "R-07"),
            .standard(to: "G0ABC/R", from: "M0XYZ/R", extra: "RR73")
        ]
        for message in messages {
            let payload = try FT8MessageCodec.pack(message)
            XCTAssertEqual(try FT8MessageCodec.unpack(payload), message)
        }
    }

    func testDirectedCQAlphaRoundTrip() throws {
        let message = FT8Message.standard(
            to: "CQ DX",
            from: "R6WA",
            extra: "LN32"
        )

        let payload = try FT8MessageCodec.pack(message)

        XCTAssertEqual(payload.count, 77)
        XCTAssertEqual(
            try FT8MessageCodec.unpack(payload),
            message
        )
    }

    func testDirectedCQNumericRoundTrip() throws {
        let message = FT8Message.standard(
            to: "CQ 123",
            from: "G0ABC",
            extra: "IO91"
        )

        let payload = try FT8MessageCodec.pack(message)

        XCTAssertEqual(
            try FT8MessageCodec.unpack(payload),
            message
        )
    }

    func testDirectedCQTextConveniencePacking() throws {
        let payload = try FT8MessageCodec.pack(
            "CQ DX R6WA LN32"
        )

        XCTAssertEqual(
            try FT8MessageCodec.unpack(payload),
            .standard(
                to: "CQ DX",
                from: "R6WA",
                extra: "LN32"
            )
        )
    }

    func testCRCAppendAndValidation() throws {
        let payload = try FT8MessageCodec.pack(.standard(to: "CQ", from: "G0ABC", extra: "IO91"))
        let protected = try FT8CRC.append(to: payload)
        XCTAssertEqual(protected.count, 91)
        XCTAssertTrue(FT8CRC.validate(protected))
        var damaged = protected
        damaged[12] ^= 1
        XCTAssertFalse(FT8CRC.validate(damaged))
    }

    func testPackedBytesRoundTrip() throws {
        let payload = try FT8MessageCodec.pack(.standard(to: "CQ", from: "G0ABC", extra: "IO91"))
        let bytes = payload.packedBytes(paddedTo: 10)
        XCTAssertEqual(FT8BitBuffer(packedBytes: bytes, bitCount: 77), payload)
    }

    func testGrayCodeRoundTrip() {
        for value in UInt8(0)...UInt8(7) {
            XCTAssertEqual(FT8GrayCode.decode(FT8GrayCode.encode(value)), value)
        }
        XCTAssertEqual(FT8Constants.grayMap, [0, 1, 3, 2, 5, 6, 4, 7])
    }

    func testFreeTextRejectsTooManyCharacters() {
        XCTAssertThrowsError(try FT8MessageCodec.pack(.freeText("12345678901234")))
    }
}
