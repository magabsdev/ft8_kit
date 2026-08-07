import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8RealWAVSymbolComparisonTests: XCTestCase {
    func testExportsRepresentativeRealWAVSymbolComparison() throws {
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
        let recording = try WAVFile.load(url: referenceCase.wavURL)

        let slotDecoder = FT8MultiPassSlotDecoder()
        let spectrogram = try Waterfall.analyse(
            samples: recording.samples,
            configuration: slotDecoder.waterfallConfiguration
        )

        var configuration = slotDecoder.decoder.decoder.configuration
        configuration.capturePipelineRecords = true

        let decoder = FT8OptimizedDecoder(
            configuration: configuration,
            synchronizer: slotDecoder.decoder.decoder.synchronizer,
            extractor: slotDecoder.decoder.decoder.extractor,
            ldpcDecoder: slotDecoder.decoder.decoder.ldpcDecoder,
            messageDecoder: slotDecoder.decoder.decoder.messageDecoder
        )
        let batch = try decoder.decode(spectrogram: spectrogram)

        let report = RealWAVSymbolComparator.buildReport(
            recording: referenceCase.name,
            records: batch.pipelineRecords,
            references: expected
        )

        XCTAssertGreaterThan(report.candidateCount, 0)
        XCTAssertEqual(
            report.symbolCount,
            report.candidateCount * FT8PipelineRecord.dataToneCount
        )
        XCTAssertTrue(
            report.rows.allSatisfy {
                $0.expectedGrayBits.count == 3
                    && $0.detectedGrayBits.count == 3
                    && $0.decodedBits.count == 3
                    && $0.soft0.isFinite
                    && $0.soft1.isFinite
                    && $0.soft2.isFinite
                    && $0.confidence.isFinite
            }
        )

        RealWAVSymbolComparisonExporter.printSummary(report)
        try RealWAVSymbolComparisonExporter.exportIfRequested(report)
    }
}
