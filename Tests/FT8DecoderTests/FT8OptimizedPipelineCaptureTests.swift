import XCTest
import FT8Encoder
@testable import FT8Decoder

final class FT8OptimizedPipelineCaptureTests: XCTestCase {
    func testPipelineCaptureIsDisabledByDefault() {
        XCTAssertFalse(
            FT8OptimizedDecoderConfiguration().capturePipelineRecords
        )
    }

    func testGeneratedWaveformProducesCompletePipelineRecord() throws {
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
                    capturePipelineRecords: true
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

        XCTAssertFalse(batch.pipelineRecords.isEmpty)
        XCTAssertTrue(
            batch.pipelineRecords.allSatisfy(\.isStructurallyValid)
        )

        let successful = batch.pipelineRecords.first {
            $0.decodedText == text
                && $0.failureReason == nil
                && $0.decodedCodeword.count
                    == FT8PipelineRecord.channelBitCount
                && $0.informationBits.count
                    == FT8PipelineRecord.informationBitCount
        }

        XCTAssertNotNil(successful)
        XCTAssertEqual(successful?.parityPassed, true)
        XCTAssertEqual(successful?.crcPassed, true)
        XCTAssertNotNil(successful?.messageConfidence)
    }

    func testBatchInitializerRetainsPipelineRecords() {
        let record = FT8PipelineRecord(
            candidateIndex: 1,
            startTime: 0,
            frequency: 1_000,
            synchronizerScore: 0.8
        )
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

        let batch = FT8DecodeBatch(
            messages: [],
            metrics: metrics,
            pipelineRecords: [record]
        )

        XCTAssertEqual(batch.pipelineRecords, [record])
    }
}
