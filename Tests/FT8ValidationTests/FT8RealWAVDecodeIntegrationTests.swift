import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8RealWAVDecodeIntegrationTests: XCTestCase {
    private struct CorpusResult: Codable {
        let recording: String
        let expectedCount: Int
        let decodedCount: Int
        let matchedCount: Int
        let missedCount: Int
        let unexpectedCount: Int
        let candidatesFound: Int
        let candidatesScheduled: Int
        let elapsedSeconds: Double
    }

    /// Runs in the normal test suite so a real receiver recording always
    /// exercises WAV loading, waterfall generation, synchronisation, soft
    /// symbols, LDPC decoding and message decoding.
    func testRepresentativeRealWAVCompletesDecoderPipeline() async throws {
        let fixtureDirectory = try fixturesDirectory()
        let referenceCase = try XCTUnwrap(
            try ReferenceCorpus.discover(in: fixtureDirectory).first {
                $0.name == "191111_110130"
            }
        )

        let expectedURL = try XCTUnwrap(referenceCase.expectedURL)
        let expected = try WSJTXReferenceParser.parse(url: expectedURL)
        XCTAssertFalse(expected.isEmpty)

        let result = try await decode(referenceCase.wavURL)
        let observed = observedDecodes(from: result)
        let comparison = ReferenceMatcher.compare(
            expected: expected,
            observed: observed
        )

        XCTAssertGreaterThan(result.metrics.passesCompleted, 0)
        XCTAssertGreaterThan(
            result.metrics.passes.reduce(0) { $0 + $1.candidatesFound },
            0
        )
        XCTAssertTrue(result.metrics.elapsedSeconds.isFinite)
        XCTAssertGreaterThan(result.metrics.elapsedSeconds, 0)
        XCTAssertTrue(
            result.messages.allSatisfy {
                !$0.decoded.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            }
        )

        // The current real-recording floor is deliberately conservative.
        // Raising this value becomes a controlled decoder-quality checkpoint,
        // rather than silently depending only on synthetic waveforms.
        XCTAssertGreaterThanOrEqual(
            comparison.matched,
            1,
            "The representative real WAV must retain at least one WSJT-X reference decode."
        )
    }

    /// Full 31-recording corpus run. It is intentionally opt-in because it is
    /// substantially slower than the regular unit suite.
    ///
    /// Run with:
    /// FT8_RUN_REAL_WAV_CORPUS=1 swift test --filter FT8RealWAVDecodeIntegrationTests/testCompleteRealWAVCorpus
    ///
    /// Optional report destination:
    /// FT8_REAL_WAV_REPORT=/absolute/path/real-wav-corpus.json
    func testCompleteRealWAVCorpus() async throws {
        guard ProcessInfo.processInfo.environment[
            "FT8_RUN_REAL_WAV_CORPUS"
        ] == "1" else {
            throw XCTSkip(
                "Set FT8_RUN_REAL_WAV_CORPUS=1 to run all real WAV fixtures."
            )
        }

        let fixtureDirectory = try fixturesDirectory()
        let cases = try ReferenceCorpus.discover(in: fixtureDirectory)
        XCTAssertEqual(cases.count, 31)

        var results: [CorpusResult] = []
        var totalExpected = 0
        var totalMatched = 0

        for referenceCase in cases {
            let expected = try referenceCase.expectedURL.map {
                try WSJTXReferenceParser.parse(url: $0)
            } ?? []

            let batch = try await decode(referenceCase.wavURL)
            let observed = observedDecodes(from: batch)
            let comparison = ReferenceMatcher.compare(
                expected: expected,
                observed: observed
            )

            let candidatesFound = batch.metrics.passes.reduce(0) {
                $0 + $1.candidatesFound
            }
            let candidatesScheduled = batch.metrics.passes.reduce(0) {
                $0 + $1.candidatesScheduled
            }

            results.append(
                CorpusResult(
                    recording: referenceCase.name,
                    expectedCount: expected.count,
                    decodedCount: observed.count,
                    matchedCount: comparison.matched,
                    missedCount: comparison.missed.count,
                    unexpectedCount: comparison.unexpected.count,
                    candidatesFound: candidatesFound,
                    candidatesScheduled: candidatesScheduled,
                    elapsedSeconds: batch.metrics.elapsedSeconds
                )
            )

            totalExpected += expected.count
            totalMatched += comparison.matched
        }

        XCTAssertEqual(results.count, cases.count)
        XCTAssertGreaterThan(totalExpected, 0)
        XCTAssertGreaterThan(totalMatched, 0)

        if let path = ProcessInfo.processInfo.environment[
            "FT8_REAL_WAV_REPORT"
        ], !path.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(
                to: URL(fileURLWithPath: path),
                options: .atomic
            )
        }
    }

    private func fixturesDirectory() throws -> URL {
        try XCTUnwrap(
            Bundle.module.resourceURL?.appendingPathComponent(
                "Fixtures",
                isDirectory: true
            )
        )
    }

    private func decode(
        _ wavURL: URL
    ) async throws -> FT8MultiPassDecodeBatch {
        let recording = try WAVFile.load(url: wavURL)
        XCTAssertEqual(recording.sampleRate, 12_000)
        XCTAssertFalse(recording.samples.isEmpty)

        let slotDecoder = FT8MultiPassSlotDecoder()
        let spectrogram = try Waterfall.analyse(
            samples: recording.samples,
            configuration: slotDecoder.waterfallConfiguration
        )

        let parallelDecoder = FT8ParallelMultiPassDecoder(
            configuration: slotDecoder.decoder.configuration,
            decoder: FT8ParallelDecoder(
                optimizedConfiguration:
                    slotDecoder.decoder.decoder.configuration,
                synchronizer:
                    slotDecoder.decoder.decoder.synchronizer,
                extractor:
                    slotDecoder.decoder.decoder.extractor,
                ldpcDecoder:
                    slotDecoder.decoder.decoder.ldpcDecoder,
                messageDecoder:
                    slotDecoder.decoder.decoder.messageDecoder
            ),
            canceller: slotDecoder.decoder.canceller
        )

        return try await parallelDecoder.decode(
            spectrogram: spectrogram
        )
    }

    private func observedDecodes(
        from result: FT8MultiPassDecodeBatch
    ) -> [ObservedDecode] {
        result.messages.map {
            ObservedDecode(
                message: $0.decoded.text,
                frequencyHz: Double($0.candidate.frequency),
                timeOffset: $0.candidate.startTime,
                snrDB: Double($0.candidate.snrDB)
            )
        }
    }
}

