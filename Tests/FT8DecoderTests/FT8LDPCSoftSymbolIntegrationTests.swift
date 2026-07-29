import XCTest
import FT8Encoder
import FT8Protocol
@testable import FT8Decoder

final class FT8LDPCSoftSymbolIntegrationTests: XCTestCase {
    func testSoftSymbolContainerToLDPCRoundTrip() throws {
        let message = try FT8CRC.append(
            to: FT8MessageCodec.pack("CQ NATIVE")
        )
        let codeword = try FT8Encoder.encodeLDPC(message)
        let llrs = codeword.bits.map {
            $0 == 0 ? Float(14) : Float(-14)
        }
        let soft = FT8SoftSymbols(
            logLikelihoodRatios: llrs,
            symbolConfidences: Array(repeating: 1, count: 58)
        )

        let result = try FT8LDPCDecoder().decode(soft)

        XCTAssertTrue(result.parityPassed)
        XCTAssertTrue(result.crcPassed)
        XCTAssertEqual(result.informationBits, message)
    }

    func testCRCRejectsValidParityCodewordWithInvalidMessageCRC() throws {
        var message = try FT8CRC.append(
            to: FT8MessageCodec.pack("CQ CRC")
        )
        message[80] ^= 1
        let codeword = try FT8Encoder.encodeLDPC(message)
        let llrs = codeword.bits.map {
            $0 == 0 ? Float(12) : Float(-12)
        }

        let result = try FT8LDPCDecoder().decode(
            logLikelihoodRatios: llrs
        )

        XCTAssertTrue(result.parityPassed)
        XCTAssertFalse(result.crcPassed)
    }
}
