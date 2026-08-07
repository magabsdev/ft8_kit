import Foundation
import FT8DSP
import FT8Protocol

public struct FT8CandidateGuidedFineDecodeConfiguration:
    Equatable,
    Sendable
{
    public var maximumSeeds: Int
    public var minimumCandidateConfidence: Float
    public var maximumSeedSyndromeWeight: Int
    public var seedFrequencySeparationHz: Float

    public var coarseTimeRadius: Double
    public var coarseTimeStep: Double
    public var coarseFrequencyRadiusHz: Float
    public var coarseFrequencyStepHz: Float
    public var coarseHypothesesRetained: Int

    public var fineTimeRadius: Double
    public var fineTimeStep: Double
    public var fineFrequencyRadiusHz: Float
    public var fineFrequencyStepHz: Float
    public var fineSeedsPerCandidate: Int

    public var minimumCostasScore: Float
    public var minimumSoftConfidence: Float

    // WSJT-X-style ordered-statistics decoding is deliberately a bounded
    // final rescue stage. Running OSD for every time/frequency/profile
    // hypothesis is prohibitively expensive and is not how the search
    // hierarchy should be structured.
    public var maximumOSDRescuesPerSeed: Int
    public var maximumOSDSyndromeWeight: Int

    public init(
        maximumSeeds: Int = 4,
        minimumCandidateConfidence: Float = 0.68,
        maximumSeedSyndromeWeight: Int = 48,
        seedFrequencySeparationHz: Float = 18.75,
        coarseTimeRadius: Double = 0.16,
        coarseTimeStep: Double = 0.04,
        coarseFrequencyRadiusHz: Float = 6.25,
        coarseFrequencyStepHz: Float = 1.5625,
        coarseHypothesesRetained: Int = 6,
        fineTimeRadius: Double = 0.02,
        fineTimeStep: Double = 0.01,
        fineFrequencyRadiusHz: Float = 0.78125,
        fineFrequencyStepHz: Float = 0.78125,
        fineSeedsPerCandidate: Int = 2,
        minimumCostasScore: Float = 0.50,
        minimumSoftConfidence: Float = 0.08,
        maximumOSDRescuesPerSeed: Int = 2,
        maximumOSDSyndromeWeight: Int = 12
    ) {
        self.maximumSeeds = maximumSeeds
        self.minimumCandidateConfidence =
            minimumCandidateConfidence
        self.maximumSeedSyndromeWeight =
            maximumSeedSyndromeWeight
        self.seedFrequencySeparationHz =
            seedFrequencySeparationHz

        self.coarseTimeRadius = coarseTimeRadius
        self.coarseTimeStep = coarseTimeStep
        self.coarseFrequencyRadiusHz =
            coarseFrequencyRadiusHz
        self.coarseFrequencyStepHz =
            coarseFrequencyStepHz
        self.coarseHypothesesRetained =
            coarseHypothesesRetained

        self.fineTimeRadius = fineTimeRadius
        self.fineTimeStep = fineTimeStep
        self.fineFrequencyRadiusHz =
            fineFrequencyRadiusHz
        self.fineFrequencyStepHz =
            fineFrequencyStepHz
        self.fineSeedsPerCandidate =
            fineSeedsPerCandidate

        self.minimumCostasScore =
            minimumCostasScore
        self.minimumSoftConfidence =
            minimumSoftConfidence
        self.maximumOSDRescuesPerSeed =
            max(0, maximumOSDRescuesPerSeed)
        self.maximumOSDSyndromeWeight =
            max(0, maximumOSDSyndromeWeight)
    }
}

public struct FT8FineDecodeHypothesis:
    Equatable,
    Sendable
{
    public let seedPass: Int
    public let seedCandidateIndex: Int
    public let seedTime: Double
    public let seedFrequencyHz: Float

    public let startTime: Double
    public let frequencyHz: Float
    public let costasScore: Float
    public let costasSNRDB: Float
    public let profileName: String?
    public let softConfidence: Float?
    public let syndromeWeight: Int?
    public let parityPassed: Bool?
    public let crcPassed: Bool?
    public let decodedText: String?
}

