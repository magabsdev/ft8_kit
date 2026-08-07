import XCTest
import FT8DSP
import FT8Encoder
import FT8Protocol
@testable import FT8Decoder

final class FT8SignalCancellerTests: XCTestCase {
    func testCancellationReducesModelledEnergy()
        throws
    {
        let decode = try makeDecode()
        let spectrogram = SyntheticSpectrogram.make(
            baseFrequency: 1_000,
            duration: 13,
            signalDB: -10,
            noiseDB: -100
        )

        let result = try FT8SignalCanceller(
            configuration: .init(
                cancellationStrength: 1.0,
                binRadius: 1,
                timeTaperFloor: 0.5
            )
        ).cancel([decode], from: spectrogram)

        XCTAssertGreaterThan(result.affectedBins, 0)
        XCTAssertGreaterThan(
            result.energyBefore,
            result.energyAfter
        )
        XCTAssertGreaterThan(
            result.reductionFraction,
            0
        )
        XCTAssertEqual(
            result.spectrogram.frames.count,
            spectrogram.frames.count
        )
    }

    func testProductionDefaultsMatchCalibratedProfile() {
        let configuration =
            FT8SignalCancellationConfiguration()

        XCTAssertEqual(
            configuration.binRadius,
            1
        )
        XCTAssertEqual(
            configuration.cancellationStrength,
            1.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            configuration.timeTaperFloor,
            0.5,
            accuracy: 0.0001
        )
        XCTAssertTrue(
            configuration.preserveNoiseFloor
        )
    }

    func testEmptyCancellationPreservesSpectrogram()
        throws
    {
        let spectrogram = SyntheticSpectrogram.make(
            baseFrequency: 1_000,
            duration: 13
        )
        let result = try FT8SignalCanceller().cancel(
            [],
            from: spectrogram
        )

        XCTAssertEqual(
            result.spectrogram,
            spectrogram
        )
        XCTAssertEqual(result.affectedBins, 0)
    }

    func testInvalidConfigurationThrows() throws {
        let decode = try makeDecode()
        let spectrogram = SyntheticSpectrogram.make(
            baseFrequency: 1_000,
            duration: 13
        )

        let invalidStrength = FT8SignalCanceller(
            configuration: .init(
                cancellationStrength: 1.5
            )
        )

        XCTAssertThrowsError(
            try invalidStrength.cancel(
                [decode],
                from: spectrogram
            )
        )

        let invalidTaper = FT8SignalCanceller(
            configuration: .init(
                timeTaperFloor: 1.5
            )
        )

        XCTAssertThrowsError(
            try invalidTaper.cancel(
                [decode],
                from: spectrogram
            )
        )
    }

    private func makeDecode() throws
        -> FT8CompleteDecode
    {
        let payload = try FT8MessageCodec.pack(
            "CQ G0ABC IO91"
        )
        let message91 = try FT8CRC.append(
            to: payload
        )
        let codeword = try FT8Encoder.encodeLDPC(
            message91
        )
        let soft = FT8SoftSymbols(
            logLikelihoodRatios:
                codeword.bits.map {
                    $0 == 0 ? 12 : -12
                },
            symbolConfidences:
                Array(repeating: 1, count: 58)
        )
        let ldpc = try FT8LDPCDecoder().decode(soft)
        let decoded = try FT8MessageDecoder().decode(
            ldpc,
            softSymbols: soft
        )

        return FT8CompleteDecode(
            candidate: FT8Candidate(
                startTime: 0,
                frequency: 1_000,
                syncScore: 1,
                snrDB: 20,
                confidence: 1
            ),
            softSymbols: soft,
            ldpc: ldpc,
            decoded: decoded
        )
    }
}
