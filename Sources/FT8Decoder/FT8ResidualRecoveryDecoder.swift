import Foundation
import FT8DSP

public enum FT8ResidualRecoveryDecoderError:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
}

public struct FT8ResidualRecoveryConfiguration:
    Equatable,
    Sendable
{
    public var enabled: Bool
    public var maximumRecoveryPasses: Int
    public var maximumSignalsPerPass: Int

    public var minimumSyncScore: Float
    public var minimumSNRDB: Float
    public var maximumSynchronizerCandidates: Int

    public var deduplicationTime: Double
    public var deduplicationFrequency: Float

    public var minimumRelativeConfidence: Float
    public var minimumPeakIsolation: Float
    public var minimumCandidatesAfterPruning: Int
    public var maximumCandidatesAfterPruning: Int

    /// Residual recovery is intentionally COARSE globally.
    ///
    /// Do not turn on FT8Synchronizer's global fine search here. With hundreds
    /// of relaxed residual seeds, an 8×8 refinement grid expands into millions
    /// of Costas evaluations. Fine timing/frequency work belongs in the
    /// decoder's bounded nearby-hypothesis stage after coarse candidates exist.
    public var enableGlobalFineSearch: Bool

    public var maximumCandidatesToDecode: Int
    public var minimumCandidateConfidence: Float
    public var minimumSoftSymbolConfidence: Float
    public var disableRobustLDPC: Bool

    public init(
        enabled: Bool = true,
        maximumRecoveryPasses: Int = 1,
        maximumSignalsPerPass: Int = 1,
        minimumSyncScore: Float = 0.34,
        minimumSNRDB: Float = -3.0,
        maximumSynchronizerCandidates: Int = 120,
        deduplicationTime: Double = 0.060,
        deduplicationFrequency: Float = 4.6875,
        minimumRelativeConfidence: Float = 0.42,
        minimumPeakIsolation: Float = 0,
        minimumCandidatesAfterPruning: Int = 24,
        maximumCandidatesAfterPruning: Int = 90,
        enableGlobalFineSearch: Bool = false,
        maximumCandidatesToDecode: Int = 80,
        minimumCandidateConfidence: Float = 0.05,
        minimumSoftSymbolConfidence: Float = 0.05,
        disableRobustLDPC: Bool = true
    ) {
        self.enabled = enabled
        self.maximumRecoveryPasses =
            maximumRecoveryPasses
        self.maximumSignalsPerPass =
            maximumSignalsPerPass
        self.minimumSyncScore = minimumSyncScore
        self.minimumSNRDB = minimumSNRDB
        self.maximumSynchronizerCandidates =
            maximumSynchronizerCandidates
        self.deduplicationTime = deduplicationTime
        self.deduplicationFrequency =
            deduplicationFrequency
        self.minimumRelativeConfidence =
            minimumRelativeConfidence
        self.minimumPeakIsolation =
            minimumPeakIsolation
        self.minimumCandidatesAfterPruning =
            minimumCandidatesAfterPruning
        self.maximumCandidatesAfterPruning =
            maximumCandidatesAfterPruning
        self.enableGlobalFineSearch =
            enableGlobalFineSearch
        self.maximumCandidatesToDecode =
            maximumCandidatesToDecode
        self.minimumCandidateConfidence =
            minimumCandidateConfidence
        self.minimumSoftSymbolConfidence =
            minimumSoftSymbolConfidence
        self.disableRobustLDPC =
            disableRobustLDPC
    }

    func validate() throws {
        guard maximumRecoveryPasses > 0,
              maximumSignalsPerPass > 0,
              minimumSyncScore >= 0,
              maximumSynchronizerCandidates > 0,
              deduplicationTime >= 0,
              deduplicationFrequency >= 0,
              (0 ... 1).contains(
                minimumRelativeConfidence
              ),
              minimumPeakIsolation >= 0,
              minimumCandidatesAfterPruning > 0,
              maximumCandidatesAfterPruning
                >= minimumCandidatesAfterPruning,
              maximumCandidatesToDecode > 0,
              (0 ... 1).contains(
                minimumCandidateConfidence
              ),
              (0 ... 1).contains(
                minimumSoftSymbolConfidence
              ) else {
            throw FT8ResidualRecoveryDecoderError
                .invalidConfiguration
        }
    }
}

public struct FT8ResidualRecoveryPassMetrics:
    Equatable,
    Sendable
{
    public let pass: Int
    public let candidatesFound: Int
    public let candidatesScheduled: Int
    public let parityPassed: Int
    public let crcPassed: Int
    public let messagesReturned: Int
    public let newMessages: Int
    public let signalsCancelled: Int
    public let affectedBins: Int
    public let energyReductionFraction: Double
    public let elapsedSeconds: Double
}

