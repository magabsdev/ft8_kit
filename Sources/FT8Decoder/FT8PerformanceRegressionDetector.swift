import Foundation

public struct FT8PerformanceRegressionThresholds:
    Codable,
    Equatable,
    Sendable
{
    public var maximumElapsedTimeIncreaseRate: Double
    public var minimumCandidateThroughputRetentionRate: Double
    public var minimumScheduledThroughputRetentionRate: Double
    public var minimumMessageYieldRetentionRate: Double
    public var minimumTimingCoverageRate: Double
    public var maximumStageTimeIncreaseRate: Double

    public init(
        maximumElapsedTimeIncreaseRate: Double = 0.15,
        minimumCandidateThroughputRetentionRate: Double = 0.85,
        minimumScheduledThroughputRetentionRate: Double = 0.85,
        minimumMessageYieldRetentionRate: Double = 0.90,
        minimumTimingCoverageRate: Double = 0.80,
        maximumStageTimeIncreaseRate: Double = 0.25
    ) {
        self.maximumElapsedTimeIncreaseRate =
            Self.nonNegative(maximumElapsedTimeIncreaseRate)
        self.minimumCandidateThroughputRetentionRate =
            Self.bounded(minimumCandidateThroughputRetentionRate)
        self.minimumScheduledThroughputRetentionRate =
            Self.bounded(minimumScheduledThroughputRetentionRate)
        self.minimumMessageYieldRetentionRate =
            Self.bounded(minimumMessageYieldRetentionRate)
        self.minimumTimingCoverageRate =
            Self.bounded(minimumTimingCoverageRate)
        self.maximumStageTimeIncreaseRate =
            Self.nonNegative(maximumStageTimeIncreaseRate)
    }

    private static func bounded(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    private static func nonNegative(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }
}

public enum FT8PerformanceRegressionMetric:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case elapsedSeconds
    case candidatesPerSecond
    case scheduledCandidatesPerSecond
    case messageYieldRate
    case timingCoverageRate
    case stageSeconds
}

public struct FT8PerformanceRegression:
    Codable,
    Equatable,
    Sendable
{
    public let metric: FT8PerformanceRegressionMetric
    public let stage: FT8DecodeStage?
    public let baselineValue: Double
    public let currentValue: Double
    public let allowedValue: Double

    public init(
        metric: FT8PerformanceRegressionMetric,
        stage: FT8DecodeStage? = nil,
        baselineValue: Double,
        currentValue: Double,
        allowedValue: Double
    ) {
        self.metric = metric
        self.stage = stage
        self.baselineValue = baselineValue
        self.currentValue = currentValue
        self.allowedValue = allowedValue
    }
}

public struct FT8PerformanceComparisonReport:
    Codable,
    Equatable,
    Sendable
{
    public let generatedAt: Date
    public let baselineGeneratedAt: Date
    public let currentGeneratedAt: Date
    public let regressions: [FT8PerformanceRegression]

    public init(
        generatedAt: Date = Date(),
        baselineGeneratedAt: Date,
        currentGeneratedAt: Date,
        regressions: [FT8PerformanceRegression]
    ) {
        self.generatedAt = generatedAt
        self.baselineGeneratedAt = baselineGeneratedAt
        self.currentGeneratedAt = currentGeneratedAt
        self.regressions = regressions
    }

    public var passed: Bool {
        regressions.isEmpty
    }
}

public struct FT8PerformanceRegressionDetector: Sendable {
    public let thresholds: FT8PerformanceRegressionThresholds

    public init(
        thresholds: FT8PerformanceRegressionThresholds = .init()
    ) {
        self.thresholds = thresholds
    }

