import XCTest
import FT8Encoder
import FT8Protocol
@testable import FT8Decoder

final class FT8LDPCDecoderTests: XCTestCase {
    func testPerfectCodewordExitsImmediately() throws {
        let vector = try makeVector("CQ TEST")
        let result = try FT8LDPCDecoder().decode(
            logLikelihoodRatios: llrs(for: vector.codeword, strength: 12)
        )

        XCTAssertEqual(result.iterations, 0)
        XCTAssertTrue(result.parityPassed)
        XCTAssertTrue(result.crcPassed)
        XCTAssertEqual(result.codeword, vector.codeword)
        XCTAssertEqual(result.informationBits, vector.message)
    }

    func testCorrectsSingleInvertedChannelBit() throws {
        let vector = try makeVector("CQ TEST")
        var values = llrs(for: vector.codeword, strength: 10)
        values[42] *= -0.25

        let result = try FT8LDPCDecoder().decode(
            logLikelihoodRatios: values
        )

        XCTAssertTrue(result.parityPassed)
        XCTAssertTrue(result.crcPassed)
        XCTAssertEqual(result.codeword, vector.codeword)
    }

    func testCorrectsSeveralWeakErrors() throws {
        let vector = try makeVector("TEST LDPC")
        var values = llrs(for: vector.codeword, strength: 9)
        for index in [3, 19, 54, 92, 137] {
            values[index] *= -0.18
        }

        let result = try FT8LDPCDecoder(
            configuration: .init(maximumIterations: 80)
        ).decode(logLikelihoodRatios: values)

        XCTAssertTrue(result.parityPassed)
        XCTAssertTrue(result.crcPassed)
        XCTAssertEqual(result.codeword, vector.codeword)
    }

    func testSumProductDecodesSingleWeakError() throws {
        let vector = try makeVector("CQ SUM")
        var values = llrs(for: vector.codeword, strength: 8)
        values[80] = -values[80] * 0.1

        let result = try FT8LDPCDecoder(
            configuration: .init(
                algorithm: .sumProduct,
                maximumIterations: 30
            )
        ).decode(logLikelihoodRatios: values)

        XCTAssertTrue(result.parityPassed)
        XCTAssertEqual(result.codeword, vector.codeword)
    }

    func testInvalidLLRCountThrows() {
        XCTAssertThrowsError(
            try FT8LDPCDecoder().decode(
                logLikelihoodRatios: Array(repeating: 0, count: 173)
            )
        ) {
            XCTAssertEqual(
                $0 as? FT8LDPCError,
                .invalidLLRCount(173)
            )
        }
    }

    func testInvalidConfigurationThrows() {
        let decoder = FT8LDPCDecoder(
            configuration: .init(maximumIterations: 0)
        )
        XCTAssertThrowsError(
            try decoder.decode(
                logLikelihoodRatios: Array(repeating: 1, count: 174)
            )
        ) {
            XCTAssertEqual(
                $0 as? FT8LDPCError,
                .invalidConfiguration
            )
        }
    }

    func testIterationLimitReturnsDiagnosticResult() throws {
        var values = Array(repeating: Float(8), count: 174)
        for index in stride(from: 0, to: 174, by: 3) {
            values[index] = -8
        }
        let result = try FT8LDPCDecoder(
            configuration: .init(maximumIterations: 1)
        ).decode(logLikelihoodRatios: values)

        XCTAssertEqual(result.iterations, 1)
        XCTAssertGreaterThan(result.syndromeWeight, 0)
    }

    private func makeVector(
        _ text: String
    ) throws -> (message: FT8BitBuffer, codeword: FT8BitBuffer) {
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
        codeword.bits.map { $0 == 0 ? strength : -strength }
    }
}
