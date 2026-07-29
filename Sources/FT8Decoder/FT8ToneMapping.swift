import FT8Protocol

public enum FT8ToneMapping {
    public static let dataSymbolIndices: [Int] =
        (0..<79).filter { !CostasSequence.isSyncSymbol($0) }

    public static let inverseGrayMap: [UInt8] = {
        var inverse = Array(repeating: UInt8.zero, count: 8)
        for (binary, tone) in FT8Constants.grayMap.enumerated() {
            inverse[Int(tone)] = UInt8(binary)
        }
        return inverse
    }()

    public static func bits(forTone tone: Int) -> (UInt8, UInt8, UInt8) {
        let value = Int(inverseGrayMap[tone])
        return (
            UInt8((value >> 2) & 1),
            UInt8((value >> 1) & 1),
            UInt8(value & 1)
        )
    }
}
