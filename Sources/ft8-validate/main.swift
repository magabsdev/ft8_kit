import Foundation
import FT8Decoder
import FT8DSP
import FT8Validation

private struct JSONDecode: Codable {
    let message: String
    let frequencyHz: Double
    let timeSeconds: Double
    let snrDB: Double
}

private struct WAVDiagnostics: Codable {
    let path: String
    let sampleRate: Int
    let sampleCount: Int
    let durationSeconds: Double
    let peakAmplitude: Double
    let rmsAmplitude: Double
}

private struct SpectrogramDiagnostics: Codable {
    let frames: Int
    let bins: Int
    let fftSize: Int
    let hopSize: Int
    let minimumFrequencyHz: Double
    let maximumFrequencyHz: Double
    let durationSeconds: Double
}

private struct PassDiagnostics: Codable {
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

private struct DecodeDiagnostics: Codable {
    let wav: WAVDiagnostics
    let spectrogram: SpectrogramDiagnostics
    let passesCompleted: Int
    let uniqueMessages: Int
    let totalSignalsCancelled: Int
    let totalAffectedBins: Int
    let elapsedSeconds: Double
    let passes: [PassDiagnostics]
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
        }
    }
}

private func analyseWAV(
    at url: URL,
    captureCandidateTraces: Bool = false
) throws -> (WAVRecording, Spectrogram, FT8MultiPassDecodeBatch) {
    func trace(_ message: String) {
        FileHandle.standardError.write(Data("[ft8-validate] \(message)\n".utf8))
    }

    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CLIError.missingPath(url.path)
    }

    trace("Loading WAV: \(url.path)")
    let recording = try WAVFile.load(url: url)
    trace(
        "WAV loaded: \(recording.samples.count) samples at " + "\(recording.sampleRate) Hz"
    )

    var slotDecoder = FT8MultiPassSlotDecoder()
    slotDecoder.decoder.decoder.configuration.captureCandidateTraces =
        captureCandidateTraces

    trace("Starting waterfall analysis")
    let waterfallStart = Date()

    let spectrogram = try Waterfall.analyse(
        samples: recording.samples,
        configuration: slotDecoder.waterfallConfiguration
    )

    trace(
        String(
            format: "Waterfall complete in %.3f s: %d rows × %d columns",
            Date().timeIntervalSince(waterfallStart),
            spectrogram.rowCount,
            spectrogram.columnCount
        )
    )

    trace("Starting FT8 decode")
    let decodeStart = Date()

    let result = try slotDecoder.decoder.decode(
        spectrogram: spectrogram
    )

    trace(
        String(
            format: "Decode complete in %.3f s: %d messages",
            Date().timeIntervalSince(decodeStart),
            result.messages.count
        )
    )

    return (recording, spectrogram, result)
}

private func observed(from result: FT8MultiPassDecodeBatch) -> [ObservedDecode] {
    result.messages.map {
        ObservedDecode(
            message: $0.decoded.text,
            frequencyHz: Double($0.candidate.frequency),
            timeOffset: $0.candidate.startTime,
            snrDB: Double($0.candidate.snrDB)
        )
    }
}

private func jsonMessages(from result: FT8MultiPassDecodeBatch) -> [JSONDecode] {
    result.messages.map {
        JSONDecode(
            message: $0.decoded.text,
            frequencyHz: Double($0.candidate.frequency),
            timeSeconds: $0.candidate.startTime,
            snrDB: Double($0.candidate.snrDB)
        )
    }
}

