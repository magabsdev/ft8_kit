import Foundation

/// Validation result for one captured FT8 decoder pipeline candidate.
public struct FT8PipelineRecordValidation: Codable, Equatable, Sendable {
    public let candidateIndex: Int
    public let structuralIssues: [FT8PipelineValidationIssue]
    public let consistencyIssues: [FT8PipelineConsistencyIssue]

    public init(
        candidateIndex: Int,
        structuralIssues: [FT8PipelineValidationIssue],
        consistencyIssues: [FT8PipelineConsistencyIssue]
    ) {
        self.candidateIndex = candidateIndex
        self.structuralIssues = structuralIssues
        self.consistencyIssues = consistencyIssues
    }

    public var isValid: Bool {
        structuralIssues.isEmpty && consistencyIssues.isEmpty
    }
}

/// Aggregate validation report for every pipeline record in a decode batch.
///
/// Checkpoint 7.3.1K combines the per-stage structural validation introduced
/// by `FT8PipelineRecord` with the cross-stage consistency validation from
/// Checkpoint 7.3.1J. The result is Codable so audit clients can persist or
/// transport the complete diagnostic outcome without rerunning validation.
public struct FT8PipelineValidationReport: Codable, Equatable, Sendable {
    public let totalRecordCount: Int
    public let structurallyValidRecordCount: Int
    public let consistentRecordCount: Int
    public let fullyValidRecordCount: Int
    public let records: [FT8PipelineRecordValidation]

    public init(
        records pipelineRecords: [FT8PipelineRecord],
        validator: FT8PipelineConsistencyValidator = .init()
    ) {
        let validations = pipelineRecords.map { record in
            FT8PipelineRecordValidation(
                candidateIndex: record.candidateIndex,
                structuralIssues: record.validationIssues,
                consistencyIssues: validator.issues(in: record)
            )
        }

        totalRecordCount = validations.count
        structurallyValidRecordCount = validations.reduce(into: 0) {
            if $1.structuralIssues.isEmpty { $0 += 1 }
        }
        consistentRecordCount = validations.reduce(into: 0) {
            if $1.consistencyIssues.isEmpty { $0 += 1 }
        }
        fullyValidRecordCount = validations.reduce(into: 0) {
            if $1.isValid { $0 += 1 }
        }
        records = validations
    }

    public init(
        batch: FT8DecodeBatch,
        validator: FT8PipelineConsistencyValidator = .init()
    ) {
        self.init(records: batch.pipelineRecords, validator: validator)
    }

    public var invalidRecordCount: Int {
        totalRecordCount - fullyValidRecordCount
    }

    public var isValid: Bool {
        invalidRecordCount == 0
    }
}
