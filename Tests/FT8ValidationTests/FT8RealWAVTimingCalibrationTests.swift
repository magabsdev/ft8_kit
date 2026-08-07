import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8RealWAVTimingCalibrationTests: XCTestCase {
    func testCalibratesWSJTXTimingConvention() throws {
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

        let expectedURL = try XCTUnwrap(
            referenceCase.expectedURL
        )

        let references =
            try WSJTXReferenceParser.parse(
                url: expectedURL
            )

        let recording = try WAVFile.load(
            url: referenceCase.wavURL
        )

        let slotDecoder = FT8MultiPassSlotDecoder()

        let spectrogram = try Waterfall.analyse(
            samples: recording.samples,
            configuration:
                slotDecoder.waterfallConfiguration
        )

        let report =
            try RealWAVTimingCalibrationDiagnostics
                .buildReport(
                    recording:
                        referenceCase.name,
                    spectrogram:
                        spectrogram,
                    extractor:
                        slotDecoder.decoder.decoder
                            .extractor,
                    references:
                        references,
                    configuration:
                        .init(
                            minimumCorrectionSeconds:
                                -0.50,
                            maximumCorrectionSeconds:
                                0.50,
                            stepSeconds:
                                0.01
                        )
                )

        XCTAssertEqual(
            report.references.count,
            references.count
        )

        XCTAssertEqual(
            report.points.count,
            references.count * 101
        )

        XCTAssertTrue(
            report.consensusCorrectionSeconds
                .isFinite
        )

        XCTAssertTrue(
            report.references.allSatisfy {
                $0.bestCorrectToneCount
                    >= $0.baselineCorrectToneCount
                    && $0.bestToneAccuracy.isFinite
                    && $0.bestDataToneAccuracy.isFinite
                    && $0.bestCostasToneAccuracy.isFinite
            }
        )

        RealWAVTimingCalibrationExporter
            .printSummary(report)

        try RealWAVTimingCalibrationExporter
            .exportIfRequested(report)
    }
}
