import Foundation
import FT8Decoder
import FT8Validation

private struct JSONDecode: Codable {
    let message: String
    let frequencyHz: Double
    let timeSeconds: Double
    let snrDB: Double
}

private struct JSONWAV: Codable {
    let path: String
    let sampleRate: Int
    let sampleCount: Int
    let durationSeconds: Double
    let peak: Double
    let rms: Double
}

private struct JSONSpectrogram: Codable {
    let frames: Int
    let bins: Int
    let fftSize: Int
    let hopSize: Int
    let minimumFrequencyHz: Double
    let maximumFrequencyHz: Double
    let durationSeconds: Double
}

private struct JSONCandidate: Codable {
    let startTimeSeconds: Double
    let frequencyHz: Double
    let driftHzPerSecond: Double
    let symbolOffsetSeconds: Double
    let syncScore: Double
    let snrDB: Double
    let confidence: Double
}

private struct JSONPassMetrics: Codable {
    let pass: Int
    let candidatesFound: Int
    let candidatesScheduled: Int
    let softSymbolsExtracted: Int
    let ldpcAttempts: Int
    let parityPassed: Int
    let crcPassed: Int
    let messagesDecoded: Int
    let newMessages: Int
    let signalsCancelled: Int
    let affectedBins: Int
    let energyReductionFraction: Double
    let elapsedSeconds: Double
}

private struct JSONMultiPassMetrics: Codable {
    let passesCompleted: Int
    let uniqueMessages: Int
    let totalSignalsCancelled: Int
    let totalAffectedBins: Int
    let elapsedSeconds: Double
    let passes: [JSONPassMetrics]
}

private struct JSONTimings: Codable {
    let waterfallSeconds: Double
    let candidateSearchSeconds: Double
    let decodeSeconds: Double
    let totalSeconds: Double
}

private struct JSONDiagnosticReport: Codable {
    let wav: JSONWAV
    let spectrogram: JSONSpectrogram
    let candidates: [JSONCandidate]
    let metrics: JSONMultiPassMetrics
    let timings: JSONTimings
    let messages: [JSONDecode]
}

private struct DecodeOptions {
    var json = false
    var diagnostics = false
    var dumpDirectory: String?
    var wavPath: String?
}

private enum CLIError: Error, CustomStringConvertible {
    case usage
    case missingPath(String)
    case missingValue(String)
    case unexpectedArgument(String)

    var description: String {
        switch self {
        case .usage:
            return """
            Usage:
              ft8-validate [corpus-directory]
              ft8-validate corpus <directory>
              ft8-validate decode [--json] [--diagnostics] [--dump-debug <directory>] <wav-file>
            """
        case .missingPath(let path):
            return "Path does not exist: \(path)"
        case .missingValue(let option):
            return "Missing value for \(option)"
        case .unexpectedArgument(let argument):
            return "Unexpected argument: \(argument)\n\n\(CLIError.usage)"
        }
    }
}

private struct DecodeRun {
    let recording: WAVRecording
    let diagnostic: FT8SlotDiagnosticBatch

    var observed: [ObservedDecode] {
        diagnostic.decodeBatch.messages.map {
            ObservedDecode(
                message: $0.decoded.text,
                frequencyHz: Double($0.candidate.frequency),
                timeOffset: $0.candidate.startTime,
                snrDB: Double($0.candidate.snrDB)
            )
        }
    }
}

private func parseDecodeOptions(_ arguments: [String]) throws -> DecodeOptions {
    var options = DecodeOptions()
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--json":
            options.json = true
        case "--diagnostics":
            options.diagnostics = true
        case "--dump-debug":
            index += 1
            guard index < arguments.count else {
                throw CLIError.missingValue("--dump-debug")
            }
            options.dumpDirectory = arguments[index]
            options.diagnostics = true
        default:
            if argument.hasPrefix("-") {
                throw CLIError.unexpectedArgument(argument)
            }
            guard options.wavPath == nil else {
                throw CLIError.unexpectedArgument(argument)
            }
            options.wavPath = argument
        }
        index += 1
    }

    guard options.wavPath != nil else { throw CLIError.usage }
    return options
}

