import XCTest
import FT8Encoder
import FT8Protocol
@testable import FT8Decoder

final class FT8CRCSystematicRescueDecoderTests: XCTestCase {
    func testRecoversNearbyCRCValidCodewordFromSyndromeZeroCRCFailure() throws {
        let trueInformation = try FT8CRC.append(
            to: FT8MessageCodec.pack("CQ TEST")
        )
        let trueCodeword = try FT8Encoder.encodeLDPC(trueInformation)

        let changedPayloadBit = 12
        var wrongInformationBits = trueInformation.bits
        wrongInformationBits[changedPayloadBit] ^= 1

        let wrongCodeword = encodeSystematicInformation(wrongInformationBits)
        let wrongInformation = FT8BitBuffer(wrongInformationBits)

        XCTAssertTrue(FT8LDPCMatrix.isValid(FT8BitBuffer(wrongCodeword)))
        XCTAssertFalse(FT8CRC.validate(wrongInformation))

        let starting = FT8LDPCResult(
            codeword: FT8BitBuffer(wrongCodeword),
            informationBits: wrongInformation,
            iterations: 0,
            parityPassed: true,
            crcPassed: false,
            syndromeWeight: 0
        )

        var llr = trueCodeword.bits.map {
            $0 == 0 ? Float(8) : Float(-8)
        }
        llr[changedPayloadBit] =
            trueCodeword[changedPayloadBit] == 0 ? 0.05 : -0.05

        let candidates = try FT8CRCSystematicRescueDecoder(
            configuration: .init(
                leastReliablePayloadBits: 8,
                maximumFlipOrder: 2,
                maximumHypotheses: 64,
                maximumResults: 8,
                maximumCodewordBitChanges: 40,
                maximumWeightedDistanceIncrease: 100
            )
        ).decode(
            logLikelihoodRatios: llr,
            startingResult: starting
        )

        let recovered = try XCTUnwrap(
            candidates.first { $0.ldpc.codeword == trueCodeword }
        )

        XCTAssertEqual(recovered.flippedPayloadBitIndices, [changedPayloadBit])
        XCTAssertTrue(recovered.ldpc.parityPassed)
        XCTAssertTrue(recovered.ldpc.crcPassed)
        XCTAssertEqual(recovered.ldpc.informationBits, trueInformation)
    }

    func testRejectsNonSyndromeZeroStartingResult() throws {
        let information = try FT8CRC.append(
            to: FT8MessageCodec.pack("CQ TEST")
        )
        let codeword = try FT8Encoder.encodeLDPC(information)

        let invalidStart = FT8LDPCResult(
            codeword: codeword,
            informationBits: information,
            iterations: 1,
            parityPassed: false,
            crcPassed: false,
            syndromeWeight: 1
        )

        let llr = codeword.bits.map {
            $0 == 0 ? Float(8) : Float(-8)
        }

        let candidates = try FT8CRCSystematicRescueDecoder()
            .decode(
                logLikelihoodRatios: llr,
                startingResult: invalidStart
            )

        XCTAssertTrue(candidates.isEmpty)
    }


