import Foundation

enum RealWAVReferenceAssociationExporter {
    static func exportIfRequested(
        _ report: RealWAVReferenceAssociationReport,
        environment: [String: String] =
            ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        if let jsonURL = outputURL(
            key: "FT8_REAL_WAV_ASSOCIATION_JSON",
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
                "Real WAV reference association JSON written to: "
                    + jsonURL.path
            )
        }

        if let csvURL = outputURL(
            key: "FT8_REAL_WAV_ASSOCIATION_CSV",
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
                "Real WAV reference association CSV written to: "
                    + csvURL.path
            )
        }
    }

    static func printSummary(
        _ report: RealWAVReferenceAssociationReport
    ) {
        print("Real WAV reference candidate association:")
        print("  recording: \(report.recording)")
        print("  WSJT-X references: \(report.referenceCount)")
        print("  pipeline candidates: \(report.candidateCount)")
        print("  confidently associated: \(report.matchedCount)")
        print("  near matches: \(report.nearMatchCount)")
        print("  unassociated: \(report.unassociatedCount)")
        print("  unmatched references: \(report.unmatchedReferenceCount)")

        print("  primary associations:")

        if report.primaryAssociations.isEmpty {
            print("    none")
        } else {
            for association in report.primaryAssociations {
                print(
                    "    reference #\(association.referenceIndex + 1) "
                        + "\"\(association.referenceMessage)\""
                )
                print(
                    "      candidate #\(association.candidateIndex + 1)"
                        + " dt=\(association.timeDelta)"
                        + " df=\(association.frequencyDeltaHz)"
                        + " confidence=\(association.synchronizerScore)"
                        + " distance=\(association.normalisedDistance)"
                )
            }
        }

        let near = report.candidateAssociations
            .filter { $0.classification == .nearMatch }
            .sorted {
                let lhs = ($0.timeDelta ?? .greatestFiniteMagnitude)
                    + ($0.frequencyDeltaHz ?? .greatestFiniteMagnitude) / 100
                let rhs = ($1.timeDelta ?? .greatestFiniteMagnitude)
                    + ($1.frequencyDeltaHz ?? .greatestFiniteMagnitude) / 100
                return lhs < rhs
            }
            .prefix(10)

        if !near.isEmpty {
            print("  nearest unselected candidates:")
            for candidate in near {
                print(
                    "    #\(candidate.candidateIndex + 1)"
                        + " nearest=\"\(candidate.nearestReferenceMessage ?? "")\""
                        + " dt=\(candidate.timeDelta ?? 0)"
                        + " df=\(candidate.frequencyDeltaHz ?? 0)"
                        + " confidence=\(candidate.synchronizerScore)"
                )
            }
        }
    }

    private static func csv(
        _ report: RealWAVReferenceAssociationReport
    ) -> String {
        var rows = [
            [
                "recording",
                "reference_index",
                "candidate_index",
                "reference_message",
                "reference_time",
                "reference_frequency_hz",
                "candidate_time",
                "candidate_frequency_hz",
                "synchronizer_score",
                "time_delta",
                "frequency_delta_hz",
                "normalised_distance",
                "eligible_matched",
                "eligible_near_match",
                "selected_primary"
            ].joined(separator: ",")
        ]

        let selected = Set(
            report.primaryAssociations.map {
                "\($0.referenceIndex):\($0.candidateIndex)"
            }
        )

        for item in report.distanceMatrix.sorted(by: {
            if $0.referenceIndex == $1.referenceIndex {
                return $0.normalisedDistance < $1.normalisedDistance
            }
            return $0.referenceIndex < $1.referenceIndex
        }) {
            let key = "\(item.referenceIndex):\(item.candidateIndex)"

            rows.append(
                [
                    csvField(report.recording),
                    String(item.referenceIndex),
                    String(item.candidateIndex),
                    csvField(item.referenceMessage),
                    String(item.referenceTimeOffset),
                    String(item.referenceFrequencyHz),
                    String(item.candidateStartTime),
                    String(item.candidateFrequencyHz),
                    String(item.synchronizerScore),
                    String(item.timeDelta),
                    String(item.frequencyDeltaHz),
                    String(item.normalisedDistance),
                    String(item.eligibleForMatched),
                    String(item.eligibleForNearMatch),
                    String(selected.contains(key))
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
