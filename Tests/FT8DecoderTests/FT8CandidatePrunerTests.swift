import XCTest
@testable import FT8Decoder

final class FT8CandidatePrunerTests: XCTestCase {
    func testKeepsMinimumCandidateCount() {
        let candidates = (0..<20).map {
            FT8Candidate(
                startTime: Double($0) * 0.2,
                frequency: 1_000 + Float($0 * 20),
                driftHzPerSecond: 0,
                symbolOffset: Double($0),
                syncScore: 0.8,
                snrDB: 8,
                confidence: 0.9 - Float($0) * 0.03
            )
        }

        let pruner = FT8CandidatePruner(
            minimumRelativeConfidence: 0.95,
            minimumPeakIsolation: 0.5,
            timeRadius: 0.16,
            frequencyRadius: 18.75,
            minimumCandidates: 8,
            maximumCandidates: 12
        )

        XCTAssertEqual(pruner.prune(candidates).count, 8)
    }

    func testSuppressesNearbyLowerConfidencePeak() {
        let strong = FT8Candidate(
            startTime: 0.5,
            frequency: 1_000,
            driftHzPerSecond: 0,
            symbolOffset: 3.125,
            syncScore: 0.95,
            snrDB: 12,
            confidence: 0.95
        )
        let nearby = FT8Candidate(
            startTime: 0.52,
            frequency: 1_006.25,
            driftHzPerSecond: 0,
            symbolOffset: 3.25,
            syncScore: 0.80,
            snrDB: 6,
            confidence: 0.75
        )
        let separate = FT8Candidate(
            startTime: 0.5,
            frequency: 1_100,
            driftHzPerSecond: 0,
            symbolOffset: 3.125,
            syncScore: 0.82,
            snrDB: 7,
            confidence: 0.78
        )

        let pruner = FT8CandidatePruner(
            minimumRelativeConfidence: 0.50,
            minimumPeakIsolation: 0.02,
            timeRadius: 0.16,
            frequencyRadius: 18.75,
            minimumCandidates: 1,
            maximumCandidates: 10
        )

        let result = pruner.prune([nearby, separate, strong])

        XCTAssertTrue(result.contains { $0.frequency == strong.frequency })
        XCTAssertTrue(result.contains { $0.frequency == separate.frequency })
        XCTAssertFalse(result.contains { $0.frequency == nearby.frequency })
    }
}
