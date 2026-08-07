import Foundation
import FT8Protocol

public enum FT8LDPCAlgorithm: Equatable, Sendable {
    case normalizedMinSum
    case sumProduct
}

public struct FT8LDPCConfiguration: Equatable, Sendable {
    public var algorithm: FT8LDPCAlgorithm
    public var maximumIterations: Int
    public var normalizationFactor: Float
    public var damping: Float
    public var messageLimit: Float

    /// Enables a bounded second-stage LDPC ensemble when the primary pass
    /// does not produce a CRC-valid codeword.
    public var enableRobustRetries: Bool

    /// Do not spend the ensemble budget on completely implausible words.
    /// A primary syndrome above this value is returned immediately.
    public var robustRetryMaximumSyndromeWeight: Int

    public init(
        algorithm: FT8LDPCAlgorithm = .normalizedMinSum,
        maximumIterations: Int = 50,
        normalizationFactor: Float = 0.8,
        damping: Float = 0,
        messageLimit: Float = 32,
        enableRobustRetries: Bool = true,
        robustRetryMaximumSyndromeWeight: Int = 45
    ) {
        self.algorithm = algorithm
        self.maximumIterations = maximumIterations
        self.normalizationFactor = normalizationFactor
        self.damping = damping
        self.messageLimit = messageLimit
        self.enableRobustRetries = enableRobustRetries
        self.robustRetryMaximumSyndromeWeight =
            robustRetryMaximumSyndromeWeight
    }

    func validate() throws {
        guard maximumIterations > 0,
              normalizationFactor > 0,
              normalizationFactor <= 1,
              damping >= 0,
              damping < 1,
              messageLimit > 0,
              robustRetryMaximumSyndromeWeight >= 0 else {
            throw FT8LDPCError.invalidConfiguration
        }
    }
}

public enum FT8LDPCError: Error, Equatable, Sendable {
    case invalidLLRCount(Int)
    case invalidConfiguration
}

public struct FT8LDPCResult: Equatable, Sendable {
    public let codeword: FT8BitBuffer
    public let informationBits: FT8BitBuffer
    public let iterations: Int
    public let parityPassed: Bool
    public let crcPassed: Bool
    public let syndromeWeight: Int

    public init(
        codeword: FT8BitBuffer,
        informationBits: FT8BitBuffer,
        iterations: Int,
        parityPassed: Bool,
        crcPassed: Bool,
        syndromeWeight: Int
    ) {
        self.codeword = codeword
        self.informationBits = informationBits
        self.iterations = iterations
        self.parityPassed = parityPassed
        self.crcPassed = crcPassed
        self.syndromeWeight = syndromeWeight
    }
}

public struct FT8LDPCDecoder: Sendable {
    public var configuration: FT8LDPCConfiguration

    public init(configuration: FT8LDPCConfiguration = .init()) {
        self.configuration = configuration
    }

    public func decode(
        _ softSymbols: FT8SoftSymbols
    ) throws -> FT8LDPCResult {
        try decode(
            logLikelihoodRatios:
                softSymbols.logLikelihoodRatios
        )
    }

    public func decode(
        logLikelihoodRatios channel: [Float]
    ) throws -> FT8LDPCResult {
        try configuration.validate()

        guard channel.count == FT8LDPCMatrix.codewordBitCount else {
            throw FT8LDPCError.invalidLLRCount(channel.count)
        }

        let primary = try decodeSingle(
            channel,
            configuration: configuration
        )

        guard configuration.enableRobustRetries,
              !primary.crcPassed,
              primary.syndromeWeight
                <= configuration.robustRetryMaximumSyndromeWeight else {
            return primary
        }

        var best = primary

        // FT8 real-world decodes can sit close to a trapping set where one
        // min-sum scaling converges and another does not. Keep this deliberately
        // bounded: four alternate decoder configurations and three reliability
        // views of the same 174 channel LLRs.
        let retryConfigurations = robustConfigurations()
        let channelVariants = robustChannelVariants(channel)

        for variant in channelVariants {
            for retryConfiguration in retryConfigurations {
                let result = try decodeSingle(
                    variant,
                    configuration: retryConfiguration
                )

                if result.crcPassed {
                    return result
                }

                if isBetter(result, than: best) {
                    best = result
                }
            }
        }

        return best
    }

