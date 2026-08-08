import XCTest
@testable import FT8Decoder
import FT8Protocol

final class FT8WSJTXCascadedGeneratorTests: XCTestCase {
    func testKeff77CascadesAllFourteenCRCBitsIntoGenerator() throws {
        let basis = FT8OrderedStatisticsDecoder.wsjtxGeneratorBasis(
            effectiveDimension: 77
        )

        XCTAssertEqual(basis.count, 77)

        for row in [0, 1, 17, 38, 76] {
            let codeword = FT8BitBuffer(basis[row])
            XCTAssertTrue(FT8LDPCMatrix.isValid(codeword))

            let information = FT8BitBuffer(
                Array(codeword.bits.prefix(91))
            )

            XCTAssertTrue(
                FT8CRC.validate(information),
                "row \(row) must contain the payload-derived CRC"
            )
        }
    }

    func testKeff80UsesThreeIndependentCRCBitsAndCascadesSuffix() throws {
        let k = 80
        let basis = FT8OrderedStatisticsDecoder.wsjtxGeneratorBasis(
            effectiveDimension: k
        )

        XCTAssertEqual(basis.count, k)

        for row in [0, 12, 44, 76] {
            let codeword = FT8BitBuffer(basis[row])
            XCTAssertTrue(FT8LDPCMatrix.isValid(codeword))

            let information = Array(codeword.bits.prefix(91))
            let payload = FT8BitBuffer(Array(information.prefix(77)))
            let expected = try FT8CRC.append(to: payload)

            XCTAssertEqual(Array(information[77..<k]), [0, 0, 0])

            XCTAssertEqual(
                Array(information[k..<91]),
                Array(expected.bits[k..<91])
            )
        }

        for row in 77..<k {
            let information = Array(basis[row].prefix(91))
            XCTAssertEqual(information[row], 1)
            XCTAssertEqual(information.reduce(0) { $0 + Int($1) }, 1)
        }
    }

    func testKeff91HasNinetyOneIndependentInformationCoordinates() {
        let basis = FT8OrderedStatisticsDecoder.wsjtxGeneratorBasis(
            effectiveDimension: 91
        )

        XCTAssertEqual(basis.count, 91)

        for row in [0, 76, 77, 90] {
            let codeword = FT8BitBuffer(basis[row])
            XCTAssertTrue(FT8LDPCMatrix.isValid(codeword))

            let information = Array(codeword.bits.prefix(91))
            XCTAssertEqual(information[row], 1)
            XCTAssertEqual(information.reduce(0) { $0 + Int($1) }, 1)
        }
    }
}
