import Foundation

public enum FT8OversampledWaterfallError: Error, Equatable, Sendable {
    case invalidConfiguration
    case insufficientSamples(required: Int, actual: Int)
}

public struct FT8OversampledWaterfallConfiguration: Equatable, Sendable {
    public var sampleRate: Float
    public var symbolSamples: Int
    public var timeOversampling: Int
    public var frequencyOversampling: Int
    public var window: WindowFunction
    public var minimumFrequency: Float
    public var maximumFrequency: Float

    public init(sampleRate: Float, symbolSamples: Int = 1_920, timeOversampling: Int = 4, frequencyOversampling: Int = 2, window: WindowFunction = .hann, minimumFrequency: Float = 100, maximumFrequency: Float = 3_000) {
        self.sampleRate = sampleRate
        self.symbolSamples = symbolSamples
        self.timeOversampling = timeOversampling
        self.frequencyOversampling = frequencyOversampling
        self.window = window
        self.minimumFrequency = minimumFrequency
        self.maximumFrequency = maximumFrequency
    }

    public var hopSamples: Int { symbolSamples / timeOversampling }
    public var fftSize: Int { symbolSamples * frequencyOversampling }
    public var baseBinWidth: Float { sampleRate / Float(symbolSamples) }
    public var oversampledBinWidth: Float { sampleRate / Float(fftSize) }

    func validate() throws {
        guard sampleRate > 0, symbolSamples >= 2, timeOversampling > 0,
              frequencyOversampling > 0, symbolSamples.isMultiple(of: timeOversampling),
              hopSamples > 0, minimumFrequency >= 0,
              maximumFrequency > minimumFrequency, maximumFrequency <= sampleRate / 2 else {
            throw FT8OversampledWaterfallError.invalidConfiguration
        }
        #if !canImport(Accelerate)
        guard (fftSize & (fftSize - 1)) == 0 else {
            throw FT8OversampledWaterfallError.invalidConfiguration
        }
        #endif
    }
}

public struct FT8OversampledWaterfall: Equatable, Sendable {
    public let sampleRate: Float
    public let symbolSamples: Int
    public let timeOversampling: Int
    public let frequencyOversampling: Int
    public let blockCount: Int
    public let frameCount: Int
    public let baseBinCount: Int
    public let firstBaseBin: Int
    public let minimumFrequency: Float
    public let maximumFrequency: Float
    public let baseBinWidth: Float
    public let oversampledBinWidth: Float
    public let magnitudes: [Float]

    public init(sampleRate: Float, symbolSamples: Int, timeOversampling: Int, frequencyOversampling: Int, blockCount: Int, frameCount: Int, baseBinCount: Int, firstBaseBin: Int, minimumFrequency: Float, maximumFrequency: Float, baseBinWidth: Float, oversampledBinWidth: Float, magnitudes: [Float]) {
        self.sampleRate = sampleRate
        self.symbolSamples = symbolSamples
        self.timeOversampling = timeOversampling
        self.frequencyOversampling = frequencyOversampling
        self.blockCount = blockCount
        self.frameCount = frameCount
        self.baseBinCount = baseBinCount
        self.firstBaseBin = firstBaseBin
        self.minimumFrequency = minimumFrequency
        self.maximumFrequency = maximumFrequency
        self.baseBinWidth = baseBinWidth
        self.oversampledBinWidth = oversampledBinWidth
        self.magnitudes = magnitudes
    }

    public var blockStride: Int { timeOversampling * frequencyOversampling * baseBinCount }
    public var timeSubdivisionStride: Int { frequencyOversampling * baseBinCount }
    public var frequencySubdivisionStride: Int { baseBinCount }
    public var framePeriod: Double { Double(symbolSamples / timeOversampling) / Double(sampleRate) }

    public func magnitude(block: Int, timeSubdivision: Int, frequencySubdivision: Int, baseBin: Int) -> Float? {
        guard block >= 0, block < blockCount,
              timeSubdivision >= 0, timeSubdivision < timeOversampling,
              frequencySubdivision >= 0, frequencySubdivision < frequencyOversampling,
              baseBin >= 0, baseBin < baseBinCount else { return nil }
        let frame = block * timeOversampling + timeSubdivision
        guard frame < frameCount else { return nil }
        let index = block * blockStride + timeSubdivision * timeSubdivisionStride + frequencySubdivision * frequencySubdivisionStride + baseBin
        return magnitudes[index]
    }

    public func magnitude(frame: Int, frequencySubdivision: Int, baseBin: Int) -> Float? {
        guard frame >= 0, frame < frameCount else { return nil }
        return magnitude(block: frame / timeOversampling, timeSubdivision: frame % timeOversampling, frequencySubdivision: frequencySubdivision, baseBin: baseBin)
    }

    public func frequency(baseBin: Int, frequencySubdivision: Int) -> Float {
        minimumFrequency + Float(baseBin) * baseBinWidth + Float(frequencySubdivision) * oversampledBinWidth
    }

    public func nearestFrame(to time: Double) -> Int {
        min(max(Int((time / framePeriod).rounded()), 0), max(frameCount - 1, 0))
    }

    public func nearestFrequencyLocation(to frequency: Float) -> (baseBin: Int, frequencySubdivision: Int)? {
        guard frequency >= minimumFrequency, frequency <= maximumFrequency, baseBinCount > 0 else { return nil }
        let oversampledIndex = Int(((frequency - minimumFrequency) / oversampledBinWidth).rounded())
        let baseBin = oversampledIndex / frequencyOversampling
        let subdivision = oversampledIndex % frequencyOversampling
        guard baseBin >= 0, baseBin < baseBinCount else { return nil }
        return (baseBin, subdivision)
    }
}
