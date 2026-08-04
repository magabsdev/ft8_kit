import Foundation

public struct FT8CandidateClusterer: Sendable {
    public var timeRadius: Double
    public var frequencyRadius: Float
    public var maximumCandidates: Int

    public init(
        timeRadius: Double,
        frequencyRadius: Float,
        maximumCandidates: Int
    ) {
        self.timeRadius = timeRadius
        self.frequencyRadius = frequencyRadius
        self.maximumCandidates = maximumCandidates
    }

    public func cluster(_ candidates: [FT8Candidate]) -> [FT8Candidate] {
        let ordered = candidates.sorted(by: isPreferred)
        var accepted: [FT8Candidate] = []
        accepted.reserveCapacity(min(maximumCandidates, ordered.count))

        for candidate in ordered {
            let duplicate = accepted.contains {
                abs($0.startTime - candidate.startTime) <= timeRadius &&
                abs($0.frequency - candidate.frequency) <= frequencyRadius
            }

            guard !duplicate else { continue }
            accepted.append(candidate)

            if accepted.count >= maximumCandidates {
                break
            }
        }

        return accepted.sorted {
            if $0.startTime == $1.startTime {
                return $0.frequency < $1.frequency
            }
            return $0.startTime < $1.startTime
        }
    }

    private func isPreferred(
        _ lhs: FT8Candidate,
        _ rhs: FT8Candidate
    ) -> Bool {
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }
        if lhs.syncScore != rhs.syncScore {
            return lhs.syncScore > rhs.syncScore
        }
        if lhs.snrDB != rhs.snrDB {
            return lhs.snrDB > rhs.snrDB
        }
        if abs(lhs.driftHzPerSecond) != abs(rhs.driftHzPerSecond) {
            return abs(lhs.driftHzPerSecond) < abs(rhs.driftHzPerSecond)
        }
        if lhs.startTime != rhs.startTime {
            return lhs.startTime < rhs.startTime
        }
        return lhs.frequency < rhs.frequency
    }
}