public struct FT8CandidateGuidedFineDecodeResult:
    Equatable,
    Sendable
{
    public let messages: [FT8CompleteDecode]
    public let hypothesesTested: Int
    public let ldpcAttempts: Int
    public let seedsSelected: Int
    public let bestHypotheses:
        [FT8FineDecodeHypothesis]
    public let elapsedSeconds: Double
}

public struct FT8CandidateGuidedFineDecoder:
    Sendable
{
    public var configuration:
        FT8CandidateGuidedFineDecodeConfiguration
    public var ensembleExtractor:
        FT8SoftSymbolEnsembleExtractor
    public var ldpcDecoder: FT8LDPCDecoder
    public var messageDecoder: FT8MessageDecoder

    public init(
        configuration:
            FT8CandidateGuidedFineDecodeConfiguration =
                .init(),
        ensembleExtractor:
            FT8SoftSymbolEnsembleExtractor = .init(),
        ldpcDecoder: FT8LDPCDecoder = .init(),
        messageDecoder: FT8MessageDecoder = .init()
    ) {
        self.configuration = configuration
        self.ensembleExtractor = ensembleExtractor
        self.ldpcDecoder = ldpcDecoder
        self.messageDecoder = messageDecoder
    }

    public func decode(
        spectrogram: Spectrogram,
        traces: [FT8CandidateTrace],
        excludingPayloads:
            [FT8BitBuffer] = []
    ) throws -> FT8CandidateGuidedFineDecodeResult {
        let started = ContinuousClock.now

        let seeds = selectSeeds(
            from: traces
        )

        var decoded: [FT8CompleteDecode] = []
        var bestDiagnostics:
            [FT8FineDecodeHypothesis] = []
        var hypothesesTested = 0
        var ldpcAttempts = 0

        for (seedOffset, seed) in seeds.enumerated() {
            print(
                "[FineDecode] Seed \(seedOffset + 1)/\(seeds.count) "
                    + "pass=\(seed.trace.pass) "
                    + "candidate=\(seed.trace.candidateIndex) "
                    + "time=\(seed.trace.startTime) "
                    + "frequency=\(seed.trace.frequency)"
            )

            let coarse = coarseHypotheses(
                for: seed,
                in: spectrogram
            )
            hypothesesTested += coarse.count

            print(
                "[FineDecode]   coarse hypotheses=\(coarse.count)"
            )

            let retained = Array(
                coarse
                    .filter {
                        $0.correlation.score
                            >= configuration.minimumCostasScore
                    }
                    .sorted {
                        if $0.correlation.score
                            != $1.correlation.score {
                            return $0.correlation.score
                                > $1.correlation.score
                        }
                        return $0.correlation.snrDB
                            > $1.correlation.snrDB
                    }
                    .prefix(
                        configuration
                            .coarseHypothesesRetained
                    )
            )

            print(
                "[FineDecode]   retained for LDPC=\(retained.count)"
            )

            var rankedOutcomes:
                [RefinedOutcome] = []

            for hypothesis in retained {
                let outcomes = try evaluate(
                    seed: seed,
                    hypothesis: hypothesis,
                    spectrogram: spectrogram
                )
                ldpcAttempts += outcomes.count
                rankedOutcomes.append(contentsOf: outcomes)

                for outcome in outcomes where outcome.ldpc.crcPassed {
                    guard let message = outcome.message,
                          !excludingPayloads.contains(message.payload)
                    else {
                        continue
                    }

                    decoded.append(
                        FT8CompleteDecode(
                            candidate: outcome.candidate,
                            softSymbols: outcome.soft,
                            ldpc: outcome.ldpc,
                            decoded: message
                        )
                    )
                }
            }

            if let currentBest = rankedOutcomes
                .sorted(by: outcomeIsBetter)
                .first {
                print(
                    "[FineDecode]   coarse best profile="
                        + "\(currentBest.profileName) "
                        + "syndrome=\(currentBest.ldpc.syndromeWeight) "
                        + "parity=\(currentBest.ldpc.parityPassed) "
                        + "crc=\(currentBest.ldpc.crcPassed)"
                )
            }

            let fineBases = rankedOutcomes
                .sorted(by: outcomeIsBetter)
                .prefix(
                    configuration
                        .fineSeedsPerCandidate
                )

            for base in fineBases {
                let fine = fineHypotheses(
                    around: base.candidate,
                    seed: seed,
                    in: spectrogram
                )

                hypothesesTested += fine.count

                for hypothesis in fine {
                    guard hypothesis.correlation.score
                        >= configuration.minimumCostasScore
                    else {
                        continue
                    }

                    let outcomes = try evaluate(
                        seed: seed,
                        hypothesis: hypothesis,
                        spectrogram: spectrogram
                    )
                    ldpcAttempts += outcomes.count
                    rankedOutcomes.append(contentsOf: outcomes)

                    for outcome in outcomes where outcome.ldpc.crcPassed {
                        guard let message = outcome.message,
                              !excludingPayloads.contains(message.payload)
                        else {
                            continue
                        }

                        decoded.append(
                            FT8CompleteDecode(
                                candidate: outcome.candidate,
                                softSymbols: outcome.soft,
                                ldpc: outcome.ldpc,
                                decoded: message
                            )
                        )
                    }
                }
            }

            print(
                "[FineDecode]   BP evaluation complete: outcomes=\(rankedOutcomes.count)"
            )

            let osdShortlist = Array(
                rankedOutcomes
                    .filter {
                        !$0.ldpc.crcPassed
                            && $0.ldpc.syndromeWeight
                                <= configuration.maximumOSDSyndromeWeight
                    }
                    .sorted(by: osdCandidateIsBetter)
                    .prefix(configuration.maximumOSDRescuesPerSeed)
            )

            print(
                "[FineDecode]   OSD shortlist=\(osdShortlist.count)"
            )

            if !osdShortlist.isEmpty {
                let osd = FT8OrderedStatisticsDecoder(
                    configuration: .init(
                        order: 1,
                        pivotSearchExtraColumns: 20,
                        maximumOrderOnePatterns: 91
                    )
                )

                for (osdIndex, outcome) in osdShortlist.enumerated() {
                    print(
                        "[FineDecode]   OSD rescue \(osdIndex + 1)/\(osdShortlist.count) "
                            + "profile=\(outcome.profileName) "
                            + "syndrome=\(outcome.ldpc.syndromeWeight)"
                    )

                    let snapshotDecoder = FT8BPReliabilitySnapshotDecoder(


                        configuration: .init(


                            maximumIterations: 30,


                            maximumSnapshots: 3,


                            messageLimit: 32


                        )


                    )



                    let reliabilitySnapshots = try snapshotDecoder.snapshots(


                        logLikelihoodRatios:


                            outcome.soft.logLikelihoodRatios


                    )



                    var recoveredPair: (FT8LDPCResult, FT8DecodedMessage)?



                    for (snapshotIndex, reliability) in reliabilitySnapshots.enumerated() {


                        print(


                            "[FineDecode]     OSD BP snapshot "


                                + "\(snapshotIndex + 1)/\(reliabilitySnapshots.count)"


                        )



                        guard let recovered = try osd.decode(


                            logLikelihoodRatios: reliability


                        ) else {


                            continue


                        }



                        guard let message = try? messageDecoder.decode(


                            recovered,


                            softSymbols: outcome.soft


                        ) else {


                            // A parity/CRC-valid but non-displayable payload must not


                            // outrank a real FT8 message. Continue with the next saved


                            // BP reliability vector, as WSJT-X does with zsave(:,i).


                            continue


                        }



                        recoveredPair = (recovered, message)


                        break


                    }



                    guard let (recovered, message) = recoveredPair else {


                        print(


                            "[FineDecode]     OSD produced no valid message from BP snapshots"


                        )


                        continue


                    }

                    let rescued = RefinedOutcome(
                        candidate: outcome.candidate,
                        profileName: outcome.profileName,
                        soft: outcome.soft,
                        ldpc: recovered,
                        message: message,
                        correlation: outcome.correlation
                    )

                    rankedOutcomes.append(rescued)

                    print(
                        "[FineDecode]     OSD result syndrome="
                            + "\(recovered.syndromeWeight) "
                            + "parity=\(recovered.parityPassed) "
                            + "crc=\(recovered.crcPassed)"
                    )

                    if recovered.crcPassed,
                       let message,
                       !excludingPayloads.contains(message.payload) {
                        decoded.append(
                            FT8CompleteDecode(
                                candidate: rescued.candidate,
                                softSymbols: rescued.soft,
                                ldpc: rescued.ldpc,
                                decoded: message
                            )
                        )

                        print(
                            "[FineDecode]     OSD CRC success; stopping rescue for this seed"
                        )
                        break
                    }
                }
            }

            if let best = rankedOutcomes
                .sorted(by: outcomeIsBetter)
                .first {
                print(
                    "[FineDecode]   final best time="
                        + "\(best.candidate.startTime) "
                        + "frequency=\(best.candidate.frequency) "
                        + "profile=\(best.profileName) "
                        + "syndrome=\(best.ldpc.syndromeWeight) "
                        + "parity=\(best.ldpc.parityPassed) "
                        + "crc=\(best.ldpc.crcPassed)"
                )
                bestDiagnostics.append(
                    diagnostic(
                        seed: seed,
                        outcome: best
                    )
                )
            }
        }

        let unique = deduplicate(decoded)
        let elapsed = Self.seconds(
            ContinuousClock.now - started
        )

        return FT8CandidateGuidedFineDecodeResult(
            messages: unique,
            hypothesesTested: hypothesesTested,
            ldpcAttempts: ldpcAttempts,
            seedsSelected: seeds.count,
            bestHypotheses: bestDiagnostics,
            elapsedSeconds: elapsed
        )
    }

    private struct Seed {
        let trace: FT8CandidateTrace
    }

    private struct SearchHypothesis {
        let startTime: Double
        let frequencyHz: Float
        let correlation: CostasCorrelation
    }

    private struct RefinedOutcome {
        let candidate: FT8Candidate
        let profileName: String
        let soft: FT8SoftSymbols
        let ldpc: FT8LDPCResult
        let message: FT8DecodedMessage?
        let correlation: CostasCorrelation
    }

    private func selectSeeds(
        from traces: [FT8CandidateTrace]
    ) -> [Seed] {
        let eligible = traces.filter {
            $0.failure != nil
            && $0.candidateConfidence
                >= configuration
                    .minimumCandidateConfidence
            && (
                $0.parityPassed == true
                || ($0.syndromeWeight ?? Int.max)
                    <= configuration
                        .maximumSeedSyndromeWeight
            )
        }
        .sorted {
            if $0.parityPassed != $1.parityPassed {
                return $0.parityPassed == true
            }

            let lhsSyndrome =
                $0.syndromeWeight ?? Int.max
            let rhsSyndrome =
                $1.syndromeWeight ?? Int.max

            if lhsSyndrome != rhsSyndrome {
                return lhsSyndrome < rhsSyndrome
            }

            let lhsSoft =
                $0.averageSoftSymbolConfidence ?? 0
            let rhsSoft =
                $1.averageSoftSymbolConfidence ?? 0

            if lhsSoft != rhsSoft {
                return lhsSoft > rhsSoft
            }

            return $0.candidateConfidence
                > $1.candidateConfidence
        }

        var accepted: [Seed] = []

        for trace in eligible {
            let overlaps = accepted.contains {
                abs(
                    $0.trace.frequency
                        - trace.frequency
                ) < configuration
                    .seedFrequencySeparationHz
            }

            if overlaps {
                continue
            }

            accepted.append(
                Seed(trace: trace)
            )

            if accepted.count
                >= configuration.maximumSeeds {
                break
            }
        }

        return accepted
    }

    private func coarseHypotheses(
        for seed: Seed,
        in spectrogram: Spectrogram
    ) -> [SearchHypothesis] {
        searchGrid(
            centreTime: seed.trace.startTime,
            timeRadius:
                configuration.coarseTimeRadius,
            timeStep:
                configuration.coarseTimeStep,
            centreFrequency:
                seed.trace.frequency,
            frequencyRadius:
                configuration
                    .coarseFrequencyRadiusHz,
            frequencyStep:
                configuration
                    .coarseFrequencyStepHz,
            driftHzPerSecond:
                seed.trace.driftHzPerSecond,
            in: spectrogram
        )
    }

    private func fineHypotheses(
        around candidate: FT8Candidate,
        seed: Seed,
        in spectrogram: Spectrogram
    ) -> [SearchHypothesis] {
        searchGrid(
            centreTime: candidate.startTime,
            timeRadius:
                configuration.fineTimeRadius,
            timeStep:
                configuration.fineTimeStep,
            centreFrequency:
                candidate.frequency,
            frequencyRadius:
                configuration
                    .fineFrequencyRadiusHz,
            frequencyStep:
                configuration
                    .fineFrequencyStepHz,
            driftHzPerSecond:
                seed.trace.driftHzPerSecond,
            in: spectrogram
        )
    }

    private func searchGrid(
        centreTime: Double,
        timeRadius: Double,
        timeStep: Double,
        centreFrequency: Float,
        frequencyRadius: Float,
        frequencyStep: Float,
        driftHzPerSecond: Float,
        in spectrogram: Spectrogram
    ) -> [SearchHypothesis] {
        guard timeStep > 0,
              frequencyStep > 0 else {
            return []
        }

        var results: [SearchHypothesis] = []

        var time =
            centreTime - timeRadius

        while time
            <= centreTime + timeRadius
                + timeStep * 0.5 {
            if time >= 0 {
                var frequency =
                    centreFrequency
                    - frequencyRadius

                while frequency
                    <= centreFrequency
                        + frequencyRadius
                        + frequencyStep * 0.5 {
                    let correlation =
                        CostasCorrelator.correlate(
                            spectrogram:
                                spectrogram,
                            startTime: time,
                            baseFrequency:
                                frequency,
                            driftHzPerSecond:
                                driftHzPerSecond
                        )

                    results.append(
                        SearchHypothesis(
                            startTime: time,
                            frequencyHz:
                                frequency,
                            correlation:
                                correlation
                        )
                    )

                    frequency += frequencyStep
                }
            }

            time += timeStep
        }

        return results
    }

    private func evaluate(
        seed: Seed,
        hypothesis: SearchHypothesis,
        spectrogram: Spectrogram
    ) throws -> [RefinedOutcome] {
        let candidate = FT8Candidate(
            startTime: hypothesis.startTime,
            frequency:
                hypothesis.frequencyHz,
            driftHzPerSecond:
                seed.trace.driftHzPerSecond,
            symbolOffset: 0,
            syncScore:
                hypothesis.correlation.score,
            snrDB:
                hypothesis.correlation.snrDB,
            confidence:
                hypothesis.correlation.score
        )

        let variants: [FT8SoftSymbolVariant]

        do {
            variants = try ensembleExtractor.extract(
                from: spectrogram,
                candidate: candidate
            )
        } catch {
            return []
        }

        var outcomes: [RefinedOutcome] = []
        outcomes.reserveCapacity(variants.count)

        for variant in variants {
            let soft = variant.softSymbols

            guard soft.averageConfidence
                >= configuration.minimumSoftConfidence
            else {
                continue
            }

            let primaryLDPC = try ldpcDecoder.decode(soft)

            let message = try? messageDecoder.decode(
                primaryLDPC,
                softSymbols: soft
            )

            // The fine-search layer is BP-only. OSD is intentionally deferred
            // until all coarse/fine BP outcomes for this seed have been ranked.
            // This keeps the expensive ordered-statistics rescue bounded.
            outcomes.append(
                RefinedOutcome(
                    candidate: candidate,
                    profileName: variant.profileName,
                    soft: soft,
                    ldpc: primaryLDPC,
                    message: message,
                    correlation:
                        hypothesis.correlation
                )
            )
        }

        return outcomes
    }

    private func osdCandidateIsBetter(
        _ lhs: RefinedOutcome,
        _ rhs: RefinedOutcome
    ) -> Bool {
        if lhs.ldpc.parityPassed
            != rhs.ldpc.parityPassed {
            return lhs.ldpc.parityPassed
        }

        if lhs.ldpc.syndromeWeight
            != rhs.ldpc.syndromeWeight {
            return lhs.ldpc.syndromeWeight
                < rhs.ldpc.syndromeWeight
        }

        if lhs.soft.averageConfidence
            != rhs.soft.averageConfidence {
            return lhs.soft.averageConfidence
                > rhs.soft.averageConfidence
        }

        if lhs.correlation.score
            != rhs.correlation.score {
            return lhs.correlation.score
                > rhs.correlation.score
        }

        return lhs.profileName < rhs.profileName
    }

    private func outcomeIsBetter(
        _ lhs: RefinedOutcome,
        _ rhs: RefinedOutcome
    ) -> Bool {
        if lhs.ldpc.crcPassed
            != rhs.ldpc.crcPassed {
            return lhs.ldpc.crcPassed
        }

        if lhs.ldpc.parityPassed
            != rhs.ldpc.parityPassed {
            return lhs.ldpc.parityPassed
        }

        if lhs.ldpc.syndromeWeight
            != rhs.ldpc.syndromeWeight {
            return lhs.ldpc.syndromeWeight
                < rhs.ldpc.syndromeWeight
        }

        if lhs.soft.averageConfidence
            != rhs.soft.averageConfidence {
            return lhs.soft.averageConfidence
                > rhs.soft.averageConfidence
        }

        if lhs.correlation.score
            != rhs.correlation.score {
            return lhs.correlation.score
                > rhs.correlation.score
        }

        return lhs.profileName < rhs.profileName
    }

    private func diagnostic(
        seed: Seed,
        outcome: RefinedOutcome
    ) -> FT8FineDecodeHypothesis {
        FT8FineDecodeHypothesis(
            seedPass: seed.trace.pass,
            seedCandidateIndex:
                seed.trace.candidateIndex,
            seedTime: seed.trace.startTime,
            seedFrequencyHz:
                seed.trace.frequency,
            startTime:
                outcome.candidate.startTime,
            frequencyHz:
                outcome.candidate.frequency,
            costasScore:
                outcome.correlation.score,
            costasSNRDB:
                outcome.correlation.snrDB,
            profileName:
                outcome.profileName,
            softConfidence:
                outcome.soft.averageConfidence,
            syndromeWeight:
                outcome.ldpc.syndromeWeight,
            parityPassed:
                outcome.ldpc.parityPassed,
            crcPassed:
                outcome.ldpc.crcPassed,
            decodedText:
                outcome.message?.text
        )
    }

    private func deduplicate(
        _ messages: [FT8CompleteDecode]
    ) -> [FT8CompleteDecode] {
        var accepted:
            [FT8CompleteDecode] = []

        for message in messages.sorted(
            by: {
                $0.decoded.confidence
                    > $1.decoded.confidence
            }
        ) {
            if accepted.contains(
                where: {
                    $0.decoded.payload
                        == message.decoded.payload
                }
            ) {
                continue
            }

            accepted.append(message)
        }

        return accepted.sorted {
            if $0.candidate.startTime
                == $1.candidate.startTime {
                return $0.candidate.frequency
                    < $1.candidate.frequency
            }

            return $0.candidate.startTime
                < $1.candidate.startTime
        }
    }

    private static func seconds(
        _ duration: Duration
    ) -> Double {
        let components =
            duration.components

        return Double(components.seconds)
            + Double(components.attoseconds)
                / 1_000_000_000_000_000_000
    }
}
