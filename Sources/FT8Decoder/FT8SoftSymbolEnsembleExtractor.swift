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

/// Produces a small bounded ensemble of soft-symbol interpretations for a
/// single synchronized FT8 candidate.
///
/// Weak real-world FT8 signals can respond differently to temporal and
/// frequency integration. Rather than committing the LDPC decoder to one
/// observation strategy, this extractor provides several deliberately small,
/// deterministic alternatives that can be ranked by the decoder.
///
/// The default profiles are intentionally conservative so this stage remains
/// suitable for production candidate-guided decoding rather than turning into
/// an unbounded brute-force search.
public struct FT8SoftSymbolEnsembleExtractor: Sendable {
    public var profiles: [FT8SoftSymbolProfile]

    public init(
        profiles: [FT8SoftSymbolProfile] = Self.productionProfiles
    ) {
        self.profiles = profiles
    }

    public static let productionProfiles: [FT8SoftSymbolProfile] = [
        FT8SoftSymbolProfile(
            name: "precise",
            configuration: SoftSymbolConfiguration(
                integrationRadius: 0,
                timeIntegrationRadius: 0,
                minimumObservationsPerSymbol: 1,
                llrScale: 1,
                llrLimit: 24
            )
        ),
        FT8SoftSymbolProfile(
            name: "balanced",
            configuration: SoftSymbolConfiguration(
                integrationRadius: 0,
                timeIntegrationRadius: 1,
                minimumObservationsPerSymbol: 1,
                llrScale: 1,
                llrLimit: 24
            )
        ),
        FT8SoftSymbolProfile(
            name: "frequency-integrated",
            configuration: SoftSymbolConfiguration(
                integrationRadius: 1,
                timeIntegrationRadius: 1,
                minimumObservationsPerSymbol: 1,
                llrScale: 1,
                llrLimit: 24
            )
        ),
        FT8SoftSymbolProfile(
            name: "temporal-integrated",
            configuration: SoftSymbolConfiguration(
                integrationRadius: 0,
                timeIntegrationRadius: 2,
                minimumObservationsPerSymbol: 1,
                llrScale: 1,
                llrLimit: 24
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
