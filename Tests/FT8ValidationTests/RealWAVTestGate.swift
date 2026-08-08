import Foundation
import XCTest

/// Keeps the normal `swift test` suite fast.
///
/// The representative real-WAV tests deliberately run full synchronizer,
/// waterfall, LDPC and refinement/cancellation pipelines and can take minutes.
/// They are valuable integration/diagnostic tests, but they should not make the
/// ordinary unit-test suite look hung.
///
/// Opt in with:
///
///     FT8_RUN_EXPENSIVE_REAL_WAV_TESTS=1 swift test
///
/// or:
///
///     ./test-real-wav.sh
///
enum RealWAVTestGate {
    static let environmentVariable =
        "FT8_RUN_EXPENSIVE_REAL_WAV_TESTS"

    static var isEnabled: Bool {
        guard let raw =
            ProcessInfo.processInfo.environment[environmentVariable]
        else {
            return false
        }

        switch raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    static func requireEnabled(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard isEnabled else {
            throw XCTSkip(
                "Expensive representative real-WAV validation is disabled. "
                    + "Run with \(environmentVariable)=1 to enable it.",
                file: file,
                line: line
            )
        }
    }
}