    private func decodeSingle(
        _ channel: [Float],
        configuration active: FT8LDPCConfiguration
    ) throws -> FT8LDPCResult {
        try active.validate()

        let normalizedChannel =
            normalizeLogLikelihoodRatios(channel)

        let checks = FT8LDPCMatrix.checkToVariables

        var variableToCheck = checks.map { variables in
            variables.map { normalizedChannel[$0] }
        }

        var checkToVariable = checks.map {
            Array(
                repeating: Float.zero,
                count: $0.count
            )
        }

        var posterior = normalizedChannel
        var hard = hardDecision(posterior)

        if FT8LDPCMatrix.isValid(hard) {
            return makeResult(
                codeword: hard,
                iterations: 0
            )
        }

        for iteration in 1...active.maximumIterations {
            for checkIndex in checks.indices {
                let incoming =
                    variableToCheck[checkIndex]

                let updated: [Float]

                switch active.algorithm {
                case .normalizedMinSum:
                    updated = minSumMessages(
                        incoming,
                        configuration: active
                    )
                case .sumProduct:
                    updated = sumProductMessages(
                        incoming
                    )
                }

                for edge in updated.indices {
                    let clipped = clip(
                        updated[edge],
                        limit: active.messageLimit
                    )

                    checkToVariable[checkIndex][edge] =
                        active.damping
                            * checkToVariable[checkIndex][edge]
                        + (1 - active.damping)
                            * clipped
                }
            }

            posterior = normalizedChannel

            for checkIndex in checks.indices {
                for edge in checks[checkIndex].indices {
                    posterior[
                        checks[checkIndex][edge]
                    ] += checkToVariable[
                        checkIndex
                    ][edge]
                }
            }

            hard = hardDecision(posterior)

            if FT8LDPCMatrix.isValid(hard) {
                return makeResult(
                    codeword: hard,
                    iterations: iteration
                )
            }

            for checkIndex in checks.indices {
                for edge in checks[checkIndex].indices {
                    let variable =
                        checks[checkIndex][edge]

                    variableToCheck[checkIndex][edge] =
                        clip(
                            posterior[variable]
                                - checkToVariable[
                                    checkIndex
                                ][edge],
                            limit: active.messageLimit
                        )
                }
            }
        }

        return makeResult(
            codeword: hard,
            iterations: active.maximumIterations
        )
    }

    private func robustConfigurations()
        -> [FT8LDPCConfiguration] {
        [
            .init(
                algorithm: .normalizedMinSum,
                maximumIterations: 80,
                normalizationFactor: 0.68,
                damping: 0.10,
                messageLimit: 32,
                enableRobustRetries: false
            ),
            .init(
                algorithm: .normalizedMinSum,
                maximumIterations: 100,
                normalizationFactor: 0.88,
                damping: 0.20,
                messageLimit: 32,
                enableRobustRetries: false
            ),
            .init(
                algorithm: .sumProduct,
                maximumIterations: 80,
                normalizationFactor: 0.8,
                damping: 0,
                messageLimit: 32,
                enableRobustRetries: false
            ),
            .init(
                algorithm: .sumProduct,
                maximumIterations: 100,
                normalizationFactor: 0.8,
                damping: 0.15,
                messageLimit: 32,
                enableRobustRetries: false
            )
        ]
    }

    private func robustChannelVariants(
        _ channel: [Float]
    ) -> [[Float]] {
        var variants: [[Float]] = [channel]

        // Attenuating only the weakest observations acts as a soft erasure:
        // the parity graph is allowed to decide those positions instead of
        // being forced by a questionable channel sign.
        variants.append(
            attenuatingWeakest(
                channel,
                count: 8,
                factor: 0.25
            )
        )

        variants.append(
            attenuatingWeakest(
                channel,
                count: 14,
                factor: 0
            )
        )

        return variants
    }

