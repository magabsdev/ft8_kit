import Foundation

enum RealWAVOracleLLRExporter {
    static func exportIfRequested(
        _ report: RealWAVOracleLLRReport,
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
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]
            encoder.dateEncodingStrategy = .iso8601

            try encoder.encode(report).write(
                to: jsonURL,
                options: .atomic
            )

            print(
                "Real WAV oracle LLR JSON written to: "
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
                "Real WAV oracle LLR CSV written to: "
                    + csvURL.path
            )
        }
    }

    static func printSummary(
        _ report: RealWAVOracleLLRReport
    ) {
        print("Real WAV oracle LLR diagnostics:")
        print("  recording: \(report.recording)")
        print(
            "  parity-passing references: "
                + "\(report.parityPassingReferences)"
        )
        print(
            "  CRC-passing references: "
                + "\(report.crcPassingReferences)"
        )

        for reference in report.references {
            print(
                "  #\(reference.referenceIndex + 1) "
                    + "\"\(reference.referenceMessage)\""
            )
            print(
                "    bits="
                    + "\(reference.correctHardBits)"
                    + "/\(reference.bitCount)"
                    + " accuracy="
                    + String(
                        format: "%.3f",
                        reference.bitAccuracy
                    )
            )
            print(
                "    data symbols="
                    + "\(reference.correctDataSymbols)"
                    + "/\(reference.dataSymbolCount)"
                    + " accuracy="
                    + String(
                        format: "%.3f",
                        reference.dataSymbolAccuracy
                    )
            )
            print(
                "    avg|LLR|="
                    + String(
                        format: "%.3f",
                        reference.averageAbsoluteRawLLR
                    )
                    + " confidence="
                    + String(
                        format: "%.3f",
                        reference.averageSymbolConfidence
                    )
            )
            print(
                "    LDPC parity="
                    + "\(reference.ldpcParityPassed)"
                    + " crc="
                    + "\(reference.ldpcCRCPassed)"
                    + " syndrome="
                    + "\(reference.ldpcSyndromeWeight)"
                    + " iterations="
                    + "\(reference.ldpcIterations)"
            )
        }
    }

    private static func csv(
        _ report: RealWAVOracleLLRReport
    ) -> String {
        var rows = [
            [
                "recording",
                "reference_index",
                "reference_message",
                "bit_index",
                "data_symbol_ordinal",
                "symbol_index",
                "bit_within_symbol",
                "expected_tone",
                "winning_tone",
                "expected_bit",
                "hard_bit",
                "hard_bit_correct",
                "raw_llr",
                "normalized_llr",
                "absolute_raw_llr",
                "symbol_confidence",
                "expected_tone_metric_db",
                "winning_tone_metric_db",
                "runner_up_tone_metric_db",
                "tone0_db",
                "tone1_db",
                "tone2_db",
                "tone3_db",
                "tone4_db",
                "tone5_db",
                "tone6_db",
                "tone7_db"
            ].joined(separator: ",")
        ]

        for bit in report.bits {
            var fields = [
                csvField(report.recording),
                String(bit.referenceIndex),
                csvField(bit.referenceMessage),
                String(bit.bitIndex),
                String(bit.dataSymbolOrdinal),
                String(bit.symbolIndex),
                String(bit.bitWithinSymbol),
                String(bit.expectedTone),
                String(bit.winningTone),
                String(bit.expectedBit),
                String(bit.hardBit),
                String(bit.hardBitCorrect),
                String(bit.rawLLR),
                String(bit.normalizedLLR),
                String(bit.absoluteRawLLR),
                String(bit.symbolConfidence),
                String(bit.expectedToneMetricDB),
                String(bit.winningToneMetricDB),
                String(bit.runnerUpToneMetricDB)
            ]

            fields.append(
                contentsOf: bit.toneMetricsDB.map {
                    String($0)
                }
            )

            rows.append(fields.joined(separator: ","))
        }

        return rows.joined(separator: "\n") + "\n"
    }

    private static func outputURL(
        key: String,
        environment: [String: String]
    ) -> URL? {
        guard let value = environment[key]?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
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
