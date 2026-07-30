import FT8DSP

public struct FT8MultiPassSlotDecoder: Sendable {
    public var waterfallConfiguration:
        WaterfallConfiguration
    public var decoder: FT8MultiPassDecoder

    public init(
        waterfallConfiguration:
            WaterfallConfiguration = .init(
                sampleRate: 12_000,
                fftSize: 2_048,
                hopSize: 480,
                minimumFrequency: 100,
                maximumFrequency: 3_000,
                dynamicRange: 100
            ),
        decoder: FT8MultiPassDecoder = .init()
    ) {
        self.waterfallConfiguration =
            waterfallConfiguration
        self.decoder = decoder
    }

    public func decode(
        samples: [Float]
    ) throws -> FT8MultiPassDecodeBatch {
        let spectrogram = try Waterfall.analyse(
            samples: samples,
            configuration: waterfallConfiguration
        )
        return try decoder.decode(
            spectrogram: spectrogram
        )
    }
}
