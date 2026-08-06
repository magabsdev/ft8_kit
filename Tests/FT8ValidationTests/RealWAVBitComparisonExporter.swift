import Foundation

enum RealWAVBitComparisonExporter {
    static func exportIfRequested(
        _ report: RealWAVBitComparisonReport,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        if let path = nonEmptyPath(
            environment["FT8_REAL_WAV_BIT_COMPARISON_JSON"]
        ) {
            let url = URL(fileURLWithPath: path)
            try prepareParentDirectory(for: url, fileManager: fileManager)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: url, options: .atomic)

            print("Real WAV bit comparison JSON written to: \(url.path)")
        }

        if let path = nonEmptyPath(
            environment["FT8_REAL_WAV_BIT_COMPARISON_CSV"]
        ) {
            let url = URL(fileURLWithPath: path)
            try prepareParentDirectory(for: url, fileManager: fileManager)
            try csv(report).write(
                to: url,
                atomically: true,
                encoding: .utf8
            )

            print("Real WAV bit comparison CSV written to: \(url.path)")
        }
    }

    static func printSummary(_ report: RealWAVBitComparisonReport) {
        print("Real WAV bit parity comparison:")
        print("  recording: \(report.recording)")
        print("  comparisons: \(report.totalComparisons)")
        print("  total incorrect bits: \(report.totalIncorrectBits)")

        for comparison in report.comparisons {
            print(
                "  #\(comparison.candidateIndex + 1)"
                    + " reference=\"\(comparison.referenceMessage)\""
                    + " errors=\(comparison.incorrectBits)"
                    + " message=\(comparison.messageBitErrors)"
                    + " crc=\(comparison.crcBitErrors)"
                    + " parity=\(comparison.parityBitErrors)"
                    + " first=\(comparison.firstMismatch.map(String.init) ?? "none")"
                    + " longestRun=\(comparison.longestMatchingRun)"
            )
        }
    }

    private static func nonEmptyPath(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func prepareParentDirectory(
        for url: URL,
        fileManager: FileManager
    ) throws {
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
    }

    private static func csv(
        _ report: RealWAVBitComparisonReport
    ) -> String {
        var rows = [
            [
                "recording",
                "candidate_index",
                "reference_message",
                "bit",
                "section",
                "expected",
                "actual",
                "llr",
                "confidence",
                "symbol",
                "gray_bit"
            ].joined(separator: ",")
        ]

        for comparison in report.comparisons {
            let recording = csvField(report.recording)
            let candidateIndex = String(comparison.candidateIndex)
            let referenceMessage = csvField(comparison.referenceMessage)

            for mismatch in comparison.mismatches {
                let bitIndex = String(mismatch.bitIndex)
                let section = mismatch.section.rawValue
                let expected = String(mismatch.expected)
                let actual = String(mismatch.actual)
                let llr = mismatch.llr.map { String($0) } ?? ""
                let confidence = mismatch.confidence.map { String($0) } ?? ""
                let symbolIndex = String(mismatch.symbolIndex)
                let grayBit = String(mismatch.grayBit)

                let fields: [String] = [
                    recording,
                    candidateIndex,
                    referenceMessage,
                    bitIndex,
                    section,
                    expected,
                    actual,
                    llr,
                    confidence,
                    symbolIndex,
                    grayBit
                ]

                rows.append(fields.joined(separator: ","))
            }
        }

        return rows.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",")
                || value.contains("\"")
                || value.contains("\n") else {
            return value
        }

        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
