import Foundation
import FT8Protocol

/// Bounded ordered-statistics decoder for the FT8 (174,91) LDPC code.
///
/// This checkpoint moves the decoder closer to the WSJT-X hybrid BP/OSD
/// structure by separating OSD candidate generation from final FT8 CRC
/// acceptance, supporting Keff = 77...91, and adding a bounded order-2 search.
public struct FT8OrderedStatisticsDecoder: Sendable {
    public struct Configuration: Equatable, Sendable {
        public var order: Int
        public var pivotSearchExtraColumns: Int
        public var maximumOrderOnePatterns: Int
        public var maximumOrderTwoPatterns: Int
        public var effectiveDimension: Int
        public var maximumRetainedCandidates: Int

        public init(
            order: Int = 2,
            pivotSearchExtraColumns: Int = 20,
            maximumOrderOnePatterns: Int = 91,
            maximumOrderTwoPatterns: Int = 384,
            effectiveDimension: Int = 77,
            maximumRetainedCandidates: Int = 64
        ) {
            self.order = min(2, max(0, order))
            self.pivotSearchExtraColumns = max(0, pivotSearchExtraColumns)
            self.maximumOrderOnePatterns = max(0, maximumOrderOnePatterns)
            self.maximumOrderTwoPatterns = max(0, maximumOrderTwoPatterns)
            self.effectiveDimension = min(91, max(77, effectiveDimension))
            self.maximumRetainedCandidates = max(1, maximumRetainedCandidates)
        }

        /// Number of CRC bits participating in the Keff screen.
        public var effectiveCRCBitCount: Int {
            effectiveDimension - 77
        }
    }

    private struct Candidate {
        let originalOrder: [UInt8]
        let distance: Float
        let crcPrefixMatched: Bool
        let fullCRCPassed: Bool
    }

    public var configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// Decode using bounded OSD. Keff is used while generating/ranking
    /// candidates; a result is returned only after the full 14-bit FT8 CRC
    /// succeeds. This prevents partial CRC checks from becoming message
    /// acceptance checks.
    public func decode(
        logLikelihoodRatios llr: [Float]
    ) throws -> FT8LDPCResult? {
        let candidates = try generateCandidates(logLikelihoodRatios: llr)

        guard let accepted = candidates
            .filter(\.fullCRCPassed)
            .min(by: { $0.distance < $1.distance })
        else {
            return nil
        }

        let codeword = FT8BitBuffer(accepted.originalOrder)
        let information = FT8BitBuffer(Array(accepted.originalOrder.prefix(91)))

        return FT8LDPCResult(
            codeword: codeword,
            informationBits: information,
            iterations: 0,
            parityPassed: true,
            crcPassed: true,
            syndromeWeight: 0
        )
    }

    private func generateCandidates(
        logLikelihoodRatios llr: [Float]
    ) throws -> [Candidate] {
        guard llr.count == FT8LDPCMatrix.codewordBitCount else {
            throw FT8LDPCError.invalidLLRCount(llr.count)
        }

        let k = FT8LDPCMatrix.informationBitCount
        let n = FT8LDPCMatrix.codewordBitCount

        var generator = Self.generatorBasis()
        precondition(generator.count == k)

        let reliabilityOrder = llr.indices.sorted {
            abs(llr[$0]) > abs(llr[$1])
        }

        var indices = reliabilityOrder
        generator = generator.map { row in
            indices.map { row[$0] }
        }

        // Construct a most-reliable basis. As in the earlier checkpoint, the
        // pivot search is deliberately bounded rather than performing an
        // unconstrained column search.
        for diagonal in 0..<k {
            let searchEnd = min(
                n - 1,
                diagonal + configuration.pivotSearchExtraColumns
            )

            guard let pivotColumn = (diagonal...searchEnd).first(
                where: { generator[diagonal][$0] == 1 }
            ) else {
                continue
            }

            if pivotColumn != diagonal {
                for row in 0..<k {
                    generator[row].swapAt(diagonal, pivotColumn)
                }
                indices.swapAt(diagonal, pivotColumn)
            }

            for row in 0..<k where row != diagonal {
                if generator[row][diagonal] == 1 {
                    for column in 0..<n {
                        generator[row][column] ^= generator[diagonal][column]
                    }
                }
            }
        }

        let reorderedHard = indices.map { llr[$0] < 0 ? UInt8(1) : UInt8(0) }
        let reorderedReliability = indices.map { abs(llr[$0]) }
        let baseMessage = Array(reorderedHard.prefix(k))

        // Least-reliable MRB positions are the bounded OSD search set.
        let leastReliableMRB = Array(
            (0..<k).sorted {
                reorderedReliability[$0] < reorderedReliability[$1]
            }
        )

        var retained: [Candidate] = []
        retained.reserveCapacity(configuration.maximumRetainedCandidates)

        func consider(_ message: [UInt8]) {
            let reorderedCodeword = encode(message, using: generator)
            let distance = weightedDistance(
                reorderedCodeword,
                reorderedHard,
                reorderedReliability
            )

            var originalOrder = Array(repeating: UInt8(0), count: n)
            for reorderedIndex in 0..<n {
                originalOrder[indices[reorderedIndex]] = reorderedCodeword[reorderedIndex]
            }

            // OSD must only rank actual LDPC codewords. Also reject the
            // all-zero attractor before CRC handling.
            let codeword = FT8BitBuffer(originalOrder)
            guard codeword.bits.contains(1), FT8LDPCMatrix.isValid(codeword) else {
                return
            }

            let information = FT8BitBuffer(Array(originalOrder.prefix(k)))
            let prefixMatched = Self.crcPrefixMatches(
                informationBits: information,
                effectiveDimension: configuration.effectiveDimension
            )

            // Keff=77 intentionally imposes no CRC-bit screen. At larger Keff
            // retain only candidates agreeing with the corresponding CRC prefix.
            guard prefixMatched else { return }

            let candidate = Candidate(
                originalOrder: originalOrder,
                distance: distance,
                crcPrefixMatched: true,
                fullCRCPassed: FT8CRC.validate(information)
            )

            retained.append(candidate)
            retained.sort { lhs, rhs in
                if lhs.fullCRCPassed != rhs.fullCRCPassed {
                    return lhs.fullCRCPassed && !rhs.fullCRCPassed
                }
                return lhs.distance < rhs.distance
            }
            if retained.count > configuration.maximumRetainedCandidates {
                retained.removeLast(retained.count - configuration.maximumRetainedCandidates)
            }
        }

        // Order 0.
        consider(baseMessage)

        // Order 1.
        if configuration.order >= 1 {
            for bit in leastReliableMRB.prefix(configuration.maximumOrderOnePatterns) {
                var message = baseMessage
                message[bit] ^= 1
                consider(message)
            }
        }

        // Order 2. Use the least-reliable subset and a hard global bound so a
        // real-time decode cannot explode combinatorially.
        if configuration.order >= 2 && configuration.maximumOrderTwoPatterns > 0 {
            let poolCount = min(
                leastReliableMRB.count,
                max(2, configuration.maximumOrderOnePatterns)
            )
            let pool = Array(leastReliableMRB.prefix(poolCount))
            var tested = 0

            outer: for first in 0..<pool.count {
                guard first + 1 < pool.count else { break }
                for second in (first + 1)..<pool.count {
                    var message = baseMessage
                    message[pool[first]] ^= 1
                    message[pool[second]] ^= 1
                    consider(message)
                    tested += 1
                    if tested >= configuration.maximumOrderTwoPatterns {
                        break outer
                    }
                }
            }
        }

        return retained
    }

