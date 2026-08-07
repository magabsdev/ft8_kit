import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8ProductionMultiPassTests: XCTestCase {
    private struct Report: Codable {
        struct Message: Codable {
            let text: String
            let startTime: Double
            let frequencyHz: Float
            let confidence: Float
            let parityPassed: Bool
            let crcPassed: Bool
        }

        struct Pass: Codable {
            let pass: Int
            let candidatesFound: Int
            let candidatesScheduled: Int
            let primaryCRCPassed: Int
            let returnedCRCValidMessages: Int
            let messagesDecoded: Int
            let newMessages: Int
            let signalsCancelled: Int
            let cancelledMessages: [String]
            let affectedBins: Int
            let energyReductionFraction: Double
            let elapsedSeconds: Double
        }

        let recording: String
        let uniqueMessages: Int
        let passesCompleted: Int
        let elapsedSeconds: Double
        let messages: [Message]
        let passes: [Pass]
    }

    func testProductionMultiPassRealWAV() throws {
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

        var slotDecoder = FT8MultiPassSlotDecoder()

        // Make the production behaviour explicit in this validation checkpoint.
        slotDecoder.decoder.configuration =
            .init(
                maximumPasses: 5,
                maximumSignalsPerPass: 1,
                minimumNewMessages: 1,
                minimumEnergyReductionFraction: 0.001,
                stopWhenNoNewMessages: true,
                suppressDuplicatePayloadAcrossPasses: true,
                disableRobustLDPCOnResidualPasses: true,
                residualMaximumCandidatesToDecode: 60
            )

        slotDecoder.decoder.canceller.configuration =
            .init(
                cancellationStrength: 1.00,
                binRadius: 1,
                timeTaperFloor: 0.50,
                preserveNoiseFloor: true
            )

        let batch = try slotDecoder.decode(
            samples: recording.samples
        )

        print("Production multi-pass real WAV:")
        print(
            "  messages: \(batch.messages.count)"
                + " passes: \(batch.metrics.passesCompleted)"
                + " elapsed: \(batch.metrics.elapsedSeconds)"
        )

        for message in batch.messages {
            print(
                "  \"\(message.decoded.text)\""
                    + " time=\(message.candidate.startTime)"
                    + " frequency=\(message.candidate.frequency)"
                    + " parity=\(message.ldpc.parityPassed)"
                    + " crc=\(message.ldpc.crcPassed)"
            )
        }

        for pass in batch.metrics.passes {
            print(
                "  pass \(pass.pass):"
                    + " candidates=\(pass.candidatesFound)"
                    + " scheduled=\(pass.candidatesScheduled)"
                    + " primaryCRC=\(pass.crcPassed)"
                    + " returnedCRC=\(pass.returnedCRCValidMessages)"
                    + " new=\(pass.newMessages)"
                    + " cancelled=\(pass.cancelledMessages)"
                    + " reduction=\(pass.energyReductionFraction)"
                    + " elapsed=\(pass.elapsedSeconds)"
            )
        }

        XCTAssertLessThanOrEqual(
            batch.metrics.passesCompleted,
            5
        )

        XCTAssertEqual(
            batch.metrics.uniqueMessages,
            batch.messages.count
        )

        XCTAssertTrue(
            batch.messages.allSatisfy {
                $0.ldpc.parityPassed &&
                $0.ldpc.crcPassed
            }
        )

        let payloads = batch.messages.map {
            $0.decoded.payload
        }

        for index in payloads.indices {
            for other in payloads.indices
            where index < other {
                XCTAssertNotEqual(
                    payloads[index],
                    payloads[other],
                    "Production multi-pass decoder returned the same payload twice."
                )
            }
        }

        XCTAssertTrue(
            batch.messages.contains {
                normalized($0.decoded.text)
                    == "CQ R7IW LN35"
            },
            "Expected the known first-pass real-WAV decode."
        )

        let report = Report(
            recording: referenceCase.name,
            uniqueMessages: batch.metrics.uniqueMessages,
            passesCompleted: batch.metrics.passesCompleted,
            elapsedSeconds: batch.metrics.elapsedSeconds,
            messages: batch.messages.map {
                Report.Message(
                    text: $0.decoded.text,
                    startTime: $0.candidate.startTime,
                    frequencyHz: $0.candidate.frequency,
                    confidence: $0.decoded.confidence,
                    parityPassed: $0.ldpc.parityPassed,
                    crcPassed: $0.ldpc.crcPassed
                )
            },
            passes: batch.metrics.passes.map {
                Report.Pass(
                    pass: $0.pass,
                    candidatesFound: $0.candidatesFound,
                    candidatesScheduled: $0.candidatesScheduled,
                    primaryCRCPassed: $0.crcPassed,
                    returnedCRCValidMessages:
                        $0.returnedCRCValidMessages,
                    messagesDecoded: $0.messagesDecoded,
                    newMessages: $0.newMessages,
                    signalsCancelled: $0.signalsCancelled,
                    cancelledMessages: $0.cancelledMessages,
                    affectedBins: $0.affectedBins,
                    energyReductionFraction:
                        $0.energyReductionFraction,
                    elapsedSeconds: $0.elapsedSeconds
                )
            }
        )

        try exportIfRequested(report)
    }

    private func normalized(
        _ value: String
    ) -> String {
        value
            .uppercased()
            .split(
                whereSeparator: {
                    $0.isWhitespace
                }
            )
            .joined(separator: " ")
    }

    private func exportIfRequested(
        _ report: Report
    ) throws {
        let environment =
            ProcessInfo.processInfo.environment

        if let path = environment[
            "FT8_PRODUCTION_MULTIPASS_JSON"
        ]?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
           !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try prepare(url)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]

            try encoder.encode(report).write(
                to: url,
                options: .atomic
            )

            print(
                "Production multi-pass JSON written to: "
                    + url.path
            )
        }

        if let path = environment[
            "FT8_PRODUCTION_MULTIPASS_CSV"
        ]?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
           !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try prepare(url)

            var rows = [
                "pass,candidates_found,candidates_scheduled,primary_crc,returned_crc,new_messages,signals_cancelled,affected_bins,energy_reduction,elapsed_seconds,cancelled_messages"
            ]

            for pass in report.passes {
                rows.append(
                    [
                        String(pass.pass),
                        String(pass.candidatesFound),
                        String(pass.candidatesScheduled),
                        String(pass.primaryCRCPassed),
                        String(pass.returnedCRCValidMessages),
                        String(pass.newMessages),
                        String(pass.signalsCancelled),
                        String(pass.affectedBins),
                        String(pass.energyReductionFraction),
                        String(pass.elapsedSeconds),
                        csvField(
                            pass.cancelledMessages
                                .joined(separator: " | ")
                        )
                    ].joined(separator: ",")
                )
            }

            try (rows.joined(separator: "\n") + "\n")
                .write(
                    to: url,
                    atomically: true,
                    encoding: .utf8
                )

            print(
                "Production multi-pass CSV written to: "
                    + url.path
            )
        }
    }

    private func prepare(
        _ url: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func csvField(
        _ value: String
    ) -> String {
        guard value.contains(",")
                || value.contains("\"")
                || value.contains("\n") else {
            return value
        }

        return "\""
            + value.replacingOccurrences(
                of: "\"",
                with: "\"\""
            )
            + "\""
    }
}