private func decodeWAV(at url: URL) throws -> DecodeRun {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CLIError.missingPath(url.path)
    }

    let recording = try WAVFile.load(url: url)
    var decoder = FT8MultiPassSlotDecoder()
    decoder.waterfallConfiguration.sampleRate = Float(recording.sampleRate)
    let diagnostic = try decoder.decodeWithDiagnostics(samples: recording.samples)
    return DecodeRun(recording: recording, diagnostic: diagnostic)
}

private func jsonMessages(from run: DecodeRun) -> [JSONDecode] {
    run.observed.map {
        JSONDecode(
            message: $0.message,
            frequencyHz: $0.frequencyHz,
            timeSeconds: $0.timeOffset,
            snrDB: $0.snrDB ?? 0
        )
    }
}

private func candidatePayloads(_ candidates: [FT8Candidate]) -> [JSONCandidate] {
    candidates.map {
        JSONCandidate(
            startTimeSeconds: $0.startTime,
            frequencyHz: Double($0.frequency),
            driftHzPerSecond: Double($0.driftHzPerSecond),
            symbolOffsetSeconds: $0.symbolOffset,
            syncScore: Double($0.syncScore),
            snrDB: Double($0.snrDB),
            confidence: Double($0.confidence)
        )
    }
}

private func metricsPayload(_ metrics: FT8MultiPassMetrics) -> JSONMultiPassMetrics {
    JSONMultiPassMetrics(
        passesCompleted: metrics.passesCompleted,
        uniqueMessages: metrics.uniqueMessages,
        totalSignalsCancelled: metrics.totalSignalsCancelled,
        totalAffectedBins: metrics.totalAffectedBins,
        elapsedSeconds: metrics.elapsedSeconds,
        passes: metrics.passes.map {
            JSONPassMetrics(
                pass: $0.pass,
                candidatesFound: $0.candidatesFound,
                candidatesScheduled: $0.candidatesScheduled,
                softSymbolsExtracted: $0.softSymbolsExtracted,
                ldpcAttempts: $0.ldpcAttempts,
                parityPassed: $0.parityPassed,
                crcPassed: $0.crcPassed,
                messagesDecoded: $0.messagesDecoded,
                newMessages: $0.newMessages,
                signalsCancelled: $0.signalsCancelled,
                affectedBins: $0.affectedBins,
                energyReductionFraction: $0.energyReductionFraction,
                elapsedSeconds: $0.elapsedSeconds
            )
        }
    )
}

private func makeReport(path: String, run: DecodeRun) -> JSONDiagnosticReport {
    let samples = run.recording.samples
    let peak = samples.map { abs(Double($0)) }.max() ?? 0
    let meanSquare = samples.isEmpty
        ? 0
        : samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)
    let spectrogram = run.diagnostic.spectrogram
    let timings = run.diagnostic.timings

    return JSONDiagnosticReport(
        wav: JSONWAV(
            path: URL(fileURLWithPath: path).standardizedFileURL.path,
            sampleRate: run.recording.sampleRate,
            sampleCount: samples.count,
            durationSeconds: Double(samples.count) / Double(run.recording.sampleRate),
            peak: peak,
            rms: sqrt(meanSquare)
        ),
        spectrogram: JSONSpectrogram(
            frames: spectrogram.rowCount,
            bins: spectrogram.columnCount,
            fftSize: spectrogram.fftSize,
            hopSize: spectrogram.hopSize,
            minimumFrequencyHz: Double(spectrogram.minimumFrequency),
            maximumFrequencyHz: Double(spectrogram.maximumFrequency),
            durationSeconds: spectrogram.duration
        ),
        candidates: candidatePayloads(run.diagnostic.candidates),
        metrics: metricsPayload(run.diagnostic.decodeBatch.metrics),
        timings: JSONTimings(
            waterfallSeconds: timings.waterfallSeconds,
            candidateSearchSeconds: timings.candidateSearchSeconds,
            decodeSeconds: timings.decodeSeconds,
            totalSeconds: timings.totalSeconds
        ),
        messages: jsonMessages(from: run)
    )
}

