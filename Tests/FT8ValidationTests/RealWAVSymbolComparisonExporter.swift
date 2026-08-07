import Foundation

enum RealWAVSymbolComparisonExporter {
    static func exportIfRequested(
        _ report: RealWAVSymbolComparisonReport,
        environment: [String: String] =
            ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        if let jsonURL = outputURL(
            key: "FT8_REAL_WAV_SYMBOL_COMPARISON_JSON",
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
                "Real WAV symbol comparison JSON written to: "
                    + jsonURL.path
            )
        }

        if let csvURL = outputURL(
            key: "FT8_REAL_WAV_SYMBOL_COMPARISON_CSV",
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
                "Real WAV symbol comparison CSV written to: "
                    + csvURL.path
            )
        }
    }

    static func printSummary(
        _ report: RealWAVSymbolComparisonReport
    ) {
        print(
            """
            Real WAV symbol comparison:
              recording: \(report.recording)
              candidates: \(report.candidateCount)
              data symbols: \(report.symbolCount)
              matching tones: \(report.toneMatches)
              mismatching tones: \(report.toneMismatches)
            """
        )

        let grouped = Dictionary(
            grouping: report.rows,
            by: \.candidateIndex
        )

        for candidateIndex in grouped.keys.sorted() {
            guard let rows = grouped[candidateIndex],
                  let first = rows.first else {
                continue
            }

            let mismatches = rows.count {
                $0.expectedTone != $0.detectedTone
            }

            print(
                "  #\(candidateIndex + 1) "
                    + "reference=\"\(first.referenceMessage)\" "
                    + "symbols=\(rows.count) "
                    + "toneMismatches=\(mismatches)"
            )
        }
    }

    private static func csv(
        _ report: RealWAVSymbolComparisonReport
    ) -> String {
        var lines = [
            [
                "recording",
                "candidate",
                "reference",
                "dataSymbol",
                "receivedSymbol",
                "expectedTone",
                "detectedTone",
                "toneDelta",
                "expectedGray",
                "detectedGray",
                "decodedBits",
                "soft0",
                "soft1",
                "soft2",
                "confidence"
            ].joined(separator: ",")
        ]

        lines.reserveCapacity(report.rows.count + 1)

        for row in report.rows {
            let fields: [String] = [
                csvField(report.recording),
                String(row.candidateIndex + 1),
                csvField(row.referenceMessage),
                String(row.dataSymbolIndex),
                String(row.receivedSymbolIndex),
                String(row.expectedTone),
                String(row.detectedTone),
                String(row.toneDelta),
                bitString(row.expectedGrayBits),
                bitString(row.detectedGrayBits),
                bitString(row.decodedBits),
                String(row.soft0),
                String(row.soft1),
                String(row.soft2),
                String(row.confidence)
            ]
            lines.append(fields.joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func bitString(_ bits: [UInt8]) -> String {
        bits.map(String.init).joined()
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
