import Foundation

public struct FT8DecodeStageTimingWriter: Sendable {
    public init() {}

    public func write(
        _ timings: FT8DecodeStageTimings,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try encoder.encode(timings).write(
            to: directory.appendingPathComponent(
                "decode-stage-timings.json"
            ),
            options: .atomic
        )

        try csv(timings).write(
            to: directory.appendingPathComponent(
                "decode-stage-timings.csv"
            ),
            atomically: true,
            encoding: .utf8
        )
    }

    public func csv(
        _ timings: FT8DecodeStageTimings
    ) -> String {
        let header = [
            "stage",
            "seconds",
            "share_of_measured_time"
        ].joined(separator: ",")

        let total = timings.measuredSeconds
        let rows = FT8DecodeStage.allCases.map { stage in
            let seconds = timings.seconds(for: stage)
            let share = total > 0 ? seconds / total : 0
            return [
                stage.rawValue,
                String(seconds),
                String(share)
            ].joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n") + "\n"
    }
}
