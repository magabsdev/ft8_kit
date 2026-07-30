import XCTest
import FT8Encoder
import FT8Protocol
@testable import FT8Decoder

final class FT8SignalSynthesizerTests: XCTestCase {
    func testReconstructedTonesMatchEncoder() throws {
        let message = "CQ G0ABC IO91"
        let expected = try FT8Encoder.encode(text: message)
        let payload = try FT8MessageCodec.pack(message)
        let message91 = try FT8CRC.append(to: payload)
        let codeword = try FT8Encoder.encodeLDPC(message91)

        let actual = try FT8SignalSynthesizer().tones(
            for: codeword
        )

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.count, 79)
    }

    func testRejectsInvalidCodewordLength() {
        XCTAssertThrowsError(
            try FT8SignalSynthesizer().tones(
                for: FT8BitBuffer(count: 173)
            )
        ) {
            XCTAssertEqual(
                $0 as? FT8SignalSynthesisError,
                .invalidCodewordLength(173)
            )
        }
    }
}
