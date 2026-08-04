import Foundation
import FT8DSP

public extension FT8MultiPassDecoder {
    func decode(
        spectrogram: Spectrogram,
        oversampledWaterfall: FT8OversampledWaterfall,
        candidateRefiner: FT8OversampledCandidateRefiner = .init()
    ) throws -> FT8MultiPassDecodeBatch {
        try configuration.validate()
        let started = ContinuousClock.now

        var residual = spectrogram
        var accepted: [FT8CompleteDecode] = []
        var passMetrics: [FT8DecodePassMetrics] = []
        var totalCancelled = 0
        var totalAffectedBins = 0
        var candidateTraces: [FT8CandidateTrace] = []

        for passIndex in 1...configuration.maximumPasses {
            let passStarted = ContinuousClock.now
            let batch = try decoder.decode(
                spectrogram: residual,
                oversampledWaterfall: oversampledWaterfall,
                candidateRefiner: candidateRefiner
            )

            candidateTraces.append(
                contentsOf: batch.candidateTraces.map {
                    FT8CandidateTrace(
                        pass: passIndex,
                        candidateIndex: $0.candidateIndex,
                        startTime: $0.startTime,
                        frequency: $0.frequency,
                        driftHzPerSecond: $0.driftHzPerSecond,
                        syncScore: $0.syncScore,
                        snrDB: $0.snrDB,
                        candidateConfidence: $0.candidateConfidence,
                        averageSoftSymbolConfidence:
                            $0.averageSoftSymbolConfidence,
                        symbols: $0.symbols,
                        logLikelihoodRatios: $0.logLikelihoodRatios,
                        ldpcIterations: $0.ldpcIterations,
                        syndromeWeight: $0.syndromeWeight,
                        parityPassed: $0.parityPassed,
                        crcPassed: $0.crcPassed,
                        decodedText: $0.decodedText,
                        failure: $0.failure
                    )
                }
            )

            let newMessages = batch.messages.filter { candidate in
                !accepted.contains {
                    checkpoint2IsDuplicate($0, candidate)
                }
            }

            accepted.append(contentsOf: newMessages)
            accepted = checkpoint2StableOrder(accepted)

            let cancellable = Array(
                newMessages
                    .sorted {
                        $0.decoded.confidence > $1.decoded.confidence
                    }
                    .prefix(configuration.maximumSignalsPerPass)
            )

            var cancellationFraction: Double = 0
            var affectedBins = 0

            if !cancellable.isEmpty {
                let result = try canceller.cancel(
                    cancellable,
                    from: residual
                )

                residual = result.spectrogram
                cancellationFraction = result.reductionFraction
                affectedBins = result.affectedBins
                totalCancelled += cancellable.count
                totalAffectedBins += affectedBins
            }

            passMetrics.append(
                FT8DecodePassMetrics(
                    pass: passIndex,
                    candidatesFound: batch.metrics.candidatesFound,
                    candidatesScheduled: batch.metrics.candidatesScheduled,
                    softSymbolsExtracted:
                        batch.metrics.softSymbolsExtracted,
                    ldpcAttempts: batch.metrics.ldpcAttempts,
                    parityPassed: batch.metrics.parityPassed,
                    crcPassed: batch.metrics.crcPassed,
                    messagesDecoded: batch.messages.count,
                    newMessages: newMessages.count,
                    signalsCancelled: cancellable.count,
                    affectedBins: affectedBins,
                    energyReductionFraction: cancellationFraction,
                    elapsedSeconds: checkpoint2Seconds(
                        ContinuousClock.now - passStarted
                    )
                )
            )

            if configuration.stopWhenNoNewMessages,
               newMessages.count < configuration.minimumNewMessages {
                break
            }

            if !cancellable.isEmpty,
               cancellationFraction
                < configuration.minimumEnergyReductionFraction {
                break
            }
        }

        return FT8MultiPassDecodeBatch(
            messages: checkpoint2StableOrder(accepted),
            residualSpectrogram: residual,
            metrics: FT8MultiPassMetrics(
                passesCompleted: passMetrics.count,
                uniqueMessages: accepted.count,
                totalSignalsCancelled: totalCancelled,
                totalAffectedBins: totalAffectedBins,
                elapsedSeconds: checkpoint2Seconds(
                    ContinuousClock.now - started
                ),
                passes: passMetrics
            ),
            candidateTraces: candidateTraces
        )
    }

    private func checkpoint2IsDuplicate(
        _ lhs: FT8CompleteDecode,
        _ rhs: FT8CompleteDecode
    ) -> Bool {
        lhs.decoded.payload == rhs.decoded.payload
            && abs(lhs.candidate.startTime - rhs.candidate.startTime)
                <= decoder.configuration.deduplicationTime
            && abs(lhs.candidate.frequency - rhs.candidate.frequency)
                <= decoder.configuration.deduplicationFrequency
    }

    private func checkpoint2StableOrder(
        _ messages: [FT8CompleteDecode]
    ) -> [FT8CompleteDecode] {
        messages.sorted {
            if $0.candidate.startTime == $1.candidate.startTime {
                return $0.candidate.frequency < $1.candidate.frequency
            }

            return $0.candidate.startTime < $1.candidate.startTime
        }
    }

    private func checkpoint2Seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds)
            / 1_000_000_000_000_000_000
    }
}
