import Foundation

public struct SpectralPeak: Equatable, Sendable {
    public let frameIndex: Int
    public let time: Double
    public let bin: Int
    public let frequency: Float
    public let magnitude: Float
    public let decibels: Float
    public let noiseFloorDB: Float
    public let snrDB: Float
}

public struct PeakDetector: Equatable, Sendable {
    public var minimumSNRDB: Float
    public var neighbourhoodRadius: Int
    public var minimumFrequencySeparation: Float
    public var maximumPeaksPerFrame: Int

    public init(
        minimumSNRDB: Float = 6,
        neighbourhoodRadius: Int = 2,
        minimumFrequencySeparation: Float = 6.25,
        maximumPeaksPerFrame: Int = 64
    ) {
        self.minimumSNRDB = minimumSNRDB
        self.neighbourhoodRadius = max(1, neighbourhoodRadius)
        self.minimumFrequencySeparation = max(0, minimumFrequencySeparation)
        self.maximumPeaksPerFrame = max(1, maximumPeaksPerFrame)
    }

    public func detect(in frame: WaterfallFrame) -> [SpectralPeak] {
        guard frame.count >= 3 else { return [] }
        var candidates: [SpectralPeak] = []

        for index in 1..<(frame.count - 1) {
            let value = frame.decibels[index]
            let low = max(0, index - neighbourhoodRadius)
            let high = min(frame.count - 1, index + neighbourhoodRadius)

            let isMaximum = (low...high).allSatisfy {
                $0 == index || frame.decibels[$0] < value
            }
            guard isMaximum else { continue }

            let snr = value - frame.noiseFloorDB
            guard snr >= minimumSNRDB else { continue }

            candidates.append(
                SpectralPeak(
                    frameIndex: frame.index,
                    time: frame.time,
                    bin: index,
                    frequency: frame.frequency(at: index),
                    magnitude: frame.magnitudes[index],
                    decibels: value,
                    noiseFloorDB: frame.noiseFloorDB,
                    snrDB: snr
                )
            )
        }

        var selected: [SpectralPeak] = []
        for candidate in candidates.sorted(by: { $0.decibels > $1.decibels }) {
            let separated = selected.allSatisfy {
                abs($0.frequency - candidate.frequency) >= minimumFrequencySeparation
            }
            guard separated else { continue }

            selected.append(candidate)
            if selected.count == maximumPeaksPerFrame { break }
        }

        return selected.sorted { $0.frequency < $1.frequency }
    }

    public func detect(in spectrogram: Spectrogram) -> [SpectralPeak] {
        spectrogram.frames.flatMap { detect(in: $0) }
    }
}
