import Foundation
import FT8Decoder
import FT8Protocol
@testable import FT8Validation

struct RealWAVParityDiagnosticReport: Codable, Equatable {
    let recording: String
    let generatedAt: Date
    let paritySuccessCount: Int
    let candidates: [RealWAVParityCandidateDiagnostic]
}

struct RealWAVParityCandidateDiagnostic: Codable, Equatable {
    let candidateIndex: Int
    let startTime: Double
    let frequency: Float
    let synchronizerScore: Float
    let syndromeWeight: Int?
    let decodedCodewordBits: String
    let informationBits: String
    let payloadBits: String
    let receivedCRCBits: String
    let calculatedCRCBits: String?
    let nativeCRCValid: Bool
    let hypotheses: [RealWAVBitHypothesisDiagnostic]
    let nearestReference: RealWAVReferenceAssociation?
}

struct RealWAVBitHypothesisDiagnostic: Codable, Equatable {
    let name: String
    let crcValid: Bool
    let payloadBits: String
    let receivedCRCBits: String
    let calculatedCRCBits: String?
}

struct RealWAVReferenceAssociation: Codable, Equatable {
    let message: String
    let timeOffset: Double
    let frequencyHz: Double
    let timeDelta: Double
    let frequencyDeltaHz: Double
}

enum RealWAVParityDiagnostics {
    static func build(
        recording: String,
        records: [FT8PipelineRecord],
        expected: [WSJTXExpectedDecode],
        generatedAt: Date = Date()
    ) -> RealWAVParityDiagnosticReport {
        let candidates = records
            .filter {
                $0.parityPassed == true
                    && $0.syndromeWeight == 0
                    && $0.decodedCodeword.count
                        == FT8PipelineRecord.channelBitCount
                    && $0.informationBits.count
                        == FT8PipelineRecord.informationBitCount
            }
            .sorted { $0.candidateIndex < $1.candidateIndex }
            .map {
                candidateDiagnostic(
                    record: $0,
                    expected: expected
                )
            }

        return RealWAVParityDiagnosticReport(
            recording: recording,
            generatedAt: generatedAt,
            paritySuccessCount: candidates.count,
            candidates: candidates
        )
    }

    static func write(
        _ report: RealWAVParityDiagnosticReport,
        jsonURL: URL?,
        csvURL: URL?
    ) throws {
        if let jsonURL {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(
                to: jsonURL,
                options: .atomic
            )
        }

        if let csvURL {
            try csv(report).write(
                to: csvURL,
                atomically: true,
                encoding: .utf8
            )
        }
    }

    static func printSummary(
        _ report: RealWAVParityDiagnosticReport
    ) {
        print("Real WAV parity/CRC diagnostics:")
        print("  recording: \(report.recording)")
        print("  zero-syndrome candidates: \(report.paritySuccessCount)")

        for candidate in report.candidates {
            print(
                "  #\(candidate.candidateIndex + 1)"
                    + " time=\(candidate.startTime)"
                    + " frequency=\(candidate.frequency)"
                    + " nativeCRC=\(candidate.nativeCRCValid)"
                    + " receivedCRC=\(candidate.receivedCRCBits)"
                    + " calculatedCRC=\(candidate.calculatedCRCBits ?? "n/a")"
            )

            if let reference = candidate.nearestReference {
                print(
                    "    nearest=\"\(reference.message)\""
                        + " dt=\(reference.timeDelta)"
                        + " df=\(reference.frequencyDeltaHz)"
                )
            }

            let passing = candidate.hypotheses
                .filter(\.crcValid)
                .map(\.name)

            print(
                "    passing hypotheses: "
                    + (passing.isEmpty ? "none" : passing.joined(separator: ", "))
            )
        }
    }

    private static func candidateDiagnostic(
        record: FT8PipelineRecord,
        expected: [WSJTXExpectedDecode]
    ) -> RealWAVParityCandidateDiagnostic {
        let information = normalisedBits(record.informationBits)
        let payload = Array(information.prefix(77))
        let receivedCRC = Array(information.dropFirst(77).prefix(14))
        let calculatedCRC = calculatedCRCBits(payload: payload)

        let hypotheses = [
            hypothesis(name: "native", information: information),
            hypothesis(
                name: "inverted-all-bits",
                information: information.map { $0 ^ 1 }
            ),
            hypothesis(
                name: "reversed-information-bits",
                information: Array(information.reversed())
            ),
            hypothesis(
                name: "reversed-payload-bits",
                information: Array(payload.reversed()) + receivedCRC
            ),
            hypothesis(
                name: "reversed-crc-bits",
                information: payload + Array(receivedCRC.reversed())
            ),
            hypothesis(
                name: "reversed-payload-and-crc-bits",
                information:
                    Array(payload.reversed())
                    + Array(receivedCRC.reversed())
            )
        ]

        return RealWAVParityCandidateDiagnostic(
            candidateIndex: record.candidateIndex,
            startTime: record.startTime,
            frequency: record.frequency,
            synchronizerScore: record.synchronizerScore,
            syndromeWeight: record.syndromeWeight,
            decodedCodewordBits: bitString(record.decodedCodeword),
            informationBits: bitString(information),
            payloadBits: bitString(payload),
            receivedCRCBits: bitString(receivedCRC),
            calculatedCRCBits: calculatedCRC.map(bitString),
            nativeCRCValid: crcValid(information),
            hypotheses: hypotheses,
            nearestReference: nearestReference(
                to: record,
                expected: expected
            )
        )
    }

