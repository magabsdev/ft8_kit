import Foundation

public struct FT8SymbolTrace: Codable, Equatable, Sendable {
    public let symbolIndex: Int
    public let toneMetrics: [Float]
    public let confidence: Float

    public init(symbolIndex: Int, toneMetrics: [Float], confidence: Float) {
        self.symbolIndex = symbolIndex
        self.toneMetrics = toneMetrics
        self.confidence = confidence
    }
}

public struct FT8CandidateTrace: Codable, Equatable, Sendable {
    public let pass: Int
    public let candidateIndex: Int
    public let startTime: Double
    public let frequency: Float
    public let driftHzPerSecond: Float
    public let syncScore: Float
    public let snrDB: Float
    public let candidateConfidence: Float
    public let averageSoftSymbolConfidence: Float?
    public let symbols: [FT8SymbolTrace]
    public let logLikelihoodRatios: [Float]
    public let ldpcIterations: Int?
    public let syndromeWeight: Int?
    public let parityPassed: Bool?
    public let crcPassed: Bool?
    public let decodedText: String?
    public let failure: String?

    public init(
        pass: Int,
        candidateIndex: Int,
        startTime: Double,
        frequency: Float,
        driftHzPerSecond: Float,
        syncScore: Float,
        snrDB: Float,
        candidateConfidence: Float,
        averageSoftSymbolConfidence: Float?,
        symbols: [FT8SymbolTrace],
        logLikelihoodRatios: [Float],
        ldpcIterations: Int?,
        syndromeWeight: Int?,
        parityPassed: Bool?,
        crcPassed: Bool?,
        decodedText: String?,
        failure: String?
    ) {
        self.pass = pass
        self.candidateIndex = candidateIndex
        self.startTime = startTime
        self.frequency = frequency
        self.driftHzPerSecond = driftHzPerSecond
        self.syncScore = syncScore
        self.snrDB = snrDB
        self.candidateConfidence = candidateConfidence
        self.averageSoftSymbolConfidence = averageSoftSymbolConfidence
        self.symbols = symbols
        self.logLikelihoodRatios = logLikelihoodRatios
        self.ldpcIterations = ldpcIterations
        self.syndromeWeight = syndromeWeight
        self.parityPassed = parityPassed
        self.crcPassed = crcPassed
        self.decodedText = decodedText
        self.failure = failure
    }
}

public struct FT8SoftSymbolExtraction: Equatable, Sendable {
    public let softSymbols: FT8SoftSymbols
    public let symbols: [FT8SymbolTrace]

    public init(softSymbols: FT8SoftSymbols, symbols: [FT8SymbolTrace]) {
        self.softSymbols = softSymbols
        self.symbols = symbols
    }
}