    public func compare(
        baseline: FT8DecodePerformanceSnapshot,
        current: FT8DecodePerformanceSnapshot,
        generatedAt: Date = Date()
    ) -> FT8PerformanceComparisonReport {
        var regressions: [FT8PerformanceRegression] = []

        appendMaximumRegression(
            metric: .elapsedSeconds,
            baseline: baseline.elapsedSeconds,
            current: current.elapsedSeconds,
            maximumIncreaseRate:
                thresholds.maximumElapsedTimeIncreaseRate,
            to: &regressions
        )

        appendMinimumRetentionRegression(
            metric: .candidatesPerSecond,
            baseline: baseline.candidatesPerSecond,
            current: current.candidatesPerSecond,
            minimumRetentionRate:
                thresholds.minimumCandidateThroughputRetentionRate,
            to: &regressions
        )

        appendMinimumRetentionRegression(
            metric: .scheduledCandidatesPerSecond,
            baseline: baseline.scheduledCandidatesPerSecond,
            current: current.scheduledCandidatesPerSecond,
            minimumRetentionRate:
                thresholds.minimumScheduledThroughputRetentionRate,
            to: &regressions
        )

        appendMinimumRetentionRegression(
            metric: .messageYieldRate,
            baseline: baseline.messageYieldRate,
            current: current.messageYieldRate,
            minimumRetentionRate:
                thresholds.minimumMessageYieldRetentionRate,
            to: &regressions
        )

        if current.timingCoverageRate
            < thresholds.minimumTimingCoverageRate
        {
            regressions.append(
                FT8PerformanceRegression(
                    metric: .timingCoverageRate,
                    baselineValue: baseline.timingCoverageRate,
                    currentValue: current.timingCoverageRate,
                    allowedValue: thresholds.minimumTimingCoverageRate
                )
            )
        }

        if let baselineTimings = baseline.stageTimings,
           let currentTimings = current.stageTimings {
            for stage in FT8DecodeStage.allCases {
                appendMaximumRegression(
                    metric: .stageSeconds,
                    stage: stage,
                    baseline: baselineTimings.seconds(for: stage),
                    current: currentTimings.seconds(for: stage),
                    maximumIncreaseRate:
                        thresholds.maximumStageTimeIncreaseRate,
                    to: &regressions
                )
            }
        }

        return FT8PerformanceComparisonReport(
            generatedAt: generatedAt,
            baselineGeneratedAt: baseline.generatedAt,
            currentGeneratedAt: current.generatedAt,
            regressions: regressions
        )
    }

    private func appendMaximumRegression(
        metric: FT8PerformanceRegressionMetric,
        stage: FT8DecodeStage? = nil,
        baseline: Double,
        current: Double,
        maximumIncreaseRate: Double,
        to regressions: inout [FT8PerformanceRegression]
    ) {
        guard baseline.isFinite,
              current.isFinite,
              baseline > 0 else {
            return
        }

        let maximum = baseline * (1 + maximumIncreaseRate)
        guard current > maximum else { return }

        regressions.append(
            FT8PerformanceRegression(
                metric: metric,
                stage: stage,
                baselineValue: baseline,
                currentValue: current,
                allowedValue: maximum
            )
        )
    }

    private func appendMinimumRetentionRegression(
        metric: FT8PerformanceRegressionMetric,
        baseline: Double,
        current: Double,
        minimumRetentionRate: Double,
        to regressions: inout [FT8PerformanceRegression]
    ) {
        guard baseline.isFinite,
              current.isFinite,
              baseline > 0 else {
            return
        }

        let minimum = baseline * minimumRetentionRate
        guard current < minimum else { return }

        regressions.append(
            FT8PerformanceRegression(
                metric: metric,
                baselineValue: baseline,
                currentValue: current,
                allowedValue: minimum
            )
        )
    }
}

public struct FT8PerformanceComparisonWriter: Sendable {
    public init() {}

    public func write(
        report: FT8PerformanceComparisonReport,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try encoder.encode(report).write(
            to: directory.appendingPathComponent(
                "decode-performance-comparison.json"
            ),
            options: .atomic
        )

        try csv(report).write(
            to: directory.appendingPathComponent(
                "decode-performance-comparison.csv"
            ),
            atomically: true,
            encoding: .utf8
        )
    }

    public func csv(
        _ report: FT8PerformanceComparisonReport
    ) -> String {
        let header = [
            "passed",
            "metric",
            "stage",
            "baseline_value",
            "current_value",
            "allowed_value"
        ].joined(separator: ",")

        guard !report.regressions.isEmpty else {
            return header + "\ntrue,,,,,\n"
        }

        let rows = report.regressions.map { regression in
            [
                "false",
                regression.metric.rawValue,
                regression.stage?.rawValue ?? "",
                String(regression.baselineValue),
                String(regression.currentValue),
                String(regression.allowedValue)
            ].joined(separator: ",")
        }

        return header + "\n" + rows.joined(separator: "\n") + "\n"
    }
}
