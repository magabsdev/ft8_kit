import Foundation

enum RealWAVCandidateAssociationClassification: String, Codable, Sendable {
    case matched
    case nearMatch
    case unassociated
}

struct RealWAVReferenceAssociationConfiguration: Codable, Equatable, Sendable {
    var matchedTimeTolerance: Double = 0.25
    var matchedFrequencyToleranceHz: Double = 100
    var nearTimeTolerance: Double = 0.50
    var nearFrequencyToleranceHz: Double = 250
    var confidenceWeight: Double = 0.10

    static let `default` = Self()
}

struct RealWAVReferenceDescriptor: Codable, Equatable, Sendable {
    let referenceIndex: Int
    let time: String
    let snrDB: Int
    let timeOffset: Double
    let frequencyHz: Int
    let mode: String
    let message: String
}

struct RealWAVCandidateDescriptor: Codable, Equatable, Sendable {
    let candidateIndex: Int
    let startTime: Double
    let frequencyHz: Float
    let synchronizerScore: Float
}

struct RealWAVReferenceCandidateDistance: Codable, Equatable, Sendable {
    let referenceIndex: Int
    let candidateIndex: Int
    let referenceMessage: String
    let referenceTimeOffset: Double
    let referenceFrequencyHz: Int
    let candidateStartTime: Double
    let candidateFrequencyHz: Float
    let synchronizerScore: Float
    let timeDelta: Double
    let frequencyDeltaHz: Double
    let normalisedDistance: Double
    let eligibleForMatched: Bool
    let eligibleForNearMatch: Bool
}

struct RealWAVPrimaryAssociation: Codable, Equatable, Sendable {
    let referenceIndex: Int
    let candidateIndex: Int
    let referenceMessage: String
    let timeDelta: Double
    let frequencyDeltaHz: Double
    let synchronizerScore: Float
    let normalisedDistance: Double
}

struct RealWAVCandidateAssociation: Codable, Equatable, Sendable {
    let candidateIndex: Int
    let classification: RealWAVCandidateAssociationClassification
    let primaryReferenceIndex: Int?
    let nearestReferenceIndex: Int?
    let nearestReferenceMessage: String?
    let timeDelta: Double?
    let frequencyDeltaHz: Double?
    let synchronizerScore: Float
}

struct RealWAVReferenceAssociationReport: Codable, Equatable, Sendable {
    let recording: String
    let generatedAt: Date
    let configuration: RealWAVReferenceAssociationConfiguration
    let references: [RealWAVReferenceDescriptor]
    let candidates: [RealWAVCandidateDescriptor]
    let distanceMatrix: [RealWAVReferenceCandidateDistance]
    let primaryAssociations: [RealWAVPrimaryAssociation]
    let candidateAssociations: [RealWAVCandidateAssociation]

    var referenceCount: Int { references.count }
    var candidateCount: Int { candidates.count }

    var matchedCount: Int {
        candidateAssociations.count { $0.classification == .matched }
    }

    var nearMatchCount: Int {
        candidateAssociations.count { $0.classification == .nearMatch }
    }

    var unassociatedCount: Int {
        candidateAssociations.count { $0.classification == .unassociated }
    }

    var unmatchedReferenceCount: Int {
        referenceCount - primaryAssociations.count
    }

    var matchedCandidateIndices: Set<Int> {
        Set(primaryAssociations.map(\.candidateIndex))
    }
}
