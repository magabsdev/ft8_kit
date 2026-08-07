import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8RealWAVOracleLLRTests: XCTestCase {
    func testDumpsOracleLLRsForRepresentativeRealWAV() throws {
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
        let references = try WSJTXReferenceParser.parse(
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
            try RealWAVOracleLLRDiagnostics.buildReport(
                recording: referenceCase.name,
                spectrogram: spectrogram,
                extractor:
                    slotDecoder.decoder.decoder.extractor,
                ldpcDecoder:
                    slotDecoder.decoder.decoder.ldpcDecoder,
                references: references
            )

        XCTAssertEqual(
            report.references.count,
            references.count
        )

        XCTAssertEqual(
            report.bits.count,
            references.count * 174
        )

        XCTAssertTrue(
            report.references.allSatisfy {
                $0.bitCount == 174
                    && $0.dataSymbolCount == 58
                    && $0.bitAccuracy.isFinite
                    && $0.dataSymbolAccuracy.isFinite
            }
        )

        RealWAVOracleLLRExporter.printSummary(report)
        try RealWAVOracleLLRExporter.exportIfRequested(
            report
        )
    }
}