private func encodeJSON<T: Encodable>(_ value: T, pretty: Bool = false) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    return try encoder.encode(value)
}

private func printHumanReport(_ report: JSONDiagnosticReport) {
    print("Input")
    print("  Sample rate:           \(report.wav.sampleRate) Hz")
    print("  Samples:               \(report.wav.sampleCount)")
    print(String(format: "  Duration:              %.3f s", report.wav.durationSeconds))
    print(String(format: "  Peak:                  %.6f", report.wav.peak))
    print(String(format: "  RMS:                   %.6f", report.wav.rms))
    print("Spectrogram")
    print("  Frames:                \(report.spectrogram.frames)")
    print("  Bins:                  \(report.spectrogram.bins)")
    print("Detection")
    print("  Candidates found:      \(report.candidates.count)")

    for pass in report.metrics.passes {
        print("Pass \(pass.pass)")
        print("  Candidates found:      \(pass.candidatesFound)")
        print("  Candidates scheduled:  \(pass.candidatesScheduled)")
        print("  Soft symbols:          \(pass.softSymbolsExtracted)")
        print("  LDPC attempts:         \(pass.ldpcAttempts)")
        print("  Parity passed:         \(pass.parityPassed)")
        print("  CRC passed:            \(pass.crcPassed)")
        print("  Messages decoded:      \(pass.messagesDecoded)")
        print("  New messages:          \(pass.newMessages)")
    }

    print("Result")
    print("  Passes completed:      \(report.metrics.passesCompleted)")
    print("  Messages returned:     \(report.metrics.uniqueMessages)")
    print("Timing")
    print(String(format: "  Waterfall:             %.6f s", report.timings.waterfallSeconds))
    print(String(format: "  Candidate inspection:  %.6f s", report.timings.candidateSearchSeconds))
    print(String(format: "  Decode:                %.6f s", report.timings.decodeSeconds))
    print(String(format: "  Total diagnostics:     %.6f s", report.timings.totalSeconds))
}

private func csvEscape(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
}

private func writeDebugDump(
    directoryPath: String,
    report: JSONDiagnosticReport,
    run: DecodeRun
) throws {
    let manager = FileManager.default
    let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)

    try encodeJSON(report, pretty: true).write(to: directory.appendingPathComponent("metrics.json"))
    try encodeJSON(report.candidates, pretty: true).write(to: directory.appendingPathComponent("candidates.json"))
    try encodeJSON(report.messages, pretty: true).write(to: directory.appendingPathComponent("messages.json"))

    var waveform = "sampleIndex,timeSeconds,amplitude\n"
    waveform.reserveCapacity(run.recording.samples.count * 28)
    for (index, sample) in run.recording.samples.enumerated() {
        let time = Double(index) / Double(run.recording.sampleRate)
        waveform += "\(index),\(time),\(sample)\n"
    }
    try Data(waveform.utf8).write(to: directory.appendingPathComponent("waveform.csv"))

    var spectrogramCSV = "frameIndex,timeSeconds,frequencyHz,decibels,intensity,noiseFloorDB\n"
    for frame in run.diagnostic.spectrogram.frames {
        for index in frame.decibels.indices {
            spectrogramCSV += "\(frame.index),\(frame.time),\(frame.frequency(at: index)),\(frame.decibels[index]),\(frame.intensities[index]),\(frame.noiseFloorDB)\n"
        }
    }
    try Data(spectrogramCSV.utf8).write(to: directory.appendingPathComponent("spectrogram.csv"))

    var decodedCSV = "message,timeSeconds,frequencyHz,snrDB\n"
    for message in report.messages {
        decodedCSV += "\(csvEscape(message.message)),\(message.timeSeconds),\(message.frequencyHz),\(message.snrDB)\n"
    }
    try Data(decodedCSV.utf8).write(to: directory.appendingPathComponent("decoded.csv"))
}

