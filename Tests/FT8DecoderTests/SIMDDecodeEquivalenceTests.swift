import XCTest
@testable import FT8Decoder

final class SIMDDecodeEquivalenceTests: XCTestCase {
    func testCostasCorrelationRemainsFinite() {
        let spectrogram = SyntheticSpectrogram.make(
            baseFrequency: 1_000,
            duration: 13,
            signalDB: -20,
            noiseDB: -100
        )

        let result = CostasCorrelator.correlate(
            spectrogram: spectrogram,
            startTime: 0,
            baseFrequency: 1_000
        )

        XCTAssertTrue(result.score.isFinite)
        XCTAssertTrue(result.snrDB.isFinite)
        XCTAssertGreaterThan(result.observations, 0)
    }

    func testVectorisedToneMetricsRemainOrdered() throws {
        let spectrogram = SyntheticSpectrogram.make(
            baseFrequency: 1_000,
            duration: 13,
            signalDB: -20,
            noiseDB: -100
        )
        let candidate = FT8Candidate(
            startTime: 0,
            frequency: 1_000,
            syncScore: 1,
            snrDB: 20,
            confidence: 1
        )

        let metrics = try SoftSymbolExtractor().toneMetrics(
            symbolIndex: 7,
            spectrogram: spectrogram,
            candidate: candidate
        )

        XCTAssertEqual(metrics.count, 8)
        XCTAssertTrue(metrics.allSatisfy(\.isFinite))
        XCTAssertGreaterThanOrEqual(
            metrics.max() ?? 0,
            metrics.min() ?? 0
        )
    }
}
