import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8FastCancellationSelectionTests: XCTestCase {
    func testSelectsCancellationProfileBeforeSingleResidualDecode() throws {
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
            configuration:
                slotDecoder.waterfallConfiguration
        )

        var decoder =
            slotDecoder.decoder.decoder
        decoder.configuration.captureCandidateTraces = false
        decoder.configuration.capturePipelineRecords = false
        decoder.configuration.captureStageTimings = false

        let first = try decoder.decode(
            spectrogram: spectrogram
        )

        XCTAssertFalse(first.messages.isEmpty)
        XCTAssertGreaterThan(first.metrics.crcPassed, 0)

        let selected = try XCTUnwrap(
            first.messages.min {
                abs($0.candidate.frequency - 1291)
                    < abs($1.candidate.frequency - 1291)
            }
        )

        let profiles = makeProfiles()

        let evaluation =
            try RealWAVFastCancellationEvaluator.evaluate(
                decode: selected,
                spectrogram: spectrogram,
                profiles: profiles
            )

        let best = evaluation.best

        print(
            "Selected fast cancellation profile: "
                + best.profile.label
                + " suppression="
                + String(
                    format: "%.2f dB",
                    best.suppressionDB
                )
                + " collateral="
                + String(
                    format: "%.2f dB",
                    best.collateralPenaltyDB
                )
        )

        let cancellation =
            try RealWAVFastCancellationEvaluator.cancel(
                selected,
                from: spectrogram,
                profile: best.profile
            )

        var residualDecoder = decoder

        // Exactly one residual decode for this checkpoint.
        residualDecoder.ldpcDecoder.configuration
            .enableRobustRetries = false
        residualDecoder.configuration.maximumCandidatesToDecode =
            min(
                residualDecoder.configuration.maximumCandidatesToDecode,
                50
            )

        let started = ContinuousClock.now

        let residual = try residualDecoder.decode(
            spectrogram: cancellation.spectrogram
        )

        let elapsed =
            elapsedSeconds(since: started)

        let residualMessages =
            residual.messages.map {
                $0.decoded.text
            }

        let reappeared =
            residualMessages.contains {
                normalized($0)
                    == normalized(selected.decoded.text)
            }

        let report =
            RealWAVFastCancellationReport(
                recording: referenceCase.name,
                cancelledMessage:
                    selected.decoded.text,
                cancelledFrequencyHz:
                    selected.candidate.frequency,
                cancelledStartTime:
                    selected.candidate.startTime,
                selectedProfile:
                    best.profile,
                scores:
                    evaluation.scores,
                residualCandidates:
                    residual.metrics.candidatesFound,
                residualCRCPassed:
                    residual.metrics.crcPassed,
                residualMessages:
                    residualMessages,
                cancelledMessageReappeared:
                    reappeared,
                residualElapsedSeconds:
                    elapsed
            )

        RealWAVFastCancellationExporter
            .printSummary(report)

        try RealWAVFastCancellationExporter
            .exportIfRequested(report)

        XCTAssertEqual(
            report.scores.count,
            profiles.count
        )
        XCTAssertGreaterThan(
            best.suppressionDB,
            0
        )
    }

    private func makeProfiles()
        -> [RealWAVFastCancellationProfile] {
        var profiles:
            [RealWAVFastCancellationProfile] = []

        for radius in [1, 2, 3] {
            for strength: Float in [
                0.92,
                0.95,
                0.97,
                1.00
            ] {
                for taper: Float in [
                    0.25,
                    0.50
                ] {
                    profiles.append(
                        .init(
                            radiusBins: radius,
                            strength: strength,
                            timeTaperFloor: taper
                        )
                    )
                }
            }
        }

        return profiles
    }

    private func normalized(
        _ value: String
    ) -> String {
        value.uppercased()
            .split(
                whereSeparator: {
                    $0.isWhitespace
                }
            )
            .joined(separator: " ")
    }

    private func elapsedSeconds(
        since started: ContinuousClock.Instant
    ) -> Double {
        let duration =
            ContinuousClock.now - started
        let components = duration.components

        return Double(components.seconds)
            + Double(components.attoseconds)
                / 1_000_000_000_000_000_000
    }
}
