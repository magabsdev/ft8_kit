import XCTest
@testable import FT8Decoder

final class FT8PipelineConsistencyValidatorTests: XCTestCase {
    private let validator = FT8PipelineConsistencyValidator()

    func testAcceptsConsistentSuccessfulRecord() throws {
        let received = makeReceivedTones()
        let data = try FT8PipelineRecorder.extractDataTones(from: received)
        let grayBits = try FT8PipelineRecorder.mapDataTonesToBits(data)
        let llrs = grayBits.map { $0 == 0 ? Float(2) : Float(-2) }

        let record = FT8PipelineRecord(
            candidateIndex: 0,
            startTime: 0.5,
            frequency: 1_000,
            synchronizerScore: 0.95,
            receivedTones: received,
            dataTones: data,
            grayMappedBits: grayBits,
            interleavedBits: grayBits,
            logLikelihoodRatios: llrs,
            decodedCodeword: Array(repeating: 0, count: 174),
            informationBits: Array(repeating: 0, count: 91),
            ldpcIterations: 3,
            parityPassed: true,
            crcPassed: true,
            syndromeWeight: 0,
            decodedText: "CQ G0ABC IO91",
            messageConfidence: 0.95
        )

        XCTAssertTrue(validator.isConsistent(record))
        XCTAssertEqual(validator.issues(in: record), [])
    }

    func testDetectsContradictoryToneAndSoftDecisionStages() throws {
        let received = makeReceivedTones()
        let data = try FT8PipelineRecorder.extractDataTones(from: received)
        let grayBits = try FT8PipelineRecorder.mapDataTonesToBits(data)
        let llrs = grayBits.map { $0 == 0 ? Float(2) : Float(-2) }

        var incorrectData = data
        incorrectData[0] = (incorrectData[0] + 1) % 8

        var incorrectInterleaved = grayBits
        incorrectInterleaved[0] = incorrectInterleaved[0] == 0 ? 1 : 0

        let record = FT8PipelineRecord(
            candidateIndex: 1,
            startTime: 1.0,
            frequency: 1_250,
            synchronizerScore: 0.8,
            receivedTones: received,
            dataTones: incorrectData,
            grayMappedBits: grayBits,
            interleavedBits: incorrectInterleaved,
            logLikelihoodRatios: llrs
        )

        let issues = validator.issues(in: record)

        XCTAssertTrue(issues.contains(.dataTonesDoNotMatchReceivedTones))
        XCTAssertTrue(issues.contains(.grayMappedBitsDoNotMatchDataTones))
        XCTAssertTrue(issues.contains(.interleavedBitsDoNotMatchLLRs))
    }

    func testDetectsInvalidMessageOutcome() {
        let record = FT8PipelineRecord(
            candidateIndex: 2,
            startTime: 1.5,
            frequency: 1_500,
            synchronizerScore: 0.7,
            parityPassed: false,
            crcPassed: true,
            decodedText: "CQ TEST",
            failureReason: "crcFailed"
        )

        let issues = validator.issues(in: record)

        XCTAssertTrue(issues.contains(.crcPassedWithoutParity))
        XCTAssertTrue(issues.contains(.decodedMessageHasFailureReason))
        XCTAssertTrue(issues.contains(.decodedMessageMissingConfidence))
    }

    func testDetectsRejectedMessageWithoutFailureReason() {
        let record = FT8PipelineRecord(
            candidateIndex: 3,
            startTime: 2.0,
            frequency: 1_750,
            synchronizerScore: 0.6,
            parityPassed: false,
            crcPassed: false
        )

        XCTAssertEqual(
            validator.issues(in: record),
            [.rejectedMessageMissingFailureReason]
        )
    }

    private func makeReceivedTones() -> [UInt8] {
        (0..<FT8PipelineRecord.receivedToneCount).map {
            UInt8($0 % 8)
        }
    }
}
