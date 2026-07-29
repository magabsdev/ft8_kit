import FT8DSP

public struct FT8NativeDecode: Equatable, Sendable {
    public let candidate: FT8Candidate
    public let softSymbols: FT8SoftSymbols
    public let ldpc: FT8LDPCResult

    public init(
        candidate: FT8Candidate,
        softSymbols: FT8SoftSymbols,
        ldpc: FT8LDPCResult
    ) {
        self.candidate = candidate
        self.softSymbols = softSymbols
        self.ldpc = ldpc
    }
}

public struct FT8NativeDecoder: Sendable {
    public var synchronizer: FT8Synchronizer
    public var extractor: SoftSymbolExtractor
    public var ldpcDecoder: FT8LDPCDecoder

    public init(
        synchronizer: FT8Synchronizer = .init(),
        extractor: SoftSymbolExtractor = .init(),
        ldpcDecoder: FT8LDPCDecoder = .init()
    ) {
        self.synchronizer = synchronizer
        self.extractor = extractor
        self.ldpcDecoder = ldpcDecoder
    }

    public func decode(spectrogram: Spectrogram) throws -> [FT8NativeDecode] {
        var output: [FT8NativeDecode] = []
        for candidate in try synchronizer.search(in: spectrogram) {
            guard let soft = try? extractor.extract(
                from: spectrogram,
                candidate: candidate
            ) else { continue }
            let decoded = try ldpcDecoder.decode(soft)
            output.append(
                FT8NativeDecode(
                    candidate: candidate,
                    softSymbols: soft,
                    ldpc: decoded
                )
            )
        }
        return output
    }
}
