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

    public init(
        algorithm: FT8LDPCAlgorithm = .normalizedMinSum,
        maximumIterations: Int = 50,
        normalizationFactor: Float = 0.8,
        damping: Float = 0,
        messageLimit: Float = 32
    ) {
        self.algorithm = algorithm
        self.maximumIterations = maximumIterations
        self.normalizationFactor = normalizationFactor
        self.damping = damping
        self.messageLimit = messageLimit
    }

    func validate() throws {
        guard maximumIterations > 0,
              normalizationFactor > 0,
              normalizationFactor <= 1,
              damping >= 0,
              damping < 1,
              messageLimit > 0 else {
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

    public func decode(_ softSymbols: FT8SoftSymbols) throws -> FT8LDPCResult {
        try decode(logLikelihoodRatios: softSymbols.logLikelihoodRatios)
    }

    public func decode(logLikelihoodRatios channel: [Float]) throws -> FT8LDPCResult {
        try configuration.validate()
        guard channel.count == FT8LDPCMatrix.codewordBitCount else {
            throw FT8LDPCError.invalidLLRCount(channel.count)
        }

        let checks = FT8LDPCMatrix.checkToVariables
        var variableToCheck = checks.map { variables in
            variables.map { channel[$0] }
        }
        var checkToVariable = checks.map {
            Array(repeating: Float.zero, count: $0.count)
        }
        var posterior = channel
        var hard = hardDecision(posterior)

        if FT8LDPCMatrix.isValid(hard) {
            return makeResult(codeword: hard, iterations: 0)
        }

        for iteration in 1...configuration.maximumIterations {
            for checkIndex in checks.indices {
                let incoming = variableToCheck[checkIndex]
                let updated: [Float]
                switch configuration.algorithm {
                case .normalizedMinSum:
                    updated = minSumMessages(incoming)
                case .sumProduct:
                    updated = sumProductMessages(incoming)
                }

                for edge in updated.indices {
                    let clipped = clip(updated[edge])
                    checkToVariable[checkIndex][edge] =
                        configuration.damping * checkToVariable[checkIndex][edge]
                        + (1 - configuration.damping) * clipped
                }
            }

            posterior = channel
            for checkIndex in checks.indices {
                for edge in checks[checkIndex].indices {
                    posterior[checks[checkIndex][edge]] += checkToVariable[checkIndex][edge]
                }
            }

            hard = hardDecision(posterior)
            if FT8LDPCMatrix.isValid(hard) {
                return makeResult(codeword: hard, iterations: iteration)
            }

            for checkIndex in checks.indices {
                for edge in checks[checkIndex].indices {
                    let variable = checks[checkIndex][edge]
                    variableToCheck[checkIndex][edge] =
                        clip(posterior[variable] - checkToVariable[checkIndex][edge])
                }
            }
        }

        return makeResult(
            codeword: hard,
            iterations: configuration.maximumIterations
        )
    }

    private func minSumMessages(_ incoming: [Float]) -> [Float] {
        guard incoming.count > 1 else { return [0] }

        var signProduct: Float = 1
        var minimum = Float.infinity
        var secondMinimum = Float.infinity
        var minimumIndex = 0

        for (index, value) in incoming.enumerated() {
            if value < 0 { signProduct = -signProduct }
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
            let excludedSign = incoming[index] < 0 ? -signProduct : signProduct
            let magnitude = index == minimumIndex ? secondMinimum : minimum
            return excludedSign * magnitude * configuration.normalizationFactor
        }
    }

    private func sumProductMessages(_ incoming: [Float]) -> [Float] {
        incoming.indices.map { excluded in
            var product: Float = 1
            for index in incoming.indices where index != excluded {
                let argument = min(max(incoming[index] / 2, -12), 12)
                product *= tanhf(argument)
            }
            product = min(max(product, -0.999_999), 0.999_999)
            return 2 * atanhf(product)
        }
    }

    private func hardDecision(_ llrs: [Float]) -> FT8BitBuffer {
        FT8BitBuffer(llrs.map { $0 < 0 ? UInt8(1) : UInt8(0) })
    }

    private func clip(_ value: Float) -> Float {
        min(max(value, -configuration.messageLimit), configuration.messageLimit)
    }

    private func makeResult(
        codeword: FT8BitBuffer,
        iterations: Int
    ) -> FT8LDPCResult {
        let syndrome = FT8LDPCMatrix.syndrome(of: codeword)
        let information = FT8BitBuffer(
            Array(codeword.bits.prefix(FT8LDPCMatrix.informationBitCount))
        )
        let parityPassed = syndrome.allSatisfy { $0 == 0 }
        return FT8LDPCResult(
            codeword: codeword,
            informationBits: information,
            iterations: iterations,
            parityPassed: parityPassed,
            crcPassed: parityPassed && FT8CRC.validate(information),
            syndromeWeight: syndrome.reduce(0) { $0 + Int($1) }
        )
    }
}
