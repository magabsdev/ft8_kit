import XCTest
import FT8Encoder
@testable import FT8Decoder

final class FT8RoundTripTests: XCTestCase {
    func testGeneratedWaveformDecodesBackToOriginalMessage() throws {
        let expectedMessage = "CQ TEST"
        let tones = try FT8Encoder.encode(text: expectedMessage)
        let waveform = FT8Waveform.generate(
            tones: tones,
            configuration: .init(
                sampleRate: 12_000,
                baseFrequency: 1_000,
                amplitude: 0.9,
                padToSlot: true
            )
        )

        XCTAssertEqual(waveform.count, 180_000)

        let decoder = FT8MultiPassSlotDecoder(
            waterfallConfiguration: .init(
                sampleRate: 12_000,
                fftSize: 2_048,
                hopSize: 480,
                minimumFrequency: 800,
                maximumFrequency: 1_200,
                dynamicRange: 80
            )
        )

        let batch = try decoder.decode(samples: waveform)
        let decodedTexts = batch.messages.map(\.decoded.text)

        XCTAssertTrue(
            decodedTexts.contains(expectedMessage),
            """
            Expected \(expectedMessage) but decoded \(decodedTexts).
            Pass metrics: \(batch.metrics.passes)
            """
        )
    }
}
