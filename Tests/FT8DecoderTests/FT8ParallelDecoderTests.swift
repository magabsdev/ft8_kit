import XCTest
import FT8Encoder
@testable import FT8Decoder

final class FT8ParallelDecoderTests: XCTestCase {
    func testRejectsInvalidWorkerCount() async throws {
        let decoder = FT8ParallelDecoder(
            configuration: .init(
                maximumConcurrentTasks: 0
            )
        )

        let spectrogram = SyntheticSpectrogram.make(
            baseFrequency: 1_000,
            duration: 13,
            signalDB: -120,
            noiseDB: -120
        )

        do {
            _ = try await decoder.decode(
                spectrogram: spectrogram
            )
            XCTFail("Expected invalid configuration")
        } catch {
            XCTAssertEqual(
                error as? FT8ParallelDecoderError,
                .invalidConfiguration
            )
        }
    }

    func testSchedulerIsDeterministic() {
        let decoder = FT8ParallelDecoder(
            configuration: .init(
                maximumConcurrentTasks: 2
            ),
            optimizedConfiguration: .init(
                maximumCandidatesToDecode: 3,
                minimumCandidateConfidence: 0
            )
        )

        let candidates = [
            candidate(1_000, confidence: 0.5),
            candidate(1_100, confidence: 0.9),
            candidate(1_200, confidence: 0.7),
            candidate(1_300, confidence: 0.8)
        ]

        XCTAssertEqual(
            decoder.schedule(candidates).map(\.frequency),
            [1_100, 1_300, 1_200]
        )
    }

    func testEmptySearchProducesZeroMetrics() async throws {
        let decoder = FT8ParallelDecoder(
            configuration: .init(
                maximumConcurrentTasks: 3
            ),
            synchronizer: FT8Synchronizer(
                configuration: .init(
                    minimumFrequency: 900,
                    maximumFrequency: 1_100,
                    minimumSyncScore: 1,
                    minimumSNRDB: 100,
                    maximumCandidates: 5,
                    estimateDrift: false
                )
            )
        )

        let spectrogram = SyntheticSpectrogram.make(
            baseFrequency: 1_000,
            duration: 13,
            signalDB: -120,
            noiseDB: -120
        )

        let batch = try await decoder.decode(
            spectrogram: spectrogram
        )

        XCTAssertTrue(batch.messages.isEmpty)
        XCTAssertEqual(batch.metrics.candidatesScheduled, 0)
        XCTAssertEqual(
            batch.parallelMetrics.candidateTasksCompleted,
            0
        )
        XCTAssertEqual(
            batch.parallelMetrics.peakConcurrentTasks,
            0
        )
    }

    func testParallelAndSequentialSchedulersMatch() {
        let configuration = FT8OptimizedDecoderConfiguration(
            maximumCandidatesToDecode: 4,
            minimumCandidateConfidence: 0.25
        )
        let sequential = FT8OptimizedDecoder(
            configuration: configuration
        )
        let parallel = FT8ParallelDecoder(
            optimizedConfiguration: configuration
        )

        let candidates = [
            candidate(900, confidence: 0.2),
            candidate(1_000, confidence: 0.4),
            candidate(1_100, confidence: 0.9),
            candidate(1_200, confidence: 0.6),
            candidate(1_300, confidence: 0.8)
        ]

        XCTAssertEqual(
            parallel.schedule(candidates),
            sequential.schedule(candidates)
        )
    }

    func testParallelSlotDecoderProcessesGeneratedWaveform()
        async throws
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

        let decoder = FT8ParallelSlotDecoder(
            decoder: FT8ParallelDecoder(
                configuration: .init(
                    maximumConcurrentTasks: 3
                ),
                optimizedConfiguration: .init(
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

        let batch = try await decoder.decode(
            samples: waveform
        )

        XCTAssertGreaterThan(
            batch.metrics.candidatesFound,
            0
        )
        XCTAssertGreaterThan(
            batch.parallelMetrics.candidateTasksCompleted,
            0
        )
        XCTAssertLessThanOrEqual(
            batch.parallelMetrics.peakConcurrentTasks,
            3
        )
        XCTAssertEqual(
            batch.metrics.messagesReturned,
            batch.messages.count
        )
    }

    private func candidate(
        _ frequency: Float,
        confidence: Float
    ) -> FT8Candidate {
        FT8Candidate(
            startTime: 0,
            frequency: frequency,
            syncScore: confidence,
            snrDB: 10,
            confidence: confidence
        )
    }
}
