import Foundation
import XCTest
@testable import FT8Decoder

final class FT8PerformanceRegressionDetectorTests: XCTestCase {
    func testAcceptsSnapshotInsideThresholds() {
        let baseline = makeSnapshot(
            elapsedSeconds: 1,
            stageTimings: makeTimings(multiplier: 1)
        )
        let current = makeSnapshot(
            elapsedSeconds: 1.10,
            stageTimings: makeTimings(multiplier: 1.10)
        )

        let report = FT8PerformanceRegressionDetector().compare(
            baseline: baseline,
            current: current,
            generatedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertTrue(report.passed)
        XCTAssertTrue(report.regressions.isEmpty)
        XCTAssertEqual(
            report.generatedAt,
            Date(timeIntervalSince1970: 10)
        )
    }

    func testDetectsRuntimeAndThroughputRegression() {
        let baseline = makeSnapshot(elapsedSeconds: 1)
        let current = makeSnapshot(elapsedSeconds: 1.30)

        let report = FT8PerformanceRegressionDetector().compare(
            baseline: baseline,
            current: current
        )

        XCTAssertFalse(report.passed)
        XCTAssertTrue(
            report.regressions.contains {
                $0.metric == .elapsedSeconds
            }
        )
        XCTAssertTrue(
            report.regressions.contains {
                $0.metric == .candidatesPerSecond
            }
        )
        XCTAssertTrue(
            report.regressions.contains {
                $0.metric == .scheduledCandidatesPerSecond
            }
        )
    }

    func testDetectsMessageYieldAndTimingCoverageRegression() {
        let baseline = makeSnapshot(
            elapsedSeconds: 1,
            messagesReturned: 5,
            stageTimings: FT8DecodeStageTimings(
                synchronizerSeconds: 0.4,
                ldpcSeconds: 0.5
            )
        )
        let current = makeSnapshot(
            elapsedSeconds: 1,
            messagesReturned: 2,
            stageTimings: FT8DecodeStageTimings(
                synchronizerSeconds: 0.2,
                ldpcSeconds: 0.3
            )
        )

        let report = FT8PerformanceRegressionDetector().compare(
            baseline: baseline,
            current: current
        )

        XCTAssertTrue(
            report.regressions.contains {
                $0.metric == .messageYieldRate
            }
        )
        XCTAssertTrue(
            report.regressions.contains {
                $0.metric == .timingCoverageRate
            }
        )
    }

    func testDetectsPerStageRegression() {
        let baseline = makeSnapshot(
            elapsedSeconds: 1,
            stageTimings: makeTimings(multiplier: 1)
        )
        var currentTimings = makeTimings(multiplier: 1)
        currentTimings.ldpcSeconds = 0.40

        let current = makeSnapshot(
            elapsedSeconds: 1,
            stageTimings: currentTimings
        )

        let report = FT8PerformanceRegressionDetector().compare(
            baseline: baseline,
            current: current
        )

        let regression = report.regressions.first {
            $0.metric == .stageSeconds && $0.stage == .ldpc
        }

        XCTAssertNotNil(regression)
        XCTAssertEqual(
            regression?.allowedValue ?? 0,
            0.25,
            accuracy: 0.000_001
        )
    }

    func testZeroBaselineValuesDoNotCreateFalseRegressions() {
        let baseline = makeSnapshot(
            elapsedSeconds: 0,
            candidatesFound: 0,
            candidatesScheduled: 0,
            messagesReturned: 0
        )
        let current = makeSnapshot(
            elapsedSeconds: 0,
            candidatesFound: 0,
            candidatesScheduled: 0,
            messagesReturned: 0
        )

        let report = FT8PerformanceRegressionDetector(
            thresholds: .init(minimumTimingCoverageRate: 0)
        ).compare(
            baseline: baseline,
            current: current
        )

        XCTAssertTrue(report.passed)
    }

    func testThresholdsClampInvalidValues() {
        let thresholds = FT8PerformanceRegressionThresholds(
            maximumElapsedTimeIncreaseRate: -1,
            minimumCandidateThroughputRetentionRate: 2,
            minimumScheduledThroughputRetentionRate: -.infinity,
            minimumMessageYieldRetentionRate: .nan,
            minimumTimingCoverageRate: -2,
            maximumStageTimeIncreaseRate: -.infinity
        )

        XCTAssertEqual(thresholds.maximumElapsedTimeIncreaseRate, 0)
        XCTAssertEqual(
            thresholds.minimumCandidateThroughputRetentionRate,
            1
        )
        XCTAssertEqual(
            thresholds.minimumScheduledThroughputRetentionRate,
            0
        )
        XCTAssertEqual(thresholds.minimumMessageYieldRetentionRate, 0)
        XCTAssertEqual(thresholds.minimumTimingCoverageRate, 0)
        XCTAssertEqual(thresholds.maximumStageTimeIncreaseRate, 0)
    }

    func testReportRoundTripsThroughJSON() throws {
        let report = FT8PerformanceRegressionDetector().compare(
            baseline: makeSnapshot(elapsedSeconds: 1),
            current: makeSnapshot(elapsedSeconds: 2),
            generatedAt: Date(timeIntervalSince1970: 10)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            FT8PerformanceComparisonReport.self,
            from: data
        )

        XCTAssertEqual(decoded, report)
    }

    func testWriterCreatesJSONAndCSV() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let report = FT8PerformanceRegressionDetector().compare(
            baseline: makeSnapshot(elapsedSeconds: 1),
            current: makeSnapshot(elapsedSeconds: 2)
        )

        try FT8PerformanceComparisonWriter().write(
            report: report,
            to: directory
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(
                    "decode-performance-comparison.json"
                ).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(
                    "decode-performance-comparison.csv"
                ).path
            )
        )

        let csv = try String(
            contentsOf: directory.appendingPathComponent(
                "decode-performance-comparison.csv"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(csv.contains("passed,metric,stage"))
        XCTAssertTrue(csv.contains("elapsedSeconds"))

        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSnapshot(
        elapsedSeconds: Double,
        candidatesFound: Int = 10,
        candidatesScheduled: Int = 5,
        messagesReturned: Int = 1,
        stageTimings: FT8DecodeStageTimings? = nil
    ) -> FT8DecodePerformanceSnapshot {
        FT8DecodePerformanceSnapshot(
            batch: FT8DecodeBatch(
                messages: [],
                metrics: FT8DecodeMetrics(
                    candidatesFound: candidatesFound,
                    candidatesScheduled: candidatesScheduled,
                    softSymbolsExtracted: candidatesScheduled,
                    ldpcAttempts: candidatesScheduled,
                    parityPassed: candidatesScheduled,
                    crcPassed: candidatesScheduled,
                    messagesReturned: messagesReturned,
                    elapsedSeconds: elapsedSeconds
                ),
                stageTimings: stageTimings
            ),
            generatedAt: Date(timeIntervalSince1970: elapsedSeconds)
        )
    }

    private func makeTimings(
        multiplier: Double
    ) -> FT8DecodeStageTimings {
        FT8DecodeStageTimings(
            synchronizerSeconds: 0.20 * multiplier,
            schedulingSeconds: 0.05 * multiplier,
            softSymbolExtractionSeconds: 0.15 * multiplier,
            pipelineCaptureSeconds: 0.05 * multiplier,
            ldpcSeconds: 0.20 * multiplier,
            messageDecodeSeconds: 0.05 * multiplier,
            nearbyRetrySeconds: 0.05 * multiplier,
            deduplicationSeconds: 0.05 * multiplier
        )
    }
}
