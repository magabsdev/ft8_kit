import XCTest
@testable import FT8DSP

final class SpectrumTests: XCTestCase {
    func testDetectsOneKilohertzTone() throws {
        let sampleRate: Float = 12_000
        let size = 4_096
        let frequency: Float = 1_000
        let samples = (0..<size).map {
            sinf(2 * .pi * frequency * Float($0) / sampleRate)
        }

        let spectrum = try Spectrum.analyse(
            samples: samples,
            sampleRate: sampleRate,
            window: .hann
        )
        let peak = spectrum.magnitudes.enumerated().max { $0.element < $1.element }!
        XCTAssertEqual(
            spectrum.frequency(atBin: peak.offset),
            frequency,
            accuracy: spectrum.binWidth
        )
    }

    func testOneSidedSpectrumCount() throws {
        let spectrum = try Spectrum.analyse(
            samples: Array(repeating: 0, count: 1024),
            sampleRate: 12_000,
            window: .rectangular
        )
        XCTAssertEqual(spectrum.magnitudes.count, 513)
        XCTAssertEqual(spectrum.powers.count, 513)
    }

    func testZeroSignalUsesFloor() throws {
        let spectrum = try Spectrum.analyse(
            samples: Array(repeating: 0, count: 256),
            sampleRate: 12_000
        )
        XCTAssertTrue(spectrum.decibels(floor: -120).allSatisfy { $0 == -120 })
    }

    func testNearestBinClamps() throws {
        let spectrum = try Spectrum.analyse(
            samples: Array(repeating: 0, count: 256),
            sampleRate: 12_000
        )
        XCTAssertEqual(spectrum.nearestBin(to: -100), 0)
        XCTAssertEqual(spectrum.nearestBin(to: 99_999), spectrum.magnitudes.count - 1)
    }
}
