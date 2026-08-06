import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8AdaptiveFineDecodeIntegrationTests: XCTestCase {
    func testAdaptiveFineDecodeSearchesRealWAVHypotheses() throws {
        let fixtureDirectory = try XCTUnwrap(
            Bundle.module.resourceURL?.appendingPathComponent(
                "Fixtures",
                isDirectory: true
            )
        )
        let referenceCase = try XCTUnwrap(
            try ReferenceCorpus.discover(in: fixtureDirectory).first {
                $0.name == "191111_110130"
            }
        )
        let expectedURL = try XCTUnwrap(referenceCase.expectedURL)
        let expected = try WSJTXReferenceParser.parse(url: expectedURL)
        XCTAssertFalse(expected.isEmpty)

        let recording = try WAVFile.load(url: referenceCase.wavURL)
        XCTAssertEqual(recording.sampleRate, 12_000)
        XCTAssertFalse(recording.samples.isEmpty)

        let slotDecoder = FT8MultiPassSlotDecoder()
        let spectrogram = try Waterfall.analyse(
            samples: recording.samples,
            configuration: slotDecoder.waterfallConfiguration
        )

        var configuration = slotDecoder.decoder.decoder.configuration
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
        let diagnosticBatch = try diagnosticDecoder.decode(
            spectrogram: spectrogram
        )

        let parityReport = RealWAVParityDiagnostics.build(
            recording: referenceCase.name,
            records: diagnosticBatch.pipelineRecords,
            expected: expected
        )
        XCTAssertGreaterThan(
            parityReport.paritySuccessCount,
            0,
            "The adaptive stage requires at least one zero-syndrome candidate."
        )

        let refinementReport = RealWAVFineHypothesisGrid.build(
            from: parityReport
        )
        XCTAssertFalse(
            refinementReport.candidates.isEmpty,
            "No parity candidate qualified for bounded fine refinement."
        )
        XCTAssertGreaterThan(refinementReport.totalPointCount, 0)

        let adaptiveReport = RealWAVAdaptiveFineDecoder.decode(
            recording: referenceCase.name,
            spectrogram: spectrogram,
            refinementReport: refinementReport,
            extractor: slotDecoder.decoder.decoder.extractor,
            ldpcDecoder: slotDecoder.decoder.decoder.ldpcDecoder,
            messageDecoder: slotDecoder.decoder.decoder.messageDecoder
        )

        XCTAssertEqual(
            adaptiveReport.candidateCount,
            refinementReport.candidates.count
        )
        XCTAssertEqual(
            adaptiveReport.plannedAttemptCount,
            refinementReport.totalPointCount
        )
        XCTAssertGreaterThan(adaptiveReport.completedAttemptCount, 0)
        XCTAssertLessThanOrEqual(
            adaptiveReport.completedAttemptCount,
            adaptiveReport.plannedAttemptCount
        )

        RealWAVAdaptiveFineDecoder.printSummary(adaptiveReport)
        try RealWAVAdaptiveFineDecoder.exportIfRequested(adaptiveReport)

        if let minimumText = ProcessInfo.processInfo.environment[
            "FT8_REAL_WAV_MINIMUM_ADAPTIVE_MATCHES"
        ], let minimum = Int(minimumText) {
            XCTAssertGreaterThanOrEqual(
                adaptiveReport.winners.count,
                max(0, minimum),
                "Adaptive real-WAV recoveries fell below "
                    + "FT8_REAL_WAV_MINIMUM_ADAPTIVE_MATCHES."
            )
        }
    }
}
