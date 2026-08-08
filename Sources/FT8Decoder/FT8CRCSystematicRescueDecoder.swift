import Foundation
import FT8Protocol

public struct FT8CRCSystematicRescueDecoder: Sendable {
    public struct Configuration: Equatable, Sendable {
        public var leastReliablePayloadBits: Int
        public var maximumFlipOrder: Int
        public var maximumHypotheses: Int
        public var maximumResults: Int
        public var maximumCodewordBitChanges: Int
        public var maximumWeightedDistanceIncrease: Float

        public init(
            leastReliablePayloadBits: Int = 14,
            maximumFlipOrder: Int = 3,
            maximumHypotheses: Int = 512,
            maximumResults: Int = 8,
            maximumCodewordBitChanges: Int = 28,
            maximumWeightedDistanceIncrease: Float = 12
        ) {
            self.leastReliablePayloadBits = min(77, max(1, leastReliablePayloadBits))
            self.maximumFlipOrder = min(3, max(0, maximumFlipOrder))
            self.maximumHypotheses = max(1, maximumHypotheses)
            self.maximumResults = max(1, maximumResults)
            self.maximumCodewordBitChanges = max(0, maximumCodewordBitChanges)
            self.maximumWeightedDistanceIncrease = max(0, maximumWeightedDistanceIncrease)
        }
    }

    public struct Candidate: Equatable, Sendable {
        public let ldpc: FT8LDPCResult
        public let flippedPayloadBitIndices: [Int]
        public let codewordBitChanges: Int
        public let weightedDistance: Float
        public let weightedDistanceIncrease: Float
    }

    public var configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public func decode(
        logLikelihoodRatios llr: [Float],
        startingResult: FT8LDPCResult
    ) throws -> [Candidate] {
        guard llr.count == FT8LDPCMatrix.codewordBitCount else {
            throw FT8LDPCError.invalidLLRCount(llr.count)
        }

        guard startingResult.informationBits.count == 91,
              startingResult.codeword.count == FT8LDPCMatrix.codewordBitCount,
              startingResult.parityPassed,
              startingResult.syndromeWeight == 0,
              !startingResult.crcPassed,
              !startingResult.isDegenerateZeroCodeword else {
            return []
        }

        let hard = llr.map { $0 < 0 ? UInt8(1) : UInt8(0) }
        let reliability = llr.map(abs)
        let startingCodeword = startingResult.codeword.bits
        let startingDistance = weightedDistance(
            startingCodeword,
            hard: hard,
            reliability: reliability
        )

        let basePayload = Array(startingResult.informationBits.bits.prefix(77))
        let searchPositions = Array(
            (0..<77)
                .sorted { reliability[$0] < reliability[$1] }
                .prefix(configuration.leastReliablePayloadBits)
        )

        var results: [Candidate] = []
        var tested = 0

        func consider(_ flipped: [Int]) {
            guard tested < configuration.maximumHypotheses else { return }
            tested += 1

            var payloadBits = basePayload
            for index in flipped {
                payloadBits[index] ^= 1
            }

            let payload = FT8BitBuffer(payloadBits)
            guard let information = try? FT8CRC.append(to: payload) else {
                return
            }

            let codeword = encodeSystematicInformation(information.bits)
            guard codeword.contains(1) else { return }

            let changes = zip(codeword, startingCodeword).reduce(into: 0) { count, pair in
                if pair.0 != pair.1 {
                    count += 1
                }
            }
            guard changes <= configuration.maximumCodewordBitChanges else {
                return
            }

            let distance = weightedDistance(
                codeword,
                hard: hard,
                reliability: reliability
            )
            let increase = distance - startingDistance

            guard increase <= configuration.maximumWeightedDistanceIncrease else {
                return
            }

            let codewordBuffer = FT8BitBuffer(codeword)
            guard FT8LDPCMatrix.isValid(codewordBuffer),
                  FT8CRC.validate(information) else {
                return
            }

            let ldpc = FT8LDPCResult(
                codeword: codewordBuffer,
                informationBits: information,
                iterations: 0,
                parityPassed: true,
                crcPassed: true,
                syndromeWeight: 0
            )

            results.append(
                Candidate(
                    ldpc: ldpc,
                    flippedPayloadBitIndices: flipped,
                    codewordBitChanges: changes,
                    weightedDistance: distance,
                    weightedDistanceIncrease: increase
                )
            )
        }

        consider([])

        if configuration.maximumFlipOrder >= 1 {
            for first in searchPositions {
                guard tested < configuration.maximumHypotheses else { break }
                consider([first])
            }
        }

        if configuration.maximumFlipOrder >= 2 {
            outer2: for firstOffset in 0..<searchPositions.count {
                guard firstOffset + 1 < searchPositions.count else { break }
                for secondOffset in (firstOffset + 1)..<searchPositions.count {
                    if tested >= configuration.maximumHypotheses {
                        break outer2
                    }
                    consider([
                        searchPositions[firstOffset],
                        searchPositions[secondOffset],
                    ])
                }
            }
        }

        if configuration.maximumFlipOrder >= 3 {
            outer3: for firstOffset in 0..<searchPositions.count {
                guard firstOffset + 2 < searchPositions.count else { break }
                for secondOffset in (firstOffset + 1)..<searchPositions.count {
                    guard secondOffset + 1 < searchPositions.count else { break }
                    for thirdOffset in (secondOffset + 1)..<searchPositions.count {
                        if tested >= configuration.maximumHypotheses {
                            break outer3
                        }
                        consider([
                            searchPositions[firstOffset],
                            searchPositions[secondOffset],
                            searchPositions[thirdOffset],
                        ])
                    }
                }
            }
        }

        return Array(
            results
                .sorted {
                    if $0.weightedDistance != $1.weightedDistance {
                        return $0.weightedDistance < $1.weightedDistance
                    }
                    if $0.flippedPayloadBitIndices.count != $1.flippedPayloadBitIndices.count {
                        return $0.flippedPayloadBitIndices.count
                            < $1.flippedPayloadBitIndices.count
                    }
                    return $0.codewordBitChanges < $1.codewordBitChanges
                }
                .prefix(configuration.maximumResults)
        )
    }

    private func encodeSystematicInformation(
        _ information: [UInt8]
    ) -> [UInt8] {
        precondition(information.count == FT8LDPCMatrix.informationBitCount)

        var codeword = information
        codeword.reserveCapacity(FT8LDPCMatrix.codewordBitCount)

        for variables in FT8LDPCMatrix.checkToVariables {
            var parity: UInt8 = 0

            for variable in variables
            where variable < FT8LDPCMatrix.informationBitCount {
                parity ^= information[variable]
            }

            codeword.append(parity)
        }

        precondition(codeword.count == FT8LDPCMatrix.codewordBitCount)
        return codeword
    }

    private func weightedDistance(
        _ codeword: [UInt8],
        hard: [UInt8],
        reliability: [Float]
    ) -> Float {
        var result: Float = 0
        for index in codeword.indices where codeword[index] != hard[index] {
            result += reliability[index]
        }
        return result
    }
}
