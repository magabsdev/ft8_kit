import XCTest
import FT8Encoder
import FT8Protocol
@testable import FT8Decoder

final class FT8MessageDecoderTests: XCTestCase {
    func testDecodesStandardMessage() throws {
        let expected = FT8Message.standard(
            to: "CQ",
            from: "G0ABC",
            extra: "IO91"
        )
        let result = try makePerfectLDPCResult(expected)
        let decoded = try FT8MessageDecoder().decode(result)

        XCTAssertEqual(decoded.message, expected)
        XCTAssertEqual(decoded.text, "CQ G0ABC IO91")
        XCTAssertEqual(decoded.payload.count, 77)
        XCTAssertEqual(decoded.messageWithCRC.count, 91)
        XCTAssertEqual(decoded.codeword.count, 174)
        XCTAssertEqual(decoded.confidence, 1, accuracy: 0.000_001)
    }

    func testDecodesFreeText() throws {
        let expected = FT8Message.freeText("SIGNAL8 CORE")
        let decoded = try FT8MessageDecoder().decode(
            makePerfectLDPCResult(expected)
        )

        XCTAssertEqual(decoded.message, expected)
        XCTAssertEqual(decoded.text, "SIGNAL8 CORE")
    }

    func testDecodesReportAndAcknowledgements() throws {
        let messages: [FT8Message] = [
            .standard(to: "G0ABC", from: "M0XYZ", extra: "-12"),
            .standard(to: "G0ABC", from: "M0XYZ", extra: "R-07"),
            .standard(to: "G0ABC", from: "M0XYZ", extra: "RRR"),
            .standard(to: "G0ABC", from: "M0XYZ", extra: "RR73"),
            .standard(to: "G0ABC", from: "M0XYZ", extra: "73")
        ]

        for message in messages {
            let decoded = try FT8MessageDecoder().decode(
                makePerfectLDPCResult(message)
            )
            XCTAssertEqual(decoded.message, message)
        }
    }

    func testRejectsParityFailure() throws {
        let good = try makePerfectLDPCResult(.freeText("TEST"))
        let failed = FT8LDPCResult(
            codeword: good.codeword,
            informationBits: good.informationBits,
            iterations: 50,
            parityPassed: false,
            crcPassed: false,
            syndromeWeight: 4
        )

        XCTAssertThrowsError(try FT8MessageDecoder().decode(failed)) {
            XCTAssertEqual(
                $0 as? FT8MessageDecodeError,
                .parityFailed(syndromeWeight: 4)
            )
        }
    }

    func testRejectsCRCFailure() throws {
        let good = try makePerfectLDPCResult(.freeText("TEST"))
        var damaged = good.informationBits
        damaged[10] ^= 1

        let failed = FT8LDPCResult(
            codeword: good.codeword,
            informationBits: damaged,
            iterations: 2,
            parityPassed: true,
            crcPassed: false,
            syndromeWeight: 0
        )

        XCTAssertThrowsError(try FT8MessageDecoder().decode(failed)) {
            XCTAssertEqual($0 as? FT8MessageDecodeError, .crcFailed)
        }
    }

    func testRejectsCRCValidEmptyDecodedMessage() throws {
        let result = try makePerfectLDPCResult(.freeText(""))

        XCTAssertTrue(result.parityPassed)
        XCTAssertTrue(result.crcPassed)

        XCTAssertThrowsError(
            try FT8MessageDecoder().decode(result)
        ) {
            XCTAssertEqual(
                $0 as? FT8MessageDecodeError,
                .emptyDecodedText
            )
        }
    }

    func testSoftConfidenceContributesToResult() throws {
        let result = try makePerfectLDPCResult(.freeText("CONFIDENCE"))
        let soft = FT8SoftSymbols(
            logLikelihoodRatios: Array(repeating: 8, count: 174),
            symbolConfidences: Array(repeating: 0.5, count: 58)
        )
        let decoded = try FT8MessageDecoder().decode(
            result,
            softSymbols: soft
        )

        XCTAssertGreaterThan(decoded.confidence, 0.5)
        XCTAssertLessThan(decoded.confidence, 1)
    }

    private func makePerfectLDPCResult(
        _ message: FT8Message
    ) throws -> FT8LDPCResult {
        let payload = try FT8MessageCodec.pack(message)
        let information = try FT8CRC.append(to: payload)
        let codeword = try FT8Encoder.encodeLDPC(information)
        return FT8LDPCResult(
            codeword: codeword,
            informationBits: information,
            iterations: 0,
            parityPassed: true,
            crcPassed: true,
            syndromeWeight: 0
        )
    }
}
