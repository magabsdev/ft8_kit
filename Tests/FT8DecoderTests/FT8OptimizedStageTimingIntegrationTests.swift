import XCTest
import FT8DSP
import FT8Encoder
@testable import FT8Decoder

final class FT8OptimizedStageTimingIntegrationTests: XCTestCase {
    func testStageTimingCaptureIsDisabledByDefault() {
        XCTAssertFalse(
            FT8OptimizedDecoderConfiguration().captureStageTimings
        )
    }

    func testBatchInitializerRetainsStageTimings() {
        let metrics = FT8DecodeMetrics(
            candidatesFound: 0,
            candidatesScheduled: 0,
            softSymbolsExtracted: 0,
            ldpcAttempts: 0,
            parityPassed: 0,
            crcPassed: 0,
            messagesReturned: 0,
            elapsedSeconds: 0
        )
        let timings = FT8DecodeStageTimings(
            synchronizerSeconds: 0.25,
            schedulingSeconds: 0.01
        )

        let batch = FT8DecodeBatch(
            messages: [],
            metrics: metrics,
            stageTimings: timings
        )

        XCTAssertEqual(batch.stageTimings, timings)
    }

    func testGeneratedWaveformCapturesLiveStageTimings() throws {
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
                    minimumSoftSymbolConfidence: 0,
                    captureStageTimings: true
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

        let batch = try slotDecoder.decode(samples: waveform)
        let timings = try XCTUnwrap(batch.stageTimings)

        XCTAssertGreaterThan(timings.synchronizerSeconds, 0)
        XCTAssertGreaterThan(timings.schedulingSeconds, 0)
        XCTAssertGreaterThan(timings.softSymbolExtractionSeconds, 0)
        XCTAssertGreaterThan(timings.ldpcSeconds, 0)
        XCTAssertGreaterThan(timings.messageDecodeSeconds, 0)
        XCTAssertGreaterThan(timings.deduplicationSeconds, 0)
        XCTAssertGreaterThan(timings.measuredSeconds, 0)
        XCTAssertLessThanOrEqual(
            timings.measuredSeconds,
            batch.metrics.elapsedSeconds * 1.05
        )
        XCTAssertNotNil(timings.slowestStage)
        XCTAssertTrue(
            batch.messages.contains {
                $0.decoded.text == text
            }
        )
    }

    func testDisabledCaptureLeavesStageTimingsNil() throws {
        let spectrogram = Spectrogram(
            frames: [],
            sampleRate: 12_000,
            fftSize: 4_096,
            hopSize: 120
        )

        let decoder = FT8OptimizedDecoder(
            configuration: .init(captureStageTimings: false)
        )

        let batch = try decoder.decode(spectrogram: spectrogram)

        XCTAssertNil(batch.stageTimings)
    }
}
