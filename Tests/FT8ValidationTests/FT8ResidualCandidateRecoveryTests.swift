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

        let expected =
            try WSJTXReferenceParser.parse(
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

        slotDecoder.decoder.configuration =
            .init(
                enabled: true,
                maximumRecoveryPasses: 1,
                maximumSignalsPerPass: 1,
                minimumSyncScore: 0.34,
                minimumSNRDB: -3.0,
                maximumSynchronizerCandidates:
                    220,
                deduplicationTime: 0.060,
                deduplicationFrequency: 4.6875,
                minimumRelativeConfidence: 0.42,
                minimumPeakIsolation: 0,
                minimumCandidatesAfterPruning: 24,
                maximumCandidatesAfterPruning: 120,
                fineTimeSubdivisions: 8,
                fineFrequencySubdivisions: 8,
                fineTimeRadius: 0.160,
                fineFrequencyRadius: 12.5,
                maximumCandidatesToDecode: 100,
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
                    recording:
                        referenceCase.name,
                    pass: recoveryPass.pass,
                    expected: expected,
                    decodedMessages:
                        batch.messages.map {
                            $0.decoded.text
                        },
                    traces:
                        batch.candidateTraces
                )

        print(
            "Residual candidate recovery:"
        )
        print(
            "  base messages: "
                + String(
                    batch.baseBatch
                        .messages.count
                )
        )
        print(
            "  final messages: "
                + String(batch.messages.count)
        )
        print(
            "  recovery pass: "
                + String(recoveryPass.pass)
        )
        print(
            "  candidates found: "
                + String(
                    recoveryPass
                        .candidatesFound
                )
        )
        print(
            "  candidates scheduled: "
                + String(
                    recoveryPass
                        .candidatesScheduled
                )
        )
        print(
            "  parity passed: "
                + String(
                    recoveryPass
                        .parityPassed
                )
        )
        print(
            "  CRC passed: "
                + String(
                    recoveryPass.crcPassed
                )
        )
        print(
            "  new messages: "
                + String(
                    recoveryPass.newMessages
                )
        )

        for message in batch.messages {
            print(
                "  \"\(message.decoded.text)\""
                    + " time="
                    + String(
                        message.candidate
                            .startTime
                    )
                    + " frequency="
                    + String(
                        message.candidate
                            .frequency
                    )
                    + " parity="
                    + String(
                        message.ldpc
                            .parityPassed
                    )
                    + " crc="
                    + String(
                        message.ldpc
                            .crcPassed
                    )
            )
        }

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
