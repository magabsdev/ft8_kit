import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8ReferenceCandidateAssociationTests: XCTestCase {
    func testAssociatesRepresentativeRealWAVCandidatesOneToOne() throws {
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

        let report = RealWAVReferenceAssociator.buildReport(
            recording: referenceCase.name,
            records: batch.pipelineRecords,
            expected: expected
        )

        XCTAssertEqual(report.referenceCount, expected.count)
        XCTAssertEqual(
            report.candidateCount,
            batch.pipelineRecords.count
        )

        XCTAssertGreaterThan(report.primaryAssociations.count, 0)
        XCTAssertLessThanOrEqual(
            report.primaryAssociations.count,
            expected.count
        )

        XCTAssertEqual(
            Set(report.primaryAssociations.map(\.referenceIndex)).count,
            report.primaryAssociations.count
        )

        XCTAssertEqual(
            Set(report.primaryAssociations.map(\.candidateIndex)).count,
            report.primaryAssociations.count
        )

        XCTAssertTrue(
            report.primaryAssociations.allSatisfy {
                $0.timeDelta
                    <= report.configuration.matchedTimeTolerance
                    && $0.frequencyDeltaHz
                    <= report.configuration.matchedFrequencyToleranceHz
            }
        )

        XCTAssertEqual(
            report.matchedCount
                + report.nearMatchCount
                + report.unassociatedCount,
            report.candidateCount
        )

        RealWAVReferenceAssociationExporter.printSummary(report)
        try RealWAVReferenceAssociationExporter.exportIfRequested(report)
    }
}
