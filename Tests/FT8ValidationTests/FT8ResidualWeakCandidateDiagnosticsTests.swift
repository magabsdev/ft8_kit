import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8ResidualWeakCandidateDiagnosticsTests:
    XCTestCase
{
    func testDiagnosesRemainingReferencesAfterProductionCancellation()
        throws
    {
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

        let expected =
            try WSJTXReferenceParser.parse(
                url: expectedURL
            )

        let recording = try WAVFile.load(
            url: referenceCase.wavURL
        )

        var slotDecoder = FT8MultiPassSlotDecoder()

        slotDecoder.decoder.configuration =
            .init(
                maximumPasses: 3,
                maximumSignalsPerPass: 1,
                minimumNewMessages: 1,
                minimumEnergyReductionFraction:
                    0.001,
                stopWhenNoNewMessages: true,
                suppressDuplicatePayloadAcrossPasses:
                    true,
                disableRobustLDPCOnResidualPasses:
                    true,
                residualMaximumCandidatesToDecode:
                    60
            )

        slotDecoder.decoder.canceller.configuration =
            .init(
                cancellationStrength: 1.00,
                binRadius: 1,
                timeTaperFloor: 0.50,
                preserveNoiseFloor: true
            )

        // Capture per-candidate state from all passes. Pass 3 is the important
        // residual after R7IW and TA6CQ have both been removed.
        slotDecoder.decoder.decoder.configuration
            .captureCandidateTraces = true

        slotDecoder.decoder.decoder.configuration
            .capturePipelineRecords = false

        slotDecoder.decoder.decoder.configuration
            .captureStageTimings = false

        let batch = try slotDecoder.decode(
            samples: recording.samples
        )

        XCTAssertGreaterThanOrEqual(
            batch.metrics.passesCompleted,
            3
        )

        let report =
            RealWAVResidualWeakCandidateDiagnostics
                .build(
                    recording:
                        referenceCase.name,
                    pass: 3,
                    expected: expected,
                    decodedMessages:
                        batch.messages.map {
                            $0.decoded.text
                        },
                    traces:
                        batch.candidateTraces
                )

        RealWAVResidualWeakCandidateDiagnostics
            .printSummary(report)

        try RealWAVResidualWeakCandidateExporter
            .exportIfRequested(report)

        XCTAssertEqual(
            report.expectedReferenceCount,
            expected.count
        )

        XCTAssertEqual(
            report.passCandidateCount,
            batch.candidateTraces.count {
                $0.pass == 3
            }
        )

        XCTAssertEqual(
            report.remainingReferenceCount,
            max(
                expected.count
                    - batch.messages.count,
                0
            )
        )

        XCTAssertGreaterThan(
            report.passCandidateCount,
            0
        )
    }
}
