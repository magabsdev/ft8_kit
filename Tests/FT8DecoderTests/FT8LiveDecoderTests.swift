import XCTest
@testable import FT8Decoder

final class FT8LiveDecoderTests: XCTestCase {
    func testDoesNotDecodeBeforeFullSlot() async throws {
        let decoder = try makeDecoder(
            sampleRate: 10,
            slotDuration: 2,
            decodeStride: 2
        )

        let events = try await decoder.append(
            samples: Array(repeating: 0, count: 19)
        )

        XCTAssertTrue(events.isEmpty)
        let buffered = await decoder.bufferedSampleCount
        XCTAssertEqual(buffered, 19)
    }

    func testProducesDecodeEventAtStride() async throws {
        let decoder = try makeDecoder(
            sampleRate: 10,
            slotDuration: 2,
            decodeStride: 2
        )

        let events = try await decoder.append(
            samples: Array(repeating: 0, count: 20)
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].sequence, 1)
        XCTAssertEqual(events[0].slotStartSample, 0)
        let received = await decoder.receivedSampleCount
        XCTAssertEqual(received, 20)
    }

    func testChunkedStreamingProducesSameBoundary() async throws {
        let decoder = try makeDecoder(
            sampleRate: 10,
            slotDuration: 2,
            decodeStride: 2
        )

        let first = try await decoder.append(
            samples: Array(repeating: 0, count: 7)
        )
        let second = try await decoder.append(
            samples: Array(repeating: 0, count: 8)
        )
        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)

        let events = try await decoder.append(
            samples: Array(repeating: 0, count: 5)
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].slotStartSample, 0)
    }

    func testSlidingStrideProducesMultipleEvents() async throws {
        let decoder = try makeDecoder(
            sampleRate: 10,
            slotDuration: 2,
            decodeStride: 1
        )

        let first = try await decoder.append(
            samples: Array(repeating: 0, count: 20)
        )
        let second = try await decoder.append(
            samples: Array(repeating: 0, count: 10)
        )

        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(
            (first + second).map(\.sequence),
            [1, 2, 3]
        )
    }

    func testResetClearsStreamingState() async throws {
        let decoder = try makeDecoder(
            sampleRate: 10,
            slotDuration: 2,
            decodeStride: 2
        )

        _ = try await decoder.append(
            samples: Array(repeating: 0, count: 20)
        )
        await decoder.reset()

        let buffered = await decoder.bufferedSampleCount
        let received = await decoder.receivedSampleCount
        XCTAssertEqual(buffered, 0)
        XCTAssertEqual(received, 0)
    }

    func testInvalidConfigurationThrows() {
        XCTAssertThrowsError(
            try FT8LiveDecoder(
                configuration: .init(sampleRate: 0)
            )
        ) {
            XCTAssertEqual(
                $0 as? FT8LiveDecoderError,
                .invalidConfiguration
            )
        }
    }

    private func makeDecoder(
        sampleRate: Int,
        slotDuration: Double,
        decodeStride: Double
    ) throws -> FT8LiveDecoder {
        try FT8LiveDecoder(
            configuration: .init(
                sampleRate: sampleRate,
                slotDuration: slotDuration,
                retainedSlotCount: 2,
                decodeStride: decodeStride
            ),
            decoder: FT8SlotDecoder(
                waterfallConfiguration: .init(
                    sampleRate: Float(sampleRate),
                    fftSize: 8,
                    hopSize: 4,
                    minimumFrequency: 0,
                    maximumFrequency: Float(sampleRate) / 2,
                    dynamicRange: 100
                ),
                decoder: FT8OptimizedDecoder(
                    configuration: .init(
                        maximumCandidatesToDecode: 1,
                        minimumCandidateConfidence: 1,
                        minimumSoftSymbolConfidence: 1
                    ),
                    synchronizer: FT8Synchronizer(
                        configuration: .init(
                            symbolPeriod: 0.5,
                            toneSpacing: 0.1,
                            minimumFrequency: 0,
                            maximumFrequency: Float(sampleRate) / 2,
                            minimumSyncScore: 1,
                            minimumSNRDB: 100,
                            maximumCandidates: 1,
                            estimateDrift: false
                        )
                    )
                )
            )
        )
    }
}
