import Foundation

enum RealWAVLLRExporter {
    static func exportIfRequested(
        _ report: RealWAVLLRReport,
        environment: [String: String] =
            ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        if let jsonURL = outputURL(
            key: "FT8_REAL_WAV_LLR_JSON",
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
                "Real WAV LLR JSON written to: "
                    + jsonURL.path
            )
        }

        if let csvURL = outputURL(
            key: "FT8_REAL_WAV_LLR_CSV",
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
                "Real WAV LLR CSV written to: "
                    + csvURL.path
            )
        }
    }

    static func printSummary(_ report: RealWAVLLRReport) {
        let s = report.summary

        print(
            """
            Real WAV LLR validation:
              recording: \(report.recording)
              candidates: \(report.candidateCount)
              bits: \(s.bitCount)
              decoded-bit errors: \(s.incorrectDecodedBits)
              wrong LLR signs: \(s.incorrectLLRSigns) (\(s.wrongSignPercentage)%)
              avg |LLR|: \(s.averageAbsoluteLLR)
              avg |LLR| correct bits: \(s.averageAbsoluteLLRCorrectBits)
              avg |LLR| incorrect bits: \(s.averageAbsoluteLLRIncorrectBits)
              |LLR| < 0.25: \(s.below025Count) (\(s.below025Percentage)%)
              |LLR| < 0.50: \(s.below050Count) (\(s.below050Percentage)%)
              |LLR| < 1.00: \(s.below100Count) (\(s.below100Percentage)%)
              max |recorded - recomputed LLR|: \(s.maximumAbsoluteRecomputedVsRecordedDelta)
            """
        )

        let worstWrong = report.rows
            .filter { !$0.llrSignMatchesExpected }
            .sorted { $0.llrMagnitude > $1.llrMagnitude }
            .prefix(15)

        if !worstWrong.isEmpty {
            print("  strongest wrong-sign LLRs:")
            for row in worstWrong {
                print(
                    "    #\(row.candidateIndex + 1) "
                        + "bit=\(row.globalBitIndex) "
                        + "symbol=\(row.dataSymbolIndex) "
                        + "bitInSymbol=\(row.bitIndexInSymbol) "
                        + "expected=\(row.expectedBit) "
                        + "hard=\(row.llrHardBit) "
                        + "llr=\(row.recordedLLR) "
                        + "zero=\(row.bestZeroMetricDB) "
                        + "one=\(row.bestOneMetricDB) "
                        + "winnerTone=\(row.winningTone)"
                )
            }
        }

        print("  LLR histogram:")
        for bucket in s.histogram {
            print(
                "    \(label(bucket)): \(bucket.count)"
            )
        }
    }

    private static func label(
        _ bucket: RealWAVLLRHistogramBucket
    ) -> String {
        switch (bucket.lowerBound, bucket.upperBound) {
        case (nil, let upper?):
            return "<\(upper)"
        case (let lower?, nil):
            return ">=\(lower)"
        case (let lower?, let upper?):
            return "[\(lower), \(upper))"
        default:
            return "all"
        }
    }

    private static func csv(
        _ report: RealWAVLLRReport
    ) -> String {
        var header: [String] = [
            "recording",
            "candidate",
            "reference",
            "globalBit",
            "dataSymbol",
            "receivedSymbol",
            "bitInSymbol",
            "expectedTone",
            "detectedTone",
            "winningTone",
            "runnerUpTone"
        ]

        for tone in 0..<8 {
            header.append("tone\(tone)MetricDB")
        }

        header.append(contentsOf: [
            "winningMetricDB",
            "runnerUpMetricDB",
            "winningMarginDB",
            "bestZeroMetricDB",
            "bestOneMetricDB",
            "rawMetricDifference",
            "recomputedLLR",
            "recordedLLR",
            "llrDelta",
            "expectedBit",
            "decodedBit",
            "llrHardBit",
            "llrSignMatchesExpected",
            "decodedBitMatchesExpected",
            "llrMagnitude"
        ])

        var lines = [header.joined(separator: ",")]
        lines.reserveCapacity(report.rows.count + 1)

        for row in report.rows {
            var fields: [String] = [
                csvField(report.recording),
                String(row.candidateIndex + 1),
                csvField(row.referenceMessage),
                String(row.globalBitIndex),
                String(row.dataSymbolIndex),
                String(row.receivedSymbolIndex),
                String(row.bitIndexInSymbol),
                String(row.expectedTone),
                String(row.detectedTone),
                String(row.winningTone),
                String(row.runnerUpTone)
            ]

            fields.append(
                contentsOf: row.toneMetricsDB.map { String($0) }
            )

            fields.append(contentsOf: [
                String(row.winningMetricDB),
                String(row.runnerUpMetricDB),
                String(row.winningMarginDB),
                String(row.bestZeroMetricDB),
                String(row.bestOneMetricDB),
                String(row.rawMetricDifference),
                String(row.recomputedLLR),
                String(row.recordedLLR),
                String(row.llrDelta),
                String(row.expectedBit),
                String(row.decodedBit),
                String(row.llrHardBit),
                String(row.llrSignMatchesExpected),
                String(row.decodedBitMatchesExpected),
                String(row.llrMagnitude)
            ])

            lines.append(fields.joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
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
