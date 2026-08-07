import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8RealWAVTimingCorrectedDecodeTests: XCTestCase {
    func testDecodesAtCalibratedWSJTXTimingConvention() throws {
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

        // Calibration checkpoint established a median WSJT-X -> FT8Kit
        // start-time correction of +0.47 seconds with only ~60 ms spread.
        let correction = 0.47

        let report =
            try RealWAVTimingCorrectedDecodeDiagnostics
                .buildReport(
                    recording: referenceCase.name,
                    spectrogram: spectrogram,
                    extractor:
                        slotDecoder.decoder.decoder.extractor,
                    ldpcDecoder:
                        slotDecoder.decoder.decoder.ldpcDecoder,
                    references: references,
                    timingCorrectionSeconds: correction
                )

        XCTAssertEqual(
            report.references.count,
            references.count
        )

        XCTAssertTrue(
            report.references.allSatisfy {
                $0.bitCount == 174
                    && $0.dataSymbolCount == 58
                    && $0.bitAccuracy.isFinite
                    && $0.dataSymbolAccuracy.isFinite
            }
        )

        RealWAVTimingCorrectedDecodeExporter
            .printSummary(report)

        try RealWAVTimingCorrectedDecodeExporter
            .exportIfRequested(report)
    }
}
