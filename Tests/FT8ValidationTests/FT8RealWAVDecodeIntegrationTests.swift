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

    private struct CandidateDiagnosticSummary {
        let candidatesFound: Int
        let candidatesScheduled: Int
        let tracesCaptured: Int
        let extractionFailures: Int
        let belowConfidenceThreshold: Int
        let ldpcAttempts: Int
        let parityPassed: Int
        let crcPassed: Int
        let messageDecodeFailures: Int
        let emptyMessagesRejected: Int
        let otherFailures: Int
        let averageSoftConfidence: Double
        let bestSoftConfidence: Double
        let lowestSyndromeWeight: Int?
    }

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

        let candidatesFound = result.metrics.passes.reduce(0) {
            $0 + $1.candidatesFound
        }
        let candidatesScheduled = result.metrics.passes.reduce(0) {
            $0 + $1.candidatesScheduled
        }

        XCTAssertGreaterThan(result.metrics.passesCompleted, 0)
        XCTAssertGreaterThan(candidatesFound, 0)
        XCTAssertGreaterThan(candidatesScheduled, 0)
        XCTAssertTrue(result.metrics.elapsedSeconds.isFinite)
        XCTAssertGreaterThan(result.metrics.elapsedSeconds, 0)
        XCTAssertTrue(
            result.messages.allSatisfy {
                !$0.decoded.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            }
        )

        print(
            """
            Real WAV baseline:
              recording: \(referenceCase.name)
              expected: \(expected.count)
              decoded: \(observed.count)
              matched: \(comparison.matched)
              missed: \(comparison.missed.count)
              unexpected: \(comparison.unexpected.count)
              candidates found: \(candidatesFound)
              candidates scheduled: \(candidatesScheduled)
              elapsed: \(result.metrics.elapsedSeconds)
            """
        )

        if observed.isEmpty {
            let diagnostics = try decodeCandidateDiagnostics(
                referenceCase.wavURL,
                expected: expected,
                recording: referenceCase.name
            )
            printCandidateDiagnostics(
                diagnostics,
                recording: referenceCase.name
            )
        }

        if let minimumMatchesText = ProcessInfo.processInfo.environment[
            "FT8_REAL_WAV_MINIMUM_MATCHES"
        ], let minimumMatches = Int(minimumMatchesText) {
            XCTAssertGreaterThanOrEqual(
                comparison.matched,
                max(0, minimumMatches),
                "Real WAV matches fell below FT8_REAL_WAV_MINIMUM_MATCHES."
            )
        }
    }

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
        var totalCandidatesFound = 0

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
            totalCandidatesFound += candidatesFound
        }

        XCTAssertEqual(results.count, cases.count)
        XCTAssertGreaterThan(totalExpected, 0)
        XCTAssertGreaterThan(totalCandidatesFound, 0)

        if let minimumMatchesText = ProcessInfo.processInfo.environment[
            "FT8_REAL_WAV_MINIMUM_TOTAL_MATCHES"
        ], let minimumMatches = Int(minimumMatchesText) {
            XCTAssertGreaterThanOrEqual(
                totalMatched,
                max(0, minimumMatches),
                "Corpus matches fell below FT8_REAL_WAV_MINIMUM_TOTAL_MATCHES."
            )
        }

        print(
            """
            Real WAV corpus baseline:
              recordings: \(results.count)
              expected: \(totalExpected)
              matched: \(totalMatched)
              candidates found: \(totalCandidatesFound)
            """
        )

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

    private func decodeCandidateDiagnostics(
        _ wavURL: URL,
        expected: [WSJTXExpectedDecode],
        recording recordingName: String
    ) throws -> CandidateDiagnosticSummary {
        let recording = try WAVFile.load(url: wavURL)
        let slotDecoder = FT8MultiPassSlotDecoder()
        let spectrogram = try Waterfall.analyse(
            samples: recording.samples,
            configuration: slotDecoder.waterfallConfiguration
        )

        var configuration =
            slotDecoder.decoder.decoder.configuration
        configuration.captureCandidateTraces = true
        configuration.capturePipelineRecords = true
        configuration.captureStageTimings = true

        let diagnosticDecoder = FT8OptimizedDecoder(
            configuration: configuration,
            synchronizer: slotDecoder.decoder.decoder.synchronizer,
            extractor: slotDecoder.decoder.decoder.extractor,
            ldpcDecoder: slotDecoder.decoder.decoder.ldpcDecoder,
            messageDecoder: slotDecoder.decoder.decoder.messageDecoder
        )

        let batch = try diagnosticDecoder.decode(
            spectrogram: spectrogram
        )
        let traces = batch.candidateTraces
        let softConfidences = traces.compactMap {
            $0.averageSoftSymbolConfidence.map(Double.init)
        }
        let syndromeWeights = traces.compactMap {
            $0.syndromeWeight
        }

        let parityReport = RealWAVParityDiagnostics.build(
            recording: recordingName,
            records: batch.pipelineRecords,
            expected: expected
        )
        RealWAVParityDiagnostics.printSummary(parityReport)

        let refinementReport = RealWAVFineHypothesisGrid.build(
            from: parityReport
        )
        RealWAVFineHypothesisGrid.printSummary(refinementReport)
        try RealWAVFineHypothesisGrid.exportIfRequested(
            refinementReport
        )

        let environment = ProcessInfo.processInfo.environment
        let fileManager = FileManager.default

        let jsonURL = environment["FT8_REAL_WAV_PARITY_JSON"]
            .flatMap { value -> URL? in
                let path = value.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                return path.isEmpty ? nil : URL(fileURLWithPath: path)
            }
        let csvURL = environment["FT8_REAL_WAV_PARITY_CSV"]
            .flatMap { value -> URL? in
                let path = value.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                return path.isEmpty ? nil : URL(fileURLWithPath: path)
            }

        for outputURL in [jsonURL, csvURL].compactMap({ $0 }) {
            try fileManager.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        try RealWAVParityDiagnostics.write(
            parityReport,
            jsonURL: jsonURL,
            csvURL: csvURL
        )

        if let jsonURL {
            XCTAssertTrue(
                fileManager.fileExists(atPath: jsonURL.path),
                "Parity JSON was not created at \(jsonURL.path)."
            )
            print("Real WAV parity JSON written to: \(jsonURL.path)")
        }

        if let csvURL {
            XCTAssertTrue(
                fileManager.fileExists(atPath: csvURL.path),
                "Parity CSV was not created at \(csvURL.path)."
            )
            print("Real WAV parity CSV written to: \(csvURL.path)")
        }

        let summary = CandidateDiagnosticSummary(
            candidatesFound: batch.metrics.candidatesFound,
            candidatesScheduled: batch.metrics.candidatesScheduled,
            tracesCaptured: traces.count,
            extractionFailures: traces.count {
                $0.failure?.hasPrefix("softSymbolExtraction:") == true
            },
            belowConfidenceThreshold: traces.count {
                $0.failure == "softSymbolConfidenceBelowThreshold"
            },
            ldpcAttempts: batch.metrics.ldpcAttempts,
            parityPassed: batch.metrics.parityPassed,
            crcPassed: batch.metrics.crcPassed,
            messageDecodeFailures: traces.count {
                $0.failure == "messageDecodeFailed"
            },
            emptyMessagesRejected: traces.count {
                $0.failure == "emptyMessageRejected"
            },
            otherFailures: traces.count {
                guard let failure = $0.failure else { return false }
                return !failure.hasPrefix("softSymbolExtraction:")
                    && failure != "softSymbolConfidenceBelowThreshold"
                    && failure != "messageDecodeFailed"
                    && failure != "emptyMessageRejected"
            },
            averageSoftConfidence: softConfidences.isEmpty
                ? 0
                : softConfidences.reduce(0, +)
                    / Double(softConfidences.count),
            bestSoftConfidence: softConfidences.max() ?? 0,
            lowestSyndromeWeight: syndromeWeights.min()
        )

        printTopCandidateDiagnostics(traces)
        return summary
    }

    private func printCandidateDiagnostics(
        _ summary: CandidateDiagnosticSummary,
        recording: String
    ) {
        let lowestSyndrome = summary.lowestSyndromeWeight.map(String.init)
            ?? "n/a"

        print(
            """
            Real WAV candidate diagnostics:
              recording: \(recording)
              candidates found: \(summary.candidatesFound)
              candidates scheduled: \(summary.candidatesScheduled)
              traces captured: \(summary.tracesCaptured)
              extraction failures: \(summary.extractionFailures)
              below soft-confidence threshold: \(summary.belowConfidenceThreshold)
              LDPC attempts: \(summary.ldpcAttempts)
              parity passed: \(summary.parityPassed)
              CRC passed: \(summary.crcPassed)
              message decode failures: \(summary.messageDecodeFailures)
              empty messages rejected: \(summary.emptyMessagesRejected)
              other failures: \(summary.otherFailures)
              average soft confidence: \(summary.averageSoftConfidence)
              best soft confidence: \(summary.bestSoftConfidence)
              lowest syndrome weight: \(lowestSyndrome)
            """
        )
    }

    private func printTopCandidateDiagnostics(
        _ traces: [FT8CandidateTrace]
    ) {
        let ordered = traces.sorted {
            let lhsCRC = $0.crcPassed == true
            let rhsCRC = $1.crcPassed == true
            if lhsCRC != rhsCRC {
                return lhsCRC
            }

            let lhsParity = $0.parityPassed == true
            let rhsParity = $1.parityPassed == true
            if lhsParity != rhsParity {
                return lhsParity
            }

            let lhsSyndrome = $0.syndromeWeight ?? .max
            let rhsSyndrome = $1.syndromeWeight ?? .max
            if lhsSyndrome != rhsSyndrome {
                return lhsSyndrome < rhsSyndrome
            }

            return ($0.averageSoftSymbolConfidence ?? 0)
                > ($1.averageSoftSymbolConfidence ?? 0)
        }

        print("Top real-WAV candidate traces:")

        for trace in ordered.prefix(10) {
            print(
                "  #\(trace.candidateIndex + 1)"
                    + " time=\(trace.startTime)"
                    + " frequency=\(trace.frequency)"
                    + " candidate=\(trace.candidateConfidence)"
                    + " soft=\(trace.averageSoftSymbolConfidence ?? 0)"
                    + " syndrome=\(trace.syndromeWeight.map(String.init) ?? "n/a")"
                    + " parity=\(trace.parityPassed.map(String.init) ?? "n/a")"
                    + " crc=\(trace.crcPassed.map(String.init) ?? "n/a")"
                    + " failure=\(trace.failure ?? "none")"
            )
        }
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
