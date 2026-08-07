import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8RealWAVToneBinAlignmentTests: XCTestCase {
    func testExportsRepresentativeRealWAVToneBinAlignment() throws {
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

        let symbolReport = RealWAVSymbolComparator.buildReport(
            recording: referenceCase.name,
            records: batch.pipelineRecords,
            references: expected
        )

        let report = try RealWAVToneBinAlignmentDiagnostics.buildReport(
            recording: referenceCase.name,
            spectrogram: spectrogram,
            extractor: decoder.extractor,
            synchronizer: decoder.synchronizer,
            records: batch.pipelineRecords,
            symbolReport: symbolReport,
            neighbourhoodRadius: 2
        )

        XCTAssertGreaterThan(report.candidateCount, 0)
        XCTAssertGreaterThan(report.symbolCount, 0)

        XCTAssertTrue(
            report.rows.allSatisfy {
                $0.tones.count == 8
                    && $0.binWidthHz.isFinite
                    && $0.toneSpacingHz.isFinite
                    && $0.frameTimeErrorSeconds.isFinite
                    && $0.frameTimeErrorSamples.isFinite
                    && $0.appliedDriftHz.isFinite
            }
        )

        XCTAssertTrue(
            report.rows.allSatisfy { row in
                row.tones.allSatisfy {
                    $0.requestedFrequencyHz.isFinite
                        && $0.fractionalBin.isFinite
                        && $0.roundedBinFrequencyHz.isFinite
                        && $0.frequencyErrorHz.isFinite
                        && $0.neighbourhoodDB.allSatisfy(\.isFinite)
                }
            }
        )

        RealWAVToneBinAlignmentExporter.printSummary(report)
        try RealWAVToneBinAlignmentExporter.exportIfRequested(report)
    }
}
