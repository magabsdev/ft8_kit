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

        let diagnostics = makeDiagnostics(
            expectedMessage: expectedMessage,
            messages: batch.messages,
            passMetrics: String(reflecting: batch.metrics.passes),
            elapsedSeconds: batch.metrics.elapsedSeconds
        )

        XCTAssertFalse(
            batch.messages.isEmpty,
            "Decoder returned no messages.\n\(diagnostics)"
        )
        XCTAssertTrue(
            decodedTexts.contains(expectedMessage),
            "Expected '\(expectedMessage)' but decoded \(decodedTexts).\n\(diagnostics)"
        )
    }

    private func makeDiagnostics(
        expectedMessage: String,
        messages: [FT8CompleteDecode],
        passMetrics: String,
        elapsedSeconds: Double
    ) -> String {
        let messageDetails = messages.enumerated().map { index, decode in
            """
            [\(index)]
              candidate frequency: \(decode.candidate.frequency) Hz
              candidate start time: \(decode.candidate.startTime) s
              candidate drift: \(decode.candidate.driftHzPerSecond) Hz/s
              sync score: \(decode.candidate.syncScore)
              SNR: \(decode.candidate.snrDB) dB
              candidate confidence: \(decode.candidate.confidence)
              parity passed: \(decode.ldpc.parityPassed)
              CRC passed: \(decode.ldpc.crcPassed)
              syndrome weight: \(decode.ldpc.syndromeWeight)
              \(decode.decoded.diagnosticSummary.replacingOccurrences(of: "\n", with: "\n  "))
            """
        }.joined(separator: "\n")

        return """
        Round-trip diagnostics
        expected: '\(expectedMessage)'
        returned messages: \(messages.count)
        total elapsed: \(elapsedSeconds) seconds
        pass metrics: \(passMetrics)
        decoded details:
        \(messageDetails.isEmpty ? "<none>" : messageDetails)
        """
    }
}
