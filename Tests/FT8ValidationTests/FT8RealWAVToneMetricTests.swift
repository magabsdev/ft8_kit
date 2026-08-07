import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8RealWAVToneMetricTests: XCTestCase {
    func testExportsRepresentativeRealWAVToneMetrics() throws {
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

        let report = try RealWAVToneMetricDiagnostics.buildReport(
            recording: referenceCase.name,
            sampleRate: recording.sampleRate,
            spectrogram: spectrogram,
            extractor: decoder.extractor,
            synchronizer: decoder.synchronizer,
            records: batch.pipelineRecords,
            symbolReport: symbolReport
        )

        XCTAssertGreaterThan(report.candidateCount, 0)
        XCTAssertGreaterThan(report.symbolCount, 0)
        XCTAssertEqual(
            report.symbolCount,
            report.candidateCount * FT8PipelineRecord.dataToneCount
        )

        XCTAssertTrue(
            report.rows.allSatisfy {
                $0.toneMetricsDB.count == 8
                    && $0.toneMetricsDB.allSatisfy(\.isFinite)
                    && $0.expectedToneMetricDB.isFinite
                    && $0.detectedToneMetricDB.isFinite
                    && $0.winningMetricDB.isFinite
                    && $0.runnerUpMetricDB.isFinite
                    && $0.winningMarginDB.isFinite
                    && $0.expectedBinFrequencyHz.isFinite
                    && $0.winningBinFrequencyHz.isFinite
                    && $0.expectedTargetFrequencyHz.isFinite
                    && $0.winningTargetFrequencyHz.isFinite
            }
        )

        XCTAssertTrue(
            report.rows.allSatisfy {
                $0.detectedTone == $0.winningTone
            }
        )

        RealWAVToneMetricExporter.printSummary(report)
        try RealWAVToneMetricExporter.exportIfRequested(report)
    }
}
