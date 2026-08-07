import Foundation

enum RealWAVCancellationSweepExporter {
    static func exportIfRequested(
        _ report: RealWAVCancellationSweepReport,
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) throws {
        if let path = environment[
            "FT8_REAL_WAV_CANCELLATION_SWEEP_JSON"
        ]?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
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
                "Cancellation sweep JSON written to: "
                    + url.path
            )
        }

        if let path = environment[
            "FT8_REAL_WAV_CANCELLATION_SWEEP_CSV"
        ]?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
           !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try prepare(url)

            try csv(report).write(
                to: url,
                atomically: true,
                encoding: .utf8
            )

            print(
                "Cancellation sweep CSV written to: "
                    + url.path
            )
        }
    }

    static func printSummary(
        _ report: RealWAVCancellationSweepReport
    ) {
        print("Real WAV cancellation sweep:")
        print(
            "  cancelled: \"\(report.cancelledMessage)\""
                + " time=\(report.cancelledStartTime)"
                + " frequency=\(report.cancelledFrequencyHz)"
        )

        for result in report.results {
            print(
                "  \(result.profile.label)"
                    + " affected=\(result.affectedBins)"
                    + " reduction="
                    + String(
                        format: "%.3f",
                        result.reductionFraction
                    )
                    + " candidates=\(result.residualCandidates)"
                    + " crc=\(result.residualCRCPassed)"
                    + " reappeared=\(result.cancelledMessageReappeared)"
                    + " elapsed="
                    + String(
                        format: "%.3f",
                        result.elapsedSeconds
                    )
            )

            if !result.residualMessages.isEmpty {
                print(
                    "    messages: "
                        + result.residualMessages
                            .joined(separator: " | ")
                )
            }
        }
    }

    private static func csv(
        _ report: RealWAVCancellationSweepReport
    ) -> String {
        var rows = [
            [
                "recording",
                "cancelled_message",
                "cancelled_frequency_hz",
                "cancelled_start_time",
                "radius_bins",
                "strength",
                "time_taper_floor",
                "affected_bins",
                "reduction_fraction",
                "residual_candidates",
                "residual_crc_passed",
                "cancelled_message_reappeared",
                "elapsed_seconds",
                "residual_messages"
            ].joined(separator: ",")
        ]

        for result in report.results {
            rows.append(
                [
                    csvField(report.recording),
                    csvField(report.cancelledMessage),
                    String(report.cancelledFrequencyHz),
                    String(report.cancelledStartTime),
                    String(result.profile.radiusBins),
                    String(result.profile.strength),
                    String(result.profile.timeTaperFloor),
                    String(result.affectedBins),
                    String(result.reductionFraction),
                    String(result.residualCandidates),
                    String(result.residualCRCPassed),
                    String(result.cancelledMessageReappeared),
                    String(result.elapsedSeconds),
                    csvField(
                        result.residualMessages
                            .joined(separator: " | ")
                    )
                ].joined(separator: ",")
            )
        }

        return rows.joined(separator: "\n") + "\n"
    }

    private static func prepare(
        _ url: URL
    ) throws {
        try FileManager.default.createDirectory(
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
