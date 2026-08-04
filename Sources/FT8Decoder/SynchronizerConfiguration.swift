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
    public var enableFineSearch: Bool
    public var fineFrequencySubdivisions: Int
    public var fineTimeSubdivisions: Int
    public var fineFrequencyRadius: Float
    public var fineTimeRadius: Double

    // Checkpoint 5: adaptive candidate quality and pruning.
    public var enableAdaptivePruning: Bool
    public var minimumRelativeConfidence: Float
    public var minimumPeakIsolation: Float
    public var pruningTimeRadius: Double
    public var pruningFrequencyRadius: Float
    public var minimumCandidatesAfterPruning: Int
    public var maximumCandidatesAfterPruning: Int

    public init(
        symbolPeriod: Double = 0.160,
        toneSpacing: Float = 6.25,
        minimumFrequency: Float = 100,
        maximumFrequency: Float = 3_000,
        frequencyStep: Float? = nil,
        minimumSyncScore: Float = 0.42,
        minimumSNRDB: Float = 1.5,
        maximumCandidates: Int = 140,
        deduplicationFrequency: Float = 6.25,
        deduplicationTime: Double = 0.080,
        estimateDrift: Bool = true,
        maximumAbsoluteDrift: Float = 3,
        enableFineSearch: Bool = true,
        fineFrequencySubdivisions: Int = 4,
        fineTimeSubdivisions: Int = 4,
        fineFrequencyRadius: Float = 6.25,
        fineTimeRadius: Double = 0.080,
        enableAdaptivePruning: Bool = true,
        minimumRelativeConfidence: Float = 0.58,
        minimumPeakIsolation: Float = 0.015,
        pruningTimeRadius: Double = 0.160,
        pruningFrequencyRadius: Float = 18.75,
        minimumCandidatesAfterPruning: Int = 12,
        maximumCandidatesAfterPruning: Int = 72
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
        self.enableFineSearch = enableFineSearch
        self.fineFrequencySubdivisions = fineFrequencySubdivisions
        self.fineTimeSubdivisions = fineTimeSubdivisions
        self.fineFrequencyRadius = fineFrequencyRadius
        self.fineTimeRadius = fineTimeRadius
        self.enableAdaptivePruning = enableAdaptivePruning
        self.minimumRelativeConfidence = minimumRelativeConfidence
        self.minimumPeakIsolation = minimumPeakIsolation
        self.pruningTimeRadius = pruningTimeRadius
        self.pruningFrequencyRadius = pruningFrequencyRadius
        self.minimumCandidatesAfterPruning = minimumCandidatesAfterPruning
        self.maximumCandidatesAfterPruning = maximumCandidatesAfterPruning
    }

    func validate() throws {
        guard symbolPeriod > 0,
              toneSpacing > 0,
              maximumFrequency > minimumFrequency,
              minimumSyncScore >= 0,
              maximumCandidates > 0,
              deduplicationFrequency >= 0,
              deduplicationTime >= 0,
              maximumAbsoluteDrift >= 0,
              fineFrequencySubdivisions > 0,
              fineTimeSubdivisions > 0,
              fineFrequencyRadius >= 0,
              fineTimeRadius >= 0,
              (0 ... 1).contains(minimumRelativeConfidence),
              minimumPeakIsolation >= 0,
              pruningTimeRadius >= 0,
              pruningFrequencyRadius >= 0,
              minimumCandidatesAfterPruning > 0,
              maximumCandidatesAfterPruning >= minimumCandidatesAfterPruning else {
            throw SynchronizerError.invalidConfiguration
        }
    }
}
