import Foundation

public enum FT8CRC {
    public static func checksum(payload: FT8BitBuffer) throws -> UInt16 {
        guard payload.count == 77 else { throw FT8ProtocolError.invalidPayloadLength(payload.count) }
        let extended = payload.bits + [UInt8](repeating: 0, count: 5)
        var remainder: UInt16 = 0
        let topBit: UInt16 = 1 << 13
        for bit in extended {
            let incoming = UInt16(bit) << 13
            remainder ^= incoming
            remainder = (remainder & topBit) != 0 ? (remainder << 1) ^ FT8Constants.crcPolynomial : remainder << 1
            remainder &= 0x3FFF
        }
        return remainder
    }

    public static func append(to payload: FT8BitBuffer) throws -> FT8BitBuffer {
        let crc = try checksum(payload: payload)
        var bits = payload.bits
        for shift in stride(from: 13, through: 0, by: -1) { bits.append(UInt8((crc >> UInt16(shift)) & 1)) }
        return FT8BitBuffer(bits)
    }

    public static func validate(_ message91: FT8BitBuffer) -> Bool {
        guard message91.count == 91 else { return false }
        let payload = FT8BitBuffer(Array(message91.bits[0..<77]))
        guard let expected = try? checksum(payload: payload) else { return false }
        var actual: UInt16 = 0
        for bit in message91.bits[77..<91] { actual = (actual << 1) | UInt16(bit) }
        return expected == actual
    }
}
