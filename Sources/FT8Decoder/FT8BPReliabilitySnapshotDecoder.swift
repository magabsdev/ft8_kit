import Foundation

/// Produces the accumulated belief-propagation reliability vectors used by
/// WSJT-X before ordered-statistics decoding.
///
/// This mirrors the `zsum` / `zsave` path in WSJT-X `decode174_91.f90`:
///
///     zsum = zsum + zn
///     if (iter > 0 .and. iter <= maxosd) zsave(:,iter) = zsum
///
/// FT8Kit uses the opposite LLR sign convention to the original Fortran
/// implementation (negative means bit 1), but accumulation is otherwise the
/// same. The returned vectors therefore remain in FT8Kit's sign convention and
/// can be passed directly to `FT8OrderedStatisticsDecoder`.
public struct FT8BPReliabilitySnapshotDecoder: Sendable {
    public struct Configuration: Equatable, Sendable {
        public var maximumIterations: Int
        public var maximumSnapshots: Int
        public var messageLimit: Float

        public init(
            maximumIterations: Int = 30,
            maximumSnapshots: Int = 3,
            messageLimit: Float = 32
        ) {
            self.maximumIterations = maximumIterations
            self.maximumSnapshots = min(max(0, maximumSnapshots), 3)
            self.messageLimit = messageLimit
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public func snapshots(
        logLikelihoodRatios channel: [Float]
    ) throws -> [[Float]] {
        guard channel.count == FT8LDPCMatrix.codewordBitCount else {
            throw FT8LDPCError.invalidLLRCount(channel.count)
        }

        guard configuration.maximumIterations > 0,
              configuration.maximumSnapshots >= 0,
              configuration.messageLimit > 0 else {
            throw FT8LDPCError.invalidConfiguration
        }

        guard configuration.maximumSnapshots > 0 else {
            return []
        }

        let normalizedChannel = normalize(channel)
        let checks = FT8LDPCMatrix.checkToVariables

        // `toc` in decode174_91.f90: variable-to-check messages.
        var variableToCheck = checks.map { variables in
            variables.map { normalizedChannel[$0] }
        }

        // `tov` in decode174_91.f90: check-to-variable messages.
        var checkToVariable = checks.map {
            Array(repeating: Float.zero, count: $0.count)
        }

        var accumulated = Array(
            repeating: Float.zero,
            count: FT8LDPCMatrix.codewordBitCount
        )
        var saved: [[Float]] = []
        saved.reserveCapacity(configuration.maximumSnapshots)

        // WSJT-X iterates from 0 and saves zsum after iterations 1...maxosd.
        // The iteration-0 posterior is therefore included in every snapshot.
        for iteration in 0...configuration.maximumIterations {
            var posterior = normalizedChannel

            for checkIndex in checks.indices {
                for edge in checks[checkIndex].indices {
                    posterior[checks[checkIndex][edge]] +=
                        checkToVariable[checkIndex][edge]
                }
            }

            for index in posterior.indices {
                accumulated[index] += posterior[index]
            }

            if iteration > 0,
               saved.count < configuration.maximumSnapshots {
                saved.append(accumulated)

                if saved.count == configuration.maximumSnapshots {
                    break
                }
            }

            // Send messages from bits to checks: posterior minus the message
            // received along the edge, matching WSJT-X's `toc=zn-tov` step.
            for checkIndex in checks.indices {
                for edge in checks[checkIndex].indices {
                    let variable = checks[checkIndex][edge]
                    variableToCheck[checkIndex][edge] = clip(
                        posterior[variable]
                            - checkToVariable[checkIndex][edge],
                        limit: configuration.messageLimit
                    )
                }
            }

            // Sum-product check-node update. This is algebraically the same BP
            // stage used by decode174_91.f90, expressed in FT8Kit's LLR sign
            // convention.
            for checkIndex in checks.indices {
                let incoming = variableToCheck[checkIndex]
                let updated = sumProductMessages(incoming)

                for edge in updated.indices {
                    checkToVariable[checkIndex][edge] = clip(
                        updated[edge],
                        limit: configuration.messageLimit
                    )
                }
            }
        }

        return saved
    }

    private func normalize(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return values }

        var sum: Float = 0
        var sumOfSquares: Float = 0

        for value in values {
            guard value.isFinite else { return values }
            sum += value
            sumOfSquares += value * value
        }

        let count = Float(values.count)
        let mean = sum / count
        let variance = (sumOfSquares / count) - (mean * mean)

        guard variance.isFinite,
              variance > Float.leastNonzeroMagnitude else {
            return values
        }

        let factor = sqrtf(24 / variance)
        guard factor.isFinite else { return values }
        return values.map { $0 * factor }
    }

    private func sumProductMessages(_ incoming: [Float]) -> [Float] {
        guard incoming.count > 1 else { return [0] }

        return incoming.indices.map { excluded in
            var product: Float = 1

            for index in incoming.indices where index != excluded {
                let argument = min(max(incoming[index] / 2, -12), 12)
                product *= tanhf(argument)
            }

            product = min(max(product, -0.999_999), 0.999_999)
            return 2 * atanhf(product)
        }
    }

    private func clip(_ value: Float, limit: Float) -> Float {
        min(max(value, -limit), limit)
    }
}