    private static func hypothesis(
        name: String,
        information: [UInt8]
    ) -> RealWAVBitHypothesisDiagnostic {
        let bits = normalisedBits(information)
        let payload = Array(bits.prefix(77))
        let receivedCRC = Array(bits.dropFirst(77).prefix(14))

        return RealWAVBitHypothesisDiagnostic(
            name: name,
            crcValid: crcValid(bits),
            payloadBits: bitString(payload),
            receivedCRCBits: bitString(receivedCRC),
            calculatedCRCBits: calculatedCRCBits(payload: payload)
                .map(bitString)
        )
    }

    private static func crcValid(_ information: [UInt8]) -> Bool {
        guard information.count == 91 else {
            return false
        }

        return FT8CRC.validate(FT8BitBuffer(information))
    }

    private static func calculatedCRCBits(
        payload: [UInt8]
    ) -> [UInt8]? {
        guard payload.count == 77,
              let protected = try? FT8CRC.append(
                to: FT8BitBuffer(payload)
              ) else {
            return nil
        }

        return Array(protected.bits.suffix(14))
    }

    private static func nearestReference(
        to record: FT8PipelineRecord,
        expected: [WSJTXExpectedDecode]
    ) -> RealWAVReferenceAssociation? {
        var bestAssociation: RealWAVReferenceAssociation?
        var bestScore = Double.greatestFiniteMagnitude

        for reference in expected {
            let referenceFrequency = Double(reference.frequencyHz)
            let timeDelta = abs(reference.timeOffset - record.startTime)
            let frequencyDelta = abs(
                referenceFrequency - Double(record.frequency)
            )
            let score = timeDelta + frequencyDelta / 50.0

            if score < bestScore {
                bestScore = score
                bestAssociation = RealWAVReferenceAssociation(
                    message: reference.message,
                    timeOffset: reference.timeOffset,
                    frequencyHz: referenceFrequency,
                    timeDelta: timeDelta,
                    frequencyDeltaHz: frequencyDelta
                )
            }
        }

        return bestAssociation
    }

    private static func normalisedBits(
        _ bits: [UInt8]
    ) -> [UInt8] {
        bits.map { $0 & 1 }
    }

    private static func bitString(
        _ bits: [UInt8]
    ) -> String {
        bits.map(String.init).joined()
    }

    private static func csv(
        _ report: RealWAVParityDiagnosticReport
    ) -> String {
        var rows = [
            [
                "recording",
                "candidate_index",
                "start_time",
                "frequency",
                "synchronizer_score",
                "syndrome_weight",
                "native_crc_valid",
                "payload_bits",
                "received_crc_bits",
                "calculated_crc_bits",
                "nearest_message",
                "nearest_time_delta",
                "nearest_frequency_delta_hz",
                "passing_hypotheses"
            ].joined(separator: ",")
        ]

        for candidate in report.candidates {
            let passing = candidate.hypotheses
                .filter(\.crcValid)
                .map(\.name)
                .joined(separator: "|")

            rows.append(
                [
                    csvField(report.recording),
                    String(candidate.candidateIndex),
                    String(candidate.startTime),
                    String(candidate.frequency),
                    String(candidate.synchronizerScore),
                    candidate.syndromeWeight.map(String.init) ?? "",
                    String(candidate.nativeCRCValid),
                    candidate.payloadBits,
                    candidate.receivedCRCBits,
                    candidate.calculatedCRCBits ?? "",
                    csvField(candidate.nearestReference?.message ?? ""),
                    candidate.nearestReference
                        .map { String($0.timeDelta) } ?? "",
                    candidate.nearestReference
                        .map { String($0.frequencyDeltaHz) } ?? "",
                    csvField(passing)
                ].joined(separator: ",")
            )
        }

        return rows.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",")
                || value.contains("\"")
                || value.contains("\n") else {
            return value
        }

        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
