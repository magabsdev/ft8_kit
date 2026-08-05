import Foundation

public struct FT8DecodePerformanceSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let candidatesFound: Int
    public let candidatesScheduled: Int
    public let softSymbolsExtracted: Int
    public let ldpcAttempts: Int
    public let parityPassed: Int
    public let crcPassed: Int
    public let messagesReturned: Int
    public let elapsedSeconds: Double
    public let candidatesPerSecond: Double
    public let scheduledCandidatesPerSecond: Double
    public let averageSecondsPerScheduledCandidate: Double
    public let softExtractionRate: Double
    public let parityPassRate: Double
    public let crcPassRate: Double
    public let messageYieldRate: Double

    public let stageTimings: FT8DecodeStageTimings?
    public let measuredStageSeconds: Double
    public let unmeasuredSeconds: Double
    public let timingCoverageRate: Double
    public let slowestStage: FT8DecodeStage?
    public let slowestStageSeconds: Double

    public init(
        batch: FT8DecodeBatch,
        generatedAt: Date = Date()
    ) {
        let metrics = batch.metrics
        let timings = batch.stageTimings
        let measuredSeconds = timings?.measuredSeconds ?? 0
        let elapsedSeconds = max(0, metrics.elapsedSeconds)

        self.generatedAt = generatedAt
        candidatesFound = metrics.candidatesFound
        candidatesScheduled = metrics.candidatesScheduled
        softSymbolsExtracted = metrics.softSymbolsExtracted
        ldpcAttempts = metrics.ldpcAttempts
        parityPassed = metrics.parityPassed
        crcPassed = metrics.crcPassed
        messagesReturned = metrics.messagesReturned
        self.elapsedSeconds = elapsedSeconds

        candidatesPerSecond = Self.rate(
            numerator: metrics.candidatesFound,
            denominator: elapsedSeconds
        )
        scheduledCandidatesPerSecond = Self.rate(
            numerator: metrics.candidatesScheduled,
            denominator: elapsedSeconds
        )
        averageSecondsPerScheduledCandidate =
            metrics.candidatesScheduled > 0
            ? elapsedSeconds / Double(metrics.candidatesScheduled)
            : 0
        softExtractionRate = Self.ratio(
            numerator: metrics.softSymbolsExtracted,
            denominator: metrics.candidatesScheduled
        )
        parityPassRate = Self.ratio(
            numerator: metrics.parityPassed,
            denominator: metrics.ldpcAttempts
        )
        crcPassRate = Self.ratio(
            numerator: metrics.crcPassed,
            denominator: metrics.ldpcAttempts
        )
        messageYieldRate = Self.ratio(
            numerator: metrics.messagesReturned,
            denominator: metrics.candidatesScheduled
        )

        stageTimings = timings
        measuredStageSeconds = measuredSeconds
        unmeasuredSeconds = max(0, elapsedSeconds - measuredSeconds)
        timingCoverageRate = Self.boundedRatio(
            numerator: measuredSeconds,
            denominator: elapsedSeconds
        )
        slowestStage = timings?.slowestStage
        slowestStageSeconds = timings
            .flatMap { timings in
                timings.slowestStage.map {
                    timings.seconds(for: $0)
                }
            }
            ?? 0
    }

    private static func ratio(
        numerator: Int,
        denominator: Int
    ) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }

    private static func rate(
        numerator: Int,
        denominator: Double
    ) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / denominator
    }

    private static func boundedRatio(
        numerator: Double,
        denominator: Double
    ) -> Double {
        guard numerator.isFinite,
              denominator.isFinite,
              numerator >= 0,
              denominator > 0 else {
            return 0
        }

        return min(1, numerator / denominator)
    }
}

public struct FT8DecodePerformanceWriter: Sendable {
    public init() {}

    public func write(
        batch: FT8DecodeBatch,
        to directory: URL,
        generatedAt: Date = Date()
    ) throws {
        try write(
            snapshot: FT8DecodePerformanceSnapshot(
                batch: batch,
                generatedAt: generatedAt
            ),
            to: directory
        )
    }

    public func write(
        snapshot: FT8DecodePerformanceSnapshot,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try encoder.encode(snapshot).write(
            to: directory.appendingPathComponent(
                "decode-performance.json"
            ),
            options: .atomic
        )

        try csv(snapshot).write(
            to: directory.appendingPathComponent(
                "decode-performance.csv"
            ),
            atomically: true,
            encoding: .utf8
        )
    }

    public func csv(
        _ snapshot: FT8DecodePerformanceSnapshot
    ) -> String {
        let header = [
            "candidates_found",
            "candidates_scheduled",
            "soft_symbols_extracted",
            "ldpc_attempts",
            "parity_passed",
            "crc_passed",
            "messages_returned",
            "elapsed_seconds",
            "candidates_per_second",
            "scheduled_candidates_per_second",
            "average_seconds_per_scheduled_candidate",
            "soft_extraction_rate",
            "parity_pass_rate",
            "crc_pass_rate",
            "message_yield_rate",
            "measured_stage_seconds",
            "unmeasured_seconds",
            "timing_coverage_rate",
            "slowest_stage",
            "slowest_stage_seconds"
        ].joined(separator: ",")

        let row = [
            String(snapshot.candidatesFound),
            String(snapshot.candidatesScheduled),
            String(snapshot.softSymbolsExtracted),
            String(snapshot.ldpcAttempts),
            String(snapshot.parityPassed),
            String(snapshot.crcPassed),
            String(snapshot.messagesReturned),
            String(snapshot.elapsedSeconds),
            String(snapshot.candidatesPerSecond),
            String(snapshot.scheduledCandidatesPerSecond),
            String(snapshot.averageSecondsPerScheduledCandidate),
            String(snapshot.softExtractionRate),
            String(snapshot.parityPassRate),
            String(snapshot.crcPassRate),
            String(snapshot.messageYieldRate),
            String(snapshot.measuredStageSeconds),
            String(snapshot.unmeasuredSeconds),
            String(snapshot.timingCoverageRate),
            snapshot.slowestStage?.rawValue ?? "",
            String(snapshot.slowestStageSeconds)
        ].joined(separator: ",")

        return header + "\n" + row + "\n"
    }
}
