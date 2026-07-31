import Foundation
import FT8DSP

public enum FT8MultiPassDecoderError:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
}

public struct FT8MultiPassConfiguration:
    Equatable,
    Sendable
{
    public var maximumPasses: Int
    public var maximumSignalsPerPass: Int
    public var minimumNewMessages: Int
    public var minimumEnergyReductionFraction: Double
    public var stopWhenNoNewMessages: Bool

    public init(
        maximumPasses: Int = 3,
        maximumSignalsPerPass: Int = 12,
        minimumNewMessages: Int = 1,
        minimumEnergyReductionFraction: Double = 0.000_001,
        stopWhenNoNewMessages: Bool = true
    ) {
        self.maximumPasses = maximumPasses
        self.maximumSignalsPerPass =
            maximumSignalsPerPass
        self.minimumNewMessages = minimumNewMessages
        self.minimumEnergyReductionFraction =
            minimumEnergyReductionFraction
        self.stopWhenNoNewMessages =
            stopWhenNoNewMessages
    }

    func validate() throws {
        guard maximumPasses > 0,
              maximumSignalsPerPass > 0,
              minimumNewMessages >= 0,
              minimumEnergyReductionFraction >= 0,
              minimumEnergyReductionFraction <= 1 else {
            throw FT8MultiPassDecoderError.invalidConfiguration
        }
    }
}

public struct FT8DecodePassMetrics:
    Equatable,
    Sendable
{
    public let pass: Int
    public let candidatesFound: Int
    public let candidatesScheduled: Int
    public let softSymbolsExtracted: Int
    public let ldpcAttempts: Int
    public let parityPassed: Int
    public let crcPassed: Int
    public let messagesDecoded: Int
    public let newMessages: Int
    public let signalsCancelled: Int
    public let affectedBins: Int
    public let energyReductionFraction: Double
    public let elapsedSeconds: Double

    public init(
        pass: Int,
        candidatesFound: Int,
        candidatesScheduled: Int,
        softSymbolsExtracted: Int,
        ldpcAttempts: Int,
        parityPassed: Int,
        crcPassed: Int,
        messagesDecoded: Int,
        newMessages: Int,
        signalsCancelled: Int,
        affectedBins: Int,
        energyReductionFraction: Double,
        elapsedSeconds: Double
    ) {
        self.pass = pass
        self.candidatesFound = candidatesFound
        self.candidatesScheduled = candidatesScheduled
        self.softSymbolsExtracted = softSymbolsExtracted
        self.ldpcAttempts = ldpcAttempts
        self.parityPassed = parityPassed
        self.crcPassed = crcPassed
        self.messagesDecoded = messagesDecoded
        self.newMessages = newMessages
        self.signalsCancelled = signalsCancelled
        self.affectedBins = affectedBins
        self.energyReductionFraction =
            energyReductionFraction
        self.elapsedSeconds = elapsedSeconds
    }
}

public struct FT8MultiPassMetrics:
    Equatable,
    Sendable
{
    public let passesCompleted: Int
    public let uniqueMessages: Int
    public let totalSignalsCancelled: Int
    public let totalAffectedBins: Int
    public let elapsedSeconds: Double
    public let passes: [FT8DecodePassMetrics]

    public init(
        passesCompleted: Int,
        uniqueMessages: Int,
        totalSignalsCancelled: Int,
        totalAffectedBins: Int,
        elapsedSeconds: Double,
        passes: [FT8DecodePassMetrics]
    ) {
        self.passesCompleted = passesCompleted
        self.uniqueMessages = uniqueMessages
        self.totalSignalsCancelled =
            totalSignalsCancelled
        self.totalAffectedBins = totalAffectedBins
        self.elapsedSeconds = elapsedSeconds
        self.passes = passes
    }
}

public struct FT8MultiPassDecodeBatch:
    Equatable,
    Sendable
{
    public let messages: [FT8CompleteDecode]
    public let residualSpectrogram: Spectrogram
    public let metrics: FT8MultiPassMetrics

    public init(
        messages: [FT8CompleteDecode],
        residualSpectrogram: Spectrogram,
        metrics: FT8MultiPassMetrics
    ) {
        self.messages = messages
        self.residualSpectrogram =
            residualSpectrogram
        self.metrics = metrics
    }
}

public struct FT8MultiPassDecoder: Sendable {
    public var configuration:
        FT8MultiPassConfiguration
    public var decoder: FT8OptimizedDecoder
    public var canceller: FT8SignalCanceller

