import Foundation
import FT8DSP

public enum FT8PipelineRecorderError: Error, Equatable, Sendable {
    case invalidReceivedToneCount(actual: Int)
    case invalidMetricCount(symbolIndex: Int, actual: Int)
    case emptyToneMetrics(symbolIndex: Int)
}

/// Captures the detected FT8 tone pipeline for one candidate.
///
/// Checkpoint 7.3.1C records:
/// - all 79 received tones;
/// - the 58 data tones after removing the three Costas blocks.
///
/// Later checkpoints populate the bit and LLR stages.
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
    /// This overload avoids recalculating metrics when a caller already owns
    /// them and keeps tone-selection and Costas-removal independently testable.
    public func captureReceivedTones(
        candidateIndex: Int,
        candidate: FT8Candidate,
        toneMetrics: [[Float]]
    ) throws -> FT8PipelineRecord {
        let receivedTones = try Self.strongestTones(
            from: toneMetrics
        )
        let dataTones = try Self.extractDataTones(
            from: receivedTones
        )

        return FT8PipelineRecord(
            candidateIndex: candidateIndex,
            startTime: candidate.startTime,
            frequency: candidate.frequency,
            synchronizerScore: candidate.syncScore,
            receivedTones: receivedTones,
            dataTones: dataTones
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

    /// Removes the three seven-symbol Costas synchronization blocks while
    /// preserving the original order of the remaining data symbols.
    public static func extractDataTones(
        from receivedTones: [UInt8]
    ) throws -> [UInt8] {
        guard receivedTones.count
                == FT8PipelineRecord.receivedToneCount else {
            throw FT8PipelineRecorderError.invalidReceivedToneCount(
                actual: receivedTones.count
            )
        }

        var dataTones: [UInt8] = []
        dataTones.reserveCapacity(FT8PipelineRecord.dataToneCount)

        for (index, tone) in receivedTones.enumerated() {
            guard !costasToneIndices.contains(index) else {
                continue
            }

            dataTones.append(tone)
        }

        precondition(
            dataTones.count == FT8PipelineRecord.dataToneCount
        )

        return dataTones
    }

    private static let costasToneIndices: Set<Int> =
        Set(0..<7)
            .union(36..<43)
            .union(72..<79)
}
