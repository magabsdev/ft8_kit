import XCTest
import FT8DSP
@testable import FT8Decoder

final class FT8WaterfallTimingSemanticsTests: XCTestCase {
    func testSynchronizerAndExtractorUseSameCandidateStartConvention() throws {
        let expectedStart = 0.5
        let expectedFrequency: Float = 1_000

        let spectrogram = SyntheticSpectrogram.make(
            baseFrequency: expectedFrequency,
            startTime: expectedStart
        )

        var configuration = SynchronizerConfiguration()
        configuration.minimumFrequency = 980
        configuration.maximumFrequency = 1_070
        configuration.maximumCandidates = 20
        configuration.enableAdaptivePruning = false
        configuration.estimateDrift = false

        let candidates = try FT8Synchronizer(
            configuration: configuration
        ).search(in: spectrogram)

        let candidate = try XCTUnwrap(
            candidates.min {
                abs($0.frequency - expectedFrequency)
                    < abs($1.frequency - expectedFrequency)
            }
        )

        // Before this checkpoint the Costas correlator sampled its FFT window
        // half a symbol late, so the synchronizer compensated by returning a
        // start roughly 80 ms early. That made SoftSymbolExtractor sample the
        // wrong windows. Keep this as a regression on the shared convention.
        XCTAssertEqual(
            candidate.startTime,
            expectedStart,
            accuracy: 0.05
        )

        XCTAssertEqual(
            candidate.frequency,
            expectedFrequency,
            accuracy: 7
        )
    }

    func testCostasCorrelationUsesWaterfallWindowStartTimestamp() {
        let start = 0.5
        let spectrogram = SyntheticSpectrogram.make(
            startTime: start
        )

        let correct = CostasCorrelator.correlate(
            spectrogram: spectrogram,
            startTime: start,
            baseFrequency: 1_000
        )

        let halfSymbolEarly =
            CostasCorrelator.correlate(
                spectrogram: spectrogram,
                startTime: start - 0.080,
                baseFrequency: 1_000
            )

        XCTAssertGreaterThan(
            correct.score,
            halfSymbolEarly.score
        )
        XCTAssertGreaterThan(
            correct.score,
            0.99
        )
    }
}
