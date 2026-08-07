import Foundation
import XCTest
import FT8Decoder
import FT8DSP
@testable import FT8Validation

final class FT8ProductionCancellerEquivalenceTests:
    XCTestCase
{
    func testProductionResidualMatchesCalibratedExperimentalResidual()
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

        let slotDecoder = FT8MultiPassSlotDecoder()

        let spectrogram = try Waterfall.analyse(
            samples: recording.samples,
            configuration:
                slotDecoder.waterfallConfiguration
        )

        var decoder =
            slotDecoder.decoder.decoder

        decoder.configuration.captureCandidateTraces =
            false
        decoder.configuration.capturePipelineRecords =
            false
        decoder.configuration.captureStageTimings =
            false

        let first = try decoder.decode(
            spectrogram: spectrogram
        )

        let selected = try XCTUnwrap(
            first.messages.min {
                abs($0.candidate.frequency - 1291)
                    < abs($1.candidate.frequency - 1291)
            }
        )

        let profile = RealWAVFastCancellationProfile(
            radiusBins: 1,
            strength: 1.00,
            timeTaperFloor: 0.50
        )

        let experimental =
            try RealWAVFastCancellationEvaluator.cancel(
                selected,
                from: spectrogram,
                profile: profile
            )

        var productionCanceller =
            slotDecoder.decoder.canceller

        productionCanceller.configuration =
            .init(
                cancellationStrength: 1.00,
                binRadius: 1,
                timeTaperFloor: 0.50,
                preserveNoiseFloor: true
            )

        let production =
            try productionCanceller.cancel(
                [selected],
                from: spectrogram
            )

        XCTAssertEqual(
            production.affectedBins,
            experimental.affectedBins
        )

        XCTAssertEqual(
            production.reductionFraction,
            experimental.reductionFraction,
            accuracy: 0.000_01
        )

        XCTAssertEqual(
            production.spectrogram.frames.count,
            experimental.spectrogram.frames.count
        )

        var maximumDifference: Float = 0
        var squaredDifference: Double = 0
        var squaredReference: Double = 0
        var count = 0

        for frameIndex
        in experimental.spectrogram.frames.indices {
            let expected =
                experimental.spectrogram
                    .frames[frameIndex]
            let actual =
                production.spectrogram
                    .frames[frameIndex]

            XCTAssertEqual(
                actual.noiseFloorDB,
                expected.noiseFloorDB,
                accuracy: 0.000_001
            )

            let binCount = min(
                expected.magnitudes.count,
                actual.magnitudes.count
            )

            for bin in 0..<binCount {
                let difference = abs(
                    expected.magnitudes[bin]
                        - actual.magnitudes[bin]
                )

                maximumDifference = max(
                    maximumDifference,
                    difference
                )

                squaredDifference +=
                    Double(difference * difference)

                squaredReference +=
                    Double(
                        expected.magnitudes[bin]
                            * expected.magnitudes[bin]
                    )

                count += 1
            }
        }

        let relativeRMS: Double

        if count > 0,
           squaredReference > 0 {
            relativeRMS =
                sqrt(
                    squaredDifference /
                    Double(count)
                )
                /
                sqrt(
                    squaredReference /
                    Double(count)
                )
        } else {
            relativeRMS = 0
        }

        print(
            "Production canceller equivalence:"
        )
        print(
            "  affected bins: \(production.affectedBins)"
        )
        print(
            "  experimental reduction: "
                + "\(experimental.reductionFraction)"
        )
        print(
            "  production reduction: "
                + "\(production.reductionFraction)"
        )
        print(
            "  maximum magnitude difference: "
                + "\(maximumDifference)"
        )
        print(
            "  relative RMS error: "
                + "\(relativeRMS)"
        )

        XCTAssertLessThan(
            relativeRMS,
            0.005
        )
    }
}
