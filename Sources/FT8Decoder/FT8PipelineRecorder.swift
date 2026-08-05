import Foundation
import FT8DSP

public enum FT8PipelineRecorderError: Error, Equatable, Sendable {
    case invalidReceivedToneCount(actual: Int)
    case invalidDataToneCount(actual: Int)
    case invalidToneValue(index: Int, value: UInt8)
    case invalidMetricCount(symbolIndex: Int, actual: Int)
    case emptyToneMetrics(symbolIndex: Int)
}

/// Captures the detected FT8 tone and hard-bit pipeline for one candidate.
///
/// Checkpoint 7.3.1D records:
/// - all 79 received tones;
/// - the 58 data tones after removing the three Costas blocks;
/// - the 174 hard channel bits obtained through the FT8 inverse Gray map.
///
/// Later checkpoints populate the interleaved-bit and LLR stages.
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
    /// them and keeps each deterministic transformation independently testable.
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
        let grayMappedBits = try Self.mapDataTonesToBits(
            dataTones
        )

        return FT8PipelineRecord(
            candidateIndex: candidateIndex,
            startTime: candidate.startTime,
            frequency: candidate.frequency,
            synchronizerScore: candidate.syncScore,
            receivedTones: receivedTones,
            dataTones: dataTones,
            grayMappedBits: grayMappedBits
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

    /// Converts each of the 58 detected data tones into its three channel bits
    /// using the same inverse Gray mapping as `SoftSymbolExtractor`.
    ///
    /// Bit order is most-significant to least-significant for each tone.
    public static func mapDataTonesToBits(
        _ dataTones: [UInt8]
    ) throws -> [UInt8] {
        guard dataTones.count == FT8PipelineRecord.dataToneCount else {
            throw FT8PipelineRecorderError.invalidDataToneCount(
                actual: dataTones.count
            )
        }

        var bits: [UInt8] = []
        bits.reserveCapacity(FT8PipelineRecord.channelBitCount)

        for (index, tone) in dataTones.enumerated() {
            guard tone <= 7 else {
                throw FT8PipelineRecorderError.invalidToneValue(
                    index: index,
                    value: tone
                )
            }

            let mapped = FT8ToneMapping.bits(forTone: Int(tone))
            bits.append(mapped.0)
            bits.append(mapped.1)
            bits.append(mapped.2)
        }

        precondition(bits.count == FT8PipelineRecord.channelBitCount)
        return bits
    }

    private static let costasToneIndices: Set<Int> =
        Set(0..<7)
            .union(36..<43)
            .union(72..<79)
}