    public init(
        configuration:
            FT8MultiPassConfiguration = .init(),
        decoder: FT8OptimizedDecoder = .init(),
        canceller: FT8SignalCanceller = .init()
    ) {
        self.configuration = configuration
        self.decoder = decoder
        self.canceller = canceller
    }

    public func decode(
        spectrogram: Spectrogram
    ) throws -> FT8MultiPassDecodeBatch {
        try configuration.validate()
        let started = ContinuousClock.now

        var residual = spectrogram
        var accepted: [FT8CompleteDecode] = []
        var passMetrics: [FT8DecodePassMetrics] = []
        var totalCancelled = 0
        var totalAffectedBins = 0

        for passIndex in 1...configuration.maximumPasses {
            let passStarted = ContinuousClock.now
            let batch = try decoder.decode(
                spectrogram: residual
            )
            let newMessages = batch.messages.filter {
                candidate in
                !accepted.contains {
                    isDuplicate($0, candidate)
                }
            }

            accepted.append(contentsOf: newMessages)
            accepted = stableOrder(accepted)

            let cancellable = Array(
                newMessages
                    .sorted {
                        $0.decoded.confidence >
                        $1.decoded.confidence
                    }
                    .prefix(
                        configuration.maximumSignalsPerPass
                    )
            )

            var cancellationFraction: Double = 0
            var affectedBins = 0

            if !cancellable.isEmpty {
                let result = try canceller.cancel(
                    cancellable,
                    from: residual
                )
                residual = result.spectrogram
                cancellationFraction =
                    result.reductionFraction
                affectedBins = result.affectedBins
                totalCancelled += cancellable.count
                totalAffectedBins += affectedBins
            }

            passMetrics.append(
                FT8DecodePassMetrics(
                    pass: passIndex,
                    candidatesFound:
                        batch.metrics.candidatesFound,
                    candidatesScheduled:
                        batch.metrics.candidatesScheduled,
                    softSymbolsExtracted:
                        batch.metrics.softSymbolsExtracted,
                    ldpcAttempts:
                        batch.metrics.ldpcAttempts,
                    parityPassed:
                        batch.metrics.parityPassed,
                    crcPassed:
                        batch.metrics.crcPassed,
                    messagesDecoded:
                        batch.messages.count,
                    newMessages: newMessages.count,
                    signalsCancelled:
                        cancellable.count,
                    affectedBins: affectedBins,
                    energyReductionFraction:
                        cancellationFraction,
                    elapsedSeconds: Self.seconds(
                        ContinuousClock.now -
                        passStarted
                    )
                )
            )

            if configuration.stopWhenNoNewMessages,
               newMessages.count <
                configuration.minimumNewMessages {
                break
            }

            if !cancellable.isEmpty,
               cancellationFraction <
                configuration
                    .minimumEnergyReductionFraction {
                break
            }
        }

        let elapsed = Self.seconds(
            ContinuousClock.now - started
        )

        return FT8MultiPassDecodeBatch(
            messages: stableOrder(accepted),
            residualSpectrogram: residual,
            metrics: FT8MultiPassMetrics(
                passesCompleted: passMetrics.count,
                uniqueMessages: accepted.count,
                totalSignalsCancelled: totalCancelled,
                totalAffectedBins: totalAffectedBins,
                elapsedSeconds: elapsed,
                passes: passMetrics
            )
        )
    }

    private func isDuplicate(
        _ lhs: FT8CompleteDecode,
        _ rhs: FT8CompleteDecode
    ) -> Bool {
        lhs.decoded.payload == rhs.decoded.payload &&
        abs(
            lhs.candidate.startTime -
            rhs.candidate.startTime
        ) <= decoder.configuration.deduplicationTime &&
        abs(
            lhs.candidate.frequency -
            rhs.candidate.frequency
        ) <= decoder.configuration.deduplicationFrequency
    }

    private func stableOrder(
        _ messages: [FT8CompleteDecode]
    ) -> [FT8CompleteDecode] {
        messages.sorted {
            if $0.candidate.startTime ==
                $1.candidate.startTime {
                return $0.candidate.frequency <
                    $1.candidate.frequency
            }
            return $0.candidate.startTime <
                $1.candidate.startTime
        }
    }

    private static func seconds(
        _ duration: Duration
    ) -> Double {
        let components = duration.components
        return Double(components.seconds) +
            Double(components.attoseconds) /
            1_000_000_000_000_000_000
    }
}
