import XCTest
import FT8DSP
import FT8Encoder
@testable import FT8Decoder

final class FT8MultiPassDecoderTests: XCTestCase {
    func testInvalidConfigurationThrows() {
        let decoder = FT8MultiPassDecoder(
            configuration: .init(
                maximumPasses: 0
            )
        )
        let spectrogram = SyntheticSpectrogram.make(
            baseFrequency: 1_000,
            duration: 13
        )

        XCTAssertThrowsError(
            try decoder.decode(
                spectrogram: spectrogram
            )
        )
    }

    func testProductionDefaultsUseBoundedResidualPasses() {
        let configuration =
            FT8MultiPassConfiguration()

        XCTAssertEqual(
            configuration.maximumPasses,
            5
        )
        XCTAssertEqual(
            configuration.maximumSignalsPerPass,
            1
        )
        XCTAssertTrue(
            configuration
                .suppressDuplicatePayloadAcrossPasses
        )
        XCTAssertTrue(
            configuration
                .disableRobustLDPCOnResidualPasses
        )
        XCTAssertEqual(
            configuration
                .residualMaximumCandidatesToDecode,
            60
        )
    }

    func testNoiseOnlyStopsAfterFirstPass()
        throws
    {
        let optimized = FT8OptimizedDecoder(
            synchronizer: FT8Synchronizer(
                configuration: .init(
                    minimumFrequency: 900,
                    maximumFrequency: 1_100,
                    minimumSyncScore: 1,
                    minimumSNRDB: 100,
                    maximumCandidates: 4,
                    estimateDrift: false
                )
            )
        )
        let decoder = FT8MultiPassDecoder(
            configuration: .init(
                maximumPasses: 3
            ),
            decoder: optimized
        )
        let spectrogram = SyntheticSpectrogram.make(
            baseFrequency: 1_000,
            duration: 13,
            signalDB: -120,
            noiseDB: -120
        )

        let batch = try decoder.decode(
            spectrogram: spectrogram
        )

        XCTAssertTrue(batch.messages.isEmpty)
        XCTAssertEqual(
            batch.metrics.passesCompleted,
            1
        )
        XCTAssertEqual(
            batch.metrics.totalSignalsCancelled,
            0
        )
    }

    func testGeneratedWaveformProducesPassMetrics()
        throws
    {
        let tones = try FT8Encoder.encode(
            text: "CQ G0ABC IO91"
        )
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

        let optimized = FT8OptimizedDecoder(
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

        let decoder = FT8MultiPassSlotDecoder(
            decoder: FT8MultiPassDecoder(
                configuration: .init(
                    maximumPasses: 2,
                    maximumSignalsPerPass: 1
                ),
                decoder: optimized
            )
        )

        let batch = try decoder.decode(
            samples: waveform
        )

        XCTAssertFalse(
            batch.metrics.passes.isEmpty
        )
        XCTAssertLessThanOrEqual(
            batch.metrics.passesCompleted,
            2
        )
        XCTAssertEqual(
            batch.metrics.uniqueMessages,
            batch.messages.count
        )

        for pass in batch.metrics.passes {
            XCTAssertGreaterThanOrEqual(
                pass.returnedCRCValidMessages,
                0
            )
            XCTAssertEqual(
                pass.signalsCancelled,
                pass.cancelledMessages.count
            )
        }
    }
}
