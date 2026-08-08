import Foundation
import XCTest
import FT8DSP
import FT8Encoder
import FT8Protocol
@testable import FT8Decoder

final class SoftSymbolExtractorTests: XCTestCase {
    func testToneMappingRoundTripsGrayMap() {
        XCTAssertEqual(FT8ToneMapping.dataSymbolIndices.count, 58)
        for binary in 0..<8 {
            let tone = Int(FT8Constants.grayMap[binary])
            let bits = FT8ToneMapping.bits(forTone: tone)
            XCTAssertEqual(bits.0, UInt8((binary >> 2) & 1))
            XCTAssertEqual(bits.1, UInt8((binary >> 1) & 1))
            XCTAssertEqual(bits.2, UInt8(binary & 1))
        }
    }

    func testHardBitsFollowLLRSign() {
        let llrs = (0..<174).map {
            $0.isMultiple(of: 2) ? Float(5) : Float(-5)
        }
        let soft = FT8SoftSymbols(
            logLikelihoodRatios: llrs,
            symbolConfidences: Array(repeating: 0.5, count: 58)
        )
        for index in 0..<174 {
            XCTAssertEqual(
                soft.hardBits[index],
                index.isMultiple(of: 2) ? 0 : 1
            )
        }
    }

    func testExtractsEncoderCodewordFromSyntheticSpectrogram() throws {
        let text = "CQ TEST"
        let tones = try FT8Encoder.encode(text: text)
        let expected = try FT8Encoder.encodeLDPC(
            FT8CRC.append(to: FT8MessageCodec.pack(text))
        )
        let spectrogram = makeSpectrogram(
            tones: tones,
            startTime: 0.4,
            baseFrequency: 1_000
        )
        let candidate = FT8Candidate(
            startTime: 0.4,
            frequency: 1_000,
            syncScore: 1,
            snrDB: 30,
            confidence: 1
        )

        let extracted = try SoftSymbolExtractor().extract(
            from: spectrogram,
            candidate: candidate
        )

        XCTAssertEqual(extracted.hardBits, expected)
        XCTAssertEqual(extracted.logLikelihoodRatios.count, 174)
        XCTAssertEqual(extracted.symbolConfidences.count, 58)
        XCTAssertGreaterThan(extracted.averageConfidence, 0.95)
    }

    func testCompensatesForCandidateDrift() throws {
        let text = "DRIFT"
        let tones = try FT8Encoder.encode(text: text)
        let expected = try FT8Encoder.encodeLDPC(
            FT8CRC.append(to: FT8MessageCodec.pack(text))
        )

        let spectrogram = makeSpectrogram(
            tones: tones,
            startTime: 0.2,
            baseFrequency: 1_200,
            driftHzPerSecond: 2
        )
        let candidate = FT8Candidate(
            startTime: 0.2,
            frequency: 1_200,
            driftHzPerSecond: 2,
            syncScore: 1,
            snrDB: 30,
            confidence: 1
        )

        let extracted = try SoftSymbolExtractor().extract(
            from: spectrogram,
            candidate: candidate
        )

        // Fractional-bin interpolation deliberately shares energy with an
        // adjacent 6.25 Hz tone when the signal falls between FFT bins.
        // Therefore the old >0.9 margin-confidence expectation is no longer
        // valid. The important invariant is that the soft metrics preserve
        // the correct 174-bit codeword under drift.
        XCTAssertEqual(extracted.hardBits, expected)
        XCTAssertGreaterThan(extracted.averageConfidence, 0.65)
    }

    func testFractionalBinInterpolationPreservesExpectedTone() throws {
        let tones = try FT8Encoder.encode(text: "FRACTION")
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

        let extracted = try SoftSymbolExtractor().extract(
            from: spectrogram,
            candidate: candidate
        )

        let expected = try FT8Encoder.encodeLDPC(
            FT8CRC.append(to: FT8MessageCodec.pack("FRACTION"))
        )

        XCTAssertEqual(extracted.hardBits, expected)
    }

    func testTemporalIntegrationSurvivesCorruptedCentreFrame() throws {
        let text = "TEMPORAL"
        let tones = try FT8Encoder.encode(text: text)
        let expected = try FT8Encoder.encodeLDPC(
            FT8CRC.append(to: FT8MessageCodec.pack(text))
        )

        var spectrogram = makeSpectrogram(
            tones: tones,
            startTime: 0.4,
            baseFrequency: 1_000
        )

        let dataSymbol = try XCTUnwrap(
            FT8ToneMapping.dataSymbolIndices.first
        )
        let symbolStart = 0.4 + Double(dataSymbol) * 0.160
        let frameStep =
            Double(spectrogram.hopSize) / Double(spectrogram.sampleRate)
        let frameIndex = Int((symbolStart / frameStep).rounded())

        var frames = spectrogram.frames
        if frames.indices.contains(frameIndex) {
            let old = frames[frameIndex]
            let noise = old.noiseFloorDB
            let decibels = Array(repeating: noise, count: old.decibels.count)
            frames[frameIndex] = WaterfallFrame(
                index: old.index,
                sampleOffset: old.sampleOffset,
                time: old.time,
                minimumFrequency: old.minimumFrequency,
                binWidth: old.binWidth,
                magnitudes: decibels.map { powf(10, $0 / 20) },
                decibels: decibels,
                intensities: Array(repeating: 0, count: decibels.count),
                noiseFloorDB: noise
            )
        }

        spectrogram = Spectrogram(
            frames: frames,
            sampleRate: spectrogram.sampleRate,
            fftSize: spectrogram.fftSize,
            hopSize: spectrogram.hopSize,
            minimumFrequency: spectrogram.minimumFrequency,
            maximumFrequency: spectrogram.maximumFrequency
        )

        let candidate = FT8Candidate(
            startTime: 0.4,
            frequency: 1_000,
            syncScore: 1,
            snrDB: 30,
            confidence: 1
        )

        let extractor = SoftSymbolExtractor(
            configuration: SoftSymbolConfiguration(
                timeIntegrationRadius: 1
            )
        )

        let extracted = try extractor.extract(
            from: spectrogram,
            candidate: candidate
        )

        XCTAssertEqual(extracted.hardBits, expected)
    }

