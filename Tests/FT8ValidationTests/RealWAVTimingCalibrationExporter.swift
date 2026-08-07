import Foundation

enum RealWAVTimingCalibrationExporter {
    static func exportIfRequested(
        _ report: RealWAVTimingCalibrationReport,
        environment: [String: String] =
            ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        if let jsonURL = outputURL(
            key: "FT8_REAL_WAV_TIMING_JSON",
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
                "Real WAV timing calibration JSON written to: "
                    + jsonURL.path
            )
        }

        if let csvURL = outputURL(
            key: "FT8_REAL_WAV_TIMING_CSV",
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
                "Real WAV timing calibration CSV written to: "
                    + csvURL.path
            )
        }
    }

    static func printSummary(
        _ report: RealWAVTimingCalibrationReport
    ) {
        print("Real WAV timing calibration:")
        print("  recording: \(report.recording)")
        print(
            "  sweep: "
                + "\(report.configuration.minimumCorrectionSeconds)"
                + "..."
                + "\(report.configuration.maximumCorrectionSeconds)"
                + " s step="
                + "\(report.configuration.stepSeconds)"
        )
        print(
            "  consensus correction: "
                + String(
                    format: "%+.3f s",
                    report.consensusCorrectionSeconds
                )
        )
        print(
            "  correction spread: "
                + String(
                    format: "%.3f s",
                    report.correctionSpreadSeconds
                )
        )

        for result in report.references {
            print(
                "  #\(result.referenceIndex + 1) "
                    + "\"\(result.referenceMessage)\""
            )
            print(
                "    reference DT="
                    + String(
                        format: "%.3f",
                        result.referenceTimeOffset
                    )
                    + " best correction="
                    + String(
                        format: "%+.3f",
                        result.bestCorrectionSeconds
                    )
                    + " start="
                    + String(
                        format: "%.3f",
                        result.bestStartTime
                    )
            )
            print(
                "    tones="
                    + "\(result.bestCorrectToneCount)"
                    + "/\(result.toneCount)"
                    + " data="
                    + "\(result.bestCorrectDataToneCount)"
                    + "/\(result.dataToneCount)"
                    + " Costas="
                    + "\(result.bestCorrectCostasToneCount)"
                    + "/\(result.costasToneCount)"
            )
            print(
                "    baseline="
                    + "\(result.baselineCorrectToneCount)"
                    + "/\(result.toneCount)"
                    + " improvement=+"
                    + "\(result.improvementInCorrectTones)"
                    + " mean margin="
                    + String(
                        format: "%.3f dB",
                        result.bestMeanExpectedToneMarginDB
                    )
            )
        }
    }

    private static func csv(
        _ report: RealWAVTimingCalibrationReport
    ) -> String {
        var rows = [
            [
                "recording",
                "reference_index",
                "reference_message",
                "reference_dt",
                "frequency_hz",
                "trial_correction_seconds",
                "trial_start_time",
                "correct_tones",
                "tone_count",
                "tone_accuracy",
                "correct_data_tones",
                "data_tone_count",
                "data_tone_accuracy",
                "correct_costas_tones",
                "costas_tone_count",
                "costas_tone_accuracy",
                "mean_expected_margin_db",
                "median_expected_margin_db",
                "positive_margin_count"
            ].joined(separator: ",")
        ]

        for point in report.points {
            rows.append(
                [
                    csvField(report.recording),
                    String(point.referenceIndex),
                    csvField(point.referenceMessage),
                    String(point.referenceTimeOffset),
                    String(point.frequencyHz),
                    String(point.trialCorrectionSeconds),
                    String(point.trialStartTime),
                    String(point.correctToneCount),
                    String(point.toneCount),
                    String(point.toneAccuracy),
                    String(point.correctDataToneCount),
                    String(point.dataToneCount),
                    String(point.dataToneAccuracy),
                    String(point.correctCostasToneCount),
                    String(point.costasToneCount),
                    String(point.costasToneAccuracy),
                    String(point.meanExpectedToneMarginDB),
                    String(point.medianExpectedToneMarginDB),
                    String(point.positiveMarginCount)
                ].joined(separator: ",")
            )
        }

        return rows.joined(separator: "\n") + "\n"
    }

    private static func outputURL(
        key: String,
        environment: [String: String]
    ) -> URL? {
        guard let value =
            environment[key]?
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
