import XCTest
import FT8Protocol
@testable import FT8Decoder

final class FT8PipelineLDPCRecordingTests: XCTestCase {
    func testAttachesExactLDPCResultToExistingRecord() {
        let base = FT8PipelineRecord(
            candidateIndex: 7,
            startTime: 1.25,
            frequency: 1_100,
            synchronizerScore: 0.92,
            interleavedBits: Array(repeating: 0, count: 174),
            logLikelihoodRatios: Array(repeating: 4, count: 174)
        )

        let codeword = FT8BitBuffer(
            (0..<174).map { UInt8($0.isMultiple(of: 2) ? 0 : 1) }
        )
        let information = FT8BitBuffer(
            Array(codeword.bits.prefix(91))
        )
        let result = FT8LDPCResult(
            codeword: codeword,
            informationBits: information,
            iterations: 12,
            parityPassed: true,
            crcPassed: true,
            syndromeWeight: 0
        )

        let record = FT8PipelineRecorder.attaching(
            ldpcResult: result,
            to: base
        )

        XCTAssertEqual(record.decodedCodeword, codeword.bits)
        XCTAssertEqual(record.informationBits, information.bits)
        XCTAssertEqual(record.ldpcIterations, 12)
        XCTAssertEqual(record.parityPassed, true)
        XCTAssertEqual(record.crcPassed, true)
        XCTAssertEqual(record.syndromeWeight, 0)
        XCTAssertEqual(record.candidateIndex, base.candidateIndex)
        XCTAssertEqual(record.logLikelihoodRatios, base.logLikelihoodRatios)
        XCTAssertTrue(record.isStructurallyValid)
    }

    func testDecodedCodewordRequiresExactly174Bits() {
        let record = FT8PipelineRecord(
            candidateIndex: 0,
            startTime: 0,
            frequency: 1_000,
            synchronizerScore: 1,
            decodedCodeword: Array(repeating: 0, count: 173)
        )

        XCTAssertEqual(
            record.validationIssues,
            [
                .incorrectCount(
                    stage: .decodedCodeword,
                    expected: 174,
                    actual: 173
                )
            ]
        )
    }

    func testInformationStageRequiresExactly91Bits() {
        let record = FT8PipelineRecord(
            candidateIndex: 0,
            startTime: 0,
            frequency: 1_000,
            synchronizerScore: 1,
            informationBits: Array(repeating: 0, count: 90)
        )

        XCTAssertEqual(
            record.validationIssues,
            [
                .incorrectCount(
                    stage: .informationBits,
                    expected: 91,
                    actual: 90
                )
            ]
        )
    }

    func testInvalidLDPCBitAndDiagnosticValuesAreReported() {
        var codeword = Array(repeating: UInt8.zero, count: 174)
        codeword[20] = 2

        let record = FT8PipelineRecord(
            candidateIndex: 0,
            startTime: 0,
            frequency: 1_000,
            synchronizerScore: 1,
            decodedCodeword: codeword,
            ldpcIterations: -1,
            syndromeWeight: -2
        )

        XCTAssertTrue(
            record.validationIssues.contains(
                .invalidBit(stage: .decodedCodeword, value: 2)
            )
        )
        XCTAssertTrue(
            record.validationIssues.contains(
                .invalidDiagnosticValue(
                    field: .ldpcIterations,
                    value: -1
                )
            )
        )
        XCTAssertTrue(
            record.validationIssues.contains(
                .invalidDiagnosticValue(
                    field: .syndromeWeight,
                    value: -2
                )
            )
        )
    }
}
