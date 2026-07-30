import XCTest
import FT8Encoder
@testable import FT8Decoder

final class FT8SlotDecoderIntegrationTests: XCTestCase {
    func testDecodesGeneratedWaveformToText() throws {
        let expectedText = "CQ G0ABC IO91"
        let tones = try FT8Encoder.encode(text: expectedText)
        let waveform = FT8Waveform.generate(
            tones: tones,
            configuration: .init(
                sampleRate: 12_000,
                baseFrequency: 1_000,
                amplitude: 0.95,
                padToSlot: true
            )
        )

        let synchronizer = FT8Synchronizer(
            configuration: .init(
                minimumFrequency: 900,
                maximumFrequency: 1_100,
                frequencyStep: 3.125,
                minimumSyncScore: 0.30,
                minimumSNRDB: 0,
                maximumCandidates: 12,
                estimateDrift: false
            )
        )

        let slotDecoder = FT8SlotDecoder(
            decoder: FT8OptimizedDecoder(
                configuration: .init(
                    maximumCandidatesToDecode: 12,
                    minimumCandidateConfidence: 0,
                    minimumSoftSymbolConfidence: 0
                ),
                synchronizer: synchronizer,
                extractor: SoftSymbolExtractor(
                    configuration: .init(
                        integrationRadius: 1,
                        minimumObservationsPerSymbol: 2,
                        llrScale: 1,
                        llrLimit: 24
                    )
                )
            )
        )

        let result = try slotDecoder.decode(samples: waveform)
        let decodedTexts = result.messages.map(\.decoded.text)
        let diagnostics = makeDiagnostics(
            expectedText: expectedText,
            result: result
        )

        XCTAssertGreaterThan(
            result.metrics.candidatesFound,
            0,
            diagnostics
        )
        XCTAssertGreaterThan(
            result.metrics.candidatesScheduled,
            0,
            diagnostics
        )
        XCTAssertGreaterThan(
            result.metrics.softSymbolsExtracted,
            0,
            diagnostics
        )
        XCTAssertLessThanOrEqual(
            result.metrics.candidatesScheduled,
            12,
            diagnostics
        )
        XCTAssertLessThanOrEqual(
            result.metrics.ldpcAttempts,
            result.metrics.softSymbolsExtracted,
            diagnostics
        )
        XCTAssertEqual(
            result.metrics.messagesReturned,
            result.messages.count,
            diagnostics
        )
        XCTAssertGreaterThanOrEqual(
            result.metrics.elapsedSeconds,
            0,
            diagnostics
        )

        // This is the assertion the previous test was missing: the generated
        // waveform must decode back to the exact transmitted message.
        XCTAssertTrue(
            decodedTexts.contains(expectedText),
            "Expected '\(expectedText)' but decoded \(decodedTexts).\n\(diagnostics)"
        )
    }

    private func makeDiagnostics(
        expectedText: String,
        result: FT8DecodeBatch
    ) -> String {
        let messageDetails = result.messages.enumerated().map { index, decode in
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
        Slot decoder integration diagnostics
        expected: '\(expectedText)'
        metrics: \(String(reflecting: result.metrics))
        decoded details:
        \(messageDetails.isEmpty ? "<none>" : messageDetails)
        """
    }
}
