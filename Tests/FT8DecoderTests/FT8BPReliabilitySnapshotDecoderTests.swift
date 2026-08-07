import XCTest
@testable import FT8Decoder

final class FT8BPReliabilitySnapshotDecoderTests: XCTestCase {
    func testProducesThreeBoundedAccumulatedReliabilitySnapshots() throws {
        let channel = (0..<FT8LDPCMatrix.codewordBitCount).map { index in
            let magnitude = Float((index % 13) + 1) / 7
            return index.isMultiple(of: 3) ? -magnitude : magnitude
        }

        let decoder = FT8BPReliabilitySnapshotDecoder(
            configuration: .init(
                maximumIterations: 30,
                maximumSnapshots: 3,
                messageLimit: 32
            )
        )

        let snapshots = try decoder.snapshots(
            logLikelihoodRatios: channel
        )

        XCTAssertEqual(snapshots.count, 3)
        XCTAssertTrue(
            snapshots.allSatisfy {
                $0.count == FT8LDPCMatrix.codewordBitCount
                    && $0.allSatisfy(\.isFinite)
            }
        )
        XCTAssertNotEqual(snapshots[0], snapshots[1])
        XCTAssertNotEqual(snapshots[1], snapshots[2])
    }

    func testSnapshotCountIsClampedToWSJTXMaximum() throws {
        let channel = (0..<FT8LDPCMatrix.codewordBitCount).map { index in
            Float(index + 1) / 100
        }

        let decoder = FT8BPReliabilitySnapshotDecoder(
            configuration: .init(maximumSnapshots: 20)
        )

        let snapshots = try decoder.snapshots(
            logLikelihoodRatios: channel
        )

        XCTAssertEqual(snapshots.count, 3)
    }
}
