import Foundation

struct RealWAVSymbolComparisonRow: Codable, Equatable, Sendable {
    let candidateIndex: Int
    let referenceMessage: String
    let dataSymbolIndex: Int
    let receivedSymbolIndex: Int

    let expectedTone: UInt8
    let detectedTone: UInt8
    let toneDelta: Int

    let expectedGrayBits: [UInt8]
    let detectedGrayBits: [UInt8]
    let decodedBits: [UInt8]

    let soft0: Float
    let soft1: Float
    let soft2: Float
    let confidence: Float
}

struct RealWAVSymbolComparisonReport: Codable, Equatable, Sendable {
    let recording: String
    let generatedAt: Date
    let rows: [RealWAVSymbolComparisonRow]

    var candidateCount: Int {
        Set(rows.map(\.candidateIndex)).count
    }

    var symbolCount: Int {
        rows.count
    }

    var toneMatches: Int {
        rows.count { $0.expectedTone == $0.detectedTone }
    }

    var toneMismatches: Int {
        symbolCount - toneMatches
    }
}
