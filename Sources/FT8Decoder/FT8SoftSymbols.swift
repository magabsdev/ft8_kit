import FT8Protocol

public struct FT8SoftSymbols: Equatable, Sendable {
    public static let bitCount = 174
    public static let dataSymbolCount = 58

    public let logLikelihoodRatios: [Float]
    public let hardBits: FT8BitBuffer
    public let symbolConfidences: [Float]
    public let averageConfidence: Float

    public init(
        logLikelihoodRatios: [Float],
        symbolConfidences: [Float]
    ) {
        precondition(logLikelihoodRatios.count == Self.bitCount)
        precondition(symbolConfidences.count == Self.dataSymbolCount)
        self.logLikelihoodRatios = logLikelihoodRatios
        self.hardBits = FT8BitBuffer(
            logLikelihoodRatios.map { $0 < 0 ? UInt8(1) : UInt8(0) }
        )
        self.symbolConfidences = symbolConfidences
        self.averageConfidence = symbolConfidences.reduce(0, +)
            / Float(symbolConfidences.count)
    }
}
