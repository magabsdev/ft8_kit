import Foundation

enum RealWAVCancellationMapExporter {
    static func exportIfRequested(
        _ report: RealWAVCancellationMapReport,
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) throws {
        if let path = environment[
            "FT8_REAL_WAV_CANCELLATION_MAP_JSON"
        ]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try prepare(url)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]

            try encoder.encode(report).write(
                to: url,
                options: .atomic
            )

            print(
                "Cancellation map JSON written to: "
                    + url.path
            )
        }

        if let path = environment[
            "FT8_REAL_WAV_CANCELLATION_MAP_CSV"
        ]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try prepare(url)

            try touchCSV(report).write(
                to: url,
                atomically: true,
                encoding: .utf8
            )

            print(
                "Cancellation map CSV written to: "
                    + url.path
            )
        }

        if let path = environment[
            "FT8_REAL_WAV_CANCELLATION_SYMBOLS_CSV"
        ]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try prepare(url)

            try symbolCSV(report).write(
                to: url,
                atomically: true,
                encoding: .utf8
            )

            print(
                "Cancellation symbol CSV written to: "
                    + url.path
            )
        }
    }

    private static func touchCSV(
        _ report: RealWAVCancellationMapReport
    ) -> String {
        var rows = [
            [
                "implementation",
                "symbol_index",
                "tone",
                "symbol_start_time",
                "frame_index",
                "frame_time",
                "frame_centre_time",
                "frame_timing_offset",
                "tone_frequency_hz",
                "centre_bin",
                "bin",
                "bin_offset",
                "original_magnitude",
                "original_db",
                "noise_floor_db",
                "time_taper",
                "frequency_weight",
                "applied_strength"
            ].joined(separator: ",")
        ]

        let touches =
            report.experimentalTouches
            + report.productionTouches

        for touch in touches {
            rows.append(
                [
                    touch.implementation.rawValue,
                    String(touch.symbolIndex),
                    String(touch.tone),
                    String(touch.symbolStartTime),
                    String(touch.frameIndex),
                    String(touch.frameTime),
                    String(touch.frameCentreTime),
                    String(touch.frameTimingOffset),
                    String(touch.toneFrequencyHz),
                    String(touch.centreBin),
                    String(touch.bin),
                    String(touch.binOffset),
                    String(touch.originalMagnitude),
                    String(touch.originalDecibels),
                    String(touch.frameNoiseFloorDB),
                    String(touch.timeTaper),
                    String(touch.frequencyWeight),
                    String(touch.appliedStrength)
                ].joined(separator: ",")
            )
        }

        return rows.joined(separator: "\n") + "\n"
    }

    private static func symbolCSV(
        _ report: RealWAVCancellationMapReport
    ) -> String {
        var rows = [
            [
                "symbol_index",
                "tone",
                "symbol_start_time",
                "experimental_frames",
                "production_frames",
                "experimental_touch_count",
                "production_touch_count",
                "common_frame_count",
                "experimental_only_frame_count",
                "production_only_frame_count",
                "production_to_experimental_touch_ratio"
            ].joined(separator: ",")
        ]

        for symbol in report.symbols {
            rows.append(
                [
                    String(symbol.symbolIndex),
                    String(symbol.tone),
                    String(symbol.symbolStartTime),
                    csvField(
                        symbol.experimentalFrameIndices
                            .map { String($0) }
                            .joined(separator: " ")
                    ),
                    csvField(
                        symbol.productionFrameIndices
                            .map { String($0) }
                            .joined(separator: " ")
                    ),
                    String(symbol.experimentalTouchCount),
                    String(symbol.productionTouchCount),
                    String(symbol.commonFrameCount),
                    String(symbol.experimentalOnlyFrameCount),
                    String(symbol.productionOnlyFrameCount),
                    String(
                        symbol.productionToExperimentalTouchRatio
                    )
                ].joined(separator: ",")
            )
        }

        return rows.joined(separator: "\n") + "\n"
    }

    private static func prepare(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",")
                || value.contains("\"")
                || value.contains("\n")
                || value.contains(" ") else {
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
