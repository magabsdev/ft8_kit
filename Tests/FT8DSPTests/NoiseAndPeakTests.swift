import XCTest
@testable import FT8DSP

final class NoiseAndPeakTests: XCTestCase {
    func testMedianAndTrimmedMean() {
        XCTAssertEqual(
            NoiseFloorEstimator.median(of: [4, 1, 3, 2]),
            2.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            NoiseFloorEstimator.trimmedMean(
                of: [10, 10, 10, 10, 1_000],
                trimmingFraction: 0.2
            ),
            10,
            accuracy: 0.000_001
        )
    }

    func testRollingMedianRemovesSpike() {
        XCTAssertEqual(
            NoiseFloorEstimator.rollingMedian(
                values: [1, 1, 20, 1, 1],
                radius: 1
            )[2],
            1
        )
    }

    func testPeakDetectorFindsStrongLocalPeak() {
        let decibels: [Float] = [-40, -39, -20, -38, -40]
        let magnitudes = decibels.map { powf(10, $0 / 20) }
        let frame = WaterfallFrame(
            index: 0,
            sampleOffset: 0,
            time: 0,
            minimumFrequency: 1_000,
            binWidth: 6.25,
            magnitudes: magnitudes,
            decibels: decibels,
            intensities: decibels.map { _ in 0.5 },
            noiseFloorDB: -40
        )

        let peaks = PeakDetector(
            minimumSNRDB: 10,
            neighbourhoodRadius: 1
        ).detect(in: frame)

        XCTAssertEqual(peaks.count, 1)
        XCTAssertEqual(peaks[0].frequency, 1_012.5, accuracy: 0.001)
        XCTAssertEqual(peaks[0].snrDB, 20, accuracy: 0.001)
    }

    func testDetectorRejectsWeakPeak() {
        let decibels: [Float] = [-40, -39, -35, -38, -40]
        let magnitudes = decibels.map { powf(10, $0 / 20) }
        let frame = WaterfallFrame(
            index: 0,
            sampleOffset: 0,
            time: 0,
            minimumFrequency: 0,
            binWidth: 1,
            magnitudes: magnitudes,
            decibels: decibels,
            intensities: decibels.map { _ in 0 },
            noiseFloorDB: -40
        )

        XCTAssertTrue(
            PeakDetector(minimumSNRDB: 10).detect(in: frame).isEmpty
        )
    }
}
