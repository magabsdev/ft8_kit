import Foundation
import XCTest
@testable import FT8Decoder

final class FT8DecodeStageProfilerTests: XCTestCase {
    func testAccumulatesRepeatedStageMeasurements() throws {
        var profiler = FT8DecodeStageProfiler()

        _ = profiler.measure(.ldpc) { 1 }
        _ = profiler.measure(.ldpc) { 2 }

        XCTAssertGreaterThanOrEqual(
            profiler.snapshot.ldpcSeconds,
            0
        )
        XCTAssertEqual(
            profiler.snapshot.synchronizerSeconds,
            0
        )
    }

    func testMeasureReturnsOperationResult() throws {
        var profiler = FT8DecodeStageProfiler()

        let value = profiler.measure(.messageDecode) {
            "CQ G0ABC IO91"
        }

        XCTAssertEqual(value, "CQ G0ABC IO91")
    }

    func testMeasureRecordsThrowingOperation() {
        enum TestError: Error {
            case expected
        }

        var profiler = FT8DecodeStageProfiler()

        XCTAssertThrowsError(
            try profiler.measure(.softSymbolExtraction) {
                throw TestError.expected
            }
        )

        XCTAssertGreaterThanOrEqual(
            profiler.snapshot.softSymbolExtractionSeconds,
            0
        )
    }

    func testSlowestStageAndMeasuredTotal() {
        let timings = FT8DecodeStageTimings(
            synchronizerSeconds: 2,
            schedulingSeconds: 0.1,
            softSymbolExtractionSeconds: 5,
            ldpcSeconds: 1
        )

        XCTAssertEqual(timings.measuredSeconds, 8.1)
        XCTAssertEqual(
            timings.slowestStage,
            .softSymbolExtraction
        )
    }

    func testRejectsInvalidTimingValues() {
        var timings = FT8DecodeStageTimings()

        timings.add(.nan, to: .ldpc)
        timings.add(-1, to: .ldpc)
        timings.add(.infinity, to: .ldpc)

        XCTAssertEqual(timings.ldpcSeconds, 0)
    }

    func testWriterCreatesJSONAndCSV() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let timings = FT8DecodeStageTimings(
            synchronizerSeconds: 1,
            ldpcSeconds: 3
        )

        try FT8DecodeStageTimingWriter().write(
            timings,
            to: directory
        )

        let jsonURL = directory.appendingPathComponent(
            "decode-stage-timings.json"
        )
        let csvURL = directory.appendingPathComponent(
            "decode-stage-timings.csv"
        )

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: jsonURL.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: csvURL.path)
        )

        let csv = try String(
            contentsOf: csvURL,
            encoding: .utf8
        )
        XCTAssertTrue(csv.contains("softSymbolExtraction"))
        XCTAssertTrue(csv.contains("ldpc,3.0,0.75"))

        try? FileManager.default.removeItem(at: directory)
    }
}
