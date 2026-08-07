import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8CandidateGuidedFineDecodeTests:
    XCTestCase
{
    func testCandidateGuidedFineDecodeOnRepresentativeRealWAV()
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

        let recording = try WAVFile.load(
            url: referenceCase.wavURL
        )

        let spectrogram =
            try Waterfall.analyse(
                samples: recording.samples,
                configuration: .init(
                    sampleRate: 12_000,
                    fftSize: 1_920,
                    hopSize: 480,
                    minimumFrequency: 100,
                    maximumFrequency: 3_000,
                    dynamicRange: 100
                )
            )

        print("[FineDecodeTest] Running one baseline pass only")

        var base =
            FT8MultiPassDecoder()

        // This checkpoint is specifically testing candidate refinement.
        // Do not spend ~100 seconds running three full production passes
        // before the refinement test even starts.
        base.configuration = .init(
            maximumPasses: 1,
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

        base.decoder.configuration
            .captureCandidateTraces = true

        let baseBatch = try base.decode(
            spectrogram: spectrogram
        )

        print(
            "[FineDecodeTest] Baseline complete: messages="
                + "\(baseBatch.messages.count) traces="
                + "\(baseBatch.candidateTraces.count)"
        )

        var refiner =
            FT8CandidateGuidedFineDecoder()

        // Keep this diagnostic quick and deterministic.
        refiner.configuration.maximumSeeds = 4
        refiner.configuration.coarseTimeRadius = 0.16
        refiner.configuration.coarseTimeStep = 0.04
        refiner.configuration.coarseFrequencyRadiusHz = 6.25
        refiner.configuration.coarseFrequencyStepHz = 1.5625
        refiner.configuration.coarseHypothesesRetained = 6
        refiner.configuration.fineTimeRadius = 0.02
        refiner.configuration.fineTimeStep = 0.01
        refiner.configuration.fineFrequencyRadiusHz = 0.78125
        refiner.configuration.fineFrequencyStepHz = 0.78125
        refiner.configuration.fineSeedsPerCandidate = 2

        refiner.ldpcDecoder.configuration
            .enableRobustRetries = false

        print("[FineDecodeTest] Starting bounded fine refinement")

        let result = try refiner.decode(
            spectrogram: spectrogram,
            traces: baseBatch.candidateTraces,
            excludingPayloads:
                baseBatch.messages.map {
                    $0.decoded.payload
                }
        )

        print("Candidate-guided fine decode:")
        print("  base messages: \(baseBatch.messages.count)")
        print("  seeds selected: \(result.seedsSelected)")
        print("  hypotheses tested: \(result.hypothesesTested)")
        print("  LDPC attempts: \(result.ldpcAttempts)")
        print("  new messages: \(result.messages.count)")
        print("  elapsed: \(result.elapsedSeconds)")

        for hypothesis in result.bestHypotheses {
            print(
                "  seed pass=\(hypothesis.seedPass) "
                    + "candidate=\(hypothesis.seedCandidateIndex)"
            )
            print(
                "    refinedTime=\(hypothesis.startTime) "
                    + "refinedFreq=\(hypothesis.frequencyHz) "
                    + "costas=\(hypothesis.costasScore) "
                    + "soft=\(String(describing: hypothesis.softConfidence)) "
                    + "syndrome=\(String(describing: hypothesis.syndromeWeight)) "
                    + "parity=\(String(describing: hypothesis.parityPassed)) "
                    + "crc=\(String(describing: hypothesis.crcPassed)) "
                    + "text=\(hypothesis.decodedText ?? "nil")"
            )
        }

        let outputURL =
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(
                    "Downloads/ft8-candidate-guided-fine-decode.txt"
                )

        var lines: [String] = [
            "baseMessages=\(baseBatch.messages.count)",
            "seedsSelected=\(result.seedsSelected)",
            "hypothesesTested=\(result.hypothesesTested)",
            "ldpcAttempts=\(result.ldpcAttempts)",
            "newMessages=\(result.messages.count)",
            "elapsed=\(result.elapsedSeconds)"
        ]

        lines.append(
            contentsOf: result.bestHypotheses.map {
                [
                    "seedPass=\($0.seedPass)",
                    "seedCandidate=\($0.seedCandidateIndex)",
                    "seedTime=\($0.seedTime)",
                    "seedFrequency=\($0.seedFrequencyHz)",
                    "refinedTime=\($0.startTime)",
                    "refinedFrequency=\($0.frequencyHz)",
                    "costas=\($0.costasScore)",
                    "soft=\(String(describing: $0.softConfidence))",
                    "syndrome=\(String(describing: $0.syndromeWeight))",
                    "parity=\(String(describing: $0.parityPassed))",
                    "crc=\(String(describing: $0.crcPassed))",
                    "text=\($0.decodedText ?? "")"
                ].joined(separator: ",")
            }
        )

        try lines
            .joined(separator: "\n")
            .write(
                to: outputURL,
                atomically: true,
                encoding: .utf8
            )

        print(
            "Candidate-guided fine-decode diagnostics written to: "
                + outputURL.path
        )

        XCTAssertGreaterThan(
            result.seedsSelected,
            0
        )
        XCTAssertGreaterThan(
            result.hypothesesTested,
            0
        )
        XCTAssertGreaterThan(
            result.ldpcAttempts,
            0
        )
    }
}