private func diagnostics(wavURL: URL,
                         recording: WAVRecording,
                         spectrogram: Spectrogram,
                         result: FT8MultiPassDecodeBatch) -> DecodeDiagnostics {
    let peak = recording.samples.map {
        abs(Double($0))
    }.max() ?? 0
    let rms = recording.samples.isEmpty ? 0: sqrt(
        recording.samples.reduce(0.0) {
            $0 + Double($1) * Double($1)
        } / Double(recording.samples.count)
    )
    return DecodeDiagnostics(
        wav: WAVDiagnostics(
            path: wavURL.path,
            sampleRate: recording.sampleRate,
            sampleCount: recording.samples.count,
            durationSeconds: Double(recording.samples.count) / Double(recording.sampleRate),
            peakAmplitude: peak,
            rmsAmplitude: rms
        ),
        spectrogram: SpectrogramDiagnostics(
            frames: spectrogram.rowCount,
            bins: spectrogram.columnCount,
            fftSize: spectrogram.fftSize,
            hopSize: spectrogram.hopSize,
            minimumFrequencyHz: Double(spectrogram.minimumFrequency),
            maximumFrequencyHz: Double(spectrogram.maximumFrequency),
            durationSeconds: spectrogram.duration
        ),
        passesCompleted: result.metrics.passesCompleted,
        uniqueMessages: result.metrics.uniqueMessages,
        totalSignalsCancelled: result.metrics.totalSignalsCancelled,
        totalAffectedBins: result.metrics.totalAffectedBins,
        elapsedSeconds: result.metrics.elapsedSeconds,
        passes: result.metrics.passes.map {
            PassDiagnostics(
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
        },
        messages: jsonMessages(from: result)
    )
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(value).write(to: url, options: .atomic)
}

private func dumpDebug(
    directoryPath: String,
    recording: WAVRecording,
    spectrogram: Spectrogram,
    report: DecodeDiagnostics,
    candidateTraces: [FT8CandidateTrace]
) throws {
    let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try writeJSON(report, to: directory.appendingPathComponent("metrics.json"))
    try writeJSON(report.messages, to: directory.appendingPathComponent("messages.json"))
    try writeJSON(
        candidateTraces,
        to: directory.appendingPathComponent("candidate-traces.json")
    )

    var waveform = "sample,time_seconds,amplitude\n"
    waveform.reserveCapacity(recording.samples.count * 24)
    for (index, sample) in recording.samples.enumerated() {
        waveform += "\(index),\(Double(index) / Double(recording.sampleRate)),\(sample)\n"
    }
    try waveform.write(to: directory.appendingPathComponent("waveform.csv"), atomically: true, encoding: .utf8)

    var waterfall = "frame,time_seconds,bin,frequency_hz,decibels,intensity,noise_floor_db\n"
    for frame in spectrogram.frames {
        for bin in frame.decibels.indices {
            waterfall += "\(frame.index),\(frame.time),\(bin),\(frame.frequency(at: bin)),\(frame.decibels[bin]),\(frame.intensities[bin]),\(frame.noiseFloorDB)\n"
        }
    }
    try waterfall.write(to: directory.appendingPathComponent("spectrogram.csv"), atomically: true, encoding: .utf8)
}

private func printHumanDiagnostics(_ report: DecodeDiagnostics) {
    print("Input")
    print("  Sample rate:           \(report.wav.sampleRate)")
    print("  Samples:               \(report.wav.sampleCount)")
    print(String(format: "  Duration:              %.3f s", report.wav.durationSeconds))
    print(String(format: "  Peak:                  %.6f", report.wav.peakAmplitude))
    print(String(format: "  RMS:                   %.6f", report.wav.rmsAmplitude))
    print("Spectrogram")
    print("  Frames:                \(report.spectrogram.frames)")
    print("  Bins:                  \(report.spectrogram.bins)")
    for pass in report.passes {
        print("Pass \(pass.pass)")
        print("  Candidates found:      \(pass.candidatesFound)")
        print("  Candidates scheduled:  \(pass.candidatesScheduled)")
        print("  Soft symbols:          \(pass.softSymbolsExtracted)")
        print("  LDPC attempts:         \(pass.ldpcAttempts)")
        print("  Parity passed:         \(pass.parityPassed)")
        print("  CRC passed:            \(pass.crcPassed)")
        print("  Messages decoded:      \(pass.messagesDecoded)")
    }
    print("Messages returned:       \(report.uniqueMessages)")
    print(String(format: "Elapsed:                 %.3f s", report.elapsedSeconds))
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
                throw CLIError.missingValue(argument)
            }
            options.dumpDirectory = arguments[index]
        default:
            guard !argument.hasPrefix("-"), options.wavPath == nil else {
                throw CLIError.usage
            }
            options.wavPath = argument
        }
        index += 1
    }
    guard options.wavPath != nil else {
        throw CLIError.usage
    }
    return options
}

private func runDecode(arguments: [String]) throws {
    let options = try parseDecodeOptions(arguments)
    guard let wavPath = options.wavPath else {
        throw CLIError.usage
    }

    let wavURL = URL(fileURLWithPath: wavPath)
    let (recording, spectrogram, result) = try analyseWAV(
        at: wavURL,
        captureCandidateTraces: options.dumpDirectory != nil
    )
    let report = diagnostics(wavURL: wavURL, recording: recording, spectrogram: spectrogram, result: result)

    if let directory = options.dumpDirectory {
        try dumpDebug(
            directoryPath: directory,
            recording: recording,
            spectrogram: spectrogram,
            report: report,
            candidateTraces: result.candidateTraces
        )
    }

    if options.diagnostics {
        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
        } else {
            printHumanDiagnostics(report)
        }
    } else if options.json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for item in report.messages {
            print(String(decoding: try encoder.encode(item), as: UTF8.self))
        }
    } else {
        for item in report.messages {
            print(item.message)
        }
    }
}

private func runCorpus(directory: URL) throws {
    guard FileManager.default.fileExists(atPath: directory.path) else {
        throw CLIError.missingPath(directory.path)
    }
    let cases = try ReferenceCorpus.discover(in: directory)
    print("Reference recordings: \(cases.count)")
    var expectedTotal = 0, decodedTotal = 0, matchedTotal = 0, missedTotal = 0, unexpectedTotal = 0
    for item in cases {
        let expected = try item.expectedURL.map(WSJTXReferenceParser.parse (url:)) ?? []
        expectedTotal += expected.count
        let (_, _, result) = try analyseWAV(at: item.wavURL)
        let decoded = observed(from: result)
        decodedTotal += decoded.count
        let comparison = ReferenceMatcher.compare(expected: expected, observed: decoded)
        matchedTotal += comparison.matched
        missedTotal += comparison.missed.count
        unexpectedTotal += comparison.unexpected.count
        print("\(item.name): expected \(expected.count), decoded \(decoded.count), matched \(comparison.matched)")
    }
    let rate = expectedTotal == 0 ? 100: Double(matchedTotal) / Double(expectedTotal) * 100
    print(String(format: "Expected: %d  Decoded: %d  Matched: %d  Missed: %d  Unexpected: %d  Detection: %.2f%%", expectedTotal, decodedTotal, matchedTotal, missedTotal, unexpectedTotal, rate))
}

do {
    print("FT8Kit diagnostics build 2026-07-31")
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "decode" {
        try runDecode(arguments: Array(arguments.dropFirst()))
    } else if arguments.first == "corpus" {
        guard arguments.count == 2 else {
            throw CLIError.usage
        }
        try runCorpus(directory: URL(fileURLWithPath: arguments[1]))
    } else if arguments.count <= 1 {
        try runCorpus(directory: URL(fileURLWithPath: arguments.first ?? "Tests/FT8ValidationTests/Fixtures"))
    } else {
        throw CLIError.usage
    }
} catch {
    FileHandle.standardError.write(Data("ft8-validate: \(error)\n".utf8))
    exit(1)
}
