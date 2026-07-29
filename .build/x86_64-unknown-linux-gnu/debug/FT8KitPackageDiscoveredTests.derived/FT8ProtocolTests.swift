import XCTest
@testable import FT8ProtocolTests

fileprivate extension FT8ProtocolTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__FT8ProtocolTests = [
        ("testCRCAppendAndValidation", testCRCAppendAndValidation),
        ("testFreeTextRejectsTooManyCharacters", testFreeTextRejectsTooManyCharacters),
        ("testFreeTextRoundTrip", testFreeTextRoundTrip),
        ("testGrayCodeRoundTrip", testGrayCodeRoundTrip),
        ("testPackedBytesRoundTrip", testPackedBytesRoundTrip),
        ("testStandardMessageRoundTrips", testStandardMessageRoundTrips)
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __FT8ProtocolTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(FT8ProtocolTests.__allTests__FT8ProtocolTests)
    ]
}