import XCTest
@testable import FT8Encoder
import FT8Protocol

final class FT8EncoderTests: XCTestCase {
    func testStandardMessageMatchesReferenceTones() throws {
        let tones = try FT8Encoder.encode(text: "CQ G0ABC IO91")
        XCTAssertEqual(tones.map(String.init).joined(), "3140652000000001005270472307405427303140652104460762243320101552550551753140652")
    }

    func testFreeTextMatchesReferenceTones() throws {
        let tones = try FT8Encoder.encode(.freeText("SIGNAL8 CORE"))
        XCTAssertEqual(tones.map(String.init).joined(), "3140652200270451615621135320575002503140652602534401130451504735314307233140652")
    }

    func testToneStructureAndRanges() throws {
        let tones = try FT8Encoder.encode(text: "CQ G0ABC IO91")
        XCTAssertEqual(tones.count, 79)
        XCTAssertEqual(Array(tones[0..<7]), FT8Constants.costas)
        XCTAssertEqual(Array(tones[36..<43]), FT8Constants.costas)
        XCTAssertEqual(Array(tones[72..<79]), FT8Constants.costas)
        XCTAssertTrue(tones.allSatisfy { $0 < 8 })
    }

    func testLDPCSystematicPrefixAndLength() throws {
        let payload = try FT8MessageCodec.pack("CQ G0ABC IO91")
        let message91 = try FT8CRC.append(to: payload)
        let codeword = try FT8Encoder.encodeLDPC(message91)
        XCTAssertEqual(codeword.count, 174)
        XCTAssertEqual(Array(codeword.bits.prefix(91)), message91.bits)
    }

    func testWaveformHasExpectedLengthsAndFiniteSamples() throws {
        let tones = try FT8Encoder.encode(text: "CQ G0ABC IO91")
        let unpadded = FT8Waveform.generate(tones: tones, configuration: .init(padToSlot: false))
        XCTAssertEqual(unpadded.count, 79 * 1_920)
        XCTAssertTrue(unpadded.allSatisfy(\.isFinite))
        XCTAssertLessThanOrEqual(unpadded.map { abs($0) }.max() ?? 0, 0.8001)

        let padded = FT8Waveform.generate(tones: tones)
        XCTAssertEqual(padded.count, 180_000)
        XCTAssertEqual(padded.first, 0)
        XCTAssertEqual(padded.last, 0)
    }

    func testWaveformIsDeterministic() throws {
        let tones = try FT8Encoder.encode(text: "CQ G0ABC IO91")
        XCTAssertEqual(FT8Waveform.generate(tones: tones), FT8Waveform.generate(tones: tones))
    }

    func testWAVHeaderAndLength() throws {
        let tones = try FT8Encoder.encode(text: "CQ G0ABC IO91")
        let samples = FT8Waveform.generate(tones: tones)
        let data = try FT8WAVEncoder.pcm16Data(samples: samples)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(data.count, 44 + 180_000 * 2)
    }
}
