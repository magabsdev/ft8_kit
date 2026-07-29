import FT8DSP

public struct FT8CandidateAnalysis: Equatable, Sendable {
    public let candidate: FT8Candidate
    public let softSymbols: FT8SoftSymbols

    public init(candidate: FT8Candidate, softSymbols: FT8SoftSymbols) {
        self.candidate = candidate
        self.softSymbols = softSymbols
    }
}

public struct FT8CandidateAnalyzer: Sendable {
    public var synchronizer: FT8Synchronizer
    public var extractor: SoftSymbolExtractor

    public init(
        synchronizer: FT8Synchronizer = .init(),
        extractor: SoftSymbolExtractor = .init()
    ) {
        self.synchronizer = synchronizer
        self.extractor = extractor
    }

    public func analyse(
        spectrogram: Spectrogram
    ) throws -> [FT8CandidateAnalysis] {
        var results: [FT8CandidateAnalysis] = []
        for candidate in try synchronizer.search(in: spectrogram) {
            do {
                results.append(
                    FT8CandidateAnalysis(
                        candidate: candidate,
                        softSymbols: try extractor.extract(
                            from: spectrogram,
                            candidate: candidate
                        )
                    )
                )
            } catch SoftSymbolError.insufficientObservations {
                continue
            }
        }
        return results
    }
}
