import Foundation
import FT8Protocol

/// Bounded ordered-statistics decoder for the FT8 (174,91) LDPC code.
///
/// This follows the structure of WSJT-X `osd174_91.f90`:
/// 1. rank channel bits by reliability,
/// 2. construct a most-reliable basis (MRB),
/// 3. form the order-0 codeword from MRB hard decisions,
/// 4. optionally test bounded order-1 MRB error patterns,
/// 5. choose the minimum reliability-weighted-distance codeword,
/// 6. accept it only when the FT8 CRC is valid.
///
/// The implementation derives a generator basis from FT8Kit's parity-check
/// matrix so that the WSJT-X algorithm can be expressed without duplicating
/// the generated FT8 matrix constants.
public struct FT8OrderedStatisticsDecoder: Sendable {
    public struct Configuration: Equatable, Sendable {
        public var order: Int
        public var pivotSearchExtraColumns: Int
        public var maximumOrderOnePatterns: Int

        public init(
            order: Int = 1,
            pivotSearchExtraColumns: Int = 20,
            maximumOrderOnePatterns: Int = 91
        ) {
            self.order = order
            self.pivotSearchExtraColumns = pivotSearchExtraColumns
            self.maximumOrderOnePatterns = maximumOrderOnePatterns
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public func decode(
        logLikelihoodRatios llr: [Float]
    ) throws -> FT8LDPCResult? {
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

        // WSJT-X searches a small distance beyond the diagonal for a pivot.
        // Keep the same bounded MRB construction.
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

        var message = Array(reorderedHard.prefix(k))
        var best = encode(message, using: generator)
        var bestDistance = weightedDistance(
            best,
            reorderedHard,
            reorderedReliability
        )

        if configuration.order >= 1 {
            // Order-1 is deliberately bounded. WSJT-X also treats OSD depth
            // as a bounded search rather than an unconstrained bit-flip pass.
            let orderOneIndices = (0..<k)
                .sorted {
                    reorderedReliability[$0] < reorderedReliability[$1]
                }
                .prefix(configuration.maximumOrderOnePatterns)

            for bit in orderOneIndices {
                message[bit] ^= 1
                let candidate = encode(message, using: generator)
                let distance = weightedDistance(
                    candidate,
                    reorderedHard,
                    reorderedReliability
                )

                if distance < bestDistance {
                    best = candidate
                    bestDistance = distance
                }

                message[bit] ^= 1
            }
        }

        var originalOrder = Array(repeating: UInt8(0), count: n)
        for reorderedIndex in 0..<n {
            originalOrder[indices[reorderedIndex]] = best[reorderedIndex]
        }

        let codeword = FT8BitBuffer(originalOrder)

        // The all-zero word belongs to the LDPC code and can pass the FT8 CRC,
        // but it represents no FT8 message. Do not let OSD terminate on this
        // trivial attractor; continue with other reliability snapshots instead.
        guard codeword.bits.contains(1) else {
            return nil
        }

        guard FT8LDPCMatrix.isValid(codeword) else {
            return nil
        }

        let information = FT8BitBuffer(
            Array(originalOrder.prefix(k))
        )

        guard FT8CRC.validate(information) else {
            return nil
        }

        return FT8LDPCResult(
            codeword: codeword,
            informationBits: information,
            iterations: 0,
            parityPassed: true,
            crcPassed: true,
            syndromeWeight: 0
        )
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