public struct FT8ResidualRecoveryDecodeBatch:
    Equatable,
    Sendable
{
    public let messages: [FT8CompleteDecode]
    public let residualSpectrogram: Spectrogram
    public let baseBatch: FT8MultiPassDecodeBatch
    public let recoveryPasses:
        [FT8ResidualRecoveryPassMetrics]
    public let candidateTraces: [FT8CandidateTrace]
}

public struct FT8ResidualRecoveryDecoder:
    Sendable
{
    public var configuration:
        FT8ResidualRecoveryConfiguration
    public var baseDecoder: FT8MultiPassDecoder
    public var recoveryDecoder: FT8OptimizedDecoder
    public var canceller: FT8SignalCanceller

    public init(
        configuration:
            FT8ResidualRecoveryConfiguration =
                .init(),
        baseDecoder: FT8MultiPassDecoder = .init(),
        recoveryDecoder:
            FT8OptimizedDecoder = .init(),
        canceller: FT8SignalCanceller = .init()
    ) {
        self.configuration = configuration
        self.baseDecoder = baseDecoder
        self.recoveryDecoder = recoveryDecoder
        self.canceller = canceller
    }

    public func decode(
        spectrogram: Spectrogram
    ) throws -> FT8ResidualRecoveryDecodeBatch {
        try configuration.validate()

        let base = try baseDecoder.decode(
            spectrogram: spectrogram
        )

        guard configuration.enabled else {
            return FT8ResidualRecoveryDecodeBatch(
                messages: base.messages,
                residualSpectrogram:
                    base.residualSpectrogram,
                baseBatch: base,
                recoveryPasses: [],
                candidateTraces:
                    base.candidateTraces
            )
        }

        var accepted = base.messages
        var residual = base.residualSpectrogram
        var traces = base.candidateTraces
        var metrics:
            [FT8ResidualRecoveryPassMetrics] = []

        for recoveryIndex
        in 1...configuration.maximumRecoveryPasses {
            let logicalPass =
                base.metrics.passesCompleted
                + recoveryIndex

            print(
                "[ResidualRecovery] Starting pass "
                    + "\(logicalPass)"
                    + " with bounded coarse synchronizer"
            )

            let started = ContinuousClock.now
            let decoder = configuredRecoveryDecoder()

            let batch = try decoder.decode(
                spectrogram: residual
            )

            traces.append(
                contentsOf:
                    batch.candidateTraces.map {
                        remapTrace(
                            $0,
                            toPass: logicalPass
                        )
                    }
            )

            let newMessages = batch.messages.filter {
                candidate in
                !accepted.contains {
                    $0.decoded.payload
                        == candidate.decoded.payload
                }
            }

            accepted.append(
                contentsOf: newMessages
            )
            accepted = stableOrder(accepted)

            let cancellable = Array(
                newMessages
                    .filter {
                        $0.ldpc.parityPassed
                            && $0.ldpc.crcPassed
                    }
                    .sorted {
                        $0.decoded.confidence
                            > $1.decoded.confidence
                    }
                    .prefix(
                        configuration
                            .maximumSignalsPerPass
                    )
            )

            var affectedBins = 0
            var reduction = 0.0

            if !cancellable.isEmpty {
                let result = try canceller.cancel(
                    cancellable,
                    from: residual
                )
                residual = result.spectrogram
                affectedBins = result.affectedBins
                reduction = result.reductionFraction
            }

            let elapsed = Self.seconds(
                ContinuousClock.now - started
            )

            metrics.append(
                FT8ResidualRecoveryPassMetrics(
                    pass: logicalPass,
                    candidatesFound:
                        batch.metrics.candidatesFound,
                    candidatesScheduled:
                        batch.metrics.candidatesScheduled,
                    parityPassed:
                        batch.metrics.parityPassed,
                    crcPassed:
                        batch.metrics.crcPassed,
                    messagesReturned:
                        batch.messages.count,
                    newMessages:
                        newMessages.count,
                    signalsCancelled:
                        cancellable.count,
                    affectedBins: affectedBins,
                    energyReductionFraction:
                        reduction,
                    elapsedSeconds: elapsed
                )
            )

            print(
                "[ResidualRecovery] Complete pass "
                    + "\(logicalPass)"
                    + ": candidates="
                    + "\(batch.metrics.candidatesFound)"
                    + " scheduled="
                    + "\(batch.metrics.candidatesScheduled)"
                    + " new=\(newMessages.count)"
                    + " elapsed=\(elapsed)s"
            )

            if newMessages.isEmpty
                || cancellable.isEmpty {
                break
            }
        }

        return FT8ResidualRecoveryDecodeBatch(
            messages: stableOrder(accepted),
            residualSpectrogram: residual,
            baseBatch: base,
            recoveryPasses: metrics,
            candidateTraces: traces
        )
    }

    private func configuredRecoveryDecoder()
        -> FT8OptimizedDecoder
    {
        var decoder = recoveryDecoder

        decoder.configuration
            .maximumCandidatesToDecode =
            configuration.maximumCandidatesToDecode

        decoder.configuration
            .minimumCandidateConfidence =
            configuration.minimumCandidateConfidence

        decoder.configuration
            .minimumSoftSymbolConfidence =
            configuration.minimumSoftSymbolConfidence

        decoder.configuration
            .captureCandidateTraces = true

        if configuration.disableRobustLDPC {
            decoder.ldpcDecoder.configuration
                .enableRobustRetries = false
        }

        var sync =
            decoder.synchronizer.configuration

        sync.minimumSyncScore = min(
            sync.minimumSyncScore,
            configuration.minimumSyncScore
        )
        sync.minimumSNRDB = min(
            sync.minimumSNRDB,
            configuration.minimumSNRDB
        )

        // Bound the relaxed residual search. The previous checkpoint used 220,
        // which made the synchronizer retain up to 660 fine-search seeds.
        sync.maximumCandidates =
            configuration.maximumSynchronizerCandidates

        sync.deduplicationTime =
            configuration.deduplicationTime
        sync.deduplicationFrequency =
            configuration.deduplicationFrequency

        // Critical performance fix: do a broad COARSE residual search only.
        // FT8OptimizedDecoder's nearby-hypothesis retry remains responsible for
        // bounded fine timing/frequency recovery.
        sync.enableFineSearch =
            configuration.enableGlobalFineSearch

        sync.enableAdaptivePruning = true
        sync.minimumRelativeConfidence =
            configuration.minimumRelativeConfidence
        sync.minimumPeakIsolation =
            configuration.minimumPeakIsolation
        sync.minimumCandidatesAfterPruning =
            configuration.minimumCandidatesAfterPruning
        sync.maximumCandidatesAfterPruning =
            min(
                configuration.maximumCandidatesAfterPruning,
                configuration.maximumSynchronizerCandidates
            )

        decoder.synchronizer.configuration = sync
        return decoder
    }

    private func remapTrace(
        _ trace: FT8CandidateTrace,
        toPass pass: Int
    ) -> FT8CandidateTrace {
        FT8CandidateTrace(
            pass: pass,
            candidateIndex: trace.candidateIndex,
            startTime: trace.startTime,
            frequency: trace.frequency,
            driftHzPerSecond:
                trace.driftHzPerSecond,
            syncScore: trace.syncScore,
            snrDB: trace.snrDB,
            candidateConfidence:
                trace.candidateConfidence,
            averageSoftSymbolConfidence:
                trace.averageSoftSymbolConfidence,
            symbols: trace.symbols,
            logLikelihoodRatios:
                trace.logLikelihoodRatios,
            ldpcIterations: trace.ldpcIterations,
            syndromeWeight: trace.syndromeWeight,
            parityPassed: trace.parityPassed,
            crcPassed: trace.crcPassed,
            decodedText: trace.decodedText,
            failure: trace.failure
        )
    }

    private func stableOrder(
        _ messages: [FT8CompleteDecode]
    ) -> [FT8CompleteDecode] {
        messages.sorted {
            if $0.candidate.startTime
                == $1.candidate.startTime {
                return $0.candidate.frequency
                    < $1.candidate.frequency
            }
            return $0.candidate.startTime
                < $1.candidate.startTime
        }
    }

    private static func seconds(
        _ duration: Duration
    ) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds)
                / 1_000_000_000_000_000_000
    }
}

public struct FT8ResidualRecoverySlotDecoder:
    Sendable
{
    public var waterfallConfiguration:
        WaterfallConfiguration
    public var decoder:
        FT8ResidualRecoveryDecoder

    public init(
        waterfallConfiguration:
            WaterfallConfiguration = .init(
                sampleRate: 12_000,
                fftSize: 1_920,
                hopSize: 480,
                minimumFrequency: 100,
                maximumFrequency: 3_000,
                dynamicRange: 100
            ),
        decoder:
            FT8ResidualRecoveryDecoder =
                .init()
    ) {
        self.waterfallConfiguration =
            waterfallConfiguration
        self.decoder = decoder
    }

    public func decode(
        samples: [Float]
    ) throws
        -> FT8ResidualRecoveryDecodeBatch
    {
        let spectrogram = try Waterfall.analyse(
            samples: samples,
            configuration:
                waterfallConfiguration
        )
        return try decoder.decode(
            spectrogram: spectrogram
        )
    }
}
