import Foundation

public struct FT8LiveDecoderConfiguration: Equatable, Sendable {
    public var sampleRate: Int
    public var slotDuration: Double
    public var retainedSlotCount: Int
    public var decodeStride: Double

    public init(
        sampleRate: Int = 12_000,
        slotDuration: Double = 15,
        retainedSlotCount: Int = 2,
        decodeStride: Double = 15
    ) {
        self.sampleRate = sampleRate
        self.slotDuration = slotDuration
        self.retainedSlotCount = retainedSlotCount
        self.decodeStride = decodeStride
    }

    public var slotSampleCount: Int {
        Int((Double(sampleRate) * slotDuration).rounded())
    }

    public var strideSampleCount: Int {
        Int((Double(sampleRate) * decodeStride).rounded())
    }

    public var ringBufferCapacity: Int {
        slotSampleCount * retainedSlotCount
    }

    func validate() throws {
        guard sampleRate > 0,
              slotDuration > 0,
              retainedSlotCount > 0,
              decodeStride > 0,
              strideSampleCount > 0,
              ringBufferCapacity >= slotSampleCount else {
            throw FT8LiveDecoderError.invalidConfiguration
        }
    }
}

public enum FT8LiveDecoderError: Error, Equatable, Sendable {
    case invalidConfiguration
}

public struct FT8LiveDecodeEvent: Equatable, Sendable {
    public let sequence: Int
    public let slotStartSample: Int64
    public let batch: FT8DecodeBatch

    public init(
        sequence: Int,
        slotStartSample: Int64,
        batch: FT8DecodeBatch
    ) {
        self.sequence = sequence
        self.slotStartSample = slotStartSample
        self.batch = batch
    }
}

public actor FT8LiveDecoder {
    public let configuration: FT8LiveDecoderConfiguration
    public var decoder: FT8SlotDecoder

    private var buffer: PCMFloatRingBuffer
    private var totalSamplesReceived: Int64 = 0
    private var samplesSinceLastDecode: Int = 0
    private var sequence: Int = 0

    public init(
        configuration: FT8LiveDecoderConfiguration = .init(),
        decoder: FT8SlotDecoder = .init()
    ) throws {
        try configuration.validate()
        self.configuration = configuration
        self.decoder = decoder
        self.buffer = try PCMFloatRingBuffer(
            capacity: configuration.ringBufferCapacity
        )
    }

    public var bufferedSampleCount: Int {
        buffer.count
    }

    public var receivedSampleCount: Int64 {
        totalSamplesReceived
    }

    public func append(
        samples: [Float]
    ) throws -> [FT8LiveDecodeEvent] {
        guard !samples.isEmpty else { return [] }

        buffer.append(samples)
        totalSamplesReceived += Int64(samples.count)
        samplesSinceLastDecode += samples.count

        var events: [FT8LiveDecodeEvent] = []

        while buffer.count >= configuration.slotSampleCount,
              samplesSinceLastDecode >= configuration.strideSampleCount {
            let slot = buffer.suffix(
                count: configuration.slotSampleCount
            )

            let batch = try decoder.decode(samples: slot)
            sequence += 1

            let slotStart = totalSamplesReceived
                - Int64(configuration.slotSampleCount)

            events.append(
                FT8LiveDecodeEvent(
                    sequence: sequence,
                    slotStartSample: slotStart,
                    batch: batch
                )
            )

            samplesSinceLastDecode -= configuration.strideSampleCount
        }

        return events
    }

    public func flush() throws -> FT8LiveDecodeEvent? {
        guard buffer.count >= configuration.slotSampleCount else {
            return nil
        }

        let slot = buffer.suffix(
            count: configuration.slotSampleCount
        )
        let batch = try decoder.decode(samples: slot)
        sequence += 1

        return FT8LiveDecodeEvent(
            sequence: sequence,
            slotStartSample: totalSamplesReceived
                - Int64(configuration.slotSampleCount),
            batch: batch
        )
    }

    public func reset() {
        buffer.removeAll()
        totalSamplesReceived = 0
        samplesSinceLastDecode = 0
        sequence = 0
    }
}
