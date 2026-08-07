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

        var base =
            FT8MultiPassDecoder()

        base.configuration = .init(
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

        base.canceller.configuration = .init(
            cancellationStrength: 1.00,
            binRadius: 1,
            timeTaperFloor: 0.50,
            preserveNoiseFloor: true
        )

        base.decoder.configuration
            .captureCandidateTraces = true

        let baseBatch = try base.decode(
            spectrogram: spectrogram
        )

        var refiner =
            FT8CandidateGuidedFineDecoder()

        // Keep this checkpoint focused on timing/frequency refinement.
        // Robust LDPC retries can be re-enabled after we know whether the
        // refined LLRs themselves improve the real-WAV failures.
        refiner.ldpcDecoder.configuration
            .enableRobustRetries = false

        let result = try refiner.decode(
            spectrogram: spectrogram,
            traces: baseBatch.candidateTraces,
            excludingPayloads:
                baseBatch.messages.map {
                    $0.decoded.payload
                }
        )

        print("Candidate-guided fine decode:")
        print(
            "  base messages: "
                + "\(baseBatch.messages.count)"
        )
        print(
            "  seeds selected: "
                + "\(result.seedsSelected)"
        )
        print(
            "  hypotheses tested: "
                + "\(result.hypothesesTested)"
        )
        print(
            "  LDPC attempts: "
                + "\(result.ldpcAttempts)"
        )
        print(
            "  new messages: "
                + "\(result.messages.count)"
        )
        print(
            "  elapsed: "
                + "\(result.elapsedSeconds)"
        )

        for hypothesis
        in result.bestHypotheses {
            print(
                "  seed pass="
                    + "\(hypothesis.seedPass)"
                    + " candidate="
                    + "\(hypothesis.seedCandidateIndex)"
                    + " seedTime="
                    + "\(hypothesis.seedTime)"
                    + " seedFreq="
                    + "\(hypothesis.seedFrequencyHz)"
            )
            print(
                "    refinedTime="
                    + "\(hypothesis.startTime)"
                    + " refinedFreq="
                    + "\(hypothesis.frequencyHz)"
                    + " costas="
                    + "\(hypothesis.costasScore)"
                    + " soft="
                    + "\(String(describing: hypothesis.softConfidence))"
                    + " syndrome="
                    + "\(String(describing: hypothesis.syndromeWeight))"
                    + " parity="
                    + "\(String(describing: hypothesis.parityPassed))"
                    + " crc="
                    + "\(String(describing: hypothesis.crcPassed))"
                    + " text="
                    + "\(hypothesis.decodedText ?? "nil")"
            )
        }

        for message in result.messages {
            print(
                "  decoded \""
                    + message.decoded.text
                    + "\" time="
                    + "\(message.candidate.startTime)"
                    + " frequency="
                    + "\(message.candidate.frequency)"
                    + " parity="
                    + "\(message.ldpc.parityPassed)"
                    + " crc="
                    + "\(message.ldpc.crcPassed)"
            )
        }

        let outputURL =
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(
                    "Downloads/ft8-candidate-guided-fine-decode.txt"
                )

        let lines = result.bestHypotheses.map {
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
