import Foundation

public enum FT8RealtimeDecoderError:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
    case nonFiniteTimestamp
    case sampleRateMismatch(expected: Int, actual: Int)
    case timestampMovedBackwards
}

public struct FT8RealtimeDecoderConfiguration:
    Equatable,
    Sendable
{
    public var sampleRate: Int
    public var slotDuration: TimeInterval
    public var timingToleranceSamples: Int
    public var fillSmallGapsWithSilence: Bool
    public var maximumRecoverableGap: TimeInterval

    public init(
        sampleRate: Int = 12_000,
        slotDuration: TimeInterval = 15,
        timingToleranceSamples: Int = 12,
        fillSmallGapsWithSilence: Bool = true,
        maximumRecoverableGap: TimeInterval = 0.250
    ) {
        self.sampleRate = sampleRate
        self.slotDuration = slotDuration
        self.timingToleranceSamples =
            timingToleranceSamples
        self.fillSmallGapsWithSilence =
            fillSmallGapsWithSilence
        self.maximumRecoverableGap =
            maximumRecoverableGap
    }

    public var slotSampleCount: Int {
        Int(
            (Double(sampleRate) * slotDuration)
                .rounded()
        )
    }

    public var maximumRecoverableGapSamples: Int {
        Int(
            (Double(sampleRate) *
                maximumRecoverableGap)
                .rounded()
        )
    }

    func validate() throws {
        guard sampleRate > 0,
              slotDuration > 0,
              slotSampleCount > 0,
              timingToleranceSamples >= 0,
              maximumRecoverableGap >= 0 else {
            throw FT8RealtimeDecoderError
                .invalidConfiguration
        }
    }
}

public struct FT8RealtimeDiagnostics:
    Equatable,
    Sendable
{
    public let receivedSamples: Int64
    public let insertedSilenceSamples: Int64
    public let droppedOverlapSamples: Int64
    public let discardedPartialSlots: Int
    public let decodedSlots: Int

    public init(
        receivedSamples: Int64,
        insertedSilenceSamples: Int64,
        droppedOverlapSamples: Int64,
        discardedPartialSlots: Int,
        decodedSlots: Int
    ) {
        self.receivedSamples = receivedSamples
        self.insertedSilenceSamples =
            insertedSilenceSamples
        self.droppedOverlapSamples =
            droppedOverlapSamples
        self.discardedPartialSlots =
            discardedPartialSlots
        self.decodedSlots = decodedSlots
    }
}

public struct FT8RealtimeDecodeEvent:
    Equatable,
    Sendable
{
    public let sequence: Int
    public let slotIndex: Int64
    public let slotStart: Date
    public let slotEnd: Date
    public let batch: FT8MultiPassDecodeBatch
    public let diagnostics: FT8RealtimeDiagnostics

    public init(
        sequence: Int,
        slotIndex: Int64,
        slotStart: Date,
        slotEnd: Date,
        batch: FT8MultiPassDecodeBatch,
        diagnostics: FT8RealtimeDiagnostics
    ) {
        self.sequence = sequence
        self.slotIndex = slotIndex
        self.slotStart = slotStart
        self.slotEnd = slotEnd
        self.batch = batch
        self.diagnostics = diagnostics
    }
}

