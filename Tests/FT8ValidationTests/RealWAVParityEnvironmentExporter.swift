import Foundation

enum RealWAVParityEnvironmentExporter {
    static func exportIfRequested(
        report: RealWAVParityDiagnosticReport,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        let jsonURL = exportURL(
            for: "FT8_REAL_WAV_PARITY_JSON",
            environment: environment
        )
        let csvURL = exportURL(
            for: "FT8_REAL_WAV_PARITY_CSV",
            environment: environment
        )

        if let jsonURL {
            try prepareParentDirectory(
                for: jsonURL,
                fileManager: fileManager
            )
        }

        if let csvURL {
            try prepareParentDirectory(
                for: csvURL,
                fileManager: fileManager
            )
        }

        try RealWAVParityDiagnostics.write(
            report,
            jsonURL: jsonURL,
            csvURL: csvURL
        )

        if let jsonURL {
            guard fileManager.fileExists(atPath: jsonURL.path) else {
                throw ExportError.outputFileWasNotCreated(jsonURL.path)
            }

            print("Real WAV parity JSON written to: \(jsonURL.path)")
        }

        if let csvURL {
            guard fileManager.fileExists(atPath: csvURL.path) else {
                throw ExportError.outputFileWasNotCreated(csvURL.path)
            }

            print("Real WAV parity CSV written to: \(csvURL.path)")
        }
    }

    private static func exportURL(
        for variable: String,
        environment: [String: String]
    ) -> URL? {
        guard let rawPath = environment[variable]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return nil
        }

        let expandedPath = NSString(string: rawPath).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath)
    }

    private static func prepareParentDirectory(
        for fileURL: URL,
        fileManager: FileManager
    ) throws {
        let directoryURL = fileURL.deletingLastPathComponent()

        guard !directoryURL.path.isEmpty else {
            return
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }
}

extension RealWAVParityEnvironmentExporter {
    enum ExportError: LocalizedError, Equatable {
        case outputFileWasNotCreated(String)

        var errorDescription: String? {
            switch self {
            case .outputFileWasNotCreated(let path):
                return "The requested parity diagnostics file was not created: \(path)"
            }
        }
    }
}
