import Foundation
import FT8Decoder
import FT8Validation

let arguments = CommandLine.arguments
let directory = URL(fileURLWithPath: arguments.dropFirst().first ?? "Tests/FT8ValidationTests/Fixtures")
do {
    let cases = try ReferenceCorpus.discover(in: directory)
    print("Reference recordings: \(cases.count)")
    var expectedTotal = 0
    var decodedTotal = 0
    var matchedTotal = 0
    var missedTotal = 0
    var unexpectedTotal = 0
    let decoder = FT8MultiPassSlotDecoder()
    for item in cases {
        let recording = try WAVFile.load(url: item.wavURL)
        let expected = try item.expectedURL.map(WSJTXReferenceParser.parse(url:)) ?? []
        expectedTotal += expected.count
        let result = try decoder.decode(samples: recording.samples)
        let observed = result.messages.map { ObservedDecode(message: $0.decoded.text, frequencyHz: Double($0.candidate.frequency), timeOffset: $0.candidate.startTime, snrDB: Double($0.candidate.snrDB)) }
        decodedTotal += observed.count
        let comparison = ReferenceMatcher.compare(expected: expected, observed: observed)
        matchedTotal += comparison.matched; missedTotal += comparison.missed.count; unexpectedTotal += comparison.unexpected.count
        print("\(item.name): expected \(expected.count), decoded \(observed.count), matched \(comparison.matched)")
    }
    let rate = expectedTotal == 0 ? 100 : Double(matchedTotal) / Double(expectedTotal) * 100
    print(String(format: "Expected: %d  Decoded: %d  Matched: %d  Missed: %d  Unexpected: %d  Detection: %.2f%%", expectedTotal, decodedTotal, matchedTotal, missedTotal, unexpectedTotal, rate))
} catch {
    let message = "ft8-validate: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
