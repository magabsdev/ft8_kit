import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8RealWAVGroundTruthSurfaceTests: XCTestCase {
    func testRefinesAllRepresentativeRealWAVReferences() throws {
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

        var decoderConfiguration =
            slotDecoder.decoder.decoder.configuration
        decoderConfiguration.capturePipelineRecords = true

        let decoder = FT8OptimizedDecoder(
            configuration: decoderConfiguration,
            synchronizer: slotDecoder.decoder.decoder.synchronizer,
            extractor: slotDecoder.decoder.decoder.extractor,
            ldpcDecoder: slotDecoder.decoder.decoder.ldpcDecoder,
            messageDecoder: slotDecoder.decoder.decoder.messageDecoder
        )

        let batch = try decoder.decode(spectrogram: spectrogram)

        let associationReport =
            RealWAVReferenceAssociator.buildReport(
                recording: referenceCase.name,
                records: batch.pipelineRecords,
                expected: expected
            )

        let report = try RealWAVGroundTruthSurfaceDiagnostics.buildReport(
            recording: referenceCase.name,
            spectrogram: spectrogram,
            extractor: decoder.extractor,
            synchronizer: decoder.synchronizer,
            records: batch.pipelineRecords,
            references: expected,
            associationReport: associationReport
        )

        XCTAssertEqual(
            report.refinedHypotheses.count,
            expected.count
        )

        XCTAssertEqual(
            Set(report.refinedHypotheses.map(\.referenceIndex)).count,
            expected.count
        )

        XCTAssertTrue(
            report.refinedHypotheses.allSatisfy {
                $0.costasTotal == 21
                    && $0.dataSymbolsTotal == 58
                    && $0.allSymbolsTotal == 79
            }
        )

        XCTAssertTrue(
            report.refinedHypotheses.allSatisfy {
                $0.refinedStartTime.isFinite
                    && $0.refinedFrequencyHz.isFinite
                    && $0.aggregateMarginDB.isFinite
                    && $0.aggregateExpectedMetricDB.isFinite
            }
        )

        RealWAVGroundTruthSurfaceExporter.printSummary(report)
        try RealWAVGroundTruthSurfaceExporter.exportIfRequested(report)
    }
}
