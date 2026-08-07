import Foundation

enum RealWAVToneMetricExporter {
    static func exportIfRequested(
        _ report: RealWAVToneMetricReport,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        if let jsonURL = outputURL(
            key: "FT8_REAL_WAV_TONE_METRICS_JSON",
            environment: environment
        ) {
            try prepareParentDirectory(for: jsonURL, fileManager: fileManager)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            try encoder.encode(report).write(to: jsonURL, options: .atomic)
            print("Real WAV tone metrics JSON written to: \(jsonURL.path)")
        }

        if let csvURL = outputURL(
            key: "FT8_REAL_WAV_TONE_METRICS_CSV",
            environment: environment
        ) {
            try prepareParentDirectory(for: csvURL, fileManager: fileManager)

            try csv(report).write(
                to: csvURL,
                atomically: true,
                encoding: .utf8
            )
            print("Real WAV tone metrics CSV written to: \(csvURL.path)")
        }
    }

    static func printSummary(_ report: RealWAVToneMetricReport) {
        print(
            """
            Real WAV tone-metric diagnostics:
              recording: \(report.recording)
              candidates: \(report.candidateCount)
              data symbols: \(report.symbolCount)
              expected tone wins: \(report.expectedToneWins)
              expected tone losses: \(report.expectedToneLosses)
            """
        )

        let grouped = Dictionary(grouping: report.rows, by: \.candidateIndex)

        for candidateIndex in grouped.keys.sorted() {
            guard let rows = grouped[candidateIndex],
                  let first = rows.first else {
                continue
            }

            let losses = rows.filter { $0.expectedTone != $0.winningTone }
            let averageWinningMargin = rows.isEmpty
                ? 0
                : rows.reduce(Float.zero) { $0 + $1.winningMarginDB }
                    / Float(rows.count)

            let averageExpectedDeficit = losses.isEmpty
                ? 0
                : losses.reduce(Float.zero) {
                    $0 + ($1.winningMetricDB - $1.expectedToneMetricDB)
                } / Float(losses.count)

            print(
                "  #\(candidateIndex + 1) "
                    + "reference=\"\(first.referenceMessage)\" "
                    + "symbols=\(rows.count) "
                    + "expectedLosses=\(losses.count) "
                    + "avgWinnerMargin=\(averageWinningMargin) "
                    + "avgExpectedDeficit=\(averageExpectedDeficit)"
            )
        }

        let strongestWrong = report.rows
            .filter { $0.expectedTone != $0.winningTone }
            .sorted {
                ($0.winningMetricDB - $0.expectedToneMetricDB)
                    > ($1.winningMetricDB - $1.expectedToneMetricDB)
            }
            .prefix(12)

        if !strongestWrong.isEmpty {
            print("  strongest wrong-tone decisions:")
            for row in strongestWrong {
                let deficit = row.winningMetricDB - row.expectedToneMetricDB
                print(
                    "    #\(row.candidateIndex + 1) "
                        + "symbol=\(row.dataSymbolIndex) "
                        + "rxSymbol=\(row.receivedSymbolIndex) "
                        + "expected=\(row.expectedTone) "
                        + "winner=\(row.winningTone) "
                        + "runnerUp=\(row.runnerUpTone) "
                        + "winnerMargin=\(row.winningMarginDB) "
                        + "expectedDeficit=\(deficit) "
                        + "frameTime=\(row.frameTime)"
                )
            }
        }
    }

    private static func csv(_ report: RealWAVToneMetricReport) -> String {
        var header: [String] = [
            "recording",
            "candidate",
            "reference",
            "dataSymbol",
            "receivedSymbol",
            "symbolStartTime",
            "symbolStartSample",
            "frameTime",
            "expectedTone",
            "detectedTone",
            "winningTone",
            "runnerUpTone"
        ]

        for tone in 0..<8 {
            header.append("tone\(tone)MetricDB")
        }

        header.append(contentsOf: [
            "expectedToneMetricDB",
            "detectedToneMetricDB",
            "winningMetricDB",
            "runnerUpMetricDB",
            "winningMarginDB",
            "expectedToneBin",
            "winningToneBin",
            "expectedBinFrequencyHz",
            "winningBinFrequencyHz",
            "expectedTargetFrequencyHz",
            "winningTargetFrequencyHz"
        ])

        var lines = [header.joined(separator: ",")]
        lines.reserveCapacity(report.rows.count + 1)

        for row in report.rows {
            var fields: [String] = [
                csvField(report.recording),
                String(row.candidateIndex + 1),
                csvField(row.referenceMessage),
                String(row.dataSymbolIndex),
                String(row.receivedSymbolIndex),
                String(row.symbolStartTime),
                String(row.symbolStartSample),
                String(row.frameTime),
                String(row.expectedTone),
                String(row.detectedTone),
                String(row.winningTone),
                String(row.runnerUpTone)
            ]

            fields.append(contentsOf: row.toneMetricsDB.map { String($0) })

            fields.append(contentsOf: [
                String(row.expectedToneMetricDB),
                String(row.detectedToneMetricDB),
                String(row.winningMetricDB),
                String(row.runnerUpMetricDB),
                String(row.winningMarginDB),
                String(row.expectedToneBin),
                String(row.winningToneBin),
                String(row.expectedBinFrequencyHz),
                String(row.winningBinFrequencyHz),
                String(row.expectedTargetFrequencyHz),
                String(row.winningTargetFrequencyHz)
            ])

            lines.append(fields.joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func outputURL(
        key: String,
        environment: [String: String]
    ) -> URL? {
        guard let value = environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: value)
    }

    private static func prepareParentDirectory(
        for url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",")
                || value.contains("\"")
                || value.contains("\n") else {
            return value
        }

        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
