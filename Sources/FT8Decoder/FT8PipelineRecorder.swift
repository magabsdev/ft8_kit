import Foundation
import FT8DSP

public enum FT8PipelineRecorderError: Error, Equatable, Sendable {
    case invalidReceivedToneCount(actual: Int)
    case invalidDataToneCount(actual: Int)
    case invalidToneValue(index: Int, value: UInt8)
    case invalidMetricCount(symbolIndex: Int, actual: Int)
    case emptyToneMetrics(symbolIndex: Int)
    case invalidLLRCount(actual: Int)
    case nonFiniteLLR(index: Int)
}

/// Captures the detected FT8 tone, hard-bit and soft-bit pipeline for one
/// candidate.
///
/// Checkpoint 7.3.1G records:
/// - all 79 received tones;
/// - the 58 data tones after removing the three Costas blocks;
/// - the 174 hard channel bits obtained through the FT8 inverse Gray map;
/// - the exact 174 LLR values produced by `SoftSymbolExtractor`;
/// - the 174 LDPC-input hard decisions derived from those LLRs;
/// - the 174 corrected LDPC codeword bits;
/// - the 91 information bits and LDPC diagnostics.
///
/// The current decoder has no separate hard-bit permutation between tone
/// mapping and LDPC input. `interleavedBits` therefore records the hard
/// decisions in the exact order supplied to the LDPC decoder.
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

        let extraction = try extractor.extractWithTrace(
            from: spectrogram,
            candidate: candidate
        )

        return try captureReceivedTones(
            candidateIndex: candidateIndex,
            candidate: candidate,
            toneMetrics: toneMetrics,
            logLikelihoodRatios:
                extraction.softSymbols.logLikelihoodRatios
        )
    }

    /// Builds a record from precomputed tone metrics.
    ///
    /// This overload is retained for deterministic tone and Gray-map tests. It
    /// does not fabricate LLRs, so the soft and LDPC-input stages remain empty.
    public func captureReceivedTones(
        candidateIndex: Int,
        candidate: FT8Candidate,
        toneMetrics: [[Float]]
    ) throws -> FT8PipelineRecord {
        try captureReceivedTones(
            candidateIndex: candidateIndex,
            candidate: candidate,
            toneMetrics: toneMetrics,
            logLikelihoodRatios: []
        )
    }

    /// Builds a complete pre-LDPC Checkpoint 7.3.1G record.
    public func captureReceivedTones(
        candidateIndex: Int,
        candidate: FT8Candidate,
        toneMetrics: [[Float]],
        logLikelihoodRatios: [Float]
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
        let interleavedBits = try Self.hardDecisions(
            from: logLikelihoodRatios
        )

        return FT8PipelineRecord(
            candidateIndex: candidateIndex,
            startTime: candidate.startTime,
            frequency: candidate.frequency,
            synchronizerScore: candidate.syncScore,
            receivedTones: receivedTones,
            dataTones: dataTones,
            grayMappedBits: grayMappedBits,
            interleavedBits: interleavedBits,
            logLikelihoodRatios: logLikelihoodRatios
        )
    }

    /// Returns a copy of a pipeline record with the complete LDPC result
    /// attached. The decoder result is already validated by `FT8LDPCDecoder`;
    /// this method only transfers its exact output into the audit snapshot.
    public static func attaching(
        ldpcResult: FT8LDPCResult,
        to record: FT8PipelineRecord
    ) -> FT8PipelineRecord {
        FT8PipelineRecord(
            candidateIndex: record.candidateIndex,
            startTime: record.startTime,
            frequency: record.frequency,
            synchronizerScore: record.synchronizerScore,
            receivedTones: record.receivedTones,
            dataTones: record.dataTones,
            grayMappedBits: record.grayMappedBits,
            interleavedBits: record.interleavedBits,
            logLikelihoodRatios: record.logLikelihoodRatios,
            decodedCodeword: ldpcResult.codeword.bits,
            informationBits: ldpcResult.informationBits.bits,
            ldpcIterations: ldpcResult.iterations,
            parityPassed: ldpcResult.parityPassed,
            crcPassed: ldpcResult.crcPassed,
            syndromeWeight: ldpcResult.syndromeWeight
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

    /// Converts decoder LLRs to hard LDPC-input bits.
    ///
    /// The decoder convention is:
    /// - non-negative LLR -> bit 0
    /// - negative LLR -> bit 1
    ///
    /// An empty array is accepted for incremental diagnostic records.
    public static func hardDecisions(
        from logLikelihoodRatios: [Float]
    ) throws -> [UInt8] {
        guard !logLikelihoodRatios.isEmpty else {
            return []
        }

        guard logLikelihoodRatios.count == FT8PipelineRecord.llrCount else {
            throw FT8PipelineRecorderError.invalidLLRCount(
                actual: logLikelihoodRatios.count
            )
        }

        var bits: [UInt8] = []
        bits.reserveCapacity(FT8PipelineRecord.channelBitCount)

        for (index, llr) in logLikelihoodRatios.enumerated() {
            guard llr.isFinite else {
                throw FT8PipelineRecorderError.nonFiniteLLR(index: index)
            }
            bits.append(llr < 0 ? 1 : 0)
        }

        return bits
    }

    private static let costasToneIndices: Set<Int> =
        Set(0..<7)
            .union(36..<43)
            .union(72..<79)
}
