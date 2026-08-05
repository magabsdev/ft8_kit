import Foundation
import FT8Decoder
import FT8Encoder
import FT8Protocol

struct FT8ReferenceExpectation: Codable, Equatable {
    let message: String
    let frequencyHz: Double?
    let timeSeconds: Double?
}

struct FT8ReferenceCandidateComparison: Codable, Equatable {
    let message: String
    let candidateIndex: Int
    let startTime: Double
    let frequencyHz: Float
    let timeErrorSeconds: Double?
    let frequencyErrorHz: Double?
    let comparedSymbols: Int
    let toneErrors: Int
    let firstToneError: Int?
    let comparedBits: Int
    let bitErrors: Int
    let firstBitError: Int?
    let llrRootMeanSquare: Double
    let parityPassed: Bool?
    let crcPassed: Bool?
    let decodedText: String?
    let score: Double
}

struct FT8ReferenceComparisonReport: Codable, Equatable {
    let generatedAt: Date
    let expectations: [FT8ReferenceExpectation]
    let bestMatches: [FT8ReferenceCandidateComparison]
    let allComparisons: [FT8ReferenceCandidateComparison]
}

struct FT8ReferenceComparator {
    func compare(
        traces: [FT8CandidateTrace],
        expectations: [FT8ReferenceExpectation]
    ) throws -> FT8ReferenceComparisonReport {
        var all: [FT8ReferenceCandidateComparison] = []
        var best: [FT8ReferenceCandidateComparison] = []

        for expectation in expectations {
            let reference = try makeReference(expectation.message)
            let comparisons = traces.map {
                compare(
                    trace: $0,
                    expectation: expectation,
                    expectedDataTones: reference.dataTones,
                    expectedBits: reference.codewordBits
                )
            }.sorted { $0.score < $1.score }

            all.append(contentsOf: comparisons)
            if let first = comparisons.first {
                best.append(first)
            }
        }

        return FT8ReferenceComparisonReport(
            generatedAt: Date(),
            expectations: expectations,
            bestMatches: best,
            allComparisons: all
        )
    }

    func write(
        _ report: FT8ReferenceComparisonReport,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try encoder.encode(report).write(
            to: directory.appendingPathComponent("comparison.json"),
            options: .atomic
        )

        try comparisonsCSV(report.allComparisons).write(
            to: directory.appendingPathComponent("candidate-ranking.csv"),
            atomically: true,
            encoding: .utf8
        )

        try comparisonsCSV(report.bestMatches).write(
            to: directory.appendingPathComponent("best-matches.csv"),
            atomically: true,
            encoding: .utf8
        )
    }

    func printSummary(_ report: FT8ReferenceComparisonReport) {
        for match in report.bestMatches {
            print("Reference: \(match.message)")
            print("  Candidate:          \(match.candidateIndex)")
            print("  Tone errors:        \(match.toneErrors) / \(match.comparedSymbols)")
            print("  First tone error:   \(match.firstToneError.map { String($0) } ?? "none")")
            print("  Bit errors:         \(match.bitErrors) / \(match.comparedBits)")
            print("  First bit error:    \(match.firstBitError.map { String($0) } ?? "none")")
            print(String(format: "  Score:              %.3f", match.score))
        }
    }

    private func makeReference(
        _ message: String
    ) throws -> (dataTones: [UInt8], codewordBits: [UInt8]) {
        let payload = try FT8MessageCodec.pack(message)
        let messageWithCRC = try FT8CRC.append(to: payload)
        let codeword = try FT8Encoder.encodeLDPC(messageWithCRC)
        let tones = try FT8Encoder.encode(text: message)

        let dataTones = (0..<79)
            .filter { !Self.costasToneIndices.contains($0) }
            .map { tones[$0] }

        return (dataTones, codeword.bits)
    }

    private func compare(
        trace: FT8CandidateTrace,
        expectation: FT8ReferenceExpectation,
        expectedDataTones: [UInt8],
        expectedBits: [UInt8]
    ) -> FT8ReferenceCandidateComparison {
        let observedTones = trace.symbols.map { symbol -> UInt8 in
            UInt8(
                symbol.toneMetrics.enumerated().max {
                    $0.element < $1.element
                }?.offset ?? 0
            )
        }

        let symbolCount = min(observedTones.count, expectedDataTones.count)
        let toneDifferences = (0..<symbolCount).filter {
            observedTones[$0] != expectedDataTones[$0]
        }

        let observedBits = trace.logLikelihoodRatios.map {
            UInt8($0 >= 0 ? 1 : 0)
        }

        let bitCount = min(observedBits.count, expectedBits.count)
        let bitDifferences = (0..<bitCount).filter {
            observedBits[$0] != expectedBits[$0]
        }

        let llrRMS: Double
        if trace.logLikelihoodRatios.isEmpty {
            llrRMS = 0
        } else {
            let sum = trace.logLikelihoodRatios.reduce(0.0) {
                $0 + Double($1 * $1)
            }
            llrRMS = sqrt(sum / Double(trace.logLikelihoodRatios.count))
        }

        let timeError = expectation.timeSeconds.map {
            abs(trace.startTime - $0)
        }
        let frequencyError = expectation.frequencyHz.map {
            abs(Double(trace.frequency) - $0)
        }

        let score =
            Double(toneDifferences.count) * 6
            + Double(bitDifferences.count)
            + (timeError ?? 0) * 5
            + (frequencyError ?? 0) * 0.1
            + ((trace.crcPassed ?? false) ? -100 : 0)
            + ((trace.parityPassed ?? false) ? -10 : 0)

        return FT8ReferenceCandidateComparison(
            message: expectation.message,
            candidateIndex: trace.candidateIndex,
            startTime: trace.startTime,
            frequencyHz: trace.frequency,
            timeErrorSeconds: timeError,
            frequencyErrorHz: frequencyError,
            comparedSymbols: symbolCount,
            toneErrors: toneDifferences.count,
            firstToneError: toneDifferences.first,
            comparedBits: bitCount,
            bitErrors: bitDifferences.count,
            firstBitError: bitDifferences.first,
            llrRootMeanSquare: llrRMS,
            parityPassed: trace.parityPassed,
            crcPassed: trace.crcPassed,
            decodedText: trace.decodedText,
            score: score
        )
    }

    private func comparisonsCSV(
        _ comparisons: [FT8ReferenceCandidateComparison]
    ) -> String {
        var rows = [
            "message,candidate_index,start_time_seconds,frequency_hz,time_error_seconds,frequency_error_hz,compared_symbols,tone_errors,first_tone_error,compared_bits,bit_errors,first_bit_error,llr_rms,parity_passed,crc_passed,decoded_text,score"
        ]

        for item in comparisons {
            rows.append([
                quote(item.message),
                String(item.candidateIndex),
                String(item.startTime),
                String(item.frequencyHz),
                optional(item.timeErrorSeconds),
                optional(item.frequencyErrorHz),
                String(item.comparedSymbols),
                String(item.toneErrors),
                optional(item.firstToneError),
                String(item.comparedBits),
                String(item.bitErrors),
                optional(item.firstBitError),
                String(item.llrRootMeanSquare),
                optional(item.parityPassed),
                optional(item.crcPassed),
                quote(item.decodedText ?? ""),
                String(item.score)
            ].joined(separator: ","))
        }

        return rows.joined(separator: "\n") + "\n"
    }

    private func optional<T>(_ value: T?) -> String {
        value.map { String(describing: $0) } ?? ""
    }

    private func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static let costasToneIndices: Set<Int> =
        Set(0..<7).union(36..<43).union(72..<79)
}
