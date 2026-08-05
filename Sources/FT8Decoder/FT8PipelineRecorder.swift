import Foundation
import FT8DSP

public enum FT8PipelineRecorderError: Error, Equatable, Sendable {
    case invalidMetricCount(symbolIndex: Int, actual: Int)
    case emptyToneMetrics(symbolIndex: Int)
}

/// Captures the detected 79-tone sequence for one FT8 candidate.
///
/// This checkpoint records only the received tone stage. Later checkpoints
/// populate the remaining fields in `FT8PipelineRecord`.
public struct FT8PipelineRecorder: Sendable {
    public var extractor: SoftSymbolExtractor

    public init(extractor: SoftSymbolExtractor = .init()) {
        self.extractor = extractor
    }

    public func captureReceivedTones(
        candidateIndex: Int,
        candidate: FT8Candidate,
        spectrogram: Spectrogram
    ) throws -> FT8PipelineRecord {
        var toneMetrics: [[Float]] = []
        toneMetrics.reserveCapacity(FT8PipelineRecord.receivedToneCount)

        for symbolIndex in 0..<FT8PipelineRecord.receivedToneCount {
            toneMetrics.append(
                try extractor.toneMetrics(
                    symbolIndex: symbolIndex,
                    spectrogram: spectrogram,
                    candidate: candidate
                )
            )
        }

        return try captureReceivedTones(
            candidateIndex: candidateIndex,
            candidate: candidate,
            toneMetrics: toneMetrics
        )
    }

    /// Builds a pipeline record from already-calculated tone metrics.
    ///
    /// This overload is useful to avoid recalculating metrics when a caller
    /// already owns them and makes the selection logic independently testable.
    public func captureReceivedTones(
        candidateIndex: Int,
        candidate: FT8Candidate,
        toneMetrics: [[Float]]
    ) throws -> FT8PipelineRecord {
        let tones = try Self.strongestTones(from: toneMetrics)

        return FT8PipelineRecord(
            candidateIndex: candidateIndex,
            startTime: candidate.startTime,
            frequency: candidate.frequency,
            synchronizerScore: candidate.syncScore,
            receivedTones: tones
        )
    }

    public static func strongestTones(
        from toneMetrics: [[Float]]
    ) throws -> [UInt8] {
        var tones: [UInt8] = []
        tones.reserveCapacity(toneMetrics.count)

        for (symbolIndex, metrics) in toneMetrics.enumerated() {
            guard !metrics.isEmpty else {
                throw FT8PipelineRecorderError.emptyToneMetrics(
                    symbolIndex: symbolIndex
                )
            }

            guard metrics.count == 8 else {
                throw FT8PipelineRecorderError.invalidMetricCount(
                    symbolIndex: symbolIndex,
                    actual: metrics.count
                )
            }

            guard let strongest = metrics.enumerated().max(by: {
                if $0.element == $1.element {
                    return $0.offset > $1.offset
                }
                return $0.element < $1.element
            }) else {
                throw FT8PipelineRecorderError.emptyToneMetrics(
                    symbolIndex: symbolIndex
                )
            }

            tones.append(UInt8(strongest.offset))
        }

        return tones
    }
}
