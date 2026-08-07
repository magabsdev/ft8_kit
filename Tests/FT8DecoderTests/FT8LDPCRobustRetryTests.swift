import XCTest
import FT8Encoder
import FT8Protocol
@testable import FT8Decoder

final class FT8LDPCRobustRetryTests: XCTestCase {
    func testRobustRetriesDoNotRegressPerfectCodeword() throws {
        let vector = try makeVector("CQ TEST")

        let result = try FT8LDPCDecoder().decode(
            logLikelihoodRatios:
                llrs(
                    for: vector.codeword,
                    strength: 12
                )
        )

        XCTAssertTrue(result.parityPassed)
        XCTAssertTrue(result.crcPassed)
        XCTAssertEqual(result.iterations, 0)
        XCTAssertEqual(result.codeword, vector.codeword)
    }

    func testRobustResultIsNeverWorseThanPrimarySyndrome() throws {
        let vector = try makeVector("TEST LDPC")

        var values = llrs(
            for: vector.codeword,
            strength: 7
        )

        // Deterministic mixture of weak wrong signs and uncertain bits.
        for index in [3, 19, 31, 54, 77, 92, 114, 137, 151] {
            values[index] *= -0.22
        }

        for index in [8, 46, 101, 163] {
            values[index] *= 0.05
        }

        let primary = try FT8LDPCDecoder(
            configuration: .init(
                maximumIterations: 50,
                enableRobustRetries: false
            )
        ).decode(
            logLikelihoodRatios: values
        )

        let robust = try FT8LDPCDecoder(
            configuration: .init(
                maximumIterations: 50,
                enableRobustRetries: true
            )
        ).decode(
            logLikelihoodRatios: values
        )

        XCTAssertLessThanOrEqual(
            robust.syndromeWeight,
            primary.syndromeWeight
        )

        if primary.crcPassed {
            XCTAssertTrue(robust.crcPassed)
        }
    }

    func testCanDisableRobustRetries() throws {
        let vector = try makeVector("CQ TEST")

        let decoder = FT8LDPCDecoder(
            configuration: .init(
                enableRobustRetries: false
            )
        )

        let result = try decoder.decode(
            logLikelihoodRatios:
                llrs(
                    for: vector.codeword,
                    strength: 10
                )
        )

        XCTAssertTrue(result.crcPassed)
        XCTAssertEqual(result.codeword, vector.codeword)
    }

    private func makeVector(
        _ text: String
    ) throws -> (
        message: FT8BitBuffer,
        codeword: FT8BitBuffer
    ) {
        let message = try FT8CRC.append(
            to: FT8MessageCodec.pack(text)
        )

        return (
            message,
            try FT8Encoder.encodeLDPC(message)
        )
    }

    private func llrs(
        for codeword: FT8BitBuffer,
        strength: Float
    ) -> [Float] {
        codeword.bits.map {
            $0 == 0 ? strength : -strength
        }
    }
}
