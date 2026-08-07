import Foundation
import FT8DSP
import FT8Protocol

enum SyntheticSpectrogram {
    static func make(
        baseFrequency: Float = 1_000,
        startTime: Double = 0.5,
        driftHzPerSecond: Float = 0,
        sampleRate: Float = 12_000,
        fftSize: Int = 1_920,
        hopSize: Int = 480,
        duration: Double = 15,
        signalDB: Float = -12,
        noiseDB: Float = -60
    ) -> Spectrogram {
        let frameStep = Double(hopSize) / Double(sampleRate)
        let frameDuration = Double(fftSize) / Double(sampleRate)
        let frameCount = Int(duration / frameStep)
        let binWidth = sampleRate / Float(fftSize)
        let minimumFrequency: Float = 0
        let maximumFrequency: Float = sampleRate / 2
        let columnCount = fftSize / 2 + 1

        var frames: [WaterfallFrame] = []

        for frameIndex in 0..<frameCount {
            // Match Waterfall.analyse exactly: WaterfallFrame.time denotes the
            // START of the FFT window.
            let time = Double(frameIndex) * frameStep
            let windowCentre = time + frameDuration / 2

            var decibels = Array(
                repeating: noiseDB,
                count: columnCount
            )

            let relativeCentre = windowCentre - startTime

            if relativeCentre >= 0 {
                let symbol = Int(
                    floor(relativeCentre / 0.160)
                )

                if symbol >= 0,
                   symbol < 79,
                   let tone = syncTone(symbol: symbol) {
                    let symbolCentre =
                        startTime
                        + (Double(symbol) + 0.5) * 0.160

                    // A synthetic FFT window carries the signal when its centre
                    // is close to the centre of the requested FT8 symbol.
                    if abs(windowCentre - symbolCentre)
                        <= frameStep * 0.75 {
                        let frequency =
                            baseFrequency
                            + Float(tone) * 6.25
                            + driftHzPerSecond
                                * Float(
                                    symbolCentre - startTime
                                )

                        let bin = Int(
                            (frequency / binWidth).rounded()
                        )

                        if decibels.indices.contains(bin) {
                            decibels[bin] = signalDB
                        }
                    }
                }
            }

            let magnitudes =
                decibels.map { powf(10, $0 / 20) }

            frames.append(
                WaterfallFrame(
                    index: frameIndex,
                    sampleOffset: frameIndex * hopSize,
                    time: time,
                    minimumFrequency: minimumFrequency,
                    binWidth: binWidth,
                    magnitudes: magnitudes,
                    decibels: decibels,
                    intensities: decibels.map {
                        min(
                            max(
                                ($0 - noiseDB) / 60,
                                0
                            ),
                            1
                        )
                    },
                    noiseFloorDB: noiseDB
                )
            )
        }

        return Spectrogram(
            frames: frames,
            sampleRate: sampleRate,
            fftSize: fftSize,
            hopSize: hopSize,
            minimumFrequency: minimumFrequency,
            maximumFrequency: maximumFrequency
        )
    }

    private static func syncTone(
        symbol: Int
    ) -> UInt8? {
        for start in [0, 36, 72]
        where symbol >= start && symbol < start + 7 {
            return FT8Constants.costas[
                symbol - start
            ]
        }

        return nil
    }
}
