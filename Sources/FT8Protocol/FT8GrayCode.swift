public enum FT8GrayCode {
    public static func encode(_ value: UInt8) -> UInt8 {
        value ^ (value >> 1)
    }

    public static func decode(_ gray: UInt8) -> UInt8 {
        var value = gray
        value ^= value >> 1
        value ^= value >> 2
        value ^= value >> 4
        return value
    }
}
