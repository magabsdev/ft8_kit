import XCTest
import FT8DSP
@testable import FT8Decoder

final class CostasCorrelatorTests: XCTestCase {
    func testPerfectPatternProducesHighScore() {
        let spectrogram = SyntheticSpectrogram.make()
        let result = CostasCorrelator.correlate(
            spectrogram: spectrogram,
            startTime: 0.5,
            baseFrequency: 1_000
        )
        XCTAssertEqual(result.observations, 21)
        XCTAssertGreaterThan(result.score, 0.99)
        XCTAssertGreaterThan(result.snrDB, 40)
    }

    func testWrongFrequencyProducesLowScore() {
        let spectrogram = SyntheticSpectrogram.make()
        let result = CostasCorrelator.correlate(
            spectrogram: spectrogram,
            startTime: 0.5,
            baseFrequency: 1_100
        )
        XCTAssertLessThan(result.score, 0.6)
    }

    func testWrongTimeProducesLowScore() {
        let spectrogram = SyntheticSpectrogram.make()
        let result = CostasCorrelator.correlate(
            spectrogram: spectrogram,
            startTime: 0.9,
            baseFrequency: 1_000
        )
        XCTAssertLessThan(result.score, 0.75)
    }

    func testDriftCompensationImprovesScore() {
        let spectrogram = SyntheticSpectrogram.make(driftHzPerSecond: 3)
        let uncompensated = CostasCorrelator.correlate(
            spectrogram: spectrogram,
            startTime: 0.5,
            baseFrequency: 1_000,
            driftHzPerSecond: 0
        )
        let compensated = CostasCorrelator.correlate(
            spectrogram: spectrogram,
            startTime: 0.5,
            baseFrequency: 1_000,
            driftHzPerSecond: 3
        )
        XCTAssertGreaterThan(compensated.score, uncompensated.score)
    }

    func testEmptySpectrogramReturnsNoObservations() {
        let empty = FT8DSP.Spectrogram(
            frames: [],
            sampleRate: 12_000,
            fftSize: 1_920,
            hopSize: 480,
            minimumFrequency: 0,
            maximumFrequency: 6_000
        )
        let result = CostasCorrelator.correlate(
            spectrogram: empty,
            startTime: 0,
            baseFrequency: 1_000
        )
        XCTAssertEqual(result.observations, 0)
        XCTAssertEqual(result.score, 0)
    }
}
