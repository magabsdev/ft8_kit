import Foundation

/// Persists a pipeline validation report independently of the full decoder
/// audit bundle.
///
/// Checkpoint 7.3.1L provides both a lossless JSON representation and a compact
/// per-candidate CSV representation suitable for spreadsheets and CI artifacts.
public struct FT8PipelineValidationReportWriter: Sendable {
    public init() {}

    public func write(
        report: FT8PipelineValidationReport,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(
            to: directory.appendingPathComponent("pipeline-validation.json"),
            options: .atomic
        )

        try csv(report).write(
            to: directory.appendingPathComponent("pipeline-validation.csv"),
            atomically: true,
            encoding: .utf8
        )
    }

    public func write(
        batch: FT8DecodeBatch,
        to directory: URL,
        validator: FT8PipelineConsistencyValidator = .init()
    ) throws {
        try write(
            report: FT8PipelineValidationReport(
                batch: batch,
                validator: validator
            ),
            to: directory
        )
    }

    public func csv(_ report: FT8PipelineValidationReport) -> String {
        var rows = [
            "candidate_index,structural_issue_count,consistency_issue_count,is_valid,structural_issues,consistency_issues"
        ]

        for record in report.records {
            rows.append([
                String(record.candidateIndex),
                String(record.structuralIssues.count),
                String(record.consistencyIssues.count),
                String(record.isValid),
                quoted(
                    record.structuralIssues
                        .map { String(describing: $0) }
                        .joined(separator: "|")
                ),
                quoted(
                    record.consistencyIssues
                        .map(\.rawValue)
                        .joined(separator: "|")
                )
            ].joined(separator: ","))
        }

        return rows.joined(separator: "\n") + "\n"
    }

    private func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
