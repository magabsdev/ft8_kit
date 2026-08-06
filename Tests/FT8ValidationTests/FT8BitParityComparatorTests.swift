import XCTest
import FT8Decoder
import FT8Encoder
import FT8Protocol
@testable import FT8Validation

final class FT8BitParityComparatorTests: XCTestCase {
    func testPerfectCodewordProducesNoMismatches() throws {
        let reference = WSJTXExpectedDecode(
            time: "000000",
            snrDB: -10,
            timeOffset: 1.0,
            frequencyHz: 1_000,
            mode: "FT8",
            message: "CQ G0ABC IO91"
        )
        let payload = try FT8MessageCodec.pack(reference.message)
        let protected = try FT8CRC.append(to: payload)
        let codeword = try FT8Encoder.encodeLDPC(protected).bits

        let record = FT8PipelineRecord(
            candidateIndex: 0,
            startTime: 1.0,
            frequency: 1_000,
            synchronizerScore: 1,
            logLikelihoodRatios: codeword.map {
                $0 == 0 ? 8 : -8
            },
            decodedCodeword: codeword,
            informationBits: Array(codeword.prefix(91)),
            parityPassed: true,
            crcPassed: true,
            syndromeWeight: 0
        )

        let comparison = try RealWAVBitParityComparator.compare(
            record: record,
            reference: reference
        )

        XCTAssertEqual(comparison.totalBits, 174)
        XCTAssertEqual(comparison.correctBits, 174)
        XCTAssertEqual(comparison.incorrectBits, 0)
        XCTAssertNil(comparison.firstMismatch)
        XCTAssertNil(comparison.lastMismatch)
        XCTAssertEqual(comparison.longestMatchingRun, 174)
        XCTAssertEqual(comparison.messageBitErrors, 0)
        XCTAssertEqual(comparison.crcBitErrors, 0)
        XCTAssertEqual(comparison.parityBitErrors, 0)
    }

    func testMismatchCountsAreSplitAcrossProtocolSections() throws {
        let reference = WSJTXExpectedDecode(
            time: "000000",
            snrDB: -10,
            timeOffset: 1.0,
            frequencyHz: 1_000,
            mode: "FT8",
            message: "CQ G0ABC IO91"
        )
        let payload = try FT8MessageCodec.pack(reference.message)
        let protected = try FT8CRC.append(to: payload)
        var codeword = try FT8Encoder.encodeLDPC(protected).bits

        codeword[0] ^= 1
        codeword[77] ^= 1
        codeword[91] ^= 1

        let record = FT8PipelineRecord(
            candidateIndex: 0,
            startTime: 1.0,
            frequency: 1_000,
            synchronizerScore: 1,
            logLikelihoodRatios: [Float](repeating: 2, count: 174),
            decodedCodeword: codeword,
            parityPassed: false,
            crcPassed: false,
            syndromeWeight: 3
        )

        let comparison = try RealWAVBitParityComparator.compare(
            record: record,
            reference: reference
        )

        XCTAssertEqual(comparison.totalBits, 174)
        XCTAssertEqual(
            comparison.correctBits + comparison.incorrectBits,
            174
        )
        XCTAssertEqual(comparison.incorrectBits, 3)
        XCTAssertEqual(comparison.messageBitErrors, 1)
        XCTAssertEqual(comparison.crcBitErrors, 1)
        XCTAssertEqual(comparison.parityBitErrors, 1)
        XCTAssertEqual(comparison.firstMismatch, 0)
        XCTAssertEqual(comparison.lastMismatch, 91)
    }
}

extension FT8BitParityComparatorTests {
    func testWSJTXCountryAnnotationIsRemovedBeforePacking() throws {
        let reference = WSJTXExpectedDecode(
            time: "110130",
            snrDB: -6,
            timeOffset: 0.7,
            frequencyHz: 683,
            mode: "~",
            message: "CQ TA6CQ KN70      AS Turkey"
        )
        let payload = try FT8MessageCodec.pack(
            .standard(to: "CQ", from: "TA6CQ", extra: "KN70")
        )
        let protected = try FT8CRC.append(to: payload)
        let codeword = try FT8Encoder.encodeLDPC(protected).bits
        let record = makeRecord(
            codeword: codeword,
            startTime: 0.7,
            frequency: 683
        )

        let comparison = try RealWAVBitParityComparator.compare(
            record: record,
            reference: reference
        )

        XCTAssertEqual(comparison.referenceMessage, "CQ TA6CQ KN70")
        XCTAssertEqual(comparison.incorrectBits, 0)
    }

    func testDirectedCQReferenceIsPackedAsStandardMessage() throws {
        let reference = WSJTXExpectedDecode(
            time: "110130",
            snrDB: -4,
            timeOffset: 0.9,
            frequencyHz: 2_096,
            mode: "~",
            message: "CQ DX R6WA LN32    EU Russia"
        )
        let payload = try FT8MessageCodec.pack(
            .standard(to: "CQ DX", from: "R6WA", extra: "LN32")
        )
        let protected = try FT8CRC.append(to: payload)
        let codeword = try FT8Encoder.encodeLDPC(protected).bits
        let record = makeRecord(
            codeword: codeword,
            startTime: 0.9,
            frequency: 2_096
        )

        let comparison = try RealWAVBitParityComparator.compare(
            record: record,
            reference: reference
        )

        XCTAssertEqual(comparison.referenceMessage, "CQ DX R6WA LN32")
        XCTAssertEqual(comparison.incorrectBits, 0)
    }

    private func makeRecord(
        codeword: [UInt8],
        startTime: Double,
        frequency: Float
    ) -> FT8PipelineRecord {
        FT8PipelineRecord(
            candidateIndex: 0,
            startTime: startTime,
            frequency: frequency,
            synchronizerScore: 1,
            logLikelihoodRatios: codeword.map {
                $0 == 0 ? 8 : -8
            },
            decodedCodeword: codeword,
            informationBits: Array(codeword.prefix(91)),
            parityPassed: true,
            crcPassed: true,
            syndromeWeight: 0
        )
    }
}
