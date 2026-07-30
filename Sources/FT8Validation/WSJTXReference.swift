import Foundation

public struct WSJTXExpectedDecode: Equatable, Sendable {
    public let time: String
    public let snrDB: Int
    public let timeOffset: Double
    public let frequencyHz: Int
    public let mode: String
    public let message: String
    public init(time: String, snrDB: Int, timeOffset: Double, frequencyHz: Int, mode: String, message: String) {
        self.time = time; self.snrDB = snrDB; self.timeOffset = timeOffset; self.frequencyHz = frequencyHz; self.mode = mode; self.message = message
    }
}

public enum WSJTXReferenceParser {
    public static func parse(_ text: String) -> [WSJTXExpectedDecode] {
        text.split(whereSeparator: \ .isNewline).compactMap { line in
            let fields = line.split(maxSplits: 5, omittingEmptySubsequences: true, whereSeparator: \ .isWhitespace)
            guard fields.count >= 6, let snr = Int(fields[1]), let dt = Double(fields[2]), let frequency = Int(fields[3]) else { return nil }
            return WSJTXExpectedDecode(time: String(fields[0]), snrDB: snr, timeOffset: dt, frequencyHz: frequency, mode: String(fields[4]), message: String(fields[5]).trimmingCharacters(in: .whitespaces))
        }
    }
    public static func parse(url: URL) throws -> [WSJTXExpectedDecode] { parse(try String(contentsOf: url, encoding: .utf8)) }
}

public struct ValidationTolerance: Equatable, Sendable {
    public var frequencyHz: Double
    public var timeSeconds: Double
    public init(frequencyHz: Double = 12.5, timeSeconds: Double = 0.35) { self.frequencyHz = frequencyHz; self.timeSeconds = timeSeconds }
}

public struct ObservedDecode: Equatable, Sendable {
    public let message: String
    public let frequencyHz: Double
    public let timeOffset: Double
    public let snrDB: Double?
    public init(message: String, frequencyHz: Double, timeOffset: Double, snrDB: Double? = nil) { self.message = message; self.frequencyHz = frequencyHz; self.timeOffset = timeOffset; self.snrDB = snrDB }
}

public struct ValidationComparison: Equatable, Sendable {
    public let matched: Int
    public let missed: [WSJTXExpectedDecode]
    public let unexpected: [ObservedDecode]
    public var detectionRate: Double { let total = matched + missed.count; return total == 0 ? 1 : Double(matched) / Double(total) }
}

public enum ReferenceMatcher {
    public static func compare(expected: [WSJTXExpectedDecode], observed: [ObservedDecode], tolerance: ValidationTolerance = .init()) -> ValidationComparison {
        var remaining = observed
        var matched = 0
        var missed: [WSJTXExpectedDecode] = []
        for item in expected {
            let normalized = normalize(item.message)
            if let index = remaining.indices.min(by: { score(item, remaining[$0], normalized, tolerance) < score(item, remaining[$1], normalized, tolerance) }), score(item, remaining[index], normalized, tolerance).isFinite {
                matched += 1; remaining.remove(at: index)
            } else { missed.append(item) }
        }
        return ValidationComparison(matched: matched, missed: missed, unexpected: remaining)
    }
    private static func score(_ expected: WSJTXExpectedDecode, _ observed: ObservedDecode, _ normalized: String, _ tolerance: ValidationTolerance) -> Double {
        guard normalize(observed.message) == normalized else { return .infinity }
        let df = abs(Double(expected.frequencyHz) - observed.frequencyHz)
        let dt = abs(expected.timeOffset - observed.timeOffset)
        guard df <= tolerance.frequencyHz, dt <= tolerance.timeSeconds else { return .infinity }
        return df / max(tolerance.frequencyHz, 0.001) + dt / max(tolerance.timeSeconds, 0.001)
    }
    private static func normalize(_ message: String) -> String { message.uppercased().split(whereSeparator: \ .isWhitespace).joined(separator: " ") }
}
