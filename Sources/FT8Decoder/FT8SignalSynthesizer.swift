import FT8Protocol

public enum FT8SignalSynthesisError: Error, Equatable, Sendable {
    case invalidCodewordLength(Int)
}

public struct FT8SignalSynthesizer: Sendable {
    public init() {}

    public func tones(
        for decode: FT8CompleteDecode
    ) throws -> [UInt8] {
        try tones(for: decode.ldpc.codeword)
    }

    public func tones(
        for codeword: FT8BitBuffer
    ) throws -> [UInt8] {
        guard codeword.count == 174 else {
            throw FT8SignalSynthesisError.invalidCodewordLength(
                codeword.count
            )
        }

        var tones: [UInt8] = []
        tones.reserveCapacity(79)
        var dataIndex = 0

        for symbolIndex in 0..<79 {
            if let syncTone = CostasSequence.expectedTone(
                forSymbol: symbolIndex
            ) {
                tones.append(UInt8(syncTone))
                continue
            }

            let value =
                Int(codeword[dataIndex]) << 2 |
                Int(codeword[dataIndex + 1]) << 1 |
                Int(codeword[dataIndex + 2])

            tones.append(FT8Constants.grayMap[value])
            dataIndex += 3
        }

        precondition(dataIndex == 174)
        return tones
    }
}