public actor FT8RealtimeDecoder {
    public let configuration:
        FT8RealtimeDecoderConfiguration
    public let clock: FT8SlotClock
    public var decoder: FT8MultiPassSlotDecoder

    private var currentSlotStart: Date?
    private var currentSlotSamples: [Float] = []
    private var expectedNextSampleDate: Date?

    private var sequence = 0
    private var receivedSamples: Int64 = 0
    private var insertedSilenceSamples: Int64 = 0
    private var droppedOverlapSamples: Int64 = 0
    private var discardedPartialSlots = 0
    private var decodedSlots = 0

    public init(
        configuration:
            FT8RealtimeDecoderConfiguration = .init(),
        decoder: FT8MultiPassSlotDecoder = .init()
    ) throws {
        try configuration.validate()
        self.configuration = configuration
        self.clock = FT8SlotClock(
            slotDuration: configuration.slotDuration
        )
        self.decoder = decoder
        self.currentSlotSamples.reserveCapacity(
            configuration.slotSampleCount
        )
    }

    public func append(
        samples: [Float],
        sampleRate: Int,
        startingAt timestamp: Date
    ) throws -> [FT8RealtimeDecodeEvent] {
        guard timestamp.timeIntervalSince1970.isFinite else {
            throw FT8RealtimeDecoderError
                .nonFiniteTimestamp
        }
        guard sampleRate == configuration.sampleRate else {
            throw FT8RealtimeDecoderError.sampleRateMismatch(
                expected: configuration.sampleRate,
                actual: sampleRate
            )
        }
        guard !samples.isEmpty else { return [] }

        receivedSamples += Int64(samples.count)

        var adjustedSamples = samples
        var adjustedTimestamp = timestamp
        var pendingEvents: [FT8RealtimeDecodeEvent] = []

        if let expected = expectedNextSampleDate {
            let deltaSamples = Int(
                (
                    adjustedTimestamp
                        .timeIntervalSince(expected) *
                    Double(configuration.sampleRate)
                ).rounded()
            )

            if deltaSamples <
                -configuration.timingToleranceSamples {
                let overlap = -deltaSamples
                guard overlap < adjustedSamples.count else {
                    droppedOverlapSamples +=
                        Int64(adjustedSamples.count)
                    return []
                }
                adjustedSamples.removeFirst(overlap)
                droppedOverlapSamples += Int64(overlap)
                adjustedTimestamp = expected
            } else if deltaSamples >
                        configuration
                            .timingToleranceSamples {
                guard configuration
                    .fillSmallGapsWithSilence,
                      deltaSamples <= configuration
                        .maximumRecoverableGapSamples else {
                    discardPartialSlot()
                    currentSlotStart = nil
                    expectedNextSampleDate = nil
                    return try ingest(
                        adjustedSamples,
                        startingAt: adjustedTimestamp
                    )
                }

                let silence = Array(
                    repeating: Float.zero,
                    count: deltaSamples
                )
                insertedSilenceSamples +=
                    Int64(deltaSamples)
                pendingEvents.append(
                    contentsOf: try ingest(
                        silence,
                        startingAt: expected
                    )
                )
                adjustedTimestamp = expected
                    .addingTimeInterval(
                        Double(deltaSamples) /
                        Double(configuration.sampleRate)
                    )
            } else {
                adjustedTimestamp = expected
            }
        }

        pendingEvents.append(
            contentsOf: try ingest(
                adjustedSamples,
                startingAt: adjustedTimestamp
            )
        )
        return pendingEvents
    }

    public func reset() {
        currentSlotStart = nil
        currentSlotSamples.removeAll(
            keepingCapacity: true
        )
        expectedNextSampleDate = nil
        sequence = 0
        receivedSamples = 0
        insertedSilenceSamples = 0
        droppedOverlapSamples = 0
        discardedPartialSlots = 0
        decodedSlots = 0
    }

    public func diagnostics()
        -> FT8RealtimeDiagnostics
    {
        makeDiagnostics()
    }

    private func ingest(
        _ samples: [Float],
        startingAt timestamp: Date
    ) throws -> [FT8RealtimeDecodeEvent] {
        var events: [FT8RealtimeDecodeEvent] = []
        var cursor = 0
        var sampleDate = timestamp

        while cursor < samples.count {
            let slotStart = clock.slotStart(
                containing: sampleDate
            )
            let slotEnd = slotStart.addingTimeInterval(
                configuration.slotDuration
            )

            if currentSlotStart != slotStart {
                if !currentSlotSamples.isEmpty {
                    discardPartialSlot()
                }
                currentSlotStart = slotStart

                let leadingSamples = Int(
                    (
                        sampleDate
                            .timeIntervalSince(slotStart) *
                        Double(configuration.sampleRate)
                    ).rounded()
                )

                if leadingSamples > 0 {
                    currentSlotSamples.append(
                        contentsOf: repeatElement(
                            0,
                            count: min(
                                leadingSamples,
                                configuration.slotSampleCount
                            )
                        )
                    )
                    insertedSilenceSamples +=
                        Int64(leadingSamples)
                }
            }

            let available = configuration.slotSampleCount -
                currentSlotSamples.count
            let amount = min(
                available,
                samples.count - cursor
            )

            currentSlotSamples.append(
                contentsOf: samples[
                    cursor..<(cursor + amount)
                ]
            )
            cursor += amount
            sampleDate = sampleDate.addingTimeInterval(
                Double(amount) /
                Double(configuration.sampleRate)
            )

            if currentSlotSamples.count ==
                configuration.slotSampleCount {
                let batch = try decoder.decode(
                    samples: currentSlotSamples
                )
                sequence += 1
                decodedSlots += 1

                events.append(
                    FT8RealtimeDecodeEvent(
                        sequence: sequence,
                        slotIndex: clock.slotIndex(
                            containing: slotStart
                        ),
                        slotStart: slotStart,
                        slotEnd: slotEnd,
                        batch: batch,
                        diagnostics: makeDiagnostics()
                    )
                )

                currentSlotSamples.removeAll(
                    keepingCapacity: true
                )
                currentSlotStart = nil
            }
        }

        expectedNextSampleDate = timestamp
            .addingTimeInterval(
                Double(samples.count) /
                Double(configuration.sampleRate)
            )
        return events
    }

    private func discardPartialSlot() {
        if !currentSlotSamples.isEmpty {
            discardedPartialSlots += 1
            currentSlotSamples.removeAll(
                keepingCapacity: true
            )
        }
    }

    private func makeDiagnostics()
        -> FT8RealtimeDiagnostics
    {
        FT8RealtimeDiagnostics(
            receivedSamples: receivedSamples,
            insertedSilenceSamples:
                insertedSilenceSamples,
            droppedOverlapSamples:
                droppedOverlapSamples,
            discardedPartialSlots:
                discardedPartialSlots,
            decodedSlots: decodedSlots
        )
    }
}
