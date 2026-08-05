import XCTest
@testable import FT8Decoder

final class FT8PipelineValidationReportTests: XCTestCase {
    func testSummarisesStructuralAndConsistencyResults() throws {
        let valid = try makeValidRecord(candidateIndex: 0)
        let structurallyInvalid = FT8PipelineRecord(
            candidateIndex: 1,
            startTime: 1.0,
            frequency: 1_250,
            synchronizerScore: 0.8,
            receivedTones: [0, 1]
        )
        let inconsistent = FT8PipelineRecord(
            candidateIndex: 2,
            startTime: 1.5,
            frequency: 1_500,
            synchronizerScore: 0.7,
            parityPassed: false,
            crcPassed: true,
            decodedText: "CQ TEST",
            messageConfidence: 0.8
        )

        let report = FT8PipelineValidationReport(
            records: [valid, structurallyInvalid, inconsistent]
        )

        XCTAssertEqual(report.totalRecordCount, 3)
        XCTAssertEqual(report.structurallyValidRecordCount, 2)
        XCTAssertEqual(report.consistentRecordCount, 2)
        XCTAssertEqual(report.fullyValidRecordCount, 1)
        XCTAssertEqual(report.invalidRecordCount, 2)
        XCTAssertFalse(report.isValid)
        XCTAssertEqual(report.records.map(\.candidateIndex), [0, 1, 2])
        XCTAssertTrue(report.records[0].isValid)
        XCTAssertFalse(report.records[1].isValid)
        XCTAssertFalse(report.records[2].isValid)
    }

    func testBuildsReportFromDecodeBatch() throws {
        let record = try makeValidRecord(candidateIndex: 4)
        let batch = FT8DecodeBatch(
            messages: [],
            metrics: FT8DecodeMetrics(
                candidatesFound: 1,
                candidatesScheduled: 1,
                softSymbolsExtracted: 1,
                ldpcAttempts: 1,
                parityPassed: 1,
                crcPassed: 1,
                messagesReturned: 1,
                elapsedSeconds: 0.1
            ),
            pipelineRecords: [record]
        )

        let report = FT8PipelineValidationReport(batch: batch)

        XCTAssertEqual(report.totalRecordCount, 1)
        XCTAssertEqual(report.fullyValidRecordCount, 1)
        XCTAssertTrue(report.isValid)
    }

    func testReportRoundTripsThroughJSON() throws {
        let report = FT8PipelineValidationReport(
            records: [try makeValidRecord(candidateIndex: 7)]
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(
            FT8PipelineValidationReport.self,
            from: data
        )

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.records[0].consistencyIssues, [])
    }

    private func makeValidRecord(
        candidateIndex: Int
    ) throws -> FT8PipelineRecord {
        let received = (0..<FT8PipelineRecord.receivedToneCount).map {
            UInt8($0 % 8)
        }
        let data = try FT8PipelineRecorder.extractDataTones(from: received)
        let bits = try FT8PipelineRecorder.mapDataTonesToBits(data)
        let llrs = bits.map { $0 == 0 ? Float(2) : Float(-2) }

        return FT8PipelineRecord(
            candidateIndex: candidateIndex,
            startTime: 0.5,
            frequency: 1_000,
            synchronizerScore: 0.95,
            receivedTones: received,
            dataTones: data,
            grayMappedBits: bits,
            interleavedBits: bits,
            logLikelihoodRatios: llrs,
            decodedCodeword: Array(repeating: 0, count: 174),
            informationBits: Array(repeating: 0, count: 91),
            ldpcIterations: 2,
            parityPassed: true,
            crcPassed: true,
            syndromeWeight: 0,
            decodedText: "CQ G0ABC IO91",
            messageConfidence: 0.95
        )
    }
}
