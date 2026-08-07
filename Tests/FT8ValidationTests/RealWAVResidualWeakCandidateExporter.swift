import Foundation

enum RealWAVResidualWeakCandidateExporter {
    static func exportIfRequested(
        _ report:
            RealWAVResidualWeakCandidateReport,
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) throws {
        if let path = environment[
            "FT8_REAL_WAV_RESIDUAL_WEAK_JSON"
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
                "Residual weak-candidate JSON written to: "
                    + url.path
            )
        }

        if let path = environment[
            "FT8_REAL_WAV_RESIDUAL_WEAK_CSV"
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
                "Residual weak-candidate CSV written to: "
                    + url.path
            )
        }
    }

    private static func csv(
        _ report:
            RealWAVResidualWeakCandidateReport
    ) -> String {
        var rows = [
            [
                "reference_index",
                "reference_message",
                "reference_snr_db",
                "reference_time",
                "reference_frequency_hz",
                "already_decoded",
                "failure_stage",
                "tight_candidate_present",
                "best_syndrome_weight",
                "best_soft_confidence",
                "parity_candidate_count",
                "crc_candidate_count",
                "nearest_candidate_index",
                "nearest_time",
                "nearest_frequency_hz",
                "nearest_dt",
                "nearest_df",
                "nearest_confidence",
                "nearest_soft_confidence",
                "nearest_syndrome",
                "nearest_parity",
                "nearest_crc",
                "nearest_failure"
            ].joined(separator: ",")
        ]

        for reference in report.references {
            let nearest = reference.nearestCandidate

            rows.append(
                [
                    String(reference.referenceIndex),
                    csvField(reference.referenceMessage),
                    String(reference.referenceSNRDB),
                    String(reference.referenceTimeOffset),
                    String(reference.referenceFrequencyHz),
                    String(reference.alreadyDecoded),
                    reference.failureStage.rawValue,
                    String(reference.tightCandidatePresent),
                    optional(reference.bestSyndromeWeight),
                    optional(reference.bestSoftSymbolConfidence),
                    String(reference.parityCandidateCount),
                    String(reference.crcCandidateCount),
                    optional(nearest?.candidateIndex),
                    optional(nearest?.startTime),
                    optional(nearest?.frequencyHz),
                    optional(nearest?.timeDelta),
                    optional(nearest?.frequencyDeltaHz),
                    optional(nearest?.candidateConfidence),
                    optional(
                        nearest?
                            .averageSoftSymbolConfidence
                    ),
                    optional(nearest?.syndromeWeight),
                    optional(nearest?.parityPassed),
                    optional(nearest?.crcPassed),
                    csvField(nearest?.failure ?? "")
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

    private static func optional<T>(
        _ value: T?
    ) -> String {
        value.map {
            String(describing: $0)
        } ?? ""
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
