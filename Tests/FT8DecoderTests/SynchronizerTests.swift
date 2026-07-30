import Foundation
import XCTest
import FT8DSP
@testable import FT8Decoder

final class SynchronizerTests: XCTestCase {
    func testFindsSyntheticCandidate() throws {
        let spectrogram = SyntheticSpectrogram.make(
            baseFrequency: 1_000,
            startTime: 0.5
        )
        let synchronizer = FT8Synchronizer(
            configuration: .init(
                minimumFrequency: 950,
                maximumFrequency: 1_100,
                frequencyStep: 6.25,
                minimumSyncScore: 0.8,
                minimumSNRDB: 10,
                estimateDrift: false
            )
        )
        let candidates = try synchronizer.search(in: spectrogram)
        XCTAssertFalse(candidates.isEmpty)

        let best = candidates.max { $0.confidence < $1.confidence }!
        XCTAssertEqual(best.frequency, 1_000, accuracy: 6.25)
        XCTAssertEqual(best.startTime, 0.5, accuracy: 0.1)
        XCTAssertGreaterThan(best.confidence, 0.8)
    }

    func testFindsTwoSeparatedSignals() throws {
        let first = SyntheticSpectrogram.make(baseFrequency: 900, startTime: 0.4)
        let second = SyntheticSpectrogram.make(baseFrequency: 1_400, startTime: 0.6)
        let mergedFrames = zip(first.frames, second.frames).map { lhs, rhs in
            let db = zip(lhs.decibels, rhs.decibels).map(max)
            let magnitudes = db.map { powf(10, $0 / 20) }
            return FT8DSP.WaterfallFrame(
                index: lhs.index,
                sampleOffset: lhs.sampleOffset,
                time: lhs.time,
                minimumFrequency: lhs.minimumFrequency,
                binWidth: lhs.binWidth,
                magnitudes: magnitudes,
                decibels: db,
                intensities: db.map { min(max(($0 + 60) / 60, 0), 1) },
                noiseFloorDB: -60
            )
        }
        let merged = FT8DSP.Spectrogram(
            frames: mergedFrames,
            sampleRate: first.sampleRate,
            fftSize: first.fftSize,
            hopSize: first.hopSize,
            minimumFrequency: first.minimumFrequency,
            maximumFrequency: first.maximumFrequency
        )

        let candidates = try FT8Synchronizer(
            configuration: .init(
                minimumFrequency: 850,
                maximumFrequency: 1_500,
                frequencyStep: 6.25,
                minimumSyncScore: 0.8,
                minimumSNRDB: 10,
                estimateDrift: false
            )
        ).search(in: merged)

        XCTAssertTrue(candidates.contains { abs($0.frequency - 900) <= 6.25 })
        XCTAssertTrue(candidates.contains { abs($0.frequency - 1_400) <= 6.25 })
    }

    func testRejectsNoiseOnlySpectrogram() throws {
        let spectrogram = SyntheticSpectrogram.make(signalDB: -60, noiseDB: -60)
        let candidates = try FT8Synchronizer(
            configuration: .init(
                minimumFrequency: 900,
                maximumFrequency: 1_100,
                frequencyStep: 6.25,
                minimumSyncScore: 0.7,
                minimumSNRDB: 3,
                estimateDrift: false
            )
        ).search(in: spectrogram)

        XCTAssertTrue(candidates.isEmpty)
    }

    func testEstimatesPositiveDrift() throws {
        let spectrogram = SyntheticSpectrogram.make(
            baseFrequency: 1_000,
            startTime: 0.5,
            driftHzPerSecond: 3
        )
        let candidates = try FT8Synchronizer(
            configuration: .init(
                minimumFrequency: 990,
                maximumFrequency: 1_050,
                frequencyStep: 6.25,
                minimumSyncScore: 0.7,
                minimumSNRDB: 5,
                estimateDrift: true,
                maximumAbsoluteDrift: 3
            )
        ).search(in: spectrogram)

        let best = candidates.max { $0.confidence < $1.confidence }
        XCTAssertNotNil(best)
        XCTAssertEqual(best?.driftHzPerSecond ?? 0, 3, accuracy: 1.5)
    }

    func testMaximumCandidateLimit() throws {
        let spectrogram = SyntheticSpectrogram.make()
        let candidates = try FT8Synchronizer(
            configuration: .init(
                minimumFrequency: 900,
                maximumFrequency: 1_100,
                frequencyStep: 3.125,
                minimumSyncScore: 0.4,
                minimumSNRDB: 0,
                maximumCandidates: 2,
                estimateDrift: false
            )
        ).search(in: spectrogram)

        XCTAssertLessThanOrEqual(candidates.count, 2)
    }

    func testEmptySpectrogramThrows() {
        let empty = FT8DSP.Spectrogram(
            frames: [],
            sampleRate: 12_000,
            fftSize: 1_920,
            hopSize: 480,
            minimumFrequency: 0,
            maximumFrequency: 6_000
        )
        XCTAssertThrowsError(try FT8Synchronizer().search(in: empty)) {
            XCTAssertEqual($0 as? SynchronizerError, .emptySpectrogram)
        }
    }

    func testInvalidConfigurationThrows() {
        let spectrogram = SyntheticSpectrogram.make()
        let synchronizer = FT8Synchronizer(
            configuration: .init(symbolPeriod: 0)
        )
        XCTAssertThrowsError(try synchronizer.search(in: spectrogram)) {
            XCTAssertEqual($0 as? SynchronizerError, .invalidConfiguration)
        }
    }
}
