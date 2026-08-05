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

    public init(
        batch: FT8DecodeBatch,
        generatedAt: Date = Date()
    ) {
        let metrics = batch.metrics

        self.generatedAt = generatedAt
        candidatesFound = metrics.candidatesFound
        candidatesScheduled = metrics.candidatesScheduled
        softSymbolsExtracted = metrics.softSymbolsExtracted
        ldpcAttempts = metrics.ldpcAttempts
        parityPassed = metrics.parityPassed
        crcPassed = metrics.crcPassed
        messagesReturned = metrics.messagesReturned
        elapsedSeconds = metrics.elapsedSeconds

        candidatesPerSecond = Self.rate(
            numerator: metrics.candidatesFound,
            denominator: metrics.elapsedSeconds
        )
        scheduledCandidatesPerSecond = Self.rate(
            numerator: metrics.candidatesScheduled,
            denominator: metrics.elapsedSeconds
        )
        averageSecondsPerScheduledCandidate =
            metrics.candidatesScheduled > 0
            ? metrics.elapsedSeconds / Double(metrics.candidatesScheduled)
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
            "message_yield_rate"
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
            String(snapshot.messageYieldRate)
        ].joined(separator: ",")

        return header + "\n" + row + "\n"
    }
}
