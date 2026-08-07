import Foundation
import XCTest
import FT8DSP
import FT8Encoder
import FT8Protocol
@testable import FT8Decoder

final class FT8SoftSymbolEnsembleExtractorTests: XCTestCase {
    func testProductionProfilesAreBoundedAndUnique() {
        let profiles = FT8SoftSymbolEnsembleExtractor.productionProfiles

        XCTAssertEqual(profiles.count, 4)
        XCTAssertEqual(Set(profiles.map(\.name)).count, profiles.count)
        XCTAssertTrue(profiles.contains { $0.name == "precise" })
        XCTAssertTrue(profiles.contains { $0.name == "balanced" })
        XCTAssertTrue(profiles.contains { $0.name == "frequency-integrated" })
        XCTAssertTrue(profiles.contains { $0.name == "temporal-integrated" })
    }

    func testAllProfilesRecoverSyntheticCodeword() throws {
        let text = "ENSEMBLE"
        let tones = try FT8Encoder.encode(text: text)
        let expected = try FT8Encoder.encodeLDPC(
            FT8CRC.append(to: FT8MessageCodec.pack(text))
        )

        let spectrogram = makeSpectrogram(
            tones: tones,
            startTime: 0.4,
            baseFrequency: 1_003.125
        )

        let candidate = FT8Candidate(
            startTime: 0.4,
            frequency: 1_003.125,
            syncScore: 1,
            snrDB: 30,
            confidence: 1
        )

        let variants = try FT8SoftSymbolEnsembleExtractor().extract(
            from: spectrogram,
            candidate: candidate
        )

        XCTAssertEqual(variants.count, 4)

        for variant in variants {
            XCTAssertEqual(
                variant.softSymbols.logLikelihoodRatios.count,
                174,
                variant.profileName
            )
            XCTAssertEqual(
                variant.softSymbols.symbolConfidences.count,
                58,
                variant.profileName
            )
            XCTAssertEqual(
                variant.softSymbols.hardBits,
                expected,
                variant.profileName
            )
        }
    }

    func testProfilesProduceDifferentSoftEvidence() throws {
        let tones = try FT8Encoder.encode(text: "SOFT TEST")

        let spectrogram = makeSpectrogram(
            tones: tones,
            startTime: 0.4,
            baseFrequency: 1_003.125
        )

        let candidate = FT8Candidate(
            startTime: 0.4,
            frequency: 1_003.125,
            syncScore: 1,
            snrDB: 30,
            confidence: 1
        )

        let variants = try FT8SoftSymbolEnsembleExtractor().extract(
            from: spectrogram,
            candidate: candidate
        )

        let signatures = Set(
            variants.map {
                $0.softSymbols.logLikelihoodRatios
                    .map { String(format: "%.5f", $0) }
                    .joined(separator: ",")
            }
        )

        XCTAssertGreaterThan(
            signatures.count,
            1,
            "The ensemble must provide genuinely different soft evidence."
        )
    }

    private func makeSpectrogram(
        tones: [UInt8],
        startTime: Double,
        baseFrequency: Float,
        sampleRate: Float = 12_000,
        fftSize: Int = 1_920,
        hopSize: Int = 480
    ) -> Spectrogram {
        let frameStep = Double(hopSize) / Double(sampleRate)
        let frameDuration = Double(fftSize) / Double(sampleRate)
        let duration = startTime + 79 * 0.160 + 0.4
        let count = Int(ceil(duration / frameStep))
        let binWidth = sampleRate / Float(fftSize)
        let columns = fftSize / 2 + 1
        let noise: Float = -70

        var frames: [WaterfallFrame] = []
        frames.reserveCapacity(count)

        for frameIndex in 0..<count {
            let time = Double(frameIndex) * frameStep
            let centre = time + frameDuration / 2

            var decibels = Array(repeating: noise, count: columns)
            let relative = centre - startTime

            if relative >= 0 {
                let symbol = Int(floor(relative / 0.160))

                if tones.indices.contains(symbol) {
                    let frequency =
                        baseFrequency
                        + Float(tones[symbol]) * 6.25

                    let exactBin = frequency / binWidth
                    let lower = Int(floor(exactBin))
                    let upper = lower + 1
                    let fraction = exactBin - Float(lower)

                    if decibels.indices.contains(lower) {
                        let power =
                            powf(10, Float(-8) / 10) * (1 - fraction)
                        decibels[lower] =
                            10 * log10f(
                                max(power, Float.leastNonzeroMagnitude)
                            )
                    }

                    if decibels.indices.contains(upper) {
                        let power =
                            powf(10, Float(-8) / 10) * fraction
                        decibels[upper] =
                            10 * log10f(
                                max(power, Float.leastNonzeroMagnitude)
                            )
                    }
                }
            }

            let magnitudes = decibels.map { powf(10, $0 / 20) }

            frames.append(
                WaterfallFrame(
                    index: frameIndex,
                    sampleOffset: frameIndex * hopSize,
                    time: time,
                    minimumFrequency: 0,
                    binWidth: binWidth,
                    magnitudes: magnitudes,
                    decibels: decibels,
                    intensities: decibels.map {
                        min(max(($0 - noise) / 70, 0), 1)
                    },
                    noiseFloorDB: noise
                )
            )
        }

        return Spectrogram(
            frames: frames,
            sampleRate: sampleRate,
            fftSize: fftSize,
            hopSize: hopSize,
            minimumFrequency: 0,
            maximumFrequency: sampleRate / 2
        )
    }
}
