import FT8Protocol

public enum FT8EncoderError: Error, Equatable, Sendable {
    case invalidPayloadLength(Int)
    case invalidMessageWithCRCLength(Int)
}

public enum FT8Encoder {
    public static let codewordBitCount = 174
    public static let toneCount = 79

    public static func encode(_ message: FT8Message) throws -> [UInt8] {
        try encode(payload: FT8MessageCodec.pack(message))
    }

    public static func encode(text: String) throws -> [UInt8] {
        try encode(payload: FT8MessageCodec.pack(text))
    }

    public static func encode(payload: FT8BitBuffer) throws -> [UInt8] {
        guard payload.count == FT8Constants.informationBitCount else {
            throw FT8EncoderError.invalidPayloadLength(payload.count)
        }
        let message91 = try FT8CRC.append(to: payload)
        let codeword = try encodeLDPC(message91)
        return mapCodewordToTones(codeword)
    }

    public static func encodeLDPC(_ message91: FT8BitBuffer) throws -> FT8BitBuffer {
        guard message91.count == FT8Constants.messageWithCRCBitCount else {
            throw FT8EncoderError.invalidMessageWithCRCLength(message91.count)
        }

        let messageBytes = message91.packedBytes(paddedTo: 12)
        var bits = message91.bits
        bits.reserveCapacity(codewordBitCount)

        for row in FT8LDPCGenerator.rows {
            var parity: UInt8 = 0
            for index in 0..<12 {
                parity ^= UInt8((messageBytes[index] & row[index]).nonzeroBitCount & 1)
            }
            bits.append(parity)
        }

        precondition(bits.count == codewordBitCount)
        return FT8BitBuffer(bits)
    }

    private static func mapCodewordToTones(_ codeword: FT8BitBuffer) -> [UInt8] {
        var tones = [UInt8]()
        tones.reserveCapacity(toneCount)
        var dataIndex = 0

        for toneIndex in 0..<toneCount {
            switch toneIndex {
            case 0..<7:
                tones.append(FT8Constants.costas[toneIndex])
            case 36..<43:
                tones.append(FT8Constants.costas[toneIndex - 36])
            case 72..<79:
                tones.append(FT8Constants.costas[toneIndex - 72])
            default:
                let value = Int(codeword[dataIndex]) << 2
                    | Int(codeword[dataIndex + 1]) << 1
                    | Int(codeword[dataIndex + 2])
                tones.append(FT8Constants.grayMap[value])
                dataIndex += 3
            }
        }

        precondition(dataIndex == codewordBitCount)
        return tones
    }
}
