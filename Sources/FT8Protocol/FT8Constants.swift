public enum FT8Constants {
    public static let informationBitCount = 77
    public static let crcBitCount = 14
    public static let messageWithCRCBitCount = 91
    public static let crcPolynomial: UInt16 = 0x2757
    public static let freeTextAlphabet = Array(" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ+-./?")
    public static let costas: [UInt8] = [3, 1, 4, 0, 6, 5, 2]
    public static let grayMap: [UInt8] = [0, 1, 3, 2, 5, 6, 4, 7]
}
