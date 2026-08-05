import XCTest
@testable import FT8Decoder

final class FT8PipelineMessageOutcomeTests: XCTestCase {
    func testAttachesSuccessfulMessageOutcome() {
        let updated = FT8PipelineRecorder.attachingMessageOutcome(
            decodedText: "CQ G0ABC IO91",
            confidence: 0.92,
            failureReason: nil,
            to: makeRecord()
        )

        XCTAssertEqual(updated.decodedText, "CQ G0ABC IO91")
        XCTAssertEqual(updated.messageConfidence, 0.92)
        XCTAssertNil(updated.failureReason)
        XCTAssertTrue(updated.isStructurallyValid)
    }

    func testAttachesRejectedMessageOutcome() {
        let updated = FT8PipelineRecorder.attachingMessageOutcome(
            decodedText: nil,
            confidence: nil,
            failureReason: "messageDecodeFailed",
            to: makeRecord()
        )

        XCTAssertNil(updated.decodedText)
        XCTAssertNil(updated.messageConfidence)
        XCTAssertEqual(updated.failureReason, "messageDecodeFailed")
    }

    func testNonFiniteMessageConfidenceIsReported() {
        let updated = FT8PipelineRecorder.attachingMessageOutcome(
            decodedText: "CQ TEST",
            confidence: .infinity,
            failureReason: nil,
            to: makeRecord()
        )

        XCTAssertEqual(
            updated.validationIssues,
            [.nonFiniteMessageConfidence]
        )
    }

    private func makeRecord() -> FT8PipelineRecord {
        FT8PipelineRecord(
            candidateIndex: 2,
            startTime: 1.1,
            frequency: 1_000,
            synchronizerScore: 0.9,
            receivedTones: Array(repeating: 0, count: 79),
            dataTones: Array(repeating: 0, count: 58),
            grayMappedBits: Array(repeating: 0, count: 174),
            interleavedBits: Array(repeating: 0, count: 174),
            logLikelihoodRatios: Array(repeating: 1, count: 174),
            decodedCodeword: Array(repeating: 0, count: 174),
            informationBits: Array(repeating: 0, count: 91),
            ldpcIterations: 1,
            parityPassed: true,
            crcPassed: true,
            syndromeWeight: 0
        )
    }
}
