import Foundation
import XCTest
@testable import FT8Decoder

final class FT8DecodePerformanceSnapshotTests: XCTestCase {
    func testCalculatesThroughputAndRatios() {
        let snapshot = FT8DecodePerformanceSnapshot(
            batch: makeBatch(),
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(snapshot.candidatesPerSecond, 10)
        XCTAssertEqual(snapshot.scheduledCandidatesPerSecond, 5)
        XCTAssertEqual(
            snapshot.averageSecondsPerScheduledCandidate,
            0.2
        )
        XCTAssertEqual(snapshot.softExtractionRate, 0.8)
        XCTAssertEqual(snapshot.parityPassRate, 0.75)
        XCTAssertEqual(snapshot.crcPassRate, 0.5)
        XCTAssertEqual(snapshot.messageYieldRate, 0.2)
    }

    func testIncludesCapturedStageTimingSummary() {
        let timings = FT8DecodeStageTimings(
            synchronizerSeconds: 0.2,
            schedulingSeconds: 0.05,
            softSymbolExtractionSeconds: 0.3,
            pipelineCaptureSeconds: 0.05,
            ldpcSeconds: 0.2,
            messageDecodeSeconds: 0.05,
            nearbyRetrySeconds: 0.05,
            deduplicationSeconds: 0.05
        )
        let snapshot = FT8DecodePerformanceSnapshot(
            batch: makeBatch(
                elapsedSeconds: 1,
                stageTimings: timings
            )
        )

        XCTAssertEqual(snapshot.stageTimings, timings)
        XCTAssertEqual(
            snapshot.measuredStageSeconds,
            0.95,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            snapshot.unmeasuredSeconds,
            0.05,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            snapshot.timingCoverageRate,
            0.95,
            accuracy: 0.000_001
        )
        XCTAssertEqual(snapshot.slowestStage, .softSymbolExtraction)
        XCTAssertEqual(
            snapshot.slowestStageSeconds,
            0.3,
            accuracy: 0.000_001
        )
    }

    func testMissingStageTimingsProduceZeroSummary() {
        let snapshot = FT8DecodePerformanceSnapshot(
            batch: makeBatch()
        )

        XCTAssertNil(snapshot.stageTimings)
        XCTAssertEqual(snapshot.measuredStageSeconds, 0)
        XCTAssertEqual(snapshot.unmeasuredSeconds, 1)
        XCTAssertEqual(snapshot.timingCoverageRate, 0)
        XCTAssertNil(snapshot.slowestStage)
        XCTAssertEqual(snapshot.slowestStageSeconds, 0)
    }

    func testTimingCoverageIsClampedAndUnmeasuredTimeNeverNegative() {
        let timings = FT8DecodeStageTimings(
            synchronizerSeconds: 0.75,
            ldpcSeconds: 0.75
        )
        let snapshot = FT8DecodePerformanceSnapshot(
            batch: makeBatch(
                elapsedSeconds: 1,
                stageTimings: timings
            )
        )

        XCTAssertEqual(snapshot.measuredStageSeconds, 1.5)
        XCTAssertEqual(snapshot.unmeasuredSeconds, 0)
        XCTAssertEqual(snapshot.timingCoverageRate, 1)
    }

    func testZeroDenominatorsProduceFiniteZeroValues() {
        let batch = FT8DecodeBatch(
            messages: [],
            metrics: FT8DecodeMetrics(
                candidatesFound: 0,
                candidatesScheduled: 0,
                softSymbolsExtracted: 0,
                ldpcAttempts: 0,
                parityPassed: 0,
                crcPassed: 0,
                messagesReturned: 0,
                elapsedSeconds: 0
            )
        )

        let snapshot = FT8DecodePerformanceSnapshot(batch: batch)

        XCTAssertEqual(snapshot.candidatesPerSecond, 0)
        XCTAssertEqual(snapshot.averageSecondsPerScheduledCandidate, 0)
        XCTAssertEqual(snapshot.softExtractionRate, 0)
        XCTAssertEqual(snapshot.parityPassRate, 0)
        XCTAssertEqual(snapshot.crcPassRate, 0)
        XCTAssertEqual(snapshot.messageYieldRate, 0)
        XCTAssertEqual(snapshot.timingCoverageRate, 0)
        XCTAssertEqual(snapshot.unmeasuredSeconds, 0)
    }

    func testRoundTripsThroughJSON() throws {
        let original = FT8DecodePerformanceSnapshot(
            batch: makeBatch(
                stageTimings: FT8DecodeStageTimings(
                    synchronizerSeconds: 0.2,
                    ldpcSeconds: 0.3
                )
            ),
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            FT8DecodePerformanceSnapshot.self,
            from: data
        )

        XCTAssertEqual(decoded, original)
    }

    func testWriterCreatesJSONAndCSV() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FT8DecodePerformanceWriter().write(
            batch: makeBatch(
                stageTimings: FT8DecodeStageTimings(
                    synchronizerSeconds: 0.2,
                    ldpcSeconds: 0.3
                )
            ),
            to: directory,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory
                    .appendingPathComponent("decode-performance.json")
                    .path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory
                    .appendingPathComponent("decode-performance.csv")
                    .path
            )
        )

        let csv = try String(
            contentsOf: directory.appendingPathComponent(
                "decode-performance.csv"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(csv.contains("candidates_per_second"))
        XCTAssertTrue(csv.contains("timing_coverage_rate"))
        XCTAssertTrue(csv.contains("slowest_stage"))
        XCTAssertTrue(csv.contains("10,5,4,4,3,2,1,1.0"))
        XCTAssertTrue(csv.contains(",0.5,0.5,0.5,ldpc,0.3"))

        try? FileManager.default.removeItem(at: directory)
    }

    private func makeBatch(
        elapsedSeconds: Double = 1,
        stageTimings: FT8DecodeStageTimings? = nil
    ) -> FT8DecodeBatch {
        FT8DecodeBatch(
            messages: [],
            metrics: FT8DecodeMetrics(
                candidatesFound: 10,
                candidatesScheduled: 5,
                softSymbolsExtracted: 4,
                ldpcAttempts: 4,
                parityPassed: 3,
                crcPassed: 2,
                messagesReturned: 1,
                elapsedSeconds: elapsedSeconds
            ),
            stageTimings: stageTimings
        )
    }
}
