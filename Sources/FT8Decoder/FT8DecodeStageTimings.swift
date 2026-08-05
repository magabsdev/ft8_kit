import Foundation

public enum FT8DecodeStage: String, CaseIterable, Codable, Sendable {
    case synchronizer
    case scheduling
    case softSymbolExtraction
    case pipelineCapture
    case ldpc
    case messageDecode
    case nearbyRetry
    case deduplication
}

public struct FT8DecodeStageTimings: Codable, Equatable, Sendable {
    public var synchronizerSeconds: Double
    public var schedulingSeconds: Double
    public var softSymbolExtractionSeconds: Double
    public var pipelineCaptureSeconds: Double
    public var ldpcSeconds: Double
    public var messageDecodeSeconds: Double
    public var nearbyRetrySeconds: Double
    public var deduplicationSeconds: Double

    public init(
        synchronizerSeconds: Double = 0,
        schedulingSeconds: Double = 0,
        softSymbolExtractionSeconds: Double = 0,
        pipelineCaptureSeconds: Double = 0,
        ldpcSeconds: Double = 0,
        messageDecodeSeconds: Double = 0,
        nearbyRetrySeconds: Double = 0,
        deduplicationSeconds: Double = 0
    ) {
        self.synchronizerSeconds = synchronizerSeconds
        self.schedulingSeconds = schedulingSeconds
        self.softSymbolExtractionSeconds = softSymbolExtractionSeconds
        self.pipelineCaptureSeconds = pipelineCaptureSeconds
        self.ldpcSeconds = ldpcSeconds
        self.messageDecodeSeconds = messageDecodeSeconds
        self.nearbyRetrySeconds = nearbyRetrySeconds
        self.deduplicationSeconds = deduplicationSeconds
    }

    public var measuredSeconds: Double {
        synchronizerSeconds
            + schedulingSeconds
            + softSymbolExtractionSeconds
            + pipelineCaptureSeconds
            + ldpcSeconds
            + messageDecodeSeconds
            + nearbyRetrySeconds
            + deduplicationSeconds
    }

    public var slowestStage: FT8DecodeStage? {
        let values: [(FT8DecodeStage, Double)] = [
            (.synchronizer, synchronizerSeconds),
            (.scheduling, schedulingSeconds),
            (.softSymbolExtraction, softSymbolExtractionSeconds),
            (.pipelineCapture, pipelineCaptureSeconds),
            (.ldpc, ldpcSeconds),
            (.messageDecode, messageDecodeSeconds),
            (.nearbyRetry, nearbyRetrySeconds),
            (.deduplication, deduplicationSeconds)
        ]

        return values
            .filter { $0.1 > 0 }
            .max {
                if $0.1 != $1.1 {
                    return $0.1 < $1.1
                }
                return $0.0.rawValue > $1.0.rawValue
            }?
            .0
    }

    public func seconds(for stage: FT8DecodeStage) -> Double {
        switch stage {
        case .synchronizer:
            synchronizerSeconds
        case .scheduling:
            schedulingSeconds
        case .softSymbolExtraction:
            softSymbolExtractionSeconds
        case .pipelineCapture:
            pipelineCaptureSeconds
        case .ldpc:
            ldpcSeconds
        case .messageDecode:
            messageDecodeSeconds
        case .nearbyRetry:
            nearbyRetrySeconds
        case .deduplication:
            deduplicationSeconds
        }
    }

    public mutating func add(
        _ seconds: Double,
        to stage: FT8DecodeStage
    ) {
        guard seconds.isFinite, seconds >= 0 else { return }

        switch stage {
        case .synchronizer:
            synchronizerSeconds += seconds
        case .scheduling:
            schedulingSeconds += seconds
        case .softSymbolExtraction:
            softSymbolExtractionSeconds += seconds
        case .pipelineCapture:
            pipelineCaptureSeconds += seconds
        case .ldpc:
            ldpcSeconds += seconds
        case .messageDecode:
            messageDecodeSeconds += seconds
        case .nearbyRetry:
            nearbyRetrySeconds += seconds
        case .deduplication:
            deduplicationSeconds += seconds
        }
    }
}

public struct FT8DecodeStageProfiler: Sendable {
    private var timings: FT8DecodeStageTimings

    public init(timings: FT8DecodeStageTimings = .init()) {
        self.timings = timings
    }

    public var snapshot: FT8DecodeStageTimings {
        timings
    }

    @discardableResult
    public mutating func measure<T>(
        _ stage: FT8DecodeStage,
        operation: () throws -> T
    ) rethrows -> T {
        let started = ContinuousClock.now
        defer {
            timings.add(
                Self.seconds(since: started),
                to: stage
            )
        }
        return try operation()
    }

    private static func seconds(
        since started: ContinuousClock.Instant
    ) -> Double {
        let duration = ContinuousClock.now - started
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds)
                / 1_000_000_000_000_000_000
    }
}
