import XCTest
@testable import FT8Validation

final class FT8ValidationTests: XCTestCase {
    func testDiscoversStandardCorpus() throws {
        let directory = try XCTUnwrap(Bundle.module.resourceURL?.appendingPathComponent("Fixtures"))
        let cases = try ReferenceCorpus.discover(in: directory)
        XCTAssertEqual(cases.count, 31)
        XCTAssertEqual(cases.filter { $0.expectedURL != nil }.count, 22)
    }

    func testLoadsTwelveKilohertzAndResamplesWebSDR() throws {
        let directory = try XCTUnwrap(Bundle.module.resourceURL?.appendingPathComponent("Fixtures"))
        let native = try WAVFile.load(url: directory.appendingPathComponent("191111_110130.wav"))
        let resampled = try WAVFile.load(url: directory.appendingPathComponent("websdr_test16.wav"))
        XCTAssertEqual(native.sampleRate, 12_000)
        XCTAssertEqual(resampled.sampleRate, 12_000)
        XCTAssertGreaterThan(native.samples.count, 170_000)
        XCTAssertGreaterThan(resampled.samples.count, 170_000)
    }

    func testParsesReferenceFormatAndPreservesMessage() {
        let parsed = WSJTXReferenceParser.parse("110130  -6  0.7  683 ~  CQ TA6CQ KN70      AS Turkey\n")
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].snrDB, -6)
        XCTAssertEqual(parsed[0].frequencyHz, 683)
        XCTAssertEqual(parsed[0].message, "CQ TA6CQ KN70      AS Turkey")
    }

    func testMatcherUsesMessageFrequencyAndTimeTolerance() {
        let expected = [WSJTXExpectedDecode(time: "000000", snrDB: -10, timeOffset: 0.5, frequencyHz: 1000, mode: "~", message: "CQ G0ABC IO91")]
        let observed = [ObservedDecode(message: "CQ G0ABC IO91", frequencyHz: 1006, timeOffset: 0.6)]
        let result = ReferenceMatcher.compare(expected: expected, observed: observed)
        XCTAssertEqual(result.matched, 1)
        XCTAssertTrue(result.missed.isEmpty)
        XCTAssertTrue(result.unexpected.isEmpty)
    }
}
