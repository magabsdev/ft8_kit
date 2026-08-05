import XCTest
@testable import FT8Decoder

final class FT8PipelineRecorderTests: XCTestCase {
    func testStrongestTonesSelectsPeakForEverySymbol() throws {
        let expected = (0..<79).map { UInt8($0 % 8) }
        let metrics = expected.map { tone -> [Float] in
            (0..<8).map {
                $0 == Int(tone) ? 10 : Float($0)
            }
        }

        let tones = try FT8PipelineRecorder.strongestTones(
            from: metrics
        )

        XCTAssertEqual(tones, expected)
        XCTAssertEqual(tones.count, 79)
    }

    func testEqualMetricsUseLowestToneAsStableTieBreak() throws {
        let metrics = Array(
            repeating: Array(repeating: Float(1), count: 8),
            count: 79
        )

        let tones = try FT8PipelineRecorder.strongestTones(
            from: metrics
        )

        XCTAssertEqual(tones, Array(repeating: 0, count: 79))
    }

    func testInvalidMetricCountThrows() {
        XCTAssertThrowsError(
            try FT8PipelineRecorder.strongestTones(
                from: [Array(repeating: 1, count: 7)]
            )
        ) { error in
            XCTAssertEqual(
                error as? FT8PipelineRecorderError,
                .invalidMetricCount(symbolIndex: 0, actual: 7)
            )
        }
    }

    func testCapturePopulatesOnlyReceivedToneStage() throws {
        let candidate = FT8Candidate(
            startTime: 1.25,
            frequency: 1_000,
            driftHzPerSecond: 0,
            symbolOffset: 7.8125,
            syncScore: 0.9,
            snrDB: 5,
            confidence: 0.8
        )
        let metrics = (0..<79).map { symbol -> [Float] in
            (0..<8).map {
                $0 == symbol % 8 ? 5 : 0
            }
        }

        let record = try FT8PipelineRecorder().captureReceivedTones(
            candidateIndex: 3,
            candidate: candidate,
            toneMetrics: metrics
        )

        XCTAssertEqual(record.candidateIndex, 3)
        XCTAssertEqual(record.startTime, candidate.startTime)
        XCTAssertEqual(record.frequency, candidate.frequency)
        XCTAssertEqual(record.synchronizerScore, candidate.syncScore)
        XCTAssertEqual(record.receivedTones.count, 79)
        XCTAssertTrue(record.dataTones.isEmpty)
        XCTAssertTrue(record.grayMappedBits.isEmpty)
        XCTAssertTrue(record.interleavedBits.isEmpty)
        XCTAssertTrue(record.logLikelihoodRatios.isEmpty)
        XCTAssertTrue(record.isStructurallyValid)
    }
}
