import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8RealWAVLLRTests: XCTestCase {
    func testExportsRepresentativeRealWAVLLRAnalysis() throws {
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

        let report = try RealWAVLLRDiagnostics.buildReport(
            recording: referenceCase.name,
            spectrogram: spectrogram,
            extractor: decoder.extractor,
            synchronizer: decoder.synchronizer,
            records: batch.pipelineRecords,
            symbolReport: symbolReport
        )

        XCTAssertGreaterThan(report.candidateCount, 0)
        XCTAssertGreaterThan(report.rows.count, 0)
        XCTAssertEqual(
            report.rows.count,
            symbolReport.rows.count * 3
        )

        XCTAssertTrue(
            report.rows.allSatisfy {
                $0.toneMetricsDB.count == 8
                    && $0.toneMetricsDB.allSatisfy(\.isFinite)
                    && $0.winningMetricDB.isFinite
                    && $0.runnerUpMetricDB.isFinite
                    && $0.winningMarginDB.isFinite
                    && $0.bestZeroMetricDB.isFinite
                    && $0.bestOneMetricDB.isFinite
                    && $0.rawMetricDifference.isFinite
                    && $0.recomputedLLR.isFinite
                    && $0.recordedLLR.isFinite
                    && $0.llrDelta.isFinite
                    && $0.llrMagnitude.isFinite
            }
        )

        XCTAssertLessThanOrEqual(
            report.summary.maximumAbsoluteRecomputedVsRecordedDelta,
            0.000_001
        )

        XCTAssertEqual(
            report.summary.correctDecodedBits
                + report.summary.incorrectDecodedBits,
            report.summary.bitCount
        )

        XCTAssertEqual(
            report.summary.correctLLRSigns
                + report.summary.incorrectLLRSigns,
            report.summary.bitCount
        )

        RealWAVLLRExporter.printSummary(report)
        try RealWAVLLRExporter.exportIfRequested(report)
    }
}
