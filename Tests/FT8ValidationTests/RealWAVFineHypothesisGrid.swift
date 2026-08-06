import Foundation

struct RealWAVFineHypothesisPoint: Codable, Equatable {
    let candidateIndex: Int
    let referenceMessage: String
    let detectedTime: Double
    let detectedFrequencyHz: Double
    let referenceTime: Double
    let referenceFrequencyHz: Double
    let timeOffset: Double
    let frequencyOffsetHz: Double
    let trialTime: Double
    let trialFrequencyHz: Double
}

struct RealWAVFineHypothesisCandidate: Codable, Equatable {
    let candidateIndex: Int
    let referenceMessage: String
    let detectedTime: Double
    let detectedFrequencyHz: Double
    let referenceTime: Double
    let referenceFrequencyHz: Double
    let initialTimeDelta: Double
    let initialFrequencyDeltaHz: Double
    let points: [RealWAVFineHypothesisPoint]
}

struct RealWAVFineHypothesisReport: Codable, Equatable {
    let recording: String
    let generatedAt: Date
    let timeRadius: Double
    let timeStep: Double
    let frequencyRadiusHz: Double
    let frequencyStepHz: Double
    let candidates: [RealWAVFineHypothesisCandidate]

    var totalPointCount: Int {
        candidates.reduce(0) { $0 + $1.points.count }
    }
}

enum RealWAVFineHypothesisGrid {
    static let defaultTimeRadius = 0.20
    static let defaultTimeStep = 0.01
    static let defaultFrequencyRadiusHz = 50.0
    static let defaultFrequencyStepHz = 1.5625

    static func build(
        from parityReport: RealWAVParityDiagnosticReport,
        generatedAt: Date = Date(),
        timeRadius: Double = defaultTimeRadius,
        timeStep: Double = defaultTimeStep,
        frequencyRadiusHz: Double = defaultFrequencyRadiusHz,
        frequencyStepHz: Double = defaultFrequencyStepHz,
        maximumInitialTimeDelta: Double = 0.25,
        maximumInitialFrequencyDeltaHz: Double = 75.0
    ) -> RealWAVFineHypothesisReport {
        let safeTimeRadius = sanitisedPositive(timeRadius)
        let safeTimeStep = sanitisedPositive(timeStep)
        let safeFrequencyRadius = sanitisedPositive(frequencyRadiusHz)
        let safeFrequencyStep = sanitisedPositive(frequencyStepHz)

        let timeOffsets = offsets(
            radius: safeTimeRadius,
            step: safeTimeStep
        )
        let frequencyOffsets = offsets(
            radius: safeFrequencyRadius,
            step: safeFrequencyStep
        )

        let candidates = parityReport.candidates.compactMap {
            candidate -> RealWAVFineHypothesisCandidate? in
            guard let reference = candidate.nearestReference,
                  reference.timeDelta <= maximumInitialTimeDelta,
                  reference.frequencyDeltaHz <= maximumInitialFrequencyDeltaHz
            else {
                return nil
            }

            let points = timeOffsets.flatMap { timeOffset in
                frequencyOffsets.map { frequencyOffset in
                    RealWAVFineHypothesisPoint(
                        candidateIndex: candidate.candidateIndex,
                        referenceMessage: reference.message,
                        detectedTime: candidate.startTime,
                        detectedFrequencyHz: candidate.frequency,
                        referenceTime: reference.timeOffset,
                        referenceFrequencyHz: reference.frequencyHz,
                        timeOffset: timeOffset,
                        frequencyOffsetHz: frequencyOffset,
                        trialTime: candidate.startTime + timeOffset,
                        trialFrequencyHz:
                            candidate.frequency + frequencyOffset
                    )
                }
            }

            return RealWAVFineHypothesisCandidate(
                candidateIndex: candidate.candidateIndex,
                referenceMessage: reference.message,
                detectedTime: candidate.startTime,
                detectedFrequencyHz: candidate.frequency,
                referenceTime: reference.timeOffset,
                referenceFrequencyHz: reference.frequencyHz,
                initialTimeDelta: reference.timeDelta,
                initialFrequencyDeltaHz: reference.frequencyDeltaHz,
                points: points
            )
        }
        .sorted { lhs, rhs in
            if lhs.initialFrequencyDeltaHz != rhs.initialFrequencyDeltaHz {
                return lhs.initialFrequencyDeltaHz
                    < rhs.initialFrequencyDeltaHz
            }
            if lhs.initialTimeDelta != rhs.initialTimeDelta {
                return lhs.initialTimeDelta < rhs.initialTimeDelta
            }
            return lhs.candidateIndex < rhs.candidateIndex
        }

        return RealWAVFineHypothesisReport(
            recording: parityReport.recording,
            generatedAt: generatedAt,
            timeRadius: safeTimeRadius,
            timeStep: safeTimeStep,
            frequencyRadiusHz: safeFrequencyRadius,
            frequencyStepHz: safeFrequencyStep,
            candidates: candidates
        )
    }

