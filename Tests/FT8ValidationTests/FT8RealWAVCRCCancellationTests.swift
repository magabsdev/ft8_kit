import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8RealWAVCRCCancellationTests: XCTestCase {
    private struct Report: Codable {
        struct Decode: Codable {
            let text: String
            let startTime: Double
            let frequencyHz: Float
            let crcPassed: Bool
            let parityPassed: Bool
            let confidence: Float
        }

        let recording: String
        let firstPassCandidates: Int
        let firstPassCRCPassed: Int
        let firstPassMessages: [Decode]
        let cancelledText: String
        let cancellationAffectedBins: Int
        let cancellationReductionFraction: Double
        let residualCandidates: Int
        let residualCRCPassed: Int
        let residualMessages: [Decode]
    }

    func testCRCValidDecodeFeedsCancellationAndResidualSearch() throws {
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

        let slotDecoder = FT8MultiPassSlotDecoder()

        let spectrogram = try Waterfall.analyse(
            samples: recording.samples,
            configuration: slotDecoder.waterfallConfiguration
        )

        // Use the production single-pass decoder exactly as configured.
        // The previous production probe established that this path now
        // produces CRC-valid real-WAV decodes.
        var decoder = slotDecoder.decoder.decoder
        decoder.configuration.captureCandidateTraces = false
        decoder.configuration.capturePipelineRecords = false
        decoder.configuration.captureStageTimings = true

        let first = try decoder.decode(
            spectrogram: spectrogram
        )

        XCTAssertGreaterThan(
            first.metrics.candidatesFound,
            0
        )
        XCTAssertGreaterThan(
            first.metrics.crcPassed,
            0,
            "Expected at least one CRC-valid real-WAV decode before cancellation."
        )
        XCTAssertFalse(
            first.messages.isEmpty,
            "CRC-valid candidates must reach FT8MessageDecoder and produce text."
        )

        print("CRC-valid first-pass messages:")
        for message in first.messages {
            print(
                "  text=\"\(message.decoded.text)\""
                    + " time=\(message.candidate.startTime)"
                    + " frequency=\(message.candidate.frequency)"
                    + " parity=\(message.ldpc.parityPassed)"
                    + " crc=\(message.ldpc.crcPassed)"
                    + " confidence=\(message.decoded.confidence)"
            )
        }

        // Prefer the known CRC-valid signal around 1291 Hz discovered by the
        // production parity probe. Fall back to the strongest decoded message
        // so this remains useful if candidate ordering changes slightly.
        let preferred = first.messages.min {
            abs($0.candidate.frequency - 1291)
                < abs($1.candidate.frequency - 1291)
        }

        let selected = try XCTUnwrap(
            preferred ?? first.messages.max {
                $0.decoded.confidence < $1.decoded.confidence
            }
        )

        XCTAssertTrue(selected.ldpc.parityPassed)
        XCTAssertTrue(selected.ldpc.crcPassed)
        XCTAssertFalse(
            selected.decoded.text
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
        )

        // This is the key checkpoint: take a CRC-valid *decoded message*,
        // synthesize its tones through FT8SignalCanceller, subtract it from
        // the real spectrogram, then search the residual.
        let cancellation = try slotDecoder.decoder.canceller.cancel(
            [selected],
            from: spectrogram
        )

        XCTAssertGreaterThan(
            cancellation.affectedBins,
            0
        )
        XCTAssertGreaterThan(
            cancellation.reductionFraction,
            0
        )

        print(
            """
            Cancellation:
              text: \(selected.decoded.text)
              affected bins: \(cancellation.affectedBins)
              reduction fraction: \(cancellation.reductionFraction)
            """
        )

        // Keep the residual probe bounded. We are testing whether subtraction
        // exposes additional CRC-valid material, not benchmarking every
        // expensive LDPC rescue hypothesis in this checkpoint.
        var residualDecoder = decoder
        residualDecoder.configuration.maximumCandidatesToDecode = min(
            residualDecoder.configuration.maximumCandidatesToDecode,
            60
        )
        residualDecoder.ldpcDecoder.configuration.enableRobustRetries = false

        let residual = try residualDecoder.decode(
            spectrogram: cancellation.spectrogram
        )

        print("Residual-pass messages:")
        if residual.messages.isEmpty {
            print("  none")
        } else {
            for message in residual.messages {
                print(
                    "  text=\"\(message.decoded.text)\""
                        + " time=\(message.candidate.startTime)"
                        + " frequency=\(message.candidate.frequency)"
                        + " parity=\(message.ldpc.parityPassed)"
                        + " crc=\(message.ldpc.crcPassed)"
                        + " confidence=\(message.decoded.confidence)"
                )
            }
        }

        let report = Report(
            recording: referenceCase.name,
            firstPassCandidates: first.metrics.candidatesFound,
            firstPassCRCPassed: first.metrics.crcPassed,
            firstPassMessages: first.messages.map(reportDecode),
            cancelledText: selected.decoded.text,
            cancellationAffectedBins: cancellation.affectedBins,
            cancellationReductionFraction: cancellation.reductionFraction,
            residualCandidates: residual.metrics.candidatesFound,
            residualCRCPassed: residual.metrics.crcPassed,
            residualMessages: residual.messages.map(reportDecode)
        )

        try exportIfRequested(report)

        // Do not require the residual pass to recover a new message yet.
        // The checkpoint proves the CRC-valid decode reaches cancellation and
        // records whether subtraction improves the second search.
        XCTAssertGreaterThan(
            residual.metrics.candidatesFound,
            0
        )
    }

    private func reportDecode(
        _ decode: FT8CompleteDecode
    ) -> Report.Decode {
        Report.Decode(
            text: decode.decoded.text,
            startTime: decode.candidate.startTime,
            frequencyHz: decode.candidate.frequency,
            crcPassed: decode.ldpc.crcPassed,
            parityPassed: decode.ldpc.parityPassed,
            confidence: decode.decoded.confidence
        )
    }

    private func exportIfRequested(
        _ report: Report
    ) throws {
        let environment = ProcessInfo.processInfo.environment

        if let path = environment[
            "FT8_REAL_WAV_CRC_CANCELLATION_JSON"
        ]?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
           !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]

            try encoder.encode(report).write(
                to: url,
                options: .atomic
            )

            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: url.path
                )
            )

            print(
                "CRC/cancellation JSON written to: "
                    + url.path
            )
        }
    }
}
