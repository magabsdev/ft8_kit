import XCTest
@testable import FT8DSP

final class WaterfallPhase32Tests: XCTestCase {
    func testFrameCountAndDuration() throws {
        let configuration = WaterfallConfiguration(
            sampleRate: 1_024,
            fftSize: 256,
            hopSize: 128
        )
        let result = try Waterfall.analyse(
            samples: Array(repeating: 0, count: 1_024),
            configuration: configuration
        )

        XCTAssertEqual(result.rowCount, 7)
        XCTAssertEqual(result.duration, 1, accuracy: 0.000_001)
    }

    func testToneAppearsAtCorrectFrequency() throws {
        let sampleRate: Float = 12_000
        let frequency: Float = 1_500
        let samples = (0..<12_000).map {
            sinf(2 * .pi * frequency * Float($0) / sampleRate)
        }

        let result = try Waterfall.analyse(
            samples: samples,
            configuration: WaterfallConfiguration(
                sampleRate: sampleRate,
                fftSize: 2_048,
                hopSize: 1_024,
                minimumFrequency: 500,
                maximumFrequency: 2_500
            )
        )

        for frame in result.frames {
            let peak = frame.magnitudes.enumerated().max {
                $0.element < $1.element
            }!
            XCTAssertEqual(
                frame.frequency(at: peak.offset),
                frequency,
                accuracy: frame.binWidth
            )
        }
    }

    func testIntensitiesAreNormalised() throws {
        var samples = Array(repeating: Float.zero, count: 2_048)
        samples[200] = 1

        let result = try Waterfall.analyse(
            samples: samples,
            configuration: WaterfallConfiguration(
                sampleRate: 12_000,
                fftSize: 1_024
            )
        )

        XCTAssertTrue(
            result.intensityRows.flatMap { $0 }.allSatisfy {
                $0 >= 0 && $0 <= 1
            }
        )
    }

    func testInsufficientSamplesFails() {
        XCTAssertThrowsError(
            try Waterfall.analyse(
                samples: Array(repeating: 0, count: 100),
                configuration: WaterfallConfiguration(
                    sampleRate: 12_000,
                    fftSize: 1_024
                )
            )
        )
    }

    func testNearestFrame() throws {
        let result = try Waterfall.analyse(
            samples: Array(repeating: 0, count: 4_096),
            configuration: WaterfallConfiguration(
                sampleRate: 4_096,
                fftSize: 1_024,
                hopSize: 512
            )
        )

        XCTAssertEqual(
            result.frame(nearestTime: 0.27)?.time ?? -1,
            0.25,
            accuracy: 0.000_001
        )
    }
}
