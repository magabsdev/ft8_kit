import Foundation

enum RealWAVResidualFailureStage: String, Codable, Sendable {
    case noCandidate
    case candidateAssociation
    case softSymbols
    case ldpc
    case crc
    case messageDecode
    case decoded
    case unknown
}

struct RealWAVResidualCandidateDiagnostic: Codable, Equatable, Sendable {
    let pass: Int
    let candidateIndex: Int
    let startTime: Double
    let frequencyHz: Float
    let timeDelta: Double
    let frequencyDeltaHz: Double
    let normalizedDistance: Double
    let syncScore: Float
    let snrDB: Float
    let candidateConfidence: Float
    let averageSoftSymbolConfidence: Float?
    let ldpcIterations: Int?
    let syndromeWeight: Int?
    let parityPassed: Bool?
    let crcPassed: Bool?
    let decodedText: String?
    let failure: String?
}

struct RealWAVResidualReferenceDiagnostic: Codable, Equatable, Sendable {
    let referenceIndex: Int
    let referenceMessage: String
    let referenceSNRDB: Int
    let referenceTimeOffset: Double
    let referenceFrequencyHz: Int

    let alreadyDecoded: Bool
    let failureStage: RealWAVResidualFailureStage

    let nearestCandidate: RealWAVResidualCandidateDiagnostic?
    let nearbyCandidates: [RealWAVResidualCandidateDiagnostic]

    let tightCandidatePresent: Bool
    let bestSyndromeWeight: Int?
    let bestSoftSymbolConfidence: Float?
    let parityCandidateCount: Int
    let crcCandidateCount: Int
}

struct RealWAVResidualWeakCandidateReport: Codable, Equatable, Sendable {
    let recording: String
    let passAnalysed: Int
    let expectedReferenceCount: Int
    let decodedMessages: [String]
    let remainingReferenceCount: Int
    let passCandidateCount: Int
    let references: [RealWAVResidualReferenceDiagnostic]
}
