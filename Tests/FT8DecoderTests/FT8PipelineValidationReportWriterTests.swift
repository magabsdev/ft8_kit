import Foundation
import XCTest
@testable import FT8Decoder

final class FT8PipelineValidationReportWriterTests: XCTestCase {
    func testWritesJSONAndCSVFiles() throws {
        let report = FT8PipelineValidationReport(
            records: [makeValidRecord()]
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FT8PipelineValidationReportWriter().write(
            report: report,
            to: directory
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory
                    .appendingPathComponent("pipeline-validation.json")
                    .path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory
                    .appendingPathComponent("pipeline-validation.csv")
                    .path
            )
        )

        let data = try Data(
            contentsOf: directory
                .appendingPathComponent("pipeline-validation.json")
        )
        let decoded = try JSONDecoder().decode(
            FT8PipelineValidationReport.self,
            from: data
        )
        XCTAssertEqual(decoded, report)

        try? FileManager.default.removeItem(at: directory)
    }

    func testCSVExportsValidAndInvalidRecords() {
        let invalid = FT8PipelineRecord(
            candidateIndex: 1,
            startTime: 0.5,
            frequency: 1_000,
            synchronizerScore: 0.9,
            receivedTones: Array(repeating: 0, count: 79),
            dataTones: Array(repeating: 0, count: 58),
            grayMappedBits: Array(repeating: 0, count: 174),
            interleavedBits: Array(repeating: 1, count: 174),
            logLikelihoodRatios: Array(repeating: 1, count: 174),
            parityPassed: false,
            crcPassed: true,
            failureReason: "crcFailed"
        )
        let report = FT8PipelineValidationReport(
            records: [makeValidRecord(), invalid]
        )

        let csv = FT8PipelineValidationReportWriter().csv(report)

        XCTAssertTrue(csv.contains("candidate_index,structural_issue_count"))
        XCTAssertTrue(csv.contains("0,0,0,true"))
        XCTAssertTrue(csv.contains("1,0,2,false"))
        XCTAssertTrue(csv.contains("interleavedBitsDoNotMatchLLRs"))
        XCTAssertTrue(csv.contains("crcPassedWithoutParity"))
    }

    func testWritesDirectlyFromDecodeBatch() throws {
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
            pipelineRecords: [makeValidRecord()]
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FT8PipelineValidationReportWriter().write(
            batch: batch,
            to: directory
        )

        let data = try Data(
            contentsOf: directory
                .appendingPathComponent("pipeline-validation.json")
        )
        let report = try JSONDecoder().decode(
            FT8PipelineValidationReport.self,
            from: data
        )
        XCTAssertEqual(report.totalRecordCount, 1)
        XCTAssertEqual(report.fullyValidRecordCount, 1)

        try? FileManager.default.removeItem(at: directory)
    }

    private func makeValidRecord() -> FT8PipelineRecord {
        FT8PipelineRecord(
            candidateIndex: 0,
            startTime: 0.5,
            frequency: 1_000,
            synchronizerScore: 0.9,
            receivedTones: Array(repeating: 0, count: 79),
            dataTones: Array(repeating: 0, count: 58),
            grayMappedBits: Array(repeating: 0, count: 174),
            interleavedBits: Array(repeating: 0, count: 174),
            logLikelihoodRatios: Array(repeating: 1, count: 174),
            decodedCodeword: Array(repeating: 0, count: 174),
            informationBits: Array(repeating: 0, count: 91),
            ldpcIterations: 3,
            parityPassed: true,
            crcPassed: true,
            syndromeWeight: 0,
            decodedText: "CQ G0ABC IO91",
            messageConfidence: 0.95
        )
    }
}
