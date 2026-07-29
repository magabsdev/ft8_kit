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
        let llrs = (0..<174).map { $0.isMultiple(of: 2) ? Float(5) : Float(-5) }
        let soft = FT8SoftSymbols(
            logLikelihoodRatios: llrs,
            symbolConfidences: Array(repeating: 0.5, count: 58)
        )
        for index in 0..<174 {
            XCTAssertEqual(soft.hardBits[index], index.isMultiple(of: 2) ? 0 : 1)
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
        let tones = try FT8Encoder.encode(text: "DRIFT")
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
        XCTAssertGreaterThan(extracted.averageConfidence, 0.9)
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
            try SoftSymbolExtractor().extract(from: empty, candidate: candidate)
        ) {
            XCTAssertEqual($0 as? SoftSymbolError, .emptySpectrogram)
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
        let frameStep = Double(hopSize) / Double(sampleRate)
        let frameDuration = Double(fftSize) / Double(sampleRate)
        let duration = startTime + 79 * 0.160 + 0.4
        let count = Int(ceil(duration / frameStep))
        let binWidth = sampleRate / Float(fftSize)
        let columns = fftSize / 2 + 1
        let noise: Float = -70
        var frames: [WaterfallFrame] = []

        for frameIndex in 0..<count {
            let time = Double(frameIndex) * frameStep
            let centre = time + frameDuration / 2
            var decibels = Array(repeating: noise, count: columns)
            let relative = centre - startTime

            if relative >= 0 {
                let symbol = Int(floor(relative / 0.160))
                if tones.indices.contains(symbol) {
                    let frequency = baseFrequency
                        + Float(tones[symbol]) * 6.25
                        + driftHzPerSecond * Float(centre - startTime)
                    let bin = Int((frequency / binWidth).rounded())
                    if decibels.indices.contains(bin) {
                        decibels[bin] = -8
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
                    intensities: decibels.map { min(max(($0 - noise) / 70, 0), 1) },
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
