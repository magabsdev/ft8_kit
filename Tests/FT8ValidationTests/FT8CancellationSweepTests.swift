import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8CancellationSweepTests: XCTestCase {
    func testSweepsAdaptiveCancellationProfiles() throws {
        try RealWAVTestGate.requireEnabled()


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

        var firstPassDecoder =
            slotDecoder.decoder.decoder
        firstPassDecoder.configuration
            .captureCandidateTraces = false
        firstPassDecoder.configuration
            .capturePipelineRecords = false
        firstPassDecoder.configuration
            .captureStageTimings = false

        let first = try firstPassDecoder.decode(
            spectrogram: spectrogram
        )

        XCTAssertGreaterThan(
            first.metrics.crcPassed,
            0
        )
        XCTAssertFalse(first.messages.isEmpty)

        let selected = try XCTUnwrap(
            first.messages.min {
                abs($0.candidate.frequency - 1291)
                    < abs($1.candidate.frequency - 1291)
            }
        )

        print(
            "Cancellation sweep source: "
                + "\"\(selected.decoded.text)\""
                + " time=\(selected.candidate.startTime)"
                + " frequency=\(selected.candidate.frequency)"
        )

        let profiles = makeProfiles()
        var results:
            [RealWAVCancellationSweepResult] = []

        var residualDecoder =
            slotDecoder.decoder.decoder

        // Keep the sweep practical. Every profile runs a complete residual
        // search, so disable the expensive LDPC ensemble and cap candidates.
        residualDecoder.ldpcDecoder.configuration
            .enableRobustRetries = false
        residualDecoder.configuration
            .maximumCandidatesToDecode = min(
                residualDecoder.configuration
                    .maximumCandidatesToDecode,
                50
            )
        residualDecoder.configuration
            .captureCandidateTraces = false
        residualDecoder.configuration
            .capturePipelineRecords = false
        residualDecoder.configuration
            .captureStageTimings = false

        for profile in profiles {
            let cancellation =
                try RealWAVAdaptiveCanceller.cancel(
                    selected,
                    from: spectrogram,
                    profile: profile
                )

            let started = ContinuousClock.now

            let residual = try residualDecoder.decode(
                spectrogram:
                    cancellation.spectrogram
            )

            let elapsed =
                elapsedSeconds(since: started)

            let messages =
                residual.messages.map {
                    $0.decoded.text
                }

            let reappeared = messages.contains {
                normalized($0)
                    == normalized(
                        selected.decoded.text
                    )
            }

            results.append(
                RealWAVCancellationSweepResult(
                    profile: profile,
                    affectedBins:
                        cancellation.affectedBins,
                    reductionFraction:
                        cancellation.reductionFraction,
                    residualCandidates:
                        residual.metrics.candidatesFound,
                    residualCRCPassed:
                        residual.metrics.crcPassed,
                    residualMessages: messages,
                    cancelledMessageReappeared:
                        reappeared,
                    elapsedSeconds: elapsed
                )
            )
        }

        let report =
            RealWAVCancellationSweepReport(
                recording: referenceCase.name,
                cancelledMessage:
                    selected.decoded.text,
                cancelledFrequencyHz:
                    selected.candidate.frequency,
                cancelledStartTime:
                    selected.candidate.startTime,
                firstPassCRCPassed:
                    first.metrics.crcPassed,
                firstPassMessages:
                    first.messages.map {
                        $0.decoded.text
                    },
                results: results
            )

        RealWAVCancellationSweepExporter
            .printSummary(report)

        try RealWAVCancellationSweepExporter
            .exportIfRequested(report)

        XCTAssertEqual(
            report.results.count,
            profiles.count
        )

        // We are measuring the boundary here. Do not make the test fail if
        // none of the profiles fully suppress the decoded transmission yet.
        XCTAssertTrue(
            report.results.allSatisfy {
                $0.affectedBins > 0
                    && $0.reductionFraction >= 0
                    && $0.reductionFraction <= 1
            }
        )
    }

    private func makeProfiles()
        -> [RealWAVCancellationSweepProfile] {
        var profiles:
            [RealWAVCancellationSweepProfile] = []

        // 3 × 4 × 2 = 24 bounded profiles. Two taper floors are enough to
        // identify whether edge under-cancellation is why the message
        // reappears one tone away.
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
        value
            .uppercased()
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
