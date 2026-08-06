import Foundation

enum RealWAVBitSection: String, Codable, Equatable, Sendable {
    case message
    case crc
    case parity

    static func section(for bitIndex: Int) -> Self {
        switch bitIndex {
        case 0..<77:
            return .message
        case 77..<91:
            return .crc
        default:
            return .parity
        }
    }
}

struct RealWAVBitMismatch: Codable, Equatable, Sendable {
    let bitIndex: Int
    let section: RealWAVBitSection
    let symbolIndex: Int
    let grayBit: Int
    let expected: UInt8
    let actual: UInt8
    let llr: Float?
    let confidence: Float?
}

struct RealWAVBitComparison: Codable, Equatable, Sendable {
    let candidateIndex: Int
    let referenceMessage: String
    let candidateStartTime: Double
    let candidateFrequencyHz: Double
    let referenceTime: Double
    let referenceFrequencyHz: Double

    let totalBits: Int
    let correctBits: Int
    let incorrectBits: Int
    let firstMismatch: Int?
    let lastMismatch: Int?
    let longestMatchingRun: Int

    let messageBitErrors: Int
    let crcBitErrors: Int
    let parityBitErrors: Int
    let mismatches: [RealWAVBitMismatch]
}

struct RealWAVBitComparisonReport: Codable, Equatable, Sendable {
    let recording: String
    let generatedAt: Date
    let comparisons: [RealWAVBitComparison]

    var totalComparisons: Int {
        comparisons.count
    }

    var totalIncorrectBits: Int {
        comparisons.reduce(0) { $0 + $1.incorrectBits }
    }
}