    private func attenuatingWeakest(
        _ channel: [Float],
        count: Int,
        factor: Float
    ) -> [Float] {
        guard count > 0 else { return channel }

        let indices = channel.indices.sorted {
            abs(channel[$0]) < abs(channel[$1])
        }

        var adjusted = channel

        for index in indices.prefix(count) {
            adjusted[index] *= factor
        }

        return adjusted
    }

    private func isBetter(
        _ candidate: FT8LDPCResult,
        than current: FT8LDPCResult
    ) -> Bool {
        if candidate.crcPassed != current.crcPassed {
            return candidate.crcPassed
        }

        if candidate.parityPassed != current.parityPassed {
            return candidate.parityPassed
        }

        if candidate.syndromeWeight
            != current.syndromeWeight {
            return candidate.syndromeWeight
                < current.syndromeWeight
        }

        return candidate.iterations < current.iterations
    }

    /// Matches ft8_lib's `ftx_normalize_logl` step by scaling the complete
    /// 174-value LLR vector to a variance of 24 before belief propagation.
    private func normalizeLogLikelihoodRatios(
        _ values: [Float]
    ) -> [Float] {
        guard !values.isEmpty else {
            return values
        }

        var sum: Float = 0
        var sumOfSquares: Float = 0

        for value in values {
            guard value.isFinite else {
                return values
            }

            sum += value
            sumOfSquares += value * value
        }

        let count = Float(values.count)
        let mean = sum / count
        let variance =
            (sumOfSquares / count) - (mean * mean)

        guard variance.isFinite,
              variance > Float.leastNonzeroMagnitude else {
            return values
        }

        let factor = sqrtf(24 / variance)

        guard factor.isFinite else {
            return values
        }

        return values.map { $0 * factor }
    }

    private func minSumMessages(
        _ incoming: [Float],
        configuration active: FT8LDPCConfiguration
    ) -> [Float] {
        guard incoming.count > 1 else {
            return [0]
        }

        var signProduct: Float = 1
        var minimum = Float.infinity
        var secondMinimum = Float.infinity
        var minimumIndex = 0

        for (index, value) in incoming.enumerated() {
            if value < 0 {
                signProduct = -signProduct
            }

            let magnitude = abs(value)

            if magnitude < minimum {
                secondMinimum = minimum
                minimum = magnitude
                minimumIndex = index
            } else if magnitude < secondMinimum {
                secondMinimum = magnitude
            }
        }

        return incoming.indices.map { index in
            let excludedSign =
                incoming[index] < 0
                    ? -signProduct
                    : signProduct

            let magnitude =
                index == minimumIndex
                    ? secondMinimum
                    : minimum

            return excludedSign
                * magnitude
                * active.normalizationFactor
        }
    }

    private func sumProductMessages(
        _ incoming: [Float]
    ) -> [Float] {
        incoming.indices.map { excluded in
            var product: Float = 1

            for index in incoming.indices
            where index != excluded {
                let argument = min(
                    max(
                        incoming[index] / 2,
                        -12
                    ),
                    12
                )

                product *= tanhf(argument)
            }

            product = min(
                max(product, -0.999_999),
                0.999_999
            )

            return 2 * atanhf(product)
        }
    }

    private func hardDecision(
        _ llrs: [Float]
    ) -> FT8BitBuffer {
        FT8BitBuffer(
            llrs.map {
                $0 < 0 ? UInt8(1) : UInt8(0)
            }
        )
    }

    private func clip(
        _ value: Float,
        limit: Float
    ) -> Float {
        min(max(value, -limit), limit)
    }

    private func makeResult(
        codeword: FT8BitBuffer,
        iterations: Int
    ) -> FT8LDPCResult {
        let syndrome =
            FT8LDPCMatrix.syndrome(of: codeword)

        let information = FT8BitBuffer(
            Array(
                codeword.bits.prefix(
                    FT8LDPCMatrix.informationBitCount
                )
            )
        )

        let parityPassed =
            syndrome.allSatisfy { $0 == 0 }

        return FT8LDPCResult(
            codeword: codeword,
            informationBits: information,
            iterations: iterations,
            parityPassed: parityPassed,
            crcPassed:
                parityPassed
                && FT8CRC.validate(information),
            syndromeWeight:
                syndrome.reduce(0) {
                    $0 + Int($1)
                }
        )
    }
}
