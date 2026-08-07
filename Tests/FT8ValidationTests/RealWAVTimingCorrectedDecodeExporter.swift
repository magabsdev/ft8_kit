import Foundation

enum RealWAVTimingCorrectedDecodeExporter {
    static func exportIfRequested(
        _ report: RealWAVTimingCorrectedDecodeReport,
        environment: [String: String] =
            ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        if let jsonURL = outputURL(
            key: "FT8_REAL_WAV_TIMING_CORRECTED_JSON",
            environment: environment
        ) {
            try prepareParentDirectory(
                for: jsonURL,
                fileManager: fileManager
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]
            encoder.dateEncodingStrategy = .iso8601

            try encoder.encode(report).write(
                to: jsonURL,
                options: .atomic
            )

            print(
                "Timing-corrected JSON written to: "
                    + jsonURL.path
            )
        }

        if let csvURL = outputURL(
            key: "FT8_REAL_WAV_TIMING_CORRECTED_CSV",
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
                "Timing-corrected CSV written to: "
                    + csvURL.path
            )
        }
    }

    static func printSummary(
        _ report: RealWAVTimingCorrectedDecodeReport
    ) {
        print("Real WAV timing-corrected decode:")
        print("  recording: \(report.recording)")
        print(
            "  correction: "
                + String(
                    format: "%+.3f s",
                    report.timingCorrectionSeconds
                )
        )
        print(
            "  parity-passing references: "
                + "\(report.parityPassingReferences)"
        )
        print(
            "  CRC-passing references: "
                + "\(report.crcPassingReferences)"
        )

        for row in report.references {
            print(
                "  #\(row.referenceIndex + 1) "
                    + "\"\(row.referenceMessage)\""
            )
            print(
                "    DT="
                    + String(
                        format: "%.3f",
                        row.referenceTimeOffset
                    )
                    + " corrected start="
                    + String(
                        format: "%.3f",
                        row.correctedStartTime
                    )
            )
            print(
                "    hard bits="
                    + "\(row.correctHardBits)"
                    + "/\(row.bitCount)"
                    + " data symbols="
                    + "\(row.correctDataSymbols)"
                    + "/\(row.dataSymbolCount)"
            )
            print(
                "    parity=\(row.parityPassed)"
                    + " crc=\(row.crcPassed)"
                    + " syndrome=\(row.syndromeWeight)"
                    + " iterations=\(row.iterations)"
            )
        }
    }

    private static func csv(
        _ report: RealWAVTimingCorrectedDecodeReport
    ) -> String {
        var rows = [
            [
                "recording",
                "timing_correction_seconds",
                "reference_index",
                "reference_message",
                "reference_dt",
                "corrected_start_time",
                "frequency_hz",
                "correct_hard_bits",
                "bit_count",
                "bit_accuracy",
                "correct_data_symbols",
                "data_symbol_count",
                "data_symbol_accuracy",
                "parity_passed",
                "crc_passed",
                "syndrome_weight",
                "iterations"
            ].joined(separator: ",")
        ]

        for row in report.references {
            rows.append(
                [
                    csvField(report.recording),
                    String(report.timingCorrectionSeconds),
                    String(row.referenceIndex),
                    csvField(row.referenceMessage),
                    String(row.referenceTimeOffset),
                    String(row.correctedStartTime),
                    String(row.referenceFrequencyHz),
                    String(row.correctHardBits),
                    String(row.bitCount),
                    String(row.bitAccuracy),
                    String(row.correctDataSymbols),
                    String(row.dataSymbolCount),
                    String(row.dataSymbolAccuracy),
                    String(row.parityPassed),
                    String(row.crcPassed),
                    String(row.syndromeWeight),
                    String(row.iterations)
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
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
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

    private static func csvField(
        _ value: String
    ) -> String {
        guard value.contains(",")
                || value.contains("\"")
                || value.contains("\n") else {
            return value
        }

        return "\""
            + value.replacingOccurrences(
                of: "\"",
                with: "\"\""
            )
            + "\""
    }
}
