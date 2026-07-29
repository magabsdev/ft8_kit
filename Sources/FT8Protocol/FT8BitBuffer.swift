public struct FT8BitBuffer: Equatable, Sendable {
    public private(set) var bits: [UInt8]

    public init(count: Int, repeating value: UInt8 = 0) {
        bits = [UInt8](repeating: value & 1, count: count)
    }

    public init(_ bits: [UInt8]) {
        self.bits = bits.map { $0 & 1 }
    }

    public init(packedBytes: [UInt8], bitCount: Int) {
        precondition(bitCount >= 0 && bitCount <= packedBytes.count * 8)
        var unpacked = [UInt8]()
        unpacked.reserveCapacity(bitCount)
        for index in 0..<bitCount {
            unpacked.append((packedBytes[index / 8] >> UInt8(7 - (index % 8))) & 1)
        }
        bits = unpacked
    }

    public var count: Int { bits.count }

    public subscript(index: Int) -> UInt8 {
        get { bits[index] }
        set { bits[index] = newValue & 1 }
    }

    public func packedBytes(paddedTo byteCount: Int? = nil) -> [UInt8] {
        let outputCount = byteCount ?? ((bits.count + 7) / 8)
        precondition(outputCount * 8 >= bits.count)
        var bytes = [UInt8](repeating: 0, count: outputCount)
        for (index, bit) in bits.enumerated() where bit != 0 {
            bytes[index / 8] |= UInt8(1 << (7 - index % 8))
        }
        return bytes
    }

    mutating func multiply(by value: Int) {
        var carry = 0
        for index in stride(from: bits.count - 1, through: 0, by: -1) {
            let total = Int(bits[index]) * value + carry
            bits[index] = UInt8(total & 1)
            carry = total >> 1
        }
        precondition(carry == 0, "FT8 bit buffer overflow")
    }

    mutating func add(_ value: Int) {
        var carry = value
        var index = bits.count - 1
        while carry > 0 && index >= 0 {
            let total = Int(bits[index]) + (carry & 1)
            bits[index] = UInt8(total & 1)
            carry = (carry >> 1) + (total >> 1)
            index -= 1
        }
        precondition(carry == 0, "FT8 bit buffer overflow")
    }

    mutating func divide(by divisor: Int) -> Int {
        precondition(divisor > 0)
        var remainder = 0
        for index in bits.indices {
            let value = remainder * 2 + Int(bits[index])
            bits[index] = UInt8(value / divisor)
            remainder = value % divisor
        }
        return remainder
    }
}
