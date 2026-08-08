import Foundation

public enum WaterfallError: Error, Equatable, Sendable {
    case invalidConfiguration
    case insufficientSamples(required: Int, actual: Int)
}

public struct WaterfallConfiguration: Equatable, Sendable {
    public var sampleRate: Float
    public var fftSize: Int
    public var hopSize: Int
    public var window: WindowFunction
    public var minimumFrequency: Float
    public var maximumFrequency: Float
    public var dynamicRange: Float

    public init(
        sampleRate: Float,
        fftSize: Int = 2_048,
        hopSize: Int? = nil,
        window: WindowFunction = .hann,
        minimumFrequency: Float = 0,
        maximumFrequency: Float? = nil,
        dynamicRange: Float = 60
    ) {
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        self.hopSize = hopSize ?? fftSize / 2
        self.window = window
        self.minimumFrequency = minimumFrequency
        self.maximumFrequency = maximumFrequency ?? sampleRate / 2
        self.dynamicRange = dynamicRange
    }

    public var binWidth: Float { sampleRate / Float(fftSize) }

    func validate() throws {
        guard sampleRate > 0,
              fftSize >= 2,
              hopSize > 0,
              hopSize <= fftSize,
              minimumFrequency >= 0,
              maximumFrequency > minimumFrequency,
              maximumFrequency <= sampleRate / 2,
              dynamicRange > 0 else {
            throw WaterfallError.invalidConfiguration
        }

        #if !canImport(Accelerate)
        guard (fftSize & (fftSize - 1)) == 0 else {
            throw WaterfallError.invalidConfiguration
        }
        #endif
    }
}

public struct WaterfallFrame: Equatable, Sendable {
    public let index: Int
    public let sampleOffset: Int
    public let time: Double
    public let minimumFrequency: Float
    public let binWidth: Float
    public let magnitudes: [Float]
    public let decibels: [Float]
    public let intensities: [Float]
    public let noiseFloorDB: Float
    public let real: [Float]
    public let imaginary: [Float]

    public init(
        index: Int,
        sampleOffset: Int,
        time: Double,
        minimumFrequency: Float,
        binWidth: Float,
        magnitudes: [Float],
        decibels: [Float],
        intensities: [Float],
        noiseFloorDB: Float,
        real: [Float] = [],
        imaginary: [Float] = []
    ) {
        self.index = index
        self.sampleOffset = sampleOffset
        self.time = time
        self.minimumFrequency = minimumFrequency
        self.binWidth = binWidth
        self.magnitudes = magnitudes
        self.decibels = decibels
        self.intensities = intensities
        self.noiseFloorDB = noiseFloorDB
        self.real = real
        self.imaginary = imaginary
    }

    public var count: Int { magnitudes.count }

    public func frequency(at index: Int) -> Float {
        minimumFrequency + Float(index) * binWidth
    }

    public func signalToNoiseRatio(at index: Int) -> Float {
        decibels[index] - noiseFloorDB
    }
}

public struct Spectrogram: Equatable, Sendable {
    public let frames: [WaterfallFrame]
    public let sampleRate: Float
    public let fftSize: Int
    public let hopSize: Int
    public let minimumFrequency: Float
    public let maximumFrequency: Float

    public init(
        frames: [WaterfallFrame],
        sampleRate: Float,
        fftSize: Int,
        hopSize: Int,
        minimumFrequency: Float,
        maximumFrequency: Float
    ) {
        self.frames = frames
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        self.hopSize = hopSize
        self.minimumFrequency = minimumFrequency
        self.maximumFrequency = maximumFrequency
    }

    public var rowCount: Int { frames.count }
    public var columnCount: Int { frames.first?.count ?? 0 }
    public var intensityRows: [[Float]] { frames.map(\.intensities) }

    public var duration: Double {
        guard let last = frames.last else { return 0 }
        return last.time + Double(fftSize) / Double(sampleRate)
    }

    public func frame(nearestTime time: Double) -> WaterfallFrame? {
        guard !frames.isEmpty else {
            return nil
        }
        let frameStep = Double(hopSize) / Double(sampleRate)
        let index = Int((time / frameStep).rounded())
        if index < 0 || index >= frames.count {
            return nil
        }
        return frames[index]
    }
}

public enum Waterfall {
    public static func analyse(
        samples: [Float],
        configuration: WaterfallConfiguration
    ) throws -> Spectrogram {
        try configuration.validate()

        guard samples.count >= configuration.fftSize else {
            throw WaterfallError.insufficientSamples(
                required: configuration.fftSize,
                actual: samples.count
            )
        }

        let firstBin = max(
            0,
            Int(floor(configuration.minimumFrequency / configuration.binWidth))
        )
        let lastBin = min(
            configuration.fftSize / 2,
            Int(ceil(configuration.maximumFrequency / configuration.binWidth))
        )

        var frames: [WaterfallFrame] = []
        var offset = 0
        var frameIndex = 0

        while offset + configuration.fftSize <= samples.count {
            let frameSamples = Array(
                samples[offset..<(offset + configuration.fftSize)]
            )
            let spectrum = try Spectrum.analyse(
                samples: frameSamples,
                sampleRate: configuration.sampleRate,
                fftSize: configuration.fftSize,
                window: configuration.window
            )
            let range = firstBin...lastBin
            let magnitudes = Array(spectrum.magnitudes[range])
            let real = Array(spectrum.real[range])
            let imaginary = Array(spectrum.imaginary[range])
            let decibels = magnitudes.map {
                20 * log10f(max($0, Float.leastNonzeroMagnitude))
            }
            let noise = NoiseFloorEstimator.median(of: decibels)
            let ceiling = max(
                decibels.max() ?? noise,
                noise + configuration.dynamicRange
            )
            let floorDB = ceiling - configuration.dynamicRange
            let intensities = decibels.map {
                min(max(($0 - floorDB) / configuration.dynamicRange, 0), 1)
            }

            frames.append(
                WaterfallFrame(
                    index: frameIndex,
                    sampleOffset: offset,
                    time: Double(offset) / Double(configuration.sampleRate),
                    minimumFrequency: Float(firstBin) * configuration.binWidth,
                    binWidth: configuration.binWidth,
                    magnitudes: magnitudes,
                    decibels: decibels,
                    intensities: intensities,
                    noiseFloorDB: noise,
                    real: real,
                    imaginary: imaginary
                )
            )

            offset += configuration.hopSize
            frameIndex += 1
        }

        return Spectrogram(
            frames: frames,
            sampleRate: configuration.sampleRate,
            fftSize: configuration.fftSize,
            hopSize: configuration.hopSize,
            minimumFrequency: Float(firstBin) * configuration.binWidth,
            maximumFrequency: Float(lastBin) * configuration.binWidth
        )
    }
}
