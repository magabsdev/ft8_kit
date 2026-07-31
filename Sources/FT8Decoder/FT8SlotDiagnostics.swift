import Foundation
import FT8DSP

public struct FT8SlotDiagnosticTimings: Equatable, Sendable {
    public let waterfallSeconds: Double
    public let candidateSearchSeconds: Double
    public let decodeSeconds: Double
    public let totalSeconds: Double

    public init(
        waterfallSeconds: Double,
        candidateSearchSeconds: Double,
        decodeSeconds: Double,
        totalSeconds: Double
    ) {
        self.waterfallSeconds = waterfallSeconds
        self.candidateSearchSeconds = candidateSearchSeconds
        self.decodeSeconds = decodeSeconds
        self.totalSeconds = totalSeconds
    }
}

public struct FT8SlotDiagnosticBatch: Equatable, Sendable {
    public let spectrogram: Spectrogram
    public let candidates: [FT8Candidate]
    public let decodeBatch: FT8MultiPassDecodeBatch
    public let timings: FT8SlotDiagnosticTimings

    public init(
        spectrogram: Spectrogram,
        candidates: [FT8Candidate],
        decodeBatch: FT8MultiPassDecodeBatch,
        timings: FT8SlotDiagnosticTimings
    ) {
        self.spectrogram = spectrogram
        self.candidates = candidates
        self.decodeBatch = decodeBatch
        self.timings = timings
    }
}

public extension FT8MultiPassSlotDecoder {
    func decodeWithDiagnostics(samples: [Float]) throws -> FT8SlotDiagnosticBatch {
        let totalStarted = ContinuousClock.now

        let waterfallStarted = ContinuousClock.now
        let spectrogram = try Waterfall.analyse(
            samples: samples,
            configuration: waterfallConfiguration
        )
        let waterfallSeconds = Self.diagnosticSeconds(
            ContinuousClock.now - waterfallStarted
        )

        let candidateStarted = ContinuousClock.now
        let candidates = try decoder.decoder.synchronizer.search(in: spectrogram)
        let candidateSearchSeconds = Self.diagnosticSeconds(
            ContinuousClock.now - candidateStarted
        )

        let decodeStarted = ContinuousClock.now
        let decodeBatch = try decoder.decode(spectrogram: spectrogram)
        let decodeSeconds = Self.diagnosticSeconds(
            ContinuousClock.now - decodeStarted
        )

        return FT8SlotDiagnosticBatch(
            spectrogram: spectrogram,
            candidates: candidates,
            decodeBatch: decodeBatch,
            timings: FT8SlotDiagnosticTimings(
                waterfallSeconds: waterfallSeconds,
                candidateSearchSeconds: candidateSearchSeconds,
                decodeSeconds: decodeSeconds,
                totalSeconds: Self.diagnosticSeconds(
                    ContinuousClock.now - totalStarted
                )
            )
        )
    }

    private static func diagnosticSeconds(
        _ duration: Duration
    ) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
