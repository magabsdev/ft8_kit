import Foundation
import XCTest
@testable import FT8Decoder

final class FT8AuditWriterTests: XCTestCase {
    func testWritesAuditFiles() throws {
        let batch = FT8DecodeBatch(
            messages: [],
            metrics: makeMetrics(),
            candidateTraces: [makeTrace()],
            pipelineRecords: [makePipelineRecord()]
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FT8AuditWriter().write(batch: batch, to: directory)

        for name in [
            "summary.json",
            "candidate-traces.json",
            "pipeline-records.json",
            "candidates.csv",
            "symbols.csv",
            "llr.csv",
            "ldpc.csv",
            "pipeline-records.csv"
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(name).path
                )
            )
        }

        try? FileManager.default.removeItem(at: directory)
    }

    func testSummaryIncludesPipelineRecordCount() {
        let batch = FT8DecodeBatch(
            messages: [],
            metrics: makeMetrics(),
            pipelineRecords: [makePipelineRecord()]
        )

        let summary = FT8AuditSummary(
            batch: batch,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(summary.pipelineRecordCount, 1)
        XCTAssertEqual(summary.traceCount, 0)
    }

    func testPipelineCSVExportsStageCountsAndOutcome() {
        let csv = FT8AuditWriter().pipelineCSV([makePipelineRecord()])

        XCTAssertTrue(csv.contains("received_tone_count"))
        XCTAssertTrue(csv.contains(",79,58,174,174,174,174,91,"))
        XCTAssertTrue(csv.contains("\"CQ G0ABC IO91\""))
        XCTAssertTrue(csv.contains(",true\n"))
    }

    private func makeTrace() -> FT8CandidateTrace {
        FT8CandidateTrace(
            pass: 1,
            candidateIndex: 0,
            startTime: 0.5,
            frequency: 1_000,
            driftHzPerSecond: 0,
            syncScore: 0.9,
            snrDB: 4,
            candidateConfidence: 0.8,
            averageSoftSymbolConfidence: 0.7,
            symbols: [
                FT8SymbolTrace(
                    symbolIndex: 0,
                    toneMetrics: [8, 7, 6, 5, 4, 3, 2, 1],
                    confidence: 0.9
                )
            ],
            logLikelihoodRatios: [1, -2],
            ldpcIterations: 3,
            syndromeWeight: 1,
            parityPassed: false,
            crcPassed: false,
            decodedText: nil,
            failure: "crcFailed"
        )
    }

    private func makePipelineRecord() -> FT8PipelineRecord {
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

    private func makeMetrics() -> FT8DecodeMetrics {
        FT8DecodeMetrics(
            candidatesFound: 1,
            candidatesScheduled: 1,
            softSymbolsExtracted: 1,
            ldpcAttempts: 1,
            parityPassed: 1,
            crcPassed: 1,
            messagesReturned: 1,
            elapsedSeconds: 0.1
        )
    }
}