    /// WSJT-X Keff semantics for the CRC portion of the 91 information bits.
    /// Keff=77 checks no CRC bits; Keff=91 checks all 14 CRC bits.
    public static func crcPrefixMatches(
        informationBits: FT8BitBuffer,
        effectiveDimension: Int
    ) -> Bool {
        guard informationBits.count == 91 else { return false }

        let keff = min(91, max(77, effectiveDimension))
        let crcBitsToCheck = keff - 77
        guard crcBitsToCheck > 0 else { return true }

        let payload = FT8BitBuffer(Array(informationBits.bits.prefix(77)))
        guard let expected = try? FT8CRC.append(to: payload) else { return false }

        for offset in 0..<crcBitsToCheck {
            let index = 77 + offset
            if informationBits[index] != expected[index] {
                return false
            }
        }
        return true
    }

    private func encode(
        _ message: [UInt8],
        using generator: [[UInt8]]
    ) -> [UInt8] {
        let n = FT8LDPCMatrix.codewordBitCount
        var codeword = Array(repeating: UInt8(0), count: n)

        for row in message.indices where message[row] == 1 {
            for column in 0..<n {
                codeword[column] ^= generator[row][column]
            }
        }

        return codeword
    }

    private func weightedDistance(
        _ codeword: [UInt8],
        _ hard: [UInt8],
        _ reliability: [Float]
    ) -> Float {
        var value: Float = 0
        for index in codeword.indices where codeword[index] != hard[index] {
            value += reliability[index]
        }
        return value
    }

    /// Construct a 91-row basis for null(H) over GF(2).
    private static func generatorBasis() -> [[UInt8]] {
        let rows = FT8LDPCMatrix.checkCount
        let columns = FT8LDPCMatrix.codewordBitCount

        var h = Array(
            repeating: Array(repeating: UInt8(0), count: columns),
            count: rows
        )

        for (row, variables) in FT8LDPCMatrix.checkToVariables.enumerated() {
            for column in variables {
                h[row][column] = 1
            }
        }

        var pivotColumns: [Int] = []
        var pivotRow = 0

        for column in 0..<columns where pivotRow < rows {
            guard let row = (pivotRow..<rows).first(
                where: { h[$0][column] == 1 }
            ) else {
                continue
            }

            if row != pivotRow {
                h.swapAt(row, pivotRow)
            }

            for other in 0..<rows where other != pivotRow {
                if h[other][column] == 1 {
                    for c in column..<columns {
                        h[other][c] ^= h[pivotRow][c]
                    }
                }
            }

            pivotColumns.append(column)
            pivotRow += 1
        }

        let pivotSet = Set(pivotColumns)
        let freeColumns = (0..<columns).filter { !pivotSet.contains($0) }

        precondition(
            freeColumns.count == FT8LDPCMatrix.informationBitCount,
            "FT8 parity-check matrix must have dimension 91"
        )

        var basis: [[UInt8]] = []
        basis.reserveCapacity(freeColumns.count)

        for free in freeColumns {
            var vector = Array(repeating: UInt8(0), count: columns)
            vector[free] = 1

            for row in stride(from: pivotColumns.count - 1, through: 0, by: -1) {
                let pivot = pivotColumns[row]
                var sum: UInt8 = 0

                if pivot + 1 < columns {
                    for column in (pivot + 1)..<columns where h[row][column] == 1 {
                        sum ^= vector[column]
                    }
                }

                vector[pivot] = sum
            }

            basis.append(vector)
        }

        return basis
    }
}
