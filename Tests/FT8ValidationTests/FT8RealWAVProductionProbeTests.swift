import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8RealWAVProductionProbeTests: XCTestCase {
    func testRepresentativeRealWAVProductionProbe() throws {
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

        let slotDecoder = FT8MultiPassSlotDecoder()

        let spectrogram = try Waterfall.analyse(
            samples: recording.samples,
            configuration:
                slotDecoder.waterfallConfiguration
        )

        var configuration =
            slotDecoder.decoder.decoder.configuration

        // This is a one-pass production probe. Capture everything during the
        // same decode rather than first running the normal integration decode
        // and then performing a second full diagnostic decode.
        configuration.captureCandidateTraces = true
        configuration.capturePipelineRecords = true
        configuration.captureStageTimings = true

        let decoder = FT8OptimizedDecoder(
            configuration: configuration,
            synchronizer:
                slotDecoder.decoder.decoder.synchronizer,
            extractor:
                slotDecoder.decoder.decoder.extractor,
            ldpcDecoder:
                slotDecoder.decoder.decoder.ldpcDecoder,
            messageDecoder:
                slotDecoder.decoder.decoder.messageDecoder
        )

        let started = ContinuousClock.now
        let batch = try decoder.decode(
            spectrogram: spectrogram
        )
        let elapsed = elapsedSeconds(
            since: started
        )

        print(
            """
            Real WAV production probe:
              recording: \(referenceCase.name)
              expected references: \(expected.count)
              candidates found: \(batch.metrics.candidatesFound)
              candidates scheduled: \(batch.metrics.candidatesScheduled)
              soft symbols extracted: \(batch.metrics.softSymbolsExtracted)
              LDPC attempts: \(batch.metrics.ldpcAttempts)
              parity passed: \(batch.metrics.parityPassed)
              CRC passed: \(batch.metrics.crcPassed)
              messages returned: \(batch.metrics.messagesReturned)
              wall clock: \(elapsed)
            """
        )

        if batch.messages.isEmpty {
            print("  decoded messages: none")
        } else {
            print("  decoded messages:")

            for (index, message) in batch.messages.enumerated() {
                print(
                    "    #\(index + 1)"
                        + " text=\"\(message.decoded.text)\""
                        + " time=\(message.candidate.startTime)"
                        + " frequency=\(message.candidate.frequency)"
                        + " snr=\(message.candidate.snrDB)"
                        + " parity=\(message.ldpc.parityPassed)"
                        + " crc=\(message.ldpc.crcPassed)"
                )
            }
        }

        let parityReport = RealWAVParityDiagnostics.build(
            recording: referenceCase.name,
            records: batch.pipelineRecords,
            expected: expected
        )

        RealWAVParityDiagnostics.printSummary(
            parityReport
        )

        let environment =
            ProcessInfo.processInfo.environment
        let fileManager = FileManager.default

        let jsonURL = outputURL(
            key: "FT8_REAL_WAV_PARITY_JSON",
            environment: environment
        )
        let csvURL = outputURL(
            key: "FT8_REAL_WAV_PARITY_CSV",
            environment: environment
        )

        for url in [jsonURL, csvURL].compactMap({ $0 }) {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        try RealWAVParityDiagnostics.write(
            parityReport,
            jsonURL: jsonURL,
            csvURL: csvURL
        )

        if let jsonURL {
            XCTAssertTrue(
                fileManager.fileExists(
                    atPath: jsonURL.path
                ),
                "Parity JSON was not created at \(jsonURL.path)."
            )
            print(
                "Real WAV parity JSON written to: "
                    + jsonURL.path
            )
        }

        if let csvURL {
            XCTAssertTrue(
                fileManager.fileExists(
                    atPath: csvURL.path
                ),
                "Parity CSV was not created at \(csvURL.path)."
            )
            print(
                "Real WAV parity CSV written to: "
                    + csvURL.path
            )
        }

        // This is diagnostic by design. It verifies that the production path
        // actually ran and that pipeline records were captured, but it does not
        // impose a decode-count target while we are still calibrating matching.
        XCTAssertGreaterThan(
            batch.metrics.candidatesFound,
            0
        )
        XCTAssertGreaterThan(
            batch.metrics.candidatesScheduled,
            0
        )
        XCTAssertFalse(
            batch.pipelineRecords.isEmpty
        )
    }

    private func outputURL(
        key: String,
        environment: [String: String]
    ) -> URL? {
        guard let value =
            environment[key]?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
              !value.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: value)
    }

    private func elapsedSeconds(
        since started: ContinuousClock.Instant
    ) -> Double {
        let duration = ContinuousClock.now - started
        let components = duration.components

        return Double(components.seconds)
            + Double(components.attoseconds)
                / 1_000_000_000_000_000_000
    }
}
