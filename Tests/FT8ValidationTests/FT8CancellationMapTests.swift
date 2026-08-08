import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8CancellationMapTests: XCTestCase {
    func testMapsExperimentalAndProductionCancellationFootprints()
        throws
    {
        try RealWAVTestGate.requireEnabled()


        let fixtureDirectory = try XCTUnwrap(
            Bundle.module.resourceURL?
                .appendingPathComponent(
                    "Fixtures",
                    isDirectory: true
                )
        )

        let referenceCase = try XCTUnwrap(
            try ReferenceCorpus.discover(
                in: fixtureDirectory
            ).first {
                $0.name == "191111_110130"
            }
        )

        let recording = try WAVFile.load(
            url: referenceCase.wavURL
        )

        let slotDecoder = FT8MultiPassSlotDecoder()

        let spectrogram = try Waterfall.analyse(
            samples: recording.samples,
            configuration: slotDecoder.waterfallConfiguration
        )

        // One first-pass decode only. There is no residual LDPC decode here,
        // so this checkpoint remains close to the normal first-pass runtime.
        var decoder = slotDecoder.decoder.decoder
        decoder.configuration.captureCandidateTraces = false
        decoder.configuration.capturePipelineRecords = false
        decoder.configuration.captureStageTimings = false

        let first = try decoder.decode(
            spectrogram: spectrogram
        )

        XCTAssertFalse(first.messages.isEmpty)

        let selected = try XCTUnwrap(
            first.messages.min {
                abs($0.candidate.frequency - 1291)
                    < abs($1.candidate.frequency - 1291)
            }
        )

        XCTAssertTrue(selected.ldpc.parityPassed)
        XCTAssertTrue(selected.ldpc.crcPassed)

        let report = try RealWAVCancellationMapDiagnostics.build(
            recording: referenceCase.name,
            decode: selected,
            spectrogram: spectrogram,
            binRadius: 1,
            strength: 1.00,
            timeTaperFloor: 0.50
        )

        RealWAVCancellationMapDiagnostics.printSummary(
            report
        )

        try RealWAVCancellationMapExporter
            .exportIfRequested(report)

        XCTAssertEqual(report.symbolCount, 79)
        XCTAssertGreaterThan(
            report.experimentalTouchCount,
            0
        )
        XCTAssertGreaterThan(
            report.productionTouchCount,
            0
        )

        // The previous equivalence test found the production footprint much
        // larger. This checkpoint maps why rather than failing on the mismatch.
        XCTAssertGreaterThanOrEqual(
            report.productionTouchCount,
            report.experimentalTouchCount
        )
        XCTAssertTrue(
            report.productionToExperimentalTouchRatio
                .isFinite
        )
    }
}
