import XCTest
import FT8Encoder
@testable import FT8Decoder

final class FT8SlotDecoderIntegrationTests: XCTestCase {
    func testDecodesGeneratedWaveformToText() throws {
        let text = "CQ G0ABC IO91"
        let tones = try FT8Encoder.encode(text: text)
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

        XCTAssertGreaterThan(result.metrics.candidatesFound, 0)
        XCTAssertGreaterThan(result.metrics.candidatesScheduled, 0)
        XCTAssertGreaterThan(result.metrics.softSymbolsExtracted, 0)
        XCTAssertLessThanOrEqual(
            result.metrics.candidatesScheduled,
            12
        )
        XCTAssertLessThanOrEqual(
            result.metrics.ldpcAttempts,
            result.metrics.softSymbolsExtracted
        )
        XCTAssertEqual(
            result.metrics.messagesReturned,
            result.messages.count
        )
        XCTAssertGreaterThanOrEqual(result.metrics.elapsedSeconds, 0)
    }
}
