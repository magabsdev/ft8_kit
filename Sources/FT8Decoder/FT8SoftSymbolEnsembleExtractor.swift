import Foundation
import FT8DSP

public struct FT8SoftSymbolProfile: Equatable, Sendable {
    public let name: String
    public let configuration: SoftSymbolConfiguration

    public init(
        name: String,
        configuration: SoftSymbolConfiguration
    ) {
        self.name = name
        self.configuration = configuration
    }
}

public struct FT8SoftSymbolVariant: Equatable, Sendable {
    public let profileName: String
    public let softSymbols: FT8SoftSymbols

    public init(
        profileName: String,
        softSymbols: FT8SoftSymbols
    ) {
        self.profileName = profileName
        self.softSymbols = softSymbols
    }
}

/// Produces a bounded set of soft-symbol interpretations for one synchronized
/// FT8 candidate. The ensemble remains at four profiles; this checkpoint
/// changes the weak-signal likelihood model rather than widening the search.
public struct FT8SoftSymbolEnsembleExtractor: Sendable {
    public var profiles: [FT8SoftSymbolProfile]

    public init(
        profiles: [FT8SoftSymbolProfile] = Self.productionProfiles
    ) {
        self.profiles = profiles
    }

    public static let productionProfiles: [FT8SoftSymbolProfile] = [
        FT8SoftSymbolProfile(
            name: "wsjtx-amplitude",
            configuration: SoftSymbolConfiguration(
                integrationRadius: 0,
                timeIntegrationRadius: 0,
                minimumObservationsPerSymbol: 1,
                llrScale: 1,
                llrLimit: 24,
                metricMode: .wsjtxNormalizedMaxAmplitude
            )
        ),
        FT8SoftSymbolProfile(
            name: "balanced",
            configuration: SoftSymbolConfiguration(
                integrationRadius: 0,
                timeIntegrationRadius: 1,
                minimumObservationsPerSymbol: 1,
                llrScale: 1,
                llrLimit: 24,
                metricMode: .logMAP
            )
        ),
        FT8SoftSymbolProfile(
            name: "frequency-integrated",
            configuration: SoftSymbolConfiguration(
                integrationRadius: 1,
                timeIntegrationRadius: 1,
                minimumObservationsPerSymbol: 1,
                llrScale: 1,
                llrLimit: 24,
                metricMode: .logMAP
            )
        ),
        FT8SoftSymbolProfile(
            name: "temporal-integrated",
            configuration: SoftSymbolConfiguration(
                integrationRadius: 0,
                timeIntegrationRadius: 2,
                minimumObservationsPerSymbol: 1,
                llrScale: 1,
                llrLimit: 24,
                metricMode: .logMAP
            )
        )
    ]

    public func extract(
        from spectrogram: Spectrogram,
        candidate: FT8Candidate
    ) throws -> [FT8SoftSymbolVariant] {
        var variants: [FT8SoftSymbolVariant] = []
        variants.reserveCapacity(profiles.count)

        for profile in profiles {
            let extractor = SoftSymbolExtractor(
                configuration: profile.configuration
            )

            let softSymbols = try extractor.extract(
                from: spectrogram,
                candidate: candidate
            )

            variants.append(
                FT8SoftSymbolVariant(
                    profileName: profile.name,
                    softSymbols: softSymbols
                )
            )
        }

        return variants
    }
}
