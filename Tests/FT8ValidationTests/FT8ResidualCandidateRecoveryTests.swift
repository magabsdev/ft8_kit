import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8ResidualCandidateRecoveryTests:
    XCTestCase
{
    func testResidualCandidateRecoveryOnRepresentativeRealWAV()
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
        let expected = try WSJTXReferenceParser.parse(
            url: expectedURL
        )
        let recording = try WAVFile.load(
            url: referenceCase.wavURL
        )

        var slotDecoder =
            FT8ResidualRecoverySlotDecoder()

        slotDecoder.decoder
            .baseDecoder.configuration =
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

        slotDecoder.decoder
            .baseDecoder.canceller.configuration =
            .init(
                cancellationStrength: 1.00,
                binRadius: 1,
                timeTaperFloor: 0.50,
                preserveNoiseFloor: true
            )

        slotDecoder.decoder
            .baseDecoder.decoder.configuration
            .captureCandidateTraces = true

        // Performance-safe residual recovery profile.
        //
        // The previous checkpoint used global fine search with 220 candidates,
        // 8× time subdivisions, 8× frequency subdivisions and wide radii.
        // FT8Synchronizer refines up to maximumCandidates*3 seeds, so that
        // profile can generate millions of Costas correlation evaluations.
        slotDecoder.decoder.configuration =
            .init(
                enabled: true,
                maximumRecoveryPasses: 1,
                maximumSignalsPerPass: 1,
                minimumSyncScore: 0.34,
                minimumSNRDB: -3.0,
                maximumSynchronizerCandidates: 120,
                deduplicationTime: 0.060,
                deduplicationFrequency: 4.6875,
                minimumRelativeConfidence: 0.42,
                minimumPeakIsolation: 0,
                minimumCandidatesAfterPruning: 24,
                maximumCandidatesAfterPruning: 90,
                enableGlobalFineSearch: false,
                maximumCandidatesToDecode: 80,
                minimumCandidateConfidence: 0.05,
                minimumSoftSymbolConfidence: 0.05,
                disableRobustLDPC: true
            )

        let batch = try slotDecoder.decode(
            samples: recording.samples
        )

        let recoveryPass = try XCTUnwrap(
            batch.recoveryPasses.first
        )

        let report =
            RealWAVResidualWeakCandidateDiagnostics
                .build(
                    recording: referenceCase.name,
                    pass: recoveryPass.pass,
                    expected: expected,
                    decodedMessages:
                        batch.messages.map {
                            $0.decoded.text
                        },
                    traces:
                        batch.candidateTraces
                )

        print("Residual candidate recovery:")
        print(
            "  base messages: "
                + "\(batch.baseBatch.messages.count)"
        )
        print(
            "  final messages: "
                + "\(batch.messages.count)"
        )
        print(
            "  recovery pass: \(recoveryPass.pass)"
        )
        print(
            "  candidates found: "
                + "\(recoveryPass.candidatesFound)"
        )
        print(
            "  candidates scheduled: "
                + "\(recoveryPass.candidatesScheduled)"
        )
        print(
            "  parity passed: "
                + "\(recoveryPass.parityPassed)"
        )
        print(
            "  CRC passed: "
                + "\(recoveryPass.crcPassed)"
        )
        print(
            "  new messages: "
                + "\(recoveryPass.newMessages)"
        )
        print(
            "  recovery elapsed: "
                + "\(recoveryPass.elapsedSeconds)"
        )

        RealWAVResidualWeakCandidateDiagnostics
            .printSummary(report)

        try RealWAVResidualWeakCandidateExporter
            .exportIfRequested(report)

        XCTAssertGreaterThanOrEqual(
            batch.messages.count,
            batch.baseBatch.messages.count
        )
        XCTAssertGreaterThan(
            recoveryPass.candidatesFound,
            0
        )
        XCTAssertGreaterThan(
            recoveryPass.candidatesScheduled,
            0
        )
    }
}
