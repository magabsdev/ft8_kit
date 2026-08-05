import Foundation

/// Cross-stage consistency failures in a captured FT8 decoder pipeline record.
///
/// `FT8PipelineRecord.validationIssues` validates each stage independently.
/// This validator checks that adjacent stages describe the same candidate.
public enum FT8PipelineConsistencyIssue: String, Codable, Equatable, Sendable {
    case dataTonesDoNotMatchReceivedTones
    case grayMappedBitsDoNotMatchDataTones
    case interleavedBitsDoNotMatchLLRs
    case crcPassedWithoutParity
    case decodedMessageWithoutCRC
    case decodedMessageHasFailureReason
    case rejectedMessageMissingFailureReason
    case decodedMessageMissingConfidence
}

public struct FT8PipelineConsistencyValidator: Sendable {
    public init() {}

    public func issues(
        in record: FT8PipelineRecord
    ) -> [FT8PipelineConsistencyIssue] {
        var issues: [FT8PipelineConsistencyIssue] = []

        validateToneStages(record, into: &issues)
        validateSoftDecisionStages(record, into: &issues)
        validateOutcome(record, into: &issues)

        return issues
    }

    public func isConsistent(_ record: FT8PipelineRecord) -> Bool {
        issues(in: record).isEmpty
    }

    private func validateToneStages(
        _ record: FT8PipelineRecord,
        into issues: inout [FT8PipelineConsistencyIssue]
    ) {
        if record.receivedTones.count == FT8PipelineRecord.receivedToneCount,
           record.dataTones.count == FT8PipelineRecord.dataToneCount,
           let expectedDataTones = try? FT8PipelineRecorder.extractDataTones(
               from: record.receivedTones
           ),
           expectedDataTones != record.dataTones {
            issues.append(.dataTonesDoNotMatchReceivedTones)
        }

        if record.dataTones.count == FT8PipelineRecord.dataToneCount,
           record.grayMappedBits.count == FT8PipelineRecord.channelBitCount,
           let expectedBits = try? FT8PipelineRecorder.mapDataTonesToBits(
               record.dataTones
           ),
           expectedBits != record.grayMappedBits {
            issues.append(.grayMappedBitsDoNotMatchDataTones)
        }
    }

    private func validateSoftDecisionStages(
        _ record: FT8PipelineRecord,
        into issues: inout [FT8PipelineConsistencyIssue]
    ) {
        if record.logLikelihoodRatios.count == FT8PipelineRecord.llrCount,
           record.interleavedBits.count == FT8PipelineRecord.channelBitCount,
           let expectedBits = try? FT8PipelineRecorder.hardDecisions(
               from: record.logLikelihoodRatios
           ),
           expectedBits != record.interleavedBits {
            issues.append(.interleavedBitsDoNotMatchLLRs)
        }
    }

    private func validateOutcome(
        _ record: FT8PipelineRecord,
        into issues: inout [FT8PipelineConsistencyIssue]
    ) {
        let decodedText = record.decodedText?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let hasDecodedMessage = decodedText?.isEmpty == false
        let hasFailureReason = record.failureReason?.isEmpty == false

        if record.crcPassed == true, record.parityPassed == false {
            issues.append(.crcPassedWithoutParity)
        }

        if hasDecodedMessage, record.crcPassed != true {
            issues.append(.decodedMessageWithoutCRC)
        }

        if hasDecodedMessage, hasFailureReason {
            issues.append(.decodedMessageHasFailureReason)
        }

        if !hasDecodedMessage,
           !hasFailureReason,
           record.parityPassed != nil || record.crcPassed != nil {
            issues.append(.rejectedMessageMissingFailureReason)
        }

        if hasDecodedMessage, record.messageConfidence == nil {
            issues.append(.decodedMessageMissingConfidence)
        }
    }
}