    static func printSummary(
        _ report: RealWAVFineHypothesisReport
    ) {
        print("Real WAV fine-hypothesis grid:")
        print("  recording: \(report.recording)")
        print("  selected candidates: \(report.candidates.count)")
        print("  trial points: \(report.totalPointCount)")
        print(
            "  time sweep: ±\(report.timeRadius)s"
                + " step=\(report.timeStep)s"
        )
        print(
            "  frequency sweep: ±\(report.frequencyRadiusHz)Hz"
                + " step=\(report.frequencyStepHz)Hz"
        )

        for candidate in report.candidates {
            print(
                "  #\(candidate.candidateIndex + 1)"
                    + " reference=\"\(candidate.referenceMessage)\""
                    + " dt=\(candidate.initialTimeDelta)"
                    + " df=\(candidate.initialFrequencyDeltaHz)"
                    + " points=\(candidate.points.count)"
            )
        }
    }

    static func exportIfRequested(
        _ report: RealWAVFineHypothesisReport,
        fileManager: FileManager = .default,
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) throws {
        if let jsonURL = exportURL(
            variable: "FT8_REAL_WAV_REFINEMENT_JSON",
            environment: environment
        ) {
            try prepareParentDirectory(
                for: jsonURL,
                fileManager: fileManager
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(
                to: jsonURL,
                options: .atomic
            )

            print(
                "Real WAV refinement JSON written to: \(jsonURL.path)"
            )
        }

        if let csvURL = exportURL(
            variable: "FT8_REAL_WAV_REFINEMENT_CSV",
            environment: environment
        ) {
            try prepareParentDirectory(
                for: csvURL,
                fileManager: fileManager
            )
            try csv(report).write(
                to: csvURL,
                atomically: true,
                encoding: .utf8
            )

            print(
                "Real WAV refinement CSV written to: \(csvURL.path)"
            )
        }
    }

    private static func offsets(
        radius: Double,
        step: Double
    ) -> [Double] {
        guard radius > 0, step > 0 else {
            return [0]
        }

        let count = Int((radius / step).rounded(.down))
        var values = (-count...count).map { Double($0) * step }

        if values.first.map({ abs($0 + radius) > 1e-9 }) == true {
            values.insert(-radius, at: 0)
        }
        if values.last.map({ abs($0 - radius) > 1e-9 }) == true {
            values.append(radius)
        }

        return values
            .map { abs($0) < 1e-12 ? 0 : $0 }
            .sorted()
    }

    private static func sanitisedPositive(
        _ value: Double
    ) -> Double {
        value.isFinite && value > 0 ? value : 0
    }

    private static func exportURL(
        variable: String,
        environment: [String: String]
    ) -> URL? {
        guard let rawPath = environment[variable]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty
        else {
            return nil
        }

        let expandedPath =
            NSString(string: rawPath).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath)
    }

    private static func prepareParentDirectory(
        for fileURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private static func csv(
        _ report: RealWAVFineHypothesisReport
    ) -> String {
        var rows = [
            [
                "recording",
                "candidate_index",
                "reference_message",
                "detected_time",
                "detected_frequency_hz",
                "reference_time",
                "reference_frequency_hz",
                "initial_time_delta",
                "initial_frequency_delta_hz",
                "time_offset",
                "frequency_offset_hz",
                "trial_time",
                "trial_frequency_hz"
            ].joined(separator: ",")
        ]

        for candidate in report.candidates {
            for point in candidate.points {
                rows.append(
                    [
                        csvField(report.recording),
                        String(point.candidateIndex),
                        csvField(point.referenceMessage),
                        String(point.detectedTime),
                        String(point.detectedFrequencyHz),
                        String(point.referenceTime),
                        String(point.referenceFrequencyHz),
                        String(candidate.initialTimeDelta),
                        String(candidate.initialFrequencyDeltaHz),
                        String(point.timeOffset),
                        String(point.frequencyOffsetHz),
                        String(point.trialTime),
                        String(point.trialFrequencyHz)
                    ].joined(separator: ",")
                )
            }
        }

        return rows.joined(separator: "\n") + "\n"
    }

    private static func csvField(
        _ value: String
    ) -> String {
        guard value.contains(",")
                || value.contains("\"")
                || value.contains("\n")
        else {
            return value
        }

        return "\"\(value.replacingOccurrences(
            of: "\"",
            with: "\"\""
        ))\""
    }
}
