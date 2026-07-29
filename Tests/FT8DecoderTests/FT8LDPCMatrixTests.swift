import XCTest
import FT8Encoder
import FT8Protocol
@testable import FT8Decoder

final class FT8LDPCMatrixTests: XCTestCase {
    func testDimensions() {
        XCTAssertEqual(FT8LDPCMatrix.checkToVariables.count, 83)
        XCTAssertEqual(FT8LDPCMatrix.variableToChecks.count, 174)
        XCTAssertEqual(FT8LDPCMatrix.informationBitCount, 91)
    }

    func testEveryCheckIncludesItsSystematicParityBit() {
        for check in 0..<83 {
            XCTAssertTrue(
                FT8LDPCMatrix.checkToVariables[check].contains(91 + check)
            )
        }
    }

    func testEncodedCodewordHasZeroSyndrome() throws {
        let message = try FT8CRC.append(
            to: FT8MessageCodec.pack("CQ TEST")
        )
        let codeword = try FT8Encoder.encodeLDPC(message)
        XCTAssertTrue(FT8LDPCMatrix.isValid(codeword))
        XCTAssertEqual(
            FT8LDPCMatrix.syndrome(of: codeword),
            Array(repeating: 0, count: 83)
        )
    }

    func testSingleBitErrorCreatesNonzeroSyndrome() throws {
        let message = try FT8CRC.append(
            to: FT8MessageCodec.pack("CQ TEST")
        )
        var codeword = try FT8Encoder.encodeLDPC(message)
        codeword[17] ^= 1
        XCTAssertFalse(FT8LDPCMatrix.isValid(codeword))
        XCTAssertGreaterThan(
            FT8LDPCMatrix.syndrome(of: codeword).reduce(0) { $0 + Int($1) },
            0
        )
    }

    func testAllVariablesParticipateInChecks() {
        XCTAssertTrue(
            FT8LDPCMatrix.variableToChecks.allSatisfy { !$0.isEmpty }
        )
    }
}
