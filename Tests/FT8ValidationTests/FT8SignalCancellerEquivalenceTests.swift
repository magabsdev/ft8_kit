import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8SignalCancellerEquivalenceTests: XCTestCase {
    func testExperimentalAndProductionCancellationResiduals() throws {
        let fixtureDirectory = try XCTUnwrap(
            Bundle.module.resourceURL?.appendingPathComponent("Fixtures", isDirectory: true)
        )
        let referenceCase = try XCTUnwrap(
            try ReferenceCorpus.discover(in: fixtureDirectory).first { $0.name == "191111_110130" }
        )
        let recording = try WAVFile.load(url: referenceCase.wavURL)
        let slotDecoder = FT8MultiPassSlotDecoder()
        let spectrogram = try Waterfall.analyse(samples: recording.samples, configuration: slotDecoder.waterfallConfiguration)

        var decoder = slotDecoder.decoder.decoder
        decoder.configuration.captureCandidateTraces = false
        decoder.configuration.capturePipelineRecords = false
        decoder.configuration.captureStageTimings = false

        let first = try decoder.decode(spectrogram: spectrogram)
        XCTAssertFalse(first.messages.isEmpty)

        let selected = try XCTUnwrap(
            first.messages.min {
                abs($0.candidate.frequency - 1291) < abs($1.candidate.frequency - 1291)
            }
        )
        XCTAssertTrue(selected.ldpc.parityPassed)
        XCTAssertTrue(selected.ldpc.crcPassed)

        let experimental = try RealWAVFastCancellationEvaluator.cancel(
            selected,
            from: spectrogram,
            profile: .init(radiusBins: 1, strength: 1.00, timeTaperFloor: 0.50)
        )

        var productionCanceller = slotDecoder.decoder.canceller
        productionCanceller.configuration = .init(
            cancellationStrength: 1.00,
            binRadius: 1,
            timeTaperFloor: 0.50,
            preserveNoiseFloor: true
        )

        let production = try productionCanceller.cancel([selected], from: spectrogram)

        let report = try RealWAVCancellerEquivalenceDiagnostics.buildReport(
            recording: referenceCase.name,
            decode: selected,
            original: spectrogram,
            experimental: experimental,
            production: production,
            synchronizer: decoder.synchronizer
        )

        RealWAVCancellerEquivalenceDiagnostics.printSummary(report)
        try RealWAVCancellerEquivalenceExporter.exportIfRequested(report)

        XCTAssertGreaterThan(report.experimentalAffectedBins, 0)
        XCTAssertGreaterThan(report.productionAffectedBins, 0)
        XCTAssertTrue(report.relativeRMSError.isFinite)
        XCTAssertTrue(report.experimentalReductionFraction.isFinite)
        XCTAssertTrue(report.productionReductionFraction.isFinite)

        // Diagnostic checkpoint: do not assert equality yet. This run is
        // deliberately designed to quantify the production-vs-experimental
        // mismatch so the following checkpoint can remove it precisely.
    }
}