private func runDecode(options: DecodeOptions) throws {
    guard let wavPath = options.wavPath else { throw CLIError.usage }
    let run = try decodeWAV(at: URL(fileURLWithPath: wavPath))

    if options.diagnostics {
        let report = makeReport(path: wavPath, run: run)
        if options.json {
            print(String(decoding: try encodeJSON(report, pretty: true), as: UTF8.self))
        } else {
            printHumanReport(report)
            for message in report.messages {
                print(String(
                    format: "  %.3f s  %8.1f Hz  %6.1f dB  %@",
                    message.timeSeconds,
                    message.frequencyHz,
                    message.snrDB,
                    message.message
                ))
            }
        }

        if let dumpDirectory = options.dumpDirectory {
            try writeDebugDump(directoryPath: dumpDirectory, report: report, run: run)
            if !options.json {
                print("Debug dump: \(URL(fileURLWithPath: dumpDirectory).standardizedFileURL.path)")
            }
        }
        return
    }

    let messages = jsonMessages(from: run)
    if options.json {
        for item in messages {
            print(String(decoding: try encodeJSON(item), as: UTF8.self))
        }
    } else {
        for item in messages {
            print(String(
                format: "%.3f s  %8.1f Hz  %6.1f dB  %@",
                item.timeSeconds,
                item.frequencyHz,
                item.snrDB,
                item.message
            ))
        }
    }
}

private func runCorpus(directory: URL) throws {
    guard FileManager.default.fileExists(atPath: directory.path) else {
        throw CLIError.missingPath(directory.path)
    }

    let cases = try ReferenceCorpus.discover(in: directory)
    print("Reference recordings: \(cases.count)")

    var expectedTotal = 0
    var decodedTotal = 0
    var matchedTotal = 0
    var missedTotal = 0
    var unexpectedTotal = 0

    for item in cases {
        let expected = try item.expectedURL.map(WSJTXReferenceParser.parse(url:)) ?? []
        expectedTotal += expected.count

        let observed = try decodeWAV(at: item.wavURL).observed
        decodedTotal += observed.count

        let comparison = ReferenceMatcher.compare(expected: expected, observed: observed)
        matchedTotal += comparison.matched
        missedTotal += comparison.missed.count
        unexpectedTotal += comparison.unexpected.count

        print("\(item.name): expected \(expected.count), decoded \(observed.count), matched \(comparison.matched)")
    }

    let rate = expectedTotal == 0 ? 100 : Double(matchedTotal) / Double(expectedTotal) * 100
    print(String(
        format: "Expected: %d  Decoded: %d  Matched: %d  Missed: %d  Unexpected: %d  Detection: %.2f%%",
        expectedTotal,
        decodedTotal,
        matchedTotal,
        missedTotal,
        unexpectedTotal,
        rate
    ))
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())

    if arguments.first == "decode" {
        try runDecode(options: parseDecodeOptions(Array(arguments.dropFirst())))
    } else if arguments.first == "corpus" {
        guard arguments.count == 2 else { throw CLIError.usage }
        try runCorpus(directory: URL(fileURLWithPath: arguments[1]))
    } else if arguments.count <= 1 {
        let path = arguments.first ?? "Tests/FT8ValidationTests/Fixtures"
        try runCorpus(directory: URL(fileURLWithPath: path))
    } else {
        throw CLIError.usage
    }
} catch {
    FileHandle.standardError.write(Data("ft8-validate: \(error)\n".utf8))
    exit(1)
}
