import Foundation

public struct FT8CandidateQuality: Equatable, Sendable {
    public let candidate: FT8Candidate
    public let relativeConfidence: Float
    public let peakIsolation: Float
    public let quality: Float

    public init(
        candidate: FT8Candidate,
        relativeConfidence: Float,
        peakIsolation: Float,
        quality: Float
    ) {
        self.candidate = candidate
        self.relativeConfidence = relativeConfidence
        self.peakIsolation = peakIsolation
        self.quality = quality
    }
}

public struct FT8CandidatePruner: Sendable {
    public var minimumRelativeConfidence: Float
    public var minimumPeakIsolation: Float
    public var timeRadius: Double
    public var frequencyRadius: Float
    public var minimumCandidates: Int
    public var maximumCandidates: Int

    public init(
        minimumRelativeConfidence: Float,
        minimumPeakIsolation: Float,
        timeRadius: Double,
        frequencyRadius: Float,
        minimumCandidates: Int,
        maximumCandidates: Int
    ) {
        self.minimumRelativeConfidence = minimumRelativeConfidence
        self.minimumPeakIsolation = minimumPeakIsolation
        self.timeRadius = timeRadius
        self.frequencyRadius = frequencyRadius
        self.minimumCandidates = minimumCandidates
        self.maximumCandidates = maximumCandidates
    }

    public func prune(_ candidates: [FT8Candidate]) -> [FT8Candidate] {
        guard !candidates.isEmpty else { return [] }

        let bestConfidence = max(
            candidates.map(\.confidence).max() ?? 0,
            Float.leastNonzeroMagnitude
        )

        let scored = candidates.map { candidate in
            score(
                candidate,
                among: candidates,
                bestConfidence: bestConfidence
            )
        }
        .sorted(by: isPreferred)

        let passing = scored.filter {
            $0.relativeConfidence >= minimumRelativeConfidence &&
            $0.peakIsolation >= minimumPeakIsolation
        }

        let targetCount = min(
            maximumCandidates,
            max(minimumCandidates, passing.count)
        )

        var selected = Array(passing.prefix(targetCount))

        if selected.count < minimumCandidates {
            let selectedCandidates = Set(
                selected.map(candidateKey)
            )

            for quality in scored
                where !selectedCandidates.contains(candidateKey(quality)) {
                selected.append(quality)

                if selected.count >= minimumCandidates {
                    break
                }
            }
        }

        return selected
            .prefix(maximumCandidates)
            .map(\.candidate)
    }

    public func score(
        _ candidate: FT8Candidate,
        among candidates: [FT8Candidate],
        bestConfidence: Float
    ) -> FT8CandidateQuality {
        let relativeConfidence = candidate.confidence / bestConfidence

        let strongestNeighbour = candidates
            .filter {
                candidateKey($0) != candidateKey(candidate) &&
                abs($0.startTime - candidate.startTime) <= timeRadius &&
                abs($0.frequency - candidate.frequency) <= frequencyRadius
            }
            .map(\.confidence)
            .max() ?? 0

        let peakIsolation = max(
            candidate.confidence - strongestNeighbour,
            0
        )

        let syncComponent = min(max(candidate.syncScore, 0), 1)
        let snrComponent = min(max((candidate.snrDB + 3) / 21, 0), 1)
        let isolationComponent = min(
            peakIsolation / max(candidate.confidence, 0.001),
            1
        )
        let driftPenalty = min(
            abs(candidate.driftHzPerSecond) / 10,
            0.15
        )

        let quality = min(
            max(
                0.42 * relativeConfidence +
                0.28 * syncComponent +
                0.20 * snrComponent +
                0.10 * isolationComponent -
                driftPenalty,
                0
            ),
            1
        )

        return FT8CandidateQuality(
            candidate: candidate,
            relativeConfidence: relativeConfidence,
            peakIsolation: peakIsolation,
            quality: quality
        )
    }

    private func isPreferred(
        _ lhs: FT8CandidateQuality,
        _ rhs: FT8CandidateQuality
    ) -> Bool {
        if lhs.quality != rhs.quality {
            return lhs.quality > rhs.quality
        }
        if lhs.candidate.confidence != rhs.candidate.confidence {
            return lhs.candidate.confidence > rhs.candidate.confidence
        }
        if lhs.candidate.syncScore != rhs.candidate.syncScore {
            return lhs.candidate.syncScore > rhs.candidate.syncScore
        }
        if lhs.candidate.snrDB != rhs.candidate.snrDB {
            return lhs.candidate.snrDB > rhs.candidate.snrDB
        }
        if lhs.candidate.startTime != rhs.candidate.startTime {
            return lhs.candidate.startTime < rhs.candidate.startTime
        }
        return lhs.candidate.frequency < rhs.candidate.frequency
    }

    private func candidateKey(_ quality: FT8CandidateQuality) -> String {
        candidateKey(quality.candidate)
    }

    private func candidateKey(_ candidate: FT8Candidate) -> String {
        "\(candidate.startTime)|\(candidate.frequency)|\(candidate.driftHzPerSecond)"
    }
}
