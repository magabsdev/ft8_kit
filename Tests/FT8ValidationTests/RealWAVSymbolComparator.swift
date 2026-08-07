import Foundation
import FT8Decoder
import FT8Encoder
import FT8Protocol
@testable import FT8Validation

enum RealWAVSymbolComparatorError: Error, Equatable {
    case invalidExpectedToneCount(Int)
    case invalidDetectedToneCount(Int)
    case invalidLLRCount(Int)
    case invalidDecodedBitCount(Int)
}

enum RealWAVSymbolComparator {
    static func buildReport(
        recording: String,
        records: [FT8PipelineRecord],
        references: [WSJTXExpectedDecode],
        generatedAt: Date = Date()
    ) -> RealWAVSymbolComparisonReport {
        var rows: [RealWAVSymbolComparisonRow] = []

        for record in records
            .filter({
                $0.receivedTones.count == FT8PipelineRecord.receivedToneCount
                    && $0.dataTones.count == FT8PipelineRecord.dataToneCount
                    && $0.logLikelihoodRatios.count == FT8PipelineRecord.llrCount
                    && $0.interleavedBits.count == FT8PipelineRecord.channelBitCount
            })
            .sorted(by: { $0.candidateIndex < $1.candidateIndex }) {
            guard let reference = nearestReference(
                to: record,
                references: references
            ) else {
                continue
            }

            do {
                rows.append(
                    contentsOf: try compare(
                        record: record,
                        reference: reference
                    )
                )
            } catch {
                print(
                    "Skipping real-WAV symbol comparison for candidate "
                        + "#\(record.candidateIndex + 1): "
                        + "reference=\"\(reference.message)\" error=\(error)"
                )
            }
        }

        return RealWAVSymbolComparisonReport(
            recording: recording,
            generatedAt: generatedAt,
            rows: rows
        )
    }

    static func compare(
        record: FT8PipelineRecord,
        reference: WSJTXExpectedDecode
    ) throws -> [RealWAVSymbolComparisonRow] {
        let protocolMessage = referenceProtocolMessage(reference.message)
        let expectedReceivedTones = try FT8Encoder.encode(protocolMessage)

        guard expectedReceivedTones.count
                == FT8PipelineRecord.receivedToneCount else {
            throw RealWAVSymbolComparatorError.invalidExpectedToneCount(
                expectedReceivedTones.count
            )
        }

        guard record.dataTones.count
                == FT8PipelineRecord.dataToneCount else {
            throw RealWAVSymbolComparatorError.invalidDetectedToneCount(
                record.dataTones.count
            )
        }

        guard record.logLikelihoodRatios.count
                == FT8PipelineRecord.llrCount else {
            throw RealWAVSymbolComparatorError.invalidLLRCount(
                record.logLikelihoodRatios.count
            )
        }

        guard record.interleavedBits.count
                == FT8PipelineRecord.channelBitCount else {
            throw RealWAVSymbolComparatorError.invalidDecodedBitCount(
                record.interleavedBits.count
            )
        }

        let expectedDataTones = try FT8PipelineRecorder.extractDataTones(
            from: expectedReceivedTones
        )
        let receivedIndices = dataReceivedSymbolIndices

        var rows: [RealWAVSymbolComparisonRow] = []
        rows.reserveCapacity(FT8PipelineRecord.dataToneCount)

        for dataSymbolIndex in 0..<FT8PipelineRecord.dataToneCount {
            let bitOffset = dataSymbolIndex * 3
            let expectedTone = expectedDataTones[dataSymbolIndex]
            let detectedTone = record.dataTones[dataSymbolIndex]
            let expectedBits = bits(for: expectedTone)
            let detectedBits = bits(for: detectedTone)
            let decodedBits = Array(
                record.interleavedBits[bitOffset..<(bitOffset + 3)]
            )
            let soft = Array(
                record.logLikelihoodRatios[bitOffset..<(bitOffset + 3)]
            )

            rows.append(
                RealWAVSymbolComparisonRow(
                    candidateIndex: record.candidateIndex,
                    referenceMessage: protocolMessage.displayText,
                    dataSymbolIndex: dataSymbolIndex,
                    receivedSymbolIndex: receivedIndices[dataSymbolIndex],
                    expectedTone: expectedTone,
                    detectedTone: detectedTone,
                    toneDelta: Int(detectedTone) - Int(expectedTone),
                    expectedGrayBits: expectedBits,
                    detectedGrayBits: detectedBits,
                    decodedBits: decodedBits,
                    soft0: soft[0],
                    soft1: soft[1],
                    soft2: soft[2],
                    confidence: (
                        abs(soft[0]) + abs(soft[1]) + abs(soft[2])
                    ) / 3
                )
            )
        }

        return rows
    }

    private static func bits(for tone: UInt8) -> [UInt8] {
        let mapped = FT8ToneMapping.bits(forTone: Int(tone))
        return [mapped.0, mapped.1, mapped.2]
    }

    private static let dataReceivedSymbolIndices: [Int] = {
        (0..<FT8PipelineRecord.receivedToneCount).filter {
            !(0..<7).contains($0)
                && !(36..<43).contains($0)
                && !(72..<79).contains($0)
        }
    }()

    private static func referenceProtocolMessage(
        _ rawMessage: String
    ) -> FT8Message {
        let protocolText = stripWSJTXAnnotation(from: rawMessage)
        let fields = protocolText
            .uppercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        if fields.count == 3 {
            return .standard(
                to: fields[0],
                from: fields[1],
                extra: fields[2]
            )
        }

        if fields.count == 4, fields[0] == "CQ" {
            return .standard(
                to: "CQ \(fields[1])",
                from: fields[2],
                extra: fields[3]
            )
        }

        return .freeText(fields.joined(separator: " "))
    }

    private static func stripWSJTXAnnotation(
        from message: String
    ) -> String {
        let trimmed = message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard let range = trimmed.range(
            of: #"\s{2,}"#,
            options: .regularExpression
        ) else {
            return trimmed
        }

        return String(trimmed[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nearestReference(
        to record: FT8PipelineRecord,
        references: [WSJTXExpectedDecode]
    ) -> WSJTXExpectedDecode? {
        references.min { lhs, rhs in
            associationScore(lhs, record: record)
                < associationScore(rhs, record: record)
        }
    }

    private static func associationScore(
        _ reference: WSJTXExpectedDecode,
        record: FT8PipelineRecord
    ) -> Double {
        let timeDelta = abs(reference.timeOffset - record.startTime)
        let frequencyDelta = abs(
            Double(reference.frequencyHz) - Double(record.frequency)
        )
        return timeDelta + frequencyDelta / 50
    }
}
