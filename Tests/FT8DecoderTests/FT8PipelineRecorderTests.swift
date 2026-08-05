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

    func testExtractDataTonesRemovesThreeCostasBlocks() throws {
        let received = (0..<79).map { UInt8($0) }
        let data = try FT8PipelineRecorder.extractDataTones(
            from: received
        )

        XCTAssertEqual(data.count, 58)
        XCTAssertEqual(data.first, 7)
        XCTAssertEqual(data[28], 35)
        XCTAssertEqual(data[29], 43)
        XCTAssertEqual(data.last, 71)
    }

    func testExtractDataTonesRejectsWrongInputLength() {
        XCTAssertThrowsError(
            try FT8PipelineRecorder.extractDataTones(
                from: Array(repeating: 0, count: 78)
            )
        ) { error in
            XCTAssertEqual(
                error as? FT8PipelineRecorderError,
                .invalidReceivedToneCount(actual: 78)
            )
        }
    }

    func testGrayMappingForAllEightTonesMatchesToneMapping() throws {
        let tones = Array(0...7).map(UInt8.init)
        let repeated = Array(
            repeating: tones,
            count: 8
        ).flatMap { $0 }.prefix(58)

        let bits = try FT8PipelineRecorder.mapDataTonesToBits(
            Array(repeated)
        )

        XCTAssertEqual(bits.count, 174)

        for index in 0..<58 {
            let tone = Int(repeated[repeated.index(
                repeated.startIndex,
                offsetBy: index
            )])
            let expected = FT8ToneMapping.bits(forTone: tone)
            let offset = index * 3

            XCTAssertEqual(bits[offset], expected.0)
            XCTAssertEqual(bits[offset + 1], expected.1)
            XCTAssertEqual(bits[offset + 2], expected.2)
        }
    }

    func testKnownInverseGrayMap() throws {
        let tones: [UInt8] = [
            0, 1, 3, 2, 7, 6, 4, 5
        ]
        let dataTones = Array(
            repeating: tones,
            count: 8
        ).flatMap { $0 }.prefix(58)

        let bits = try FT8PipelineRecorder.mapDataTonesToBits(
            Array(dataTones)
        )

        XCTAssertEqual(
            Array(bits.prefix(24)),
            [
                0, 0, 0,
                0, 0, 1,
                0, 1, 0,
                0, 1, 1,
                1, 0, 0,
                1, 0, 1,
                1, 1, 0,
                1, 1, 1
            ]
        )
    }

    func testMapDataTonesRejectsWrongLength() {
        XCTAssertThrowsError(
            try FT8PipelineRecorder.mapDataTonesToBits(
                Array(repeating: 0, count: 57)
            )
        ) { error in
            XCTAssertEqual(
                error as? FT8PipelineRecorderError,
                .invalidDataToneCount(actual: 57)
            )
        }
    }

    func testMapDataTonesRejectsInvalidTone() {
        var tones = Array(repeating: UInt8.zero, count: 58)
        tones[12] = 8

        XCTAssertThrowsError(
            try FT8PipelineRecorder.mapDataTonesToBits(tones)
        ) { error in
            XCTAssertEqual(
                error as? FT8PipelineRecorderError,
                .invalidToneValue(index: 12, value: 8)
            )
        }
    }

    func testCapturePopulatesToneAndGrayBitStages() throws {
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

        XCTAssertEqual(record.receivedTones.count, 79)
        XCTAssertEqual(record.dataTones.count, 58)
        XCTAssertEqual(record.grayMappedBits.count, 174)
        XCTAssertEqual(
            record.grayMappedBits,
            try FT8PipelineRecorder.mapDataTonesToBits(
                record.dataTones
            )
        )
        XCTAssertTrue(record.interleavedBits.isEmpty)
        XCTAssertTrue(record.logLikelihoodRatios.isEmpty)
        XCTAssertTrue(record.isStructurallyValid)
    }
}
