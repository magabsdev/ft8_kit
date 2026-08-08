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
        let payloadWeightedDistance: Float
        let payloadWeightedDistanceIncrease: Float
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
        let payloadHard = Array(hard.prefix(77))
        let payloadReliability = Array(reliability.prefix(77))
        let startingPayloadDistance = weightedDistance(
            basePayload,
            hard: payloadHard,
            reliability: payloadReliability
        )

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

        func projected(_ flipped: [Int]) -> (
            information: FT8BitBuffer,
            codeword: [UInt8],
            codewordBitChanges: Int,
            weightedDistance: Float,
            weightedDistanceIncrease: Float,
            payloadWeightedDistance: Float,
            payloadWeightedDistanceIncrease: Float
        )? {
            var payloadBits = basePayload
            for index in flipped {
                payloadBits[index] ^= 1
            }

            let payloadDistance = weightedDistance(
                payloadBits,
                hard: payloadHard,
                reliability: payloadReliability
            )

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

            let distance = weightedDistance(
                codeword,
                hard: hard,
                reliability: reliability
            )

            return (
                information,
                codeword,
                changes,
                distance,
                distance - startingDistance,
                payloadDistance,
                payloadDistance - startingPayloadDistance
            )
        }

        func evaluate(_ flipped: [Int]) -> Candidate? {
            guard tested < configuration.maximumHypotheses else { return nil }

            let flipKey = key(for: flipped)
            guard seenFlipSets.insert(flipKey).inserted else { return nil }
            tested += 1

            guard let trial = projected(flipped) else { return nil }

            guard trial.codewordBitChanges <= configuration.maximumCodewordBitChanges,
                  trial.weightedDistanceIncrease <= configuration.maximumWeightedDistanceIncrease else {
                return nil
            }

            let codewordBuffer = FT8BitBuffer(trial.codeword)
            guard FT8LDPCMatrix.isValid(codewordBuffer),
                  FT8CRC.validate(trial.information) else {
                return nil
            }

            let ldpc = FT8LDPCResult(
                codeword: codewordBuffer,
                informationBits: trial.information,
                iterations: 0,
                parityPassed: true,
                crcPassed: true,
                syndromeWeight: 0
            )

            return Candidate(
                ldpc: ldpc,
                flippedPayloadBitIndices: flipped,
                codewordBitChanges: trial.codewordBitChanges,
                weightedDistance: trial.weightedDistance,
                weightedDistanceIncrease: trial.weightedDistanceIncrease
            )
        }

        func makeState(
            flipped: [Int],
            lastSearchOffset: Int
        ) -> SearchState? {
            guard let trial = projected(flipped) else { return nil }

            return SearchState(
                flippedPayloadBitIndices: flipped,
                lastSearchOffset: lastSearchOffset,
                payloadWeightedDistance: trial.payloadWeightedDistance,
                payloadWeightedDistanceIncrease: trial.payloadWeightedDistanceIncrease,
                weightedDistance: trial.weightedDistance,
                weightedDistanceIncrease: trial.weightedDistanceIncrease,
                codewordBitChanges: trial.codewordBitChanges
            )
        }

        func record(_ candidate: Candidate?) {
            guard let candidate else { return }
            retained.append(candidate)

            if retained.count > configuration.maximumResults * 8 {
                retained = Array(
                    retained
                        .sorted(by: candidateIsBetter)
                        .prefix(configuration.maximumResults * 4)
                )
            }
        }

        record(evaluate([]))

        guard configuration.maximumFlipOrder > 0,
              tested < configuration.maximumHypotheses else {
            return Array(
                retained
                    .sorted(by: candidateIsBetter)
                    .prefix(configuration.maximumResults)
            )
        }

        var beam: [SearchState] = []
        for (offset, payloadIndex) in searchPositions.enumerated() {
            guard tested < configuration.maximumHypotheses else { break }

            let flipped = [payloadIndex]
            record(evaluate(flipped))

            if let state = makeState(
                flipped: flipped,
                lastSearchOffset: offset
            ) {
                beam.append(state)
            }
        }

        beam = Array(
            beam
                .sorted(by: stateIsBetter)
                .prefix(configuration.beamWidth)
        )

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

                        record(evaluate(flipped))

                        if let next = makeState(
                            flipped: flipped,
                            lastSearchOffset: offset
                        ) {
                            nextBeam.append(next)
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
        if lhs.payloadWeightedDistance != rhs.payloadWeightedDistance {
            return lhs.payloadWeightedDistance < rhs.payloadWeightedDistance
        }
        if lhs.payloadWeightedDistanceIncrease != rhs.payloadWeightedDistanceIncrease {
            return lhs.payloadWeightedDistanceIncrease < rhs.payloadWeightedDistanceIncrease
        }
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
