import Foundation
import XCTest
@testable import FT8Decoder

final class FT8AuditWriterTests: XCTestCase {
    func testWritesAuditFiles() throws {
        let trace = FT8CandidateTrace(
            pass: 1,
            candidateIndex: 0,
            startTime: 0.5,
            frequency: 1_000,
            driftHzPerSecond: 0,
            syncScore: 0.9,
            snrDB: 4,
            candidateConfidence: 0.8,
            averageSoftSymbolConfidence: 0.7,
            symbols: [
                FT8SymbolTrace(
                    symbolIndex: 0,
                    toneMetrics: [8, 7, 6, 5, 4, 3, 2, 1],
                    confidence: 0.9
                )
            ],
            logLikelihoodRatios: [1, -2],
            ldpcIterations: 3,
            syndromeWeight: 1,
            parityPassed: false,
            crcPassed: false,
            decodedText: nil,
            failure: "crcFailed"
        )

        let batch = FT8DecodeBatch(
            messages: [],
            metrics: FT8DecodeMetrics(
                candidatesFound: 1,
                candidatesScheduled: 1,
                softSymbolsExtracted: 1,
                ldpcAttempts: 1,
                parityPassed: 0,
                crcPassed: 0,
                messagesReturned: 0,
                elapsedSeconds: 0.1
            ),
            candidateTraces: [trace]
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FT8AuditWriter().write(batch: batch, to: directory)

        for name in [
            "summary.json",
            "candidate-traces.json",
            "candidates.csv",
            "symbols.csv",
            "llr.csv",
            "ldpc.csv"
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(name).path
                )
            )
        }

        try? FileManager.default.removeItem(at: directory)
    }
}
