import Foundation

enum RealWAVFastCancellationExporter {
    static func exportIfRequested(
        _ report: RealWAVFastCancellationReport,
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) throws {
        if let path = environment[
            "FT8_REAL_WAV_FAST_CANCELLATION_JSON"
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
                "Fast cancellation JSON written to: "
                    + url.path
            )
        }

        if let path = environment[
            "FT8_REAL_WAV_FAST_CANCELLATION_CSV"
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
                "Fast cancellation CSV written to: "
                    + url.path
            )
        }
    }

    static func printSummary(
        _ report: RealWAVFastCancellationReport
    ) {
        print("Fast cancellation profile selection:")
        print(
            "  cancelled: \"\(report.cancelledMessage)\""
                + " time=\(report.cancelledStartTime)"
                + " frequency=\(report.cancelledFrequencyHz)"
        )
        print(
            "  selected profile: "
                + report.selectedProfile.label
        )

        for score in report.scores
            .sorted(by: { $0.objective > $1.objective })
            .prefix(8)
        {
            print(
                "  \(score.profile.label)"
                    + " suppression="
                    + String(format: "%.2f", score.suppressionDB)
                    + " dB collateral="
                    + String(format: "%.2f", score.collateralPenaltyDB)
                    + " dB objective="
                    + String(format: "%.2f", score.objective)
            )
        }

        print(
            "  residual candidates: \(report.residualCandidates)"
        )
        print(
            "  residual CRC passed: \(report.residualCRCPassed)"
        )
        print(
            "  cancelled message reappeared: "
                + "\(report.cancelledMessageReappeared)"
        )
        print(
            "  residual elapsed: "
                + String(
                    format: "%.3f s",
                    report.residualElapsedSeconds
                )
        )

        if !report.residualMessages.isEmpty {
            print(
                "  residual messages: "
                    + report.residualMessages
                        .joined(separator: " | ")
            )
        }
    }

    private static func csv(
        _ report: RealWAVFastCancellationReport
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
                "residual_signal_power_db",
                "residual_neighbour_power_db",
                "suppression_db",
                "collateral_penalty_db",
                "objective",
                "selected"
            ].joined(separator: ",")
        ]

        for score in report.scores {
            rows.append(
                [
                    csvField(report.recording),
                    csvField(report.cancelledMessage),
                    String(report.cancelledFrequencyHz),
                    String(report.cancelledStartTime),
                    String(score.profile.radiusBins),
                    String(score.profile.strength),
                    String(score.profile.timeTaperFloor),
                    String(score.affectedBins),
                    String(score.reductionFraction),
                    String(score.residualSignalPowerDB),
                    String(score.residualNeighbourPowerDB),
                    String(score.suppressionDB),
                    String(score.collateralPenaltyDB),
                    String(score.objective),
                    String(
                        score.profile
                            == report.selectedProfile
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
