import FT8DSP

public extension FT8OptimizedDecoder {
    func decode(
        spectrogram: Spectrogram,
        oversampledWaterfall: FT8OversampledWaterfall,
        candidateRefiner: FT8OversampledCandidateRefiner = .init()
    ) throws -> FT8DecodeBatch {
        var refinedDecoder = self
        let baseSynchronizer = refinedDecoder.synchronizer
        let found = try baseSynchronizer.search(in: spectrogram)
        let refined = found.map { candidateRefiner.refine($0, in: oversampledWaterfall) }
        return try refinedDecoder.decodePreparedCandidates(
            refined,
            spectrogram: spectrogram,
            candidatesFound: found.count
        )
    }

    private func decodePreparedCandidates(
        _ candidates: [FT8Candidate],
        spectrogram: Spectrogram,
        candidatesFound: Int
    ) throws -> FT8DecodeBatch {
        try configuration.validate()
        let started = ContinuousClock.now
        let scheduled = schedule(candidates)

        var softCount = 0
        var ldpcAttempts = 0
        var parityPassed = 0
        var crcPassed = 0
        var decoded: [FT8CompleteDecode] = []
        var traces: [FT8CandidateTrace] = []

        for (index, candidate) in scheduled.enumerated() {
            let extraction: FT8SoftSymbolExtraction
            do {
                extraction = try extractor.extractWithTrace(from: spectrogram, candidate: candidate)
            } catch {
                continue
            }

            let soft = extraction.softSymbols
            softCount += 1
            guard soft.averageConfidence >= configuration.minimumSoftSymbolConfidence else { continue }

            ldpcAttempts += 1
            let ldpc = try ldpcDecoder.decode(soft)
            if ldpc.parityPassed { parityPassed += 1 }
            if ldpc.crcPassed { crcPassed += 1 }

            guard let message = try? messageDecoder.decode(ldpc, softSymbols: soft) else { continue }
            if !configuration.decodeUnsupportedMessages, case .unsupported = message.message { continue }

            decoded.append(FT8CompleteDecode(candidate: candidate, softSymbols: soft, ldpc: ldpc, decoded: message))

            if configuration.captureCandidateTraces {
                traces.append(FT8CandidateTrace(
                    pass: 0,
                    candidateIndex: index,
                    startTime: candidate.startTime,
                    frequency: candidate.frequency,
                    driftHzPerSecond: candidate.driftHzPerSecond,
                    syncScore: candidate.syncScore,
                    snrDB: candidate.snrDB,
                    candidateConfidence: candidate.confidence,
                    averageSoftSymbolConfidence: soft.averageConfidence,
                    symbols: extraction.symbols,
                    logLikelihoodRatios: soft.logLikelihoodRatios,
                    ldpcIterations: ldpc.iterations,
                    syndromeWeight: ldpc.syndromeWeight,
                    parityPassed: ldpc.parityPassed,
                    crcPassed: ldpc.crcPassed,
                    decodedText: message.text,
                    failure: nil
                ))
            }
        }

        let messages = deduplicatePrepared(decoded)
        let duration = ContinuousClock.now - started
        let components = duration.components
        let elapsed = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000

        return FT8DecodeBatch(
            messages: messages,
            metrics: FT8DecodeMetrics(
                candidatesFound: candidatesFound,
                candidatesScheduled: scheduled.count,
                softSymbolsExtracted: softCount,
                ldpcAttempts: ldpcAttempts,
                parityPassed: parityPassed,
                crcPassed: crcPassed,
                messagesReturned: messages.count,
                elapsedSeconds: elapsed
            ),
            candidateTraces: traces
        )
    }

    private func deduplicatePrepared(_ decodes: [FT8CompleteDecode]) -> [FT8CompleteDecode] {
        var accepted: [FT8CompleteDecode] = []
        for decode in decodes.sorted(by: { $0.decoded.confidence > $1.decoded.confidence }) {
            let duplicate = accepted.contains {
                $0.decoded.payload == decode.decoded.payload
                    && abs($0.candidate.startTime - decode.candidate.startTime) <= configuration.deduplicationTime
                    && abs($0.candidate.frequency - decode.candidate.frequency) <= configuration.deduplicationFrequency
            }
            if !duplicate { accepted.append(decode) }
        }
        return accepted.sorted {
            if $0.candidate.startTime == $1.candidate.startTime { return $0.candidate.frequency < $1.candidate.frequency }
            return $0.candidate.startTime < $1.candidate.startTime
        }
    }
}
