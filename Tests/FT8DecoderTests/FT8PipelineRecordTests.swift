import XCTest
@testable import FT8Decoder

final class FT8PipelineRecordTests: XCTestCase {
    func testEmptyIncrementalRecordIsValid() {
        let record = FT8PipelineRecord(
            candidateIndex: 4,
            startTime: 1.2,
            frequency: 1_000,
            synchronizerScore: 0.9
        )

        XCTAssertTrue(record.isStructurallyValid)
        XCTAssertTrue(record.validationIssues.isEmpty)
    }

    func testCompleteRecordIsValid() {
        let record = FT8PipelineRecord(
            candidateIndex: 0,
            startTime: 0.5,
            frequency: 1_250,
            synchronizerScore: 0.95,
            receivedTones: Array(repeating: 7, count: 79),
            dataTones: Array(repeating: 6, count: 58),
            grayMappedBits: Array(repeating: 1, count: 174),
            interleavedBits: Array(repeating: 0, count: 174),
            logLikelihoodRatios: Array(repeating: 2.5, count: 174)
        )

        XCTAssertTrue(record.isStructurallyValid)
    }

    func testIncorrectStageLengthIsReported() {
        let record = FT8PipelineRecord(
            candidateIndex: 0,
            startTime: 0,
            frequency: 1_000,
            synchronizerScore: 1,
            receivedTones: [0, 1, 2]
        )

        XCTAssertEqual(
            record.validationIssues,
            [
                .incorrectCount(
                    stage: .receivedTones,
                    expected: 79,
                    actual: 3
                )
            ]
        )
    }

    func testInvalidToneAndBitAreReported() {
        let record = FT8PipelineRecord(
            candidateIndex: 0,
            startTime: 0,
            frequency: 1_000,
            synchronizerScore: 1,
            receivedTones: Array(repeating: 8, count: 79),
            grayMappedBits: Array(repeating: 2, count: 174)
        )

        XCTAssertTrue(
            record.validationIssues.contains(
                .invalidTone(stage: .receivedTones, value: 8)
            )
        )
        XCTAssertTrue(
            record.validationIssues.contains(
                .invalidBit(stage: .grayMappedBits, value: 2)
            )
        )
    }

    func testNonFiniteLLRIsReported() {
        var values = Array(repeating: Float.zero, count: 174)
        values[10] = .infinity

        let record = FT8PipelineRecord(
            candidateIndex: 0,
            startTime: 0,
            frequency: 1_000,
            synchronizerScore: 1,
            logLikelihoodRatios: values
        )

        XCTAssertEqual(record.validationIssues, [.nonFiniteLLR])
    }
}
