import Foundation
import XCTest
@testable import FT8Decoder

final class FT8RealtimeDecoderTests: XCTestCase {
    func testRejectsMismatchedSampleRate() async throws {
        let decoder = try FT8RealtimeDecoder(
            configuration: .init(
                sampleRate: 100,
                slotDuration: 1
            )
        )

        do {
            _ = try await decoder.append(
                samples: [0, 0],
                sampleRate: 99,
                startingAt: Date(
                    timeIntervalSince1970: 0
                )
            )
            XCTFail("Expected sample-rate error")
        } catch {
            XCTAssertEqual(
                error as? FT8RealtimeDecoderError,
                .sampleRateMismatch(
                    expected: 100,
                    actual: 99
                )
            )
        }
    }

    func testSmallGapIsFilledWithSilence()
        async throws
    {
        let decoder = try FT8RealtimeDecoder(
            configuration: .init(
                sampleRate: 100,
                slotDuration: 1,
                timingToleranceSamples: 0,
                maximumRecoverableGap: 0.1
            )
        )

        _ = try await decoder.append(
            samples: Array(repeating: 0, count: 40),
            sampleRate: 100,
            startingAt: Date(
                timeIntervalSince1970: 0
            )
        )
        _ = try await decoder.append(
            samples: Array(repeating: 0, count: 40),
            sampleRate: 100,
            startingAt: Date(
                timeIntervalSince1970: 0.5
            )
        )

        let metrics = await decoder.diagnostics()
        XCTAssertEqual(
            metrics.insertedSilenceSamples,
            10
        )
    }

    func testOverlapSamplesAreDropped()
        async throws
    {
        let decoder = try FT8RealtimeDecoder(
            configuration: .init(
                sampleRate: 100,
                slotDuration: 1,
                timingToleranceSamples: 0
            )
        )

        _ = try await decoder.append(
            samples: Array(repeating: 0, count: 40),
            sampleRate: 100,
            startingAt: Date(
                timeIntervalSince1970: 0
            )
        )
        _ = try await decoder.append(
            samples: Array(repeating: 0, count: 30),
            sampleRate: 100,
            startingAt: Date(
                timeIntervalSince1970: 0.3
            )
        )

        let metrics = await decoder.diagnostics()
        XCTAssertEqual(
            metrics.droppedOverlapSamples,
            10
        )
    }

    func testResetClearsDiagnostics()
        async throws
    {
        let decoder = try FT8RealtimeDecoder(
            configuration: .init(
                sampleRate: 100,
                slotDuration: 1
            )
        )

        _ = try await decoder.append(
            samples: [0, 0, 0],
            sampleRate: 100,
            startingAt: Date(
                timeIntervalSince1970: 0.25
            )
        )
        await decoder.reset()

        let metrics = await decoder.diagnostics()
        XCTAssertEqual(
            metrics,
            FT8RealtimeDiagnostics(
                receivedSamples: 0,
                insertedSilenceSamples: 0,
                droppedOverlapSamples: 0,
                discardedPartialSlots: 0,
                decodedSlots: 0
            )
        )
    }
}
