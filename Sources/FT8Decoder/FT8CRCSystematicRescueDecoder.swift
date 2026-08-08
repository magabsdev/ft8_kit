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
        public var beamWidth: Int

        public init(
            leastReliablePayloadBits: Int = 32,
            maximumFlipOrder: Int = 5,
            maximumHypotheses: Int = 4096,
            maximumResults: Int = 12,
            maximumCodewordBitChanges: Int = 80,
            maximumWeightedDistanceIncrease: Float = 40,
            beamWidth: Int = 96
        ) {
            self.leastReliablePayloadBits = min(77, max(1, leastReliablePayloadBits))
            self.maximumFlipOrder = min(5, max(0, maximumFlipOrder))
            self.maximumHypotheses = max(1, maximumHypotheses)
            self.maximumResults = max(1, maximumResults)
            self.maximumCodewordBitChanges = max(0, maximumCodewordBitChanges)
            self.maximumWeightedDistanceIncrease = max(0, maximumWeightedDistanceIncrease)
            self.beamWidth = max(1, beamWidth)
        }
    }

    public struct Candidate: Equatable, Sendable {
        public let ldpc: FT8LDPCResult
        public let flippedPayloadBitIndices: [Int]
        public let codewordBitChanges: Int
        public let weightedDistance: Float
        public let weightedDistanceIncrease: Float
    }

    private struct SearchState: Sendable {
        let flippedPayloadBitIndices: [Int]
        let lastSearchOffset: Int
        let weightedDistance: Float
        let weightedDistanceIncrease: Float
        let codewordBitChanges: Int
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

        // Search the least-reliable payload decisions first, but use a much
        // broader bounded pool than the previous fixed 14-bit / order-3 scan.
        // Every trial is projected back onto the complete CRC(91,77)+LDPC(174,91)
        // code before it is scored against the channel LLRs.
        let searchPositions = Array(
            (0..<77)
                .sorted {
                    if reliability[$0] != reliability[$1] {
                        return reliability[$0] < reliability[$1]
                    }
                    return $0 < $1
                }
                .prefix(configuration.leastReliablePayloadBits)
        )

        var tested = 0
        var retained: [Candidate] = []
        var seenFlipSets = Set<String>()

        func key(for flipped: [Int]) -> String {
            flipped.map(String.init).joined(separator: ",")
        }

        func evaluate(_ flipped: [Int]) -> Candidate? {
            guard tested < configuration.maximumHypotheses else { return nil }

            let flipKey = key(for: flipped)
            guard seenFlipSets.insert(flipKey).inserted else { return nil }
            tested += 1

            var payloadBits = basePayload
            for index in flipped {
                payloadBits[index] ^= 1
            }

            let payload = FT8BitBuffer(payloadBits)
            guard let information = try? FT8CRC.append(to: payload) else {
                return nil
            }

            let codeword = encodeSystematicInformation(information.bits)
            guard codeword.contains(1) else { return nil }

            let changes = zip(codeword, startingCodeword).reduce(into: 0) { count, pair in
                if pair.0 != pair.1 {
                    count += 1
                }
            }

            guard changes <= configuration.maximumCodewordBitChanges else {
                return nil
            }

            let distance = weightedDistance(
                codeword,
                hard: hard,
                reliability: reliability
            )
            let increase = distance - startingDistance

            guard increase <= configuration.maximumWeightedDistanceIncrease else {
                return nil
            }

            let codewordBuffer = FT8BitBuffer(codeword)
            guard FT8LDPCMatrix.isValid(codewordBuffer),
                  FT8CRC.validate(information) else {
                return nil
            }

            let ldpc = FT8LDPCResult(
                codeword: codewordBuffer,
                informationBits: information,
                iterations: 0,
                parityPassed: true,
                crcPassed: true,
                syndromeWeight: 0
            )

            return Candidate(
                ldpc: ldpc,
                flippedPayloadBitIndices: flipped,
                codewordBitChanges: changes,
                weightedDistance: distance,
                weightedDistanceIncrease: increase
            )
        }

        func record(_ candidate: Candidate?) {
            guard let candidate else { return }
            retained.append(candidate)

            // Keep the in-memory list bounded throughout the search.
            if retained.count > configuration.maximumResults * 8 {
                retained = Array(
                    retained
                        .sorted(by: candidateIsBetter)
                        .prefix(configuration.maximumResults * 4)
                )
            }
        }

        // Order zero is important: the payload may already be correct while BP
        // has selected the wrong CRC/parity completion.
        record(evaluate([]))

        guard configuration.maximumFlipOrder > 0,
              tested < configuration.maximumHypotheses else {
            return Array(
                retained
                    .sorted(by: candidateIsBetter)
                    .prefix(configuration.maximumResults)
            )
        }

        // Order one is evaluated exhaustively over the bounded payload pool.
        var beam: [SearchState] = []
        for (offset, payloadIndex) in searchPositions.enumerated() {
            guard tested < configuration.maximumHypotheses else { break }

            if let candidate = evaluate([payloadIndex]) {
                record(candidate)
                beam.append(
                    SearchState(
                        flippedPayloadBitIndices: [payloadIndex],
                        lastSearchOffset: offset,
                        weightedDistance: candidate.weightedDistance,
                        weightedDistanceIncrease: candidate.weightedDistanceIncrease,
                        codewordBitChanges: candidate.codewordBitChanges
                    )
                )
            }
        }

        beam = Array(
            beam
                .sorted(by: stateIsBetter)
                .prefix(configuration.beamWidth)
        )

        // For orders 2...N, only expand the most channel-plausible states.
        // This is a bounded best-first/beam approximation to a much wider OSD
        // search, but it stays entirely inside the valid FT8 cascaded code.
        if configuration.maximumFlipOrder >= 2 {
            for order in 2...configuration.maximumFlipOrder {
                guard !beam.isEmpty,
                      tested < configuration.maximumHypotheses else {
                    break
                }

                var nextBeam: [SearchState] = []

                for state in beam {
                    let nextOffset = state.lastSearchOffset + 1
                    guard nextOffset < searchPositions.count else { continue }

                    for offset in nextOffset..<searchPositions.count {
                        if tested >= configuration.maximumHypotheses {
                            break
                        }

                        var flipped = state.flippedPayloadBitIndices
                        flipped.append(searchPositions[offset])
                        flipped.sort()

                        guard flipped.count == order else { continue }

                        if let candidate = evaluate(flipped) {
                            record(candidate)
                            nextBeam.append(
                                SearchState(
                                    flippedPayloadBitIndices: flipped,
                                    lastSearchOffset: offset,
                                    weightedDistance: candidate.weightedDistance,
                                    weightedDistanceIncrease: candidate.weightedDistanceIncrease,
                                    codewordBitChanges: candidate.codewordBitChanges
                                )
                            )
                        }
                    }

                    if tested >= configuration.maximumHypotheses {
                        break
                    }
                }

                beam = Array(
                    nextBeam
                        .sorted(by: stateIsBetter)
                        .prefix(configuration.beamWidth)
                )
            }
        }

        return Array(
            retained
                .sorted(by: candidateIsBetter)
                .prefix(configuration.maximumResults)
        )
    }

    private func candidateIsBetter(
        _ lhs: Candidate,
        _ rhs: Candidate
    ) -> Bool {
        if lhs.weightedDistance != rhs.weightedDistance {
            return lhs.weightedDistance < rhs.weightedDistance
        }
        if lhs.weightedDistanceIncrease != rhs.weightedDistanceIncrease {
            return lhs.weightedDistanceIncrease < rhs.weightedDistanceIncrease
        }
        if lhs.flippedPayloadBitIndices.count != rhs.flippedPayloadBitIndices.count {
            return lhs.flippedPayloadBitIndices.count
                < rhs.flippedPayloadBitIndices.count
        }
        return lhs.codewordBitChanges < rhs.codewordBitChanges
    }

    private func stateIsBetter(
        _ lhs: SearchState,
        _ rhs: SearchState
    ) -> Bool {
        if lhs.weightedDistance != rhs.weightedDistance {
            return lhs.weightedDistance < rhs.weightedDistance
        }
        if lhs.weightedDistanceIncrease != rhs.weightedDistanceIncrease {
            return lhs.weightedDistanceIncrease < rhs.weightedDistanceIncrease
        }
        if lhs.flippedPayloadBitIndices.count != rhs.flippedPayloadBitIndices.count {
            return lhs.flippedPayloadBitIndices.count
                < rhs.flippedPayloadBitIndices.count
        }
        return lhs.codewordBitChanges < rhs.codewordBitChanges
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