    func testAdaptiveBeamRecoversCorrectionOutsideOriginalFourteenBitWindow() throws {
        let trueInformation = try FT8CRC.append(
            to: FT8MessageCodec.pack("CQ TEST")
        )
        let trueCodeword = try FT8Encoder.encodeLDPC(trueInformation)

        // Deliberately choose a payload bit that will rank outside the first
        // fourteen least-reliable positions, reproducing the limitation of
        // the previous checkpoint.
        let changedPayloadBit = 42
        var wrongInformationBits = trueInformation.bits
        wrongInformationBits[changedPayloadBit] ^= 1

        let wrongCodeword = encodeSystematicInformation(wrongInformationBits)
        let wrongInformation = FT8BitBuffer(wrongInformationBits)

        let starting = FT8LDPCResult(
            codeword: FT8BitBuffer(wrongCodeword),
            informationBits: wrongInformation,
            iterations: 0,
            parityPassed: true,
            crcPassed: false,
            syndromeWeight: 0
        )

        var llr = trueCodeword.bits.map {
            $0 == 0 ? Float(8) : Float(-8)
        }

        // Make 20 other payload coordinates appear less reliable than the
        // actual wrong decision. A fixed 14-position search cannot reach it.
        for index in 0..<20 {
            llr[index] = trueCodeword[index] == 0 ? 0.01 : -0.01
        }
        llr[changedPayloadBit] =
            trueCodeword[changedPayloadBit] == 0 ? 0.20 : -0.20

        let candidates = try FT8CRCSystematicRescueDecoder(
            configuration: .init(
                leastReliablePayloadBits: 32,
                maximumFlipOrder: 3,
                maximumHypotheses: 1024,
                maximumResults: 12,
                maximumCodewordBitChanges: 80,
                maximumWeightedDistanceIncrease: 100,
                beamWidth: 64
            )
        ).decode(
            logLikelihoodRatios: llr,
            startingResult: starting
        )

        let recovered = try XCTUnwrap(
            candidates.first { $0.ldpc.codeword == trueCodeword }
        )

        XCTAssertEqual(recovered.flippedPayloadBitIndices, [changedPayloadBit])
        XCTAssertTrue(recovered.ldpc.parityPassed)
        XCTAssertTrue(recovered.ldpc.crcPassed)
        XCTAssertEqual(recovered.ldpc.informationBits, trueInformation)
    }

    func testAdaptiveBeamCanRecoverFourPayloadCorrections() throws {
        let trueInformation = try FT8CRC.append(
            to: FT8MessageCodec.pack("CQ TEST")
        )
        let trueCodeword = try FT8Encoder.encodeLDPC(trueInformation)

        let changedPayloadBits = [4, 17, 31, 46]
        var wrongInformationBits = trueInformation.bits
        for index in changedPayloadBits {
            wrongInformationBits[index] ^= 1
        }

        let wrongCodeword = encodeSystematicInformation(wrongInformationBits)
        let wrongInformation = FT8BitBuffer(wrongInformationBits)

        let starting = FT8LDPCResult(
            codeword: FT8BitBuffer(wrongCodeword),
            informationBits: wrongInformation,
            iterations: 0,
            parityPassed: true,
            crcPassed: false,
            syndromeWeight: 0
        )

        var llr = trueCodeword.bits.map {
            $0 == 0 ? Float(8) : Float(-8)
        }

        for index in changedPayloadBits {
            llr[index] = trueCodeword[index] == 0 ? 0.02 : -0.02
        }

        let candidates = try FT8CRCSystematicRescueDecoder(
            configuration: .init(
                leastReliablePayloadBits: 24,
                maximumFlipOrder: 5,
                maximumHypotheses: 4096,
                maximumResults: 16,
                maximumCodewordBitChanges: 100,
                maximumWeightedDistanceIncrease: 100,
                beamWidth: 128
            )
        ).decode(
            logLikelihoodRatios: llr,
            startingResult: starting
        )

        let recovered = try XCTUnwrap(
            candidates.first { $0.ldpc.codeword == trueCodeword }
        )

        XCTAssertEqual(
            Set(recovered.flippedPayloadBitIndices),
            Set(changedPayloadBits)
        )
        XCTAssertTrue(recovered.ldpc.crcPassed)
    }

    private func encodeSystematicInformation(
        _ information: [UInt8]
    ) -> [UInt8] {
        var codeword = information

        for variables in FT8LDPCMatrix.checkToVariables {
            var parity: UInt8 = 0
            for variable in variables
            where variable < FT8LDPCMatrix.informationBitCount {
                parity ^= information[variable]
            }
            codeword.append(parity)
        }

        return codeword
    }
}
