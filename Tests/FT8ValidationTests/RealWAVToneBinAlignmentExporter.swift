import Foundation

enum RealWAVToneBinAlignmentExporter {
    static func exportIfRequested(
        _ report: RealWAVToneBinAlignmentReport,
        environment: [String: String] =
            ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        if let jsonURL = outputURL(
            key: "FT8_REAL_WAV_TONE_BIN_JSON",
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
                "Real WAV tone-bin JSON written to: "
                    + jsonURL.path
            )
        }

        if let csvURL = outputURL(
            key: "FT8_REAL_WAV_TONE_BIN_CSV",
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
                "Real WAV tone-bin CSV written to: "
                    + csvURL.path
            )
        }
    }

    static func printSummary(
        _ report: RealWAVToneBinAlignmentReport
    ) {
        print(
            """
            Real WAV tone-bin alignment:
              recording: \(report.recording)
              candidates: \(report.candidateCount)
              symbols: \(report.symbolCount)
              sample rate: \(report.sampleRate)
              FFT size: \(report.fftSize)
              hop size: \(report.hopSize)
              bin width: \(report.sampleRate / Float(report.fftSize)) Hz
              mean |frame time error|: \(report.meanAbsoluteFrameTimeErrorSeconds) s
              max |frame time error|: \(report.maximumAbsoluteFrameTimeErrorSeconds) s
              mean |expected-tone bin error|: \(report.meanAbsoluteExpectedToneFrequencyErrorHz) Hz
              max |expected-tone bin error|: \(report.maximumAbsoluteExpectedToneFrequencyErrorHz) Hz
            """
        )

        let worstTiming = report.rows
            .sorted {
                abs($0.frameTimeErrorSeconds)
                    > abs($1.frameTimeErrorSeconds)
            }
            .prefix(10)

        if !worstTiming.isEmpty {
            print("  largest frame-time errors:")
            for row in worstTiming {
                print(
                    "    #\(row.candidateIndex + 1) "
                        + "symbol=\(row.dataSymbolIndex) "
                        + "rx=\(row.receivedSymbolIndex) "
                        + "requested=\(row.requestedSymbolTime) "
                        + "frame=\(row.selectedFrameTime) "
                        + "error=\(row.frameTimeErrorSeconds)s "
                        + "samples=\(row.frameTimeErrorSamples)"
                )
            }
        }

        let worstFrequency = report.rows
            .compactMap { row -> (
                RealWAVToneBinAlignmentRow,
                RealWAVToneBinSample
            )? in
                let tone = Int(row.expectedTone)
                guard row.tones.indices.contains(tone) else {
                    return nil
                }
                return (row, row.tones[tone])
            }
            .sorted {
                abs($0.1.frequencyErrorHz)
                    > abs($1.1.frequencyErrorHz)
            }
            .prefix(10)

        if !worstFrequency.isEmpty {
            print("  largest expected-tone bin errors:")
            for item in worstFrequency {
                let row = item.0
                let tone = item.1

                print(
                    "    #\(row.candidateIndex + 1) "
                        + "symbol=\(row.dataSymbolIndex) "
                        + "expectedTone=\(row.expectedTone) "
                        + "detectedTone=\(row.detectedTone) "
                        + "target=\(tone.requestedFrequencyHz) "
                        + "bin=\(tone.roundedBin) "
                        + "centre=\(tone.roundedBinFrequencyHz) "
                        + "error=\(tone.frequencyErrorHz)Hz "
                        + "neighbourhood=\(tone.neighbourhoodDB)"
                )
            }
        }
    }

    private static func csv(
        _ report: RealWAVToneBinAlignmentReport
    ) -> String {
        var header: [String] = [
            "recording",
            "candidate",
            "reference",
            "dataSymbol",
            "receivedSymbol",
            "expectedTone",
            "detectedTone",
            "candidateStartTime",
            "requestedSymbolTime",
            "selectedFrameIndex",
            "selectedFrameSampleOffset",
            "selectedFrameTime",
            "frameTimeErrorSeconds",
            "frameTimeErrorSamples",
            "candidateBaseFrequencyHz",
            "candidateDriftHzPerSecond",
            "elapsedSeconds",
            "appliedDriftHz",
            "binWidthHz",
            "toneSpacingHz"
        ]

        for tone in 0..<8 {
            header.append("tone\(tone)RequestedFrequencyHz")
            header.append("tone\(tone)FractionalBin")
            header.append("tone\(tone)RoundedBin")
            header.append("tone\(tone)RoundedBinFrequencyHz")
            header.append("tone\(tone)FrequencyErrorHz")
            header.append("tone\(tone)NeighbourhoodOffsets")
            header.append("tone\(tone)NeighbourhoodDB")
        }

        var lines = [header.joined(separator: ",")]
        lines.reserveCapacity(report.rows.count + 1)

        for row in report.rows {
            var fields: [String] = [
                csvField(report.recording),
                String(row.candidateIndex + 1),
                csvField(row.referenceMessage),
                String(row.dataSymbolIndex),
                String(row.receivedSymbolIndex),
                String(row.expectedTone),
                String(row.detectedTone),
                String(row.candidateStartTime),
                String(row.requestedSymbolTime),
                String(row.selectedFrameIndex),
                String(row.selectedFrameSampleOffset),
                String(row.selectedFrameTime),
                String(row.frameTimeErrorSeconds),
                String(row.frameTimeErrorSamples),
                String(row.candidateBaseFrequencyHz),
                String(row.candidateDriftHzPerSecond),
                String(row.elapsedSeconds),
                String(row.appliedDriftHz),
                String(row.binWidthHz),
                String(row.toneSpacingHz)
            ]

            for tone in row.tones {
                fields.append(String(tone.requestedFrequencyHz))
                fields.append(String(tone.fractionalBin))
                fields.append(String(tone.roundedBin))
                fields.append(String(tone.roundedBinFrequencyHz))
                fields.append(String(tone.frequencyErrorHz))
                fields.append(
                    csvField(
                        tone.neighbourhoodOffsets
                            .map { String($0) }
                            .joined(separator: "|")
                    )
                )
                fields.append(
                    csvField(
                        tone.neighbourhoodDB
                            .map { String($0) }
                            .joined(separator: "|")
                    )
                )
            }

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
