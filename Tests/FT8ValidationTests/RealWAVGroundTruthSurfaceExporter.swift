import Foundation

enum RealWAVGroundTruthSurfaceExporter {
    static func exportIfRequested(
        _ report: RealWAVGroundTruthSurfaceReport,
        environment: [String: String] =
            ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        if let jsonURL = outputURL(
            key: "FT8_REAL_WAV_SURFACE_JSON",
            environment: environment
        ) {
            try prepareParentDirectory(
                for: jsonURL,
                fileManager: fileManager
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            try encoder.encode(report).write(
                to: jsonURL,
                options: .atomic
            )

            print(
                "Real WAV ground-truth surface JSON written to: "
                    + jsonURL.path
            )
        }

        if let csvURL = outputURL(
            key: "FT8_REAL_WAV_SURFACE_CSV",
            environment: environment
        ) {
            try prepareParentDirectory(
                for: csvURL,
                fileManager: fileManager
            )

            try csv(report).write(
                to: csvURL,
                atomically: true,
                encoding: .utf8
            )

            print(
                "Real WAV ground-truth surface CSV written to: "
                    + csvURL.path
            )
        }
    }

    static func printSummary(
        _ report: RealWAVGroundTruthSurfaceReport
    ) {
        print("Real WAV ground-truth time/frequency surface:")
        print("  recording: \(report.recording)")
        print("  references refined: \(report.referenceCount)")
        print("  surface points: \(report.surfaces.count)")

        for row in report.refinedHypotheses {
            print(
                "  reference #\(row.referenceIndex + 1)"
                    + " \"\(row.referenceMessage)\""
            )
            print(
                "    seed candidate #\(row.seedCandidateIndex + 1)"
                    + " time=\(row.seedStartTime)"
                    + " frequency=\(row.seedFrequencyHz)"
            )
            print(
                "    refined time=\(row.refinedStartTime)"
                    + " frequency=\(row.refinedFrequencyHz)"
                    + " dt(ref)=\(row.refinedTimeDelta)"
                    + " df(ref)=\(row.refinedFrequencyDeltaHz)"
            )
            print(
                "    costas=\(row.costasCorrect)/\(row.costasTotal)"
                    + " data=\(row.dataSymbolsCorrect)/\(row.dataSymbolsTotal)"
                    + " all=\(row.allSymbolsCorrect)/\(row.allSymbolsTotal)"
                    + " margin=\(row.aggregateMarginDB)"
            )
        }
    }

    private static func csv(
        _ report: RealWAVGroundTruthSurfaceReport
    ) -> String {
        var rows = [
            [
                "recording",
                "reference_index",
                "reference_message",
                "seed_candidate_index",
                "trial_start_time",
                "trial_frequency_hz",
                "time_offset_from_seed",
                "frequency_offset_from_seed_hz",
                "costas_correct",
                "costas_total",
                "costas_margin_db",
                "costas_expected_metric_db"
            ].joined(separator: ",")
        ]

        for point in report.surfaces {
            rows.append(
                [
                    csvField(report.recording),
                    String(point.referenceIndex),
                    csvField(point.referenceMessage),
                    String(point.seedCandidateIndex),
                    String(point.trialStartTime),
                    String(point.trialFrequencyHz),
                    String(point.timeOffsetFromSeed),
                    String(point.frequencyOffsetFromSeedHz),
                    String(point.costasCorrect),
                    String(point.costasTotal),
                    String(point.costasMarginDB),
                    String(point.costasExpectedMetricDB)
                ].joined(separator: ",")
            )
        }

        return rows.joined(separator: "\n") + "\n"
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

        return "\"" + value.replacingOccurrences(
            of: "\"",
            with: "\"\""
        ) + "\""
    }
}
