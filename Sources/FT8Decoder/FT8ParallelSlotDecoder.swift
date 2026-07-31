import FT8DSP

public struct FT8ParallelSlotDecoder: Sendable {
    public var waterfallConfiguration: WaterfallConfiguration
    public var decoder: FT8ParallelDecoder

    public init(
        waterfallConfiguration: WaterfallConfiguration = .init(
            sampleRate: 12_000,
            fftSize: 1_920,
            hopSize: 480,
            minimumFrequency: 100,
            maximumFrequency: 3_000,
            dynamicRange: 100
        ),
        decoder: FT8ParallelDecoder = .init()
    ) {
        self.waterfallConfiguration = waterfallConfiguration
        self.decoder = decoder
    }

    public func decode(
        samples: [Float]
    ) async throws -> FT8ParallelDecodeBatch {
        let spectrogram = try Waterfall.analyse(
            samples: samples,
            configuration: waterfallConfiguration
        )
        return try await decoder.decode(
            spectrogram: spectrogram
        )
    }
}
