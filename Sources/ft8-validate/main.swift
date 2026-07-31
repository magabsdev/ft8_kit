import Foundation
import FT8Decoder
import FT8Validation

private struct JSONDecode: Codable {
    let message: String
    let frequencyHz: Double
    let timeSeconds: Double
    let snrDB: Double
}

private enum CLIError: Error, CustomStringConvertible {
    case usage
    case missingPath(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage:\n  ft8-validate [corpus-directory]\n  ft8-validate corpus <directory>\n  ft8-validate decode --json <wav-file>"
        case .missingPath(let path):
            return "Path does not exist: \(path)"
        }
    }
}

private func decodeWAV(at url: URL) throws -> [ObservedDecode] {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CLIError.missingPath(url.path)
    }
    let recording = try WAVFile.load(url: url)
    let decoder = FT8MultiPassSlotDecoder()
    let result = try decoder.decode(samples: recording.samples)
    return result.messages.map {
        ObservedDecode(
            message: $0.decoded.text,
            frequencyHz: Double($0.candidate.frequency),
            timeOffset: $0.candidate.startTime,
            snrDB: Double($0.candidate.snrDB)
        )
    }
}

private func runJSONDecode(wavPath: String) throws {
    let observed = try decodeWAV(at: URL(fileURLWithPath: wavPath))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    for item in observed {
        let payload = JSONDecode(
            message: item.message,
            frequencyHz: item.frequencyHz,
            timeSeconds: item.timeOffset,
            snrDB: item.snrDB ?? 0
        )
        let data = try encoder.encode(payload)
        print(String(decoding: data, as: UTF8.self))
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

        let observed = try decodeWAV(at: item.wavURL)
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
        guard arguments.count == 3, arguments[1] == "--json" else { throw CLIError.usage }
        try runJSONDecode(wavPath: arguments[2])
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
