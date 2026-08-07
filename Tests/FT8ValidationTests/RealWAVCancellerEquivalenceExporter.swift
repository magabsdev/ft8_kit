import Foundation

enum RealWAVCancellerEquivalenceExporter {
    static func exportIfRequested(
        _ report: RealWAVCancellerEquivalenceReport,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        if let path = environment["FT8_REAL_WAV_CANCELLER_EQUIVALENCE_JSON"]?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try prepare(url)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: url, options: .atomic)
            print("Canceller equivalence JSON written to: " + url.path)
        }

        if let path = environment["FT8_REAL_WAV_CANCELLER_EQUIVALENCE_CSV"]?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try prepare(url)
            var rows = ["frame,bin,original_magnitude,experimental_residual,production_residual,absolute_difference"]
            for item in report.largestCellDifferences {
                rows.append([
                    String(item.frameIndex),
                    String(item.bin),
                    String(item.originalMagnitude),
                    String(item.experimentalMagnitude),
                    String(item.productionMagnitude),
                    String(item.absoluteDifference)
                ].joined(separator: ","))
            }
            try (rows.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            print("Canceller equivalence CSV written to: " + url.path)
        }
    }

    private static func prepare(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
    }
}
