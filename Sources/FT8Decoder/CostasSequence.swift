import FT8Protocol

public enum CostasSequence {
    public static let tones: [UInt8] = FT8Constants.costas
    public static let blockStarts: [Int] = [0, 36, 72]
    public static let symbolCount = 79

    public static func tone(atSyncSymbol index: Int) -> UInt8 {
        tones[index % tones.count]
    }

    public static func isSyncSymbol(_ symbol: Int) -> Bool {
        blockStarts.contains { symbol >= $0 && symbol < $0 + tones.count }
    }

    public static func expectedTone(forSymbol symbol: Int) -> UInt8? {
        for start in blockStarts where symbol >= start && symbol < start + tones.count {
            return tones[symbol - start]
        }
        return nil
    }
}
