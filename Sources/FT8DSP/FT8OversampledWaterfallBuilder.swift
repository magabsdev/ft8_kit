import Foundation

public enum FT8OversampledWaterfallBuilder {
    public static func build(
        samples: [Float],
        configuration: FT8OversampledWaterfallConfiguration
    ) throws -> FT8OversampledWaterfall {
        try configuration.validate()

        guard samples.count >= configuration.symbolSamples else {
            throw FT8OversampledWaterfallError.insufficientSamples(
                required: configuration.symbolSamples,
                actual: samples.count
            )
        }

        let firstBaseBin = max(
            0,
            Int(floor(configuration.minimumFrequency / configuration.baseBinWidth))
        )
        let lastBaseBin = min(
            configuration.symbolSamples / 2,
            Int(floor(configuration.maximumFrequency / configuration.baseBinWidth))
        )
        let baseBinCount = max(0, lastBaseBin - firstBaseBin + 1)
        guard baseBinCount > 0 else {
            throw FT8OversampledWaterfallError.invalidConfiguration
        }

        let frameCount = 1
            + (samples.count - configuration.symbolSamples) / configuration.hopSamples
        let blockCount = (frameCount + configuration.timeOversampling - 1)
            / configuration.timeOversampling
        let storageCount = blockCount
            * configuration.timeOversampling
            * configuration.frequencyOversampling
            * baseBinCount

        let fft = try FFT(size: configuration.fftSize)
        let window = configuration.window.coefficients(count: configuration.symbolSamples)
        var storage = Array(repeating: Float.zero, count: storageCount)
        var fftInput = Array(repeating: Float.zero, count: configuration.fftSize)

        for frame in 0..<frameCount {
            let sampleOffset = frame * configuration.hopSamples

            for index in 0..<configuration.symbolSamples {
                fftInput[index] = samples[sampleOffset + index] * window[index]
            }
            if configuration.fftSize > configuration.symbolSamples {
                for index in configuration.symbolSamples..<configuration.fftSize {
                    fftInput[index] = 0
                }
            }

            let spectrum = try fft.forward(fftInput)
            let block = frame / configuration.timeOversampling
            let timeSubdivision = frame % configuration.timeOversampling

            for frequencySubdivision in 0..<configuration.frequencyOversampling {
                let destinationBase = block
                    * configuration.timeOversampling
                    * configuration.frequencyOversampling
                    * baseBinCount
                    + timeSubdivision
                    * configuration.frequencyOversampling
                    * baseBinCount
                    + frequencySubdivision
                    * baseBinCount

                for localBaseBin in 0..<baseBinCount {
                    let absoluteBaseBin = firstBaseBin + localBaseBin
                    let oversampledFFTBin = absoluteBaseBin
                        * configuration.frequencyOversampling
                        + frequencySubdivision
                    let real = spectrum.real[oversampledFFTBin]
                    let imaginary = spectrum.imaginary[oversampledFFTBin]
                    storage[destinationBase + localBaseBin] = sqrtf(
                        real * real + imaginary * imaginary
                    )
                }
            }
        }

        return FT8OversampledWaterfall(
            sampleRate: configuration.sampleRate,
            symbolSamples: configuration.symbolSamples,
            timeOversampling: configuration.timeOversampling,
            frequencyOversampling: configuration.frequencyOversampling,
            blockCount: blockCount,
            frameCount: frameCount,
            baseBinCount: baseBinCount,
            firstBaseBin: firstBaseBin,
            minimumFrequency: Float(firstBaseBin) * configuration.baseBinWidth,
            maximumFrequency: Float(lastBaseBin) * configuration.baseBinWidth
                + Float(configuration.frequencyOversampling - 1)
                * configuration.oversampledBinWidth,
            baseBinWidth: configuration.baseBinWidth,
            oversampledBinWidth: configuration.oversampledBinWidth,
            magnitudes: storage
        )
    }
}
