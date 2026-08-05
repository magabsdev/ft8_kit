import Foundation
import FT8DSP

public struct FT8ParallelMultiPassDecoder: Sendable {
    public var configuration: FT8MultiPassConfiguration
    public var decoder: FT8ParallelDecoder
    public var canceller: FT8SignalCanceller

    public init(
        configuration: FT8MultiPassConfiguration = .init(),
        decoder: FT8ParallelDecoder = .init(),
        canceller: FT8SignalCanceller = .init()
    ) {
        self.configuration = configuration
        self.decoder = decoder
        self.canceller = canceller
    }

    public func decode(
        spectrogram: Spectrogram
    ) async throws -> FT8MultiPassDecodeBatch {
        try configuration.validate()
        let started = ContinuousClock.now

        var residual = spectrogram
        var accepted: [FT8CompleteDecode] = []
        var passMetrics: [FT8DecodePassMetrics] = []
        var totalCancelled = 0
        var totalAffectedBins = 0

        for passIndex in 1...configuration.maximumPasses {
            let passStarted = ContinuousClock.now
            let batch = try await decoder.decode(
                spectrogram: residual
            )

            let newMessages = batch.messages.filter { candidate in
                !accepted.contains {
                    isDuplicate($0, candidate)
                }
            }

            accepted.append(contentsOf: newMessages)
            accepted = stableOrder(accepted)

            let cancellable = Array(
                newMessages
                    .sorted {
                        $0.decoded.confidence
                            > $1.decoded.confidence
                    }
                    .prefix(configuration.maximumSignalsPerPass)
            )

            var reduction: Double = 0
            var affectedBins = 0

            if !cancellable.isEmpty {
                let result = try canceller.cancel(
                    cancellable,
                    from: residual
                )
                residual = result.spectrogram
                reduction = result.reductionFraction
                affectedBins = result.affectedBins
                totalCancelled += cancellable.count
                totalAffectedBins += affectedBins
            }

            passMetrics.append(
                FT8DecodePassMetrics(
                    pass: passIndex,
                    candidatesFound: batch.metrics.candidatesFound,
                    candidatesScheduled:
                        batch.metrics.candidatesScheduled,
                    softSymbolsExtracted:
                        batch.metrics.softSymbolsExtracted,
                    ldpcAttempts: batch.metrics.ldpcAttempts,
                    parityPassed: batch.metrics.parityPassed,
                    crcPassed: batch.metrics.crcPassed,
                    messagesDecoded: batch.messages.count,
                    newMessages: newMessages.count,
                    signalsCancelled: cancellable.count,
                    affectedBins: affectedBins,
                    energyReductionFraction: reduction,
                    elapsedSeconds: Self.seconds(
                        ContinuousClock.now - passStarted
                    )
                )
            )

            if configuration.stopWhenNoNewMessages,
               newMessages.count
                < configuration.minimumNewMessages {
                break
            }

            if !cancellable.isEmpty,
               reduction
                < configuration.minimumEnergyReductionFraction {
                break
            }
        }

        return FT8MultiPassDecodeBatch(
            messages: stableOrder(accepted),
            residualSpectrogram: residual,
            metrics: FT8MultiPassMetrics(
                passesCompleted: passMetrics.count,
                uniqueMessages: accepted.count,
                totalSignalsCancelled: totalCancelled,
                totalAffectedBins: totalAffectedBins,
                elapsedSeconds: Self.seconds(
                    ContinuousClock.now - started
                ),
                passes: passMetrics
            )
        )
    }

    private func isDuplicate(
        _ lhs: FT8CompleteDecode,
        _ rhs: FT8CompleteDecode
    ) -> Bool {
        lhs.decoded.payload == rhs.decoded.payload
            && abs(
                lhs.candidate.startTime
                    - rhs.candidate.startTime
            ) <= decoder.optimizedConfiguration.deduplicationTime
            && abs(
                lhs.candidate.frequency
                    - rhs.candidate.frequency
            ) <= decoder.optimizedConfiguration.deduplicationFrequency
    }

    private func stableOrder(
        _ messages: [FT8CompleteDecode]
    ) -> [FT8CompleteDecode] {
        messages.sorted {
            if $0.candidate.startTime == $1.candidate.startTime {
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
