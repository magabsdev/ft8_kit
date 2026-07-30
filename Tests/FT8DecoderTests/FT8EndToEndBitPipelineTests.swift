import XCTest
import FT8Encoder
import FT8Protocol
@testable import FT8Decoder

final class FT8EndToEndBitPipelineTests: XCTestCase {
    func testEncoderThroughLDPCAndMessageDecoder() throws {
        let messages: [FT8Message] = [
            .freeText("SIGNAL8"),
            .standard(to: "CQ", from: "G0ABC", extra: "IO91"),
            .standard(to: "G0ABC", from: "M0XYZ", extra: "-09"),
            .standard(to: "G0ABC", from: "M0XYZ", extra: "RR73")
        ]

        for expected in messages {
            let payload = try FT8MessageCodec.pack(expected)
            let information = try FT8CRC.append(to: payload)
            let codeword = try FT8Encoder.encodeLDPC(information)
            let llrs = codeword.bits.map { $0 == 0 ? Float(12) : Float(-12) }

            let ldpc = try FT8LDPCDecoder().decode(
                logLikelihoodRatios: llrs
            )
            let decoded = try FT8MessageDecoder().decode(ldpc)

            XCTAssertTrue(ldpc.parityPassed)
            XCTAssertTrue(ldpc.crcPassed)
            XCTAssertEqual(decoded.message, expected)
        }
    }

    func testCorrectableErrorsStillUnpackMessage() throws {
        let expected = FT8Message.standard(
            to: "CQ",
            from: "G0ABC",
            extra: "IO91"
        )
        let payload = try FT8MessageCodec.pack(expected)
        let information = try FT8CRC.append(to: payload)
        let codeword = try FT8Encoder.encodeLDPC(information)
        var llrs = codeword.bits.map { $0 == 0 ? Float(10) : Float(-10) }

        for index in [3, 28, 79, 120, 161] {
            llrs[index] = -llrs[index] * 0.2
        }

        let ldpc = try FT8LDPCDecoder().decode(
            logLikelihoodRatios: llrs
        )
        let decoded = try FT8MessageDecoder().decode(ldpc)

        XCTAssertEqual(decoded.message, expected)
        XCTAssertTrue(ldpc.parityPassed)
        XCTAssertTrue(ldpc.crcPassed)
    }
}
