import XCTest
@testable import FT8Decoder

final class FT8OptimizedDecoderTests: XCTestCase {
    func testSchedulesHighestConfidenceCandidatesFirst() {
        let decoder = FT8OptimizedDecoder(
            configuration: .init(
                maximumCandidatesToDecode: 3,
                minimumCandidateConfidence: 0
            )
        )

        let candidates = [
            candidate(frequency: 1_000, confidence: 0.2),
            candidate(frequency: 1_100, confidence: 0.9),
            candidate(frequency: 1_200, confidence: 0.5),
            candidate(frequency: 1_300, confidence: 0.8)
        ]

        let scheduled = decoder.schedule(candidates)

        XCTAssertEqual(scheduled.count, 3)
        XCTAssertEqual(
            scheduled.map(\.frequency),
            [1_100, 1_300, 1_200]
        )
    }

    func testCandidateConfidenceThreshold() {
        let decoder = FT8OptimizedDecoder(
            configuration: .init(
                maximumCandidatesToDecode: 10,
                minimumCandidateConfidence: 0.5
            )
        )

        let scheduled = decoder.schedule([
            candidate(frequency: 900, confidence: 0.49),
            candidate(frequency: 1_000, confidence: 0.5),
            candidate(frequency: 1_100, confidence: 0.75)
        ])

        XCTAssertEqual(scheduled.map(\.frequency), [1_100, 1_000])
    }

    func testStableTieBreakUsesSyncThenSNR() {
        let decoder = FT8OptimizedDecoder(
            configuration: .init(
                maximumCandidatesToDecode: 10,
                minimumCandidateConfidence: 0
            )
        )

        let scheduled = decoder.schedule([
            candidate(
                frequency: 1_000,
                confidence: 0.8,
                syncScore: 0.7,
                snrDB: 10
            ),
            candidate(
                frequency: 1_100,
                confidence: 0.8,
                syncScore: 0.9,
                snrDB: 4
            ),
            candidate(
                frequency: 1_200,
                confidence: 0.8,
                syncScore: 0.9,
                snrDB: 8
            )
        ])

        XCTAssertEqual(
            scheduled.map(\.frequency),
            [1_200, 1_100, 1_000]
        )
    }

    func testInvalidConfigurationThrows() throws {
        let decoder = FT8OptimizedDecoder(
            configuration: .init(maximumCandidatesToDecode: 0)
        )
        let spectrogram = SyntheticSpectrogram.make(
            baseFrequency: 1_000,
            duration: 13,
            signalDB: -120,
            noiseDB: -120
        )

        XCTAssertThrowsError(
            try decoder.decode(spectrogram: spectrogram)
        ) {
            XCTAssertEqual(
                $0 as? FT8OptimizedDecoderError,
                .invalidConfiguration
            )
        }
    }

    private func candidate(
        frequency: Float,
        confidence: Float,
        syncScore: Float = 0.8,
        snrDB: Float = 10
    ) -> FT8Candidate {
        FT8Candidate(
            startTime: 0,
            frequency: frequency,
            syncScore: syncScore,
            snrDB: snrDB,
            confidence: confidence
        )
    }
}
