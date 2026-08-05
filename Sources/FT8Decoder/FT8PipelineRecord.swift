import Foundation

/// Immutable diagnostic snapshot of the FT8 symbol pipeline for one candidate.
///
/// This type deliberately contains no decoding logic. It is a transport model
/// used by later diagnostic checkpoints to compare decoder and encoder stages.
public struct FT8PipelineRecord: Codable, Equatable, Sendable {
    public static let receivedToneCount = 79
    public static let dataToneCount = 58
    public static let channelBitCount = 174
    public static let llrCount = 174
    public static let informationBitCount = 91

    public let candidateIndex: Int
    public let startTime: Double
    public let frequency: Float
    public let synchronizerScore: Float
    public let receivedTones: [UInt8]
    public let dataTones: [UInt8]
    public let grayMappedBits: [UInt8]
    public let interleavedBits: [UInt8]
    public let logLikelihoodRatios: [Float]
    public let decodedCodeword: [UInt8]
    public let informationBits: [UInt8]
    public let ldpcIterations: Int?
    public let parityPassed: Bool?
    public let crcPassed: Bool?
    public let syndromeWeight: Int?

    public init(
        candidateIndex: Int,
        startTime: Double,
        frequency: Float,
        synchronizerScore: Float,
        receivedTones: [UInt8] = [],
        dataTones: [UInt8] = [],
        grayMappedBits: [UInt8] = [],
        interleavedBits: [UInt8] = [],
        logLikelihoodRatios: [Float] = [],
        decodedCodeword: [UInt8] = [],
        informationBits: [UInt8] = [],
        ldpcIterations: Int? = nil,
        parityPassed: Bool? = nil,
        crcPassed: Bool? = nil,
        syndromeWeight: Int? = nil
    ) {
        self.candidateIndex = candidateIndex
        self.startTime = startTime
        self.frequency = frequency
        self.synchronizerScore = synchronizerScore
        self.receivedTones = receivedTones
        self.dataTones = dataTones
        self.grayMappedBits = grayMappedBits
        self.interleavedBits = interleavedBits
        self.logLikelihoodRatios = logLikelihoodRatios
        self.decodedCodeword = decodedCodeword
        self.informationBits = informationBits
        self.ldpcIterations = ldpcIterations
        self.parityPassed = parityPassed
        self.crcPassed = crcPassed
        self.syndromeWeight = syndromeWeight
    }

    /// Returns every structural issue currently present in the snapshot.
    ///
    /// Empty arrays are accepted because the record is populated incrementally
    /// across the 7.3.1 checkpoints. A non-empty stage must have its exact FT8
    /// protocol length and valid element values.
    public var validationIssues: [FT8PipelineValidationIssue] {
        var issues: [FT8PipelineValidationIssue] = []

        validateCount(
            receivedTones,
            expected: Self.receivedToneCount,
            stage: .receivedTones,
            into: &issues
        )
        validateCount(
            dataTones,
            expected: Self.dataToneCount,
            stage: .dataTones,
            into: &issues
        )
        validateCount(
            grayMappedBits,
            expected: Self.channelBitCount,
            stage: .grayMappedBits,
            into: &issues
        )
        validateCount(
            interleavedBits,
            expected: Self.channelBitCount,
            stage: .interleavedBits,
            into: &issues
        )
        validateCount(
            logLikelihoodRatios,
            expected: Self.llrCount,
            stage: .logLikelihoodRatios,
            into: &issues
        )
        validateCount(
            decodedCodeword,
            expected: Self.channelBitCount,
            stage: .decodedCodeword,
            into: &issues
        )
        validateCount(
            informationBits,
            expected: Self.informationBitCount,
            stage: .informationBits,
            into: &issues
        )

        if let invalidTone = receivedTones.first(where: { $0 > 7 }) {
            issues.append(
                .invalidTone(stage: .receivedTones, value: invalidTone)
            )
        }

        if let invalidTone = dataTones.first(where: { $0 > 7 }) {
            issues.append(
                .invalidTone(stage: .dataTones, value: invalidTone)
            )
        }

        validateBits(grayMappedBits, stage: .grayMappedBits, into: &issues)
        validateBits(interleavedBits, stage: .interleavedBits, into: &issues)
        validateBits(decodedCodeword, stage: .decodedCodeword, into: &issues)
        validateBits(informationBits, stage: .informationBits, into: &issues)

        if logLikelihoodRatios.contains(where: { !$0.isFinite }) {
            issues.append(.nonFiniteLLR)
        }

        if let ldpcIterations, ldpcIterations < 0 {
            issues.append(
                .invalidDiagnosticValue(
                    field: .ldpcIterations,
                    value: ldpcIterations
                )
            )
        }

        if let syndromeWeight, syndromeWeight < 0 {
            issues.append(
                .invalidDiagnosticValue(
                    field: .syndromeWeight,
                    value: syndromeWeight
                )
            )
        }

        return issues
    }

    public var isStructurallyValid: Bool {
        validationIssues.isEmpty
    }

    private func validateCount<T>(
        _ values: [T],
        expected: Int,
        stage: FT8PipelineStage,
        into issues: inout [FT8PipelineValidationIssue]
    ) {
        guard !values.isEmpty, values.count != expected else {
            return
        }

        issues.append(
            .incorrectCount(
                stage: stage,
                expected: expected,
                actual: values.count
            )
        )
    }

    private func validateBits(
        _ bits: [UInt8],
        stage: FT8PipelineStage,
        into issues: inout [FT8PipelineValidationIssue]
    ) {
        if let invalidBit = bits.first(where: { $0 > 1 }) {
            issues.append(.invalidBit(stage: stage, value: invalidBit))
        }
    }
}

public enum FT8PipelineStage: String, Codable, Equatable, Sendable {
    case receivedTones
    case dataTones
    case grayMappedBits
    case interleavedBits
    case logLikelihoodRatios
    case decodedCodeword
    case informationBits
}

public enum FT8PipelineDiagnosticField:
    String,
    Codable,
    Equatable,
    Sendable
{
    case ldpcIterations
    case syndromeWeight
}

public enum FT8PipelineValidationIssue: Codable, Equatable, Sendable {
    case incorrectCount(
        stage: FT8PipelineStage,
        expected: Int,
        actual: Int
    )
    case invalidTone(stage: FT8PipelineStage, value: UInt8)
    case invalidBit(stage: FT8PipelineStage, value: UInt8)
    case nonFiniteLLR
    case invalidDiagnosticValue(
        field: FT8PipelineDiagnosticField,
        value: Int
    )
}