    func testWSJTXNormalizedAmplitudeMetricPreservesSyntheticCodeword() throws {
        let text = "CQ WSJTX"
        let tones = try FT8Encoder.encode(text: text)
        let expected = try FT8Encoder.encodeLDPC(
            FT8CRC.append(to: FT8MessageCodec.pack(text))
        )
        let spectrogram = makeSpectrogram(
            tones: tones,
            startTime: 0.4,
            baseFrequency: 1_000
        )
        let candidate = FT8Candidate(
            startTime: 0.4,
            frequency: 1_000,
            syncScore: 1,
            snrDB: 30,
            confidence: 1
        )

        let extractor = SoftSymbolExtractor(
            configuration: SoftSymbolConfiguration(
                integrationRadius: 0,
                timeIntegrationRadius: 0,
                llrLimit: 24,
                metricMode: .wsjtxNormalizedMaxAmplitude
            )
        )
        let extracted = try extractor.extract(
            from: spectrogram,
            candidate: candidate
        )

        XCTAssertEqual(extracted.hardBits, expected)

        let values = extracted.logLikelihoodRatios
        let count = Float(values.count)
        let mean = values.reduce(Float.zero, +) / count
        let meanSquare = values.reduce(Float.zero) {
            $0 + $1 * $1
        } / count
        let sigma = sqrtf(max(meanSquare - mean * mean, 0))
        XCTAssertEqual(sigma, 2.83, accuracy: 0.03)
    }

    func testProductionEnsembleStartsWithWSJTXNSym1Profile() {
        let profile = FT8SoftSymbolEnsembleExtractor.productionProfiles.first
        XCTAssertEqual(profile?.name, "wsjtx-nsym1")
        XCTAssertEqual(
            profile?.configuration.metricMode,
            .wsjtxNormalizedMaxAmplitude
        )
    }

    func testRejectsEmptySpectrogram() {
        let empty = Spectrogram(
            frames: [],
            sampleRate: 12_000,
            fftSize: 2_048,
            hopSize: 480,
            minimumFrequency: 0,
            maximumFrequency: 6_000
        )
        let candidate = FT8Candidate(
            startTime: 0,
            frequency: 1_000,
            syncScore: 1,
            snrDB: 20,
            confidence: 1
        )

        XCTAssertThrowsError(
            try SoftSymbolExtractor().extract(
                from: empty,
                candidate: candidate
            )
        ) {
            XCTAssertEqual(
                $0 as? SoftSymbolError,
                .emptySpectrogram
            )
        }
    }

    func testRejectsOutOfRangeCandidate() {
        let spectrogram = makeSpectrogram(
            tones: Array(repeating: 0, count: 79),
            startTime: 0,
            baseFrequency: 1_000
        )
        let candidate = FT8Candidate(
            startTime: 0,
            frequency: 5_990,
            syncScore: 1,
            snrDB: 20,
            confidence: 1
        )

        XCTAssertThrowsError(
            try SoftSymbolExtractor().extract(
                from: spectrogram,
                candidate: candidate
            )
        ) {
            XCTAssertEqual(
                $0 as? SoftSymbolError,
                .invalidCandidateFrequency(5_990)
            )
        }
    }

    private func makeSpectrogram(
        tones: [UInt8],
        startTime: Double,
        baseFrequency: Float,
        driftHzPerSecond: Float = 0,
        sampleRate: Float = 12_000,
        fftSize: Int = 1_920,
        hopSize: Int = 480
    ) -> Spectrogram {
        let frameStep =
            Double(hopSize) / Double(sampleRate)
        let frameDuration =
            Double(fftSize) / Double(sampleRate)
        let duration =
            startTime + 79 * 0.160 + 0.4
        let count =
            Int(ceil(duration / frameStep))
        let binWidth =
            sampleRate / Float(fftSize)
        let columns =
            fftSize / 2 + 1
        let noise: Float = -70

        var frames: [WaterfallFrame] = []

        for frameIndex in 0..<count {
            let time =
                Double(frameIndex) * frameStep
            let centre =
                time + frameDuration / 2

            var decibels =
                Array(repeating: noise, count: columns)

            let relative =
                centre - startTime

            if relative >= 0 {
                let symbol =
                    Int(floor(relative / 0.160))

                if tones.indices.contains(symbol) {
                    let frequency =
                        baseFrequency
                        + Float(tones[symbol]) * 6.25
                        + driftHzPerSecond
                            * Float(centre - startTime)

                    let exactBin = frequency / binWidth
                    let lower = Int(floor(exactBin))
                    let upper = lower + 1
                    let fraction = exactBin - Float(lower)

                    if decibels.indices.contains(lower) {
                        let power =
                            powf(10, Float(-8) / 10) * (1 - fraction)
                        decibels[lower] =
                            10 * log10f(max(
                                power,
                                Float.leastNonzeroMagnitude
                            ))
                    }

                    if decibels.indices.contains(upper) {
                        let power =
                            powf(10, Float(-8) / 10) * fraction
                        decibels[upper] =
                            10 * log10f(max(
                                power,
                                Float.leastNonzeroMagnitude
                            ))
                    }
                }
            }

            let magnitudes =
                decibels.map { powf(10, $0 / 20) }

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
