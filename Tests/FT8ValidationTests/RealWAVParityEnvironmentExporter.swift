import Foundation
import XCTest

/// Writes real-WAV parity diagnostics when the corresponding environment
/// variables are present.
///
/// Supported variables:
/// - FT8_REAL_WAV_PARITY_JSON
/// - FT8_REAL_WAV_PARITY_CSV
enum RealWAVParityEnvironmentExporter {
    static func exportIfRequested(
        report: RealWAVParityReport,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        if let jsonPath = normalizedPath(
            environment["FT8_REAL_WAV_PARITY_JSON"]
        ) {
            let jsonURL = URL(fileURLWithPath: jsonPath)
            try prepareParentDirectory(for: jsonURL, fileManager: fileManager)
            try RealWAVParityDiagnosticsWriter.writeJSON(report, to: jsonURL)

            guard fileManager.fileExists(atPath: jsonURL.path) else {
                throw ExportError.fileWasNotCreated(jsonURL.path)
            }

            print("Real WAV parity JSON written to: \(jsonURL.path)")
        }

        if let csvPath = normalizedPath(
            environment["FT8_REAL_WAV_PARITY_CSV"]
        ) {
            let csvURL = URL(fileURLWithPath: csvPath)
            try prepareParentDirectory(for: csvURL, fileManager: fileManager)
            try RealWAVParityDiagnosticsWriter.writeCSV(report, to: csvURL)

            guard fileManager.fileExists(atPath: csvURL.path) else {
                throw ExportError.fileWasNotCreated(csvURL.path)
            }

            print("Real WAV parity CSV written to: \(csvURL.path)")
        }
    }

    private static func normalizedPath(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let path = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func prepareParentDirectory(
        for fileURL: URL,
        fileManager: FileManager
    ) throws {
        let directoryURL = fileURL.deletingLastPathComponent()

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    enum ExportError: LocalizedError {
        case fileWasNotCreated(String)

        var errorDescription: String? {
            switch self {
            case .fileWasNotCreated(let path):
                return "Requested parity export was not created at \(path)."
            }
        }
    }
}
