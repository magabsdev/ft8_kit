import Foundation
import FT8Decoder
import FT8Encoder
import FT8Protocol
@testable import FT8Validation

enum RealWAVBitParityComparatorError: Error, Equatable {
    case invalidDecodedCodewordLength(Int)
    case invalidExpectedCodewordLength(Int)
}

enum RealWAVBitParityComparator {
    static func compare(
        record: FT8PipelineRecord,
        reference: WSJTXExpectedDecode
    ) throws -> RealWAVBitComparison {
        guard record.decodedCodeword.count
                == FT8PipelineRecord.channelBitCount else {
            throw RealWAVBitParityComparatorError
                .invalidDecodedCodewordLength(record.decodedCodeword.count)
        }

        let payload = try FT8MessageCodec.pack(reference.message)
        let messageWithCRC = try FT8CRC.append(to: payload)
        let expectedCodeword = try FT8Encoder.encodeLDPC(messageWithCRC).bits

        guard expectedCodeword.count
                == FT8PipelineRecord.channelBitCount else {
            throw RealWAVBitParityComparatorError
                .invalidExpectedCodewordLength(expectedCodeword.count)
        }

        let actualCodeword = record.decodedCodeword.map { $0 & 1 }
        let expected = expectedCodeword.map { $0 & 1 }

        var mismatches: [RealWAVBitMismatch] = []
        mismatches.reserveCapacity(expected.count)

        var correctBits = 0
        var currentMatchingRun = 0
        var longestMatchingRun = 0

        for bitIndex in expected.indices {
            if expected[bitIndex] == actualCodeword[bitIndex] {
                correctBits += 1
                currentMatchingRun += 1
                longestMatchingRun = max(
                    longestMatchingRun,
                    currentMatchingRun
                )
                continue
            }

            currentMatchingRun = 0
            let llr = record.logLikelihoodRatios.indices.contains(bitIndex)
                ? record.logLikelihoodRatios[bitIndex]
                : nil

            mismatches.append(
                RealWAVBitMismatch(
                    bitIndex: bitIndex,
                    section: RealWAVBitSection.section(for: bitIndex),
                    symbolIndex: bitIndex / 3,
                    grayBit: bitIndex % 3,
                    expected: expected[bitIndex],
                    actual: actualCodeword[bitIndex],
                    llr: llr,
                    confidence: llr.map { abs($0) }
                )
            )
        }

        return RealWAVBitComparison(
            candidateIndex: record.candidateIndex,
            referenceMessage: reference.message,
            candidateStartTime: record.startTime,
            candidateFrequencyHz: Double(record.frequency),
            referenceTime: reference.timeOffset,
            referenceFrequencyHz: Double(reference.frequencyHz),
            totalBits: expected.count,
            correctBits: correctBits,
            incorrectBits: mismatches.count,
            firstMismatch: mismatches.first?.bitIndex,
            lastMismatch: mismatches.last?.bitIndex,
            longestMatchingRun: longestMatchingRun,
            messageBitErrors: mismatches.count {
                $0.section == .message
            },
            crcBitErrors: mismatches.count {
                $0.section == .crc
            },
            parityBitErrors: mismatches.count {
                $0.section == .parity
            },
            mismatches: mismatches
        )
    }

    static func buildReport(
        recording: String,
        records: [FT8PipelineRecord],
        references: [WSJTXExpectedDecode],
        generatedAt: Date = Date()
    ) throws -> RealWAVBitComparisonReport {
        let parityRecords = records
            .filter {
                $0.parityPassed == true
                    && $0.syndromeWeight == 0
                    && $0.decodedCodeword.count
                        == FT8PipelineRecord.channelBitCount
            }
            .sorted { $0.candidateIndex < $1.candidateIndex }

        var comparisons: [RealWAVBitComparison] = []
        comparisons.reserveCapacity(parityRecords.count)

        for record in parityRecords {
            guard let reference = nearestReference(
                to: record,
                references: references
            ) else {
                continue
            }

            comparisons.append(
                try compare(
                    record: record,
                    reference: reference
                )
            )
        }

        return RealWAVBitComparisonReport(
            recording: recording,
            generatedAt: generatedAt,
            comparisons: comparisons
        )
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
        return timeDelta + frequencyDelta / 50.0
    }
}
