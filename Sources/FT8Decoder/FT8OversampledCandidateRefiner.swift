import Foundation
import FT8DSP

public struct FT8OversampledCandidateRefinerConfiguration: Equatable, Sendable {
    public var timeRadiusFrames: Int
    public var frequencyRadiusBins: Int

    public init(timeRadiusFrames: Int = 2, frequencyRadiusBins: Int = 4) {
        self.timeRadiusFrames = timeRadiusFrames
        self.frequencyRadiusBins = frequencyRadiusBins
    }
}

public struct FT8OversampledCandidateRefiner: Sendable {
    public var configuration: FT8OversampledCandidateRefinerConfiguration

    public init(configuration: FT8OversampledCandidateRefinerConfiguration = .init()) {
        self.configuration = configuration
    }

    public func refine(_ candidate: FT8Candidate, in waterfall: FT8OversampledWaterfall) -> FT8Candidate {
        guard waterfall.frameCount > 0,
              waterfall.baseBinCount > 0,
              let centre = waterfall.nearestFrequencyLocation(to: candidate.frequency) else { return candidate }

        let centreFrame = waterfall.nearestFrame(to: candidate.startTime)
        var bestFrame = centreFrame
        var bestBaseBin = centre.baseBin
        var bestSubdivision = centre.frequencySubdivision
        var bestMagnitude: Float = -.greatestFiniteMagnitude

        let minimumFrame = max(0, centreFrame - configuration.timeRadiusFrames)
        let maximumFrame = min(waterfall.frameCount - 1, centreFrame + configuration.timeRadiusFrames)
        let centreBin = centre.baseBin * waterfall.frequencyOversampling + centre.frequencySubdivision
        let minimumBin = max(0, centreBin - configuration.frequencyRadiusBins)
        let maximumBin = min(waterfall.baseBinCount * waterfall.frequencyOversampling - 1, centreBin + configuration.frequencyRadiusBins)

        for frame in minimumFrame...maximumFrame {
            for bin in minimumBin...maximumBin {
                let baseBin = bin / waterfall.frequencyOversampling
                let subdivision = bin % waterfall.frequencyOversampling
                guard let magnitude = waterfall.magnitude(frame: frame, frequencySubdivision: subdivision, baseBin: baseBin) else { continue }
                if magnitude > bestMagnitude {
                    bestMagnitude = magnitude
                    bestFrame = frame
                    bestBaseBin = baseBin
                    bestSubdivision = subdivision
                }
            }
        }

        let refinedTime = Double(bestFrame) * waterfall.framePeriod
        let refinedFrequency = waterfall.frequency(baseBin: bestBaseBin, frequencySubdivision: bestSubdivision)
        return FT8Candidate(
            startTime: refinedTime,
            frequency: refinedFrequency,
            driftHzPerSecond: candidate.driftHzPerSecond,
            symbolOffset: refinedTime / 0.160,
            syncScore: candidate.syncScore,
            snrDB: candidate.snrDB,
            confidence: candidate.confidence
        )
    }
}
