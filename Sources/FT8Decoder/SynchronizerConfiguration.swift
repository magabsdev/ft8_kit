import Foundation

public enum SynchronizerError: Error, Equatable, Sendable {
    case emptySpectrogram
    case invalidConfiguration
    case incompatibleFrameSpacing
}

public struct SynchronizerConfiguration: Equatable, Sendable {
    public var symbolPeriod: Double
    public var toneSpacing: Float
    public var minimumFrequency: Float
    public var maximumFrequency: Float
    public var frequencyStep: Float?
    public var minimumSyncScore: Float
    public var minimumSNRDB: Float
    public var maximumCandidates: Int
    public var deduplicationFrequency: Float
    public var deduplicationTime: Double
    public var estimateDrift: Bool
    public var maximumAbsoluteDrift: Float

    public init(
        symbolPeriod: Double = 0.160,
        toneSpacing: Float = 6.25,
        minimumFrequency: Float = 100,
        maximumFrequency: Float = 3_000,
        frequencyStep: Float? = nil,
        minimumSyncScore: Float = 0.42,
        minimumSNRDB: Float = 1.5,
        maximumCandidates: Int = 50,
        deduplicationFrequency: Float = 6.25,
        deduplicationTime: Double = 0.080,
        estimateDrift: Bool = true,
        maximumAbsoluteDrift: Float = 3
    ) {
        self.symbolPeriod = symbolPeriod
        self.toneSpacing = toneSpacing
        self.minimumFrequency = minimumFrequency
        self.maximumFrequency = maximumFrequency
        self.frequencyStep = frequencyStep
        self.minimumSyncScore = minimumSyncScore
        self.minimumSNRDB = minimumSNRDB
        self.maximumCandidates = maximumCandidates
        self.deduplicationFrequency = deduplicationFrequency
        self.deduplicationTime = deduplicationTime
        self.estimateDrift = estimateDrift
        self.maximumAbsoluteDrift = maximumAbsoluteDrift
    }

    func validate() throws {
        guard symbolPeriod > 0,
              toneSpacing > 0,
              maximumFrequency > minimumFrequency,
              minimumSyncScore >= 0,
              maximumCandidates > 0,
              deduplicationFrequency >= 0,
              deduplicationTime >= 0,
              maximumAbsoluteDrift >= 0 else {
            throw SynchronizerError.invalidConfiguration
        }
    }
}
