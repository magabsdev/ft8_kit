import Foundation

public struct FT8AuditSummary: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let candidatesFound: Int
    public let candidatesScheduled: Int
    public let softSymbolsExtracted: Int
    public let ldpcAttempts: Int
    public let parityPassed: Int
    public let crcPassed: Int
    public let messagesReturned: Int
    public let elapsedSeconds: Double
    public let traceCount: Int

    public init(batch: FT8DecodeBatch, generatedAt: Date = Date()) {
        self.generatedAt = generatedAt
        candidatesFound = batch.metrics.candidatesFound
        candidatesScheduled = batch.metrics.candidatesScheduled
        softSymbolsExtracted = batch.metrics.softSymbolsExtracted
        ldpcAttempts = batch.metrics.ldpcAttempts
        parityPassed = batch.metrics.parityPassed
        crcPassed = batch.metrics.crcPassed
        messagesReturned = batch.metrics.messagesReturned
        elapsedSeconds = batch.metrics.elapsedSeconds
        traceCount = batch.candidateTraces.count
    }
}

public struct FT8AuditWriter: Sendable {
    public init() {}

    public func write(batch: FT8DecodeBatch, to directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        try writeJSON(
            FT8AuditSummary(batch: batch),
            to: directory.appendingPathComponent("summary.json")
        )
        try writeJSON(
            batch.candidateTraces,
            to: directory.appendingPathComponent("candidate-traces.json")
        )
        try candidatesCSV(batch.candidateTraces).write(
            to: directory.appendingPathComponent("candidates.csv"),
            atomically: true,
            encoding: .utf8
        )
        try symbolsCSV(batch.candidateTraces).write(
            to: directory.appendingPathComponent("symbols.csv"),
            atomically: true,
            encoding: .utf8
        )
        try llrCSV(batch.candidateTraces).write(
            to: directory.appendingPathComponent("llr.csv"),
            atomically: true,
            encoding: .utf8
        )
        try ldpcCSV(batch.candidateTraces).write(
            to: directory.appendingPathComponent("ldpc.csv"),
            atomically: true,
            encoding: .utf8
        )
    }

    public func candidatesCSV(_ traces: [FT8CandidateTrace]) -> String {
        var rows = [
            "pass,candidate_index,start_time_seconds,frequency_hz,drift_hz_per_second,sync_score,snr_db,candidate_confidence,average_soft_confidence,symbol_count,llr_count,ldpc_iterations,syndrome_weight,parity_passed,crc_passed,decoded_text,failure"
        ]

        for trace in traces {
            rows.append([
                String(trace.pass),
                String(trace.candidateIndex),
                String(trace.startTime),
                String(trace.frequency),
                String(trace.driftHzPerSecond),
                String(trace.syncScore),
                String(trace.snrDB),
                String(trace.candidateConfidence),
                optional(trace.averageSoftSymbolConfidence),
                String(trace.symbols.count),
                String(trace.logLikelihoodRatios.count),
                optional(trace.ldpcIterations),
                optional(trace.syndromeWeight),
                optional(trace.parityPassed),
                optional(trace.crcPassed),
                quoted(trace.decodedText ?? ""),
                quoted(trace.failure ?? "")
            ].joined(separator: ","))
        }

        return rows.joined(separator: "\n") + "\n"
    }

    public func symbolsCSV(_ traces: [FT8CandidateTrace]) -> String {
        var header = [
            "pass", "candidate_index", "symbol_index",
            "winning_tone", "second_tone",
            "winning_metric", "second_metric",
            "metric_margin", "confidence"
        ]
        header.append(contentsOf: (0..<8).map { "tone_\($0)_metric" })

        var rows = [header.joined(separator: ",")]

        for trace in traces {
            for symbol in trace.symbols {
                let ranked = symbol.toneMetrics.enumerated().sorted {
                    $0.element > $1.element
                }
                let winner = ranked.first
                let runnerUp = ranked.dropFirst().first

                var row = [
                    String(trace.pass),
                    String(trace.candidateIndex),
                    String(symbol.symbolIndex),
                    winner.map { String($0.offset) } ?? "",
                    runnerUp.map { String($0.offset) } ?? "",
                    winner.map { String($0.element) } ?? "",
                    runnerUp.map { String($0.element) } ?? "",
                    (winner != nil && runnerUp != nil)
                        ? String(winner!.element - runnerUp!.element)
                        : "",
                    String(symbol.confidence)
                ]
                row.append(contentsOf: symbol.toneMetrics.map { String($0) })
                rows.append(row.joined(separator: ","))
            }
        }

        return rows.joined(separator: "\n") + "\n"
    }

    public func llrCSV(_ traces: [FT8CandidateTrace]) -> String {
        var rows = [
            "pass,candidate_index,llr_index,llr,hard_bit,magnitude"
        ]

        for trace in traces {
            for (index, value) in trace.logLikelihoodRatios.enumerated() {
                rows.append([
                    String(trace.pass),
                    String(trace.candidateIndex),
                    String(index),
                    String(value),
                    value >= 0 ? "1" : "0",
                    String(abs(value))
                ].joined(separator: ","))
            }
        }

        return rows.joined(separator: "\n") + "\n"
    }

    public func ldpcCSV(_ traces: [FT8CandidateTrace]) -> String {
        var rows = [
            "pass,candidate_index,iterations,syndrome_weight,parity_passed,crc_passed,decoded_text,failure"
        ]

        for trace in traces {
            rows.append([
                String(trace.pass),
                String(trace.candidateIndex),
                optional(trace.ldpcIterations),
                optional(trace.syndromeWeight),
                optional(trace.parityPassed),
                optional(trace.crcPassed),
                quoted(trace.decodedText ?? ""),
                quoted(trace.failure ?? "")
            ].joined(separator: ","))
        }

        return rows.joined(separator: "\n") + "\n"
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func optional<T>(_ value: T?) -> String {
        value.map { String(describing: $0) } ?? ""
    }

    private func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
