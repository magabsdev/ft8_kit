import XCTest
import FT8DSP
import FT8Encoder
@testable import FT8Decoder

final class WaveformIntegrationTests: XCTestCase {
    func testSynchronizerFindsEncodedWaveform() throws {
        let tones = try FT8Encoder.encode(text: "CQ TEST")
        let waveform = FT8Waveform.generate(
            tones: tones,
            configuration: .init(
                sampleRate: 12_000,
                baseFrequency: 1_000,
                amplitude: 0.9,
                padToSlot: true
            )
        )

        let spectrogram = try Waterfall.analyse(
            samples: waveform,
            configuration: .init(
                sampleRate: 12_000,
                fftSize: 2_048,
                hopSize: 480,
                minimumFrequency: 800,
                maximumFrequency: 1_200,
                dynamicRange: 80
            )
        )

        let candidates = try FT8Synchronizer(
            configuration: .init(
                minimumFrequency: 900,
                maximumFrequency: 1_100,
                frequencyStep: 6.25,
                minimumSyncScore: 0.45,
                minimumSNRDB: 2,
                estimateDrift: false
            )
        ).search(in: spectrogram)

        XCTAssertTrue(candidates.contains { abs($0.frequency - 1_000) <= 12.5 })
    }
}
