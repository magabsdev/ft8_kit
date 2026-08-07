import Foundation
import FT8Decoder
import FT8DSP

enum RealWAVCancellerEquivalenceDiagnostics {
    static func buildReport(
        recording: String,
        decode: FT8CompleteDecode,
        original: Spectrogram,
        experimental: RealWAVFastCancellationEvaluator.CancellationResult,
        production: FT8CancellationResult,
        synchronizer: FT8Synchronizer,
        maximumCellDifferences: Int = 100,
        maximumCandidates: Int = 20
    ) throws -> RealWAVCancellerEquivalenceReport {
        let experimentalSpectrogram = experimental.spectrogram
        let productionSpectrogram = production.spectrogram

        var experimentalMask = Set<CellAddress>()
        var productionMask = Set<CellAddress>()
        var differences: [RealWAVCancellerCellDifference] = []
        var sumDifference: Double = 0
        var sumSquaredDifference: Double = 0
        var sumOriginalSquared: Double = 0
        var comparedCells = 0
        var maximumDifference: Float = 0
        var noiseDifferenceSum: Double = 0
        var maximumNoiseDifference: Float = 0

        for frameIndex in original.frames.indices {
            let source = original.frames[frameIndex]
            let experimentalFrame = experimentalSpectrogram.frames[frameIndex]
            let productionFrame = productionSpectrogram.frames[frameIndex]
            let count = min(source.magnitudes.count, min(experimentalFrame.magnitudes.count, productionFrame.magnitudes.count))

            let noiseDifference = abs(experimentalFrame.noiseFloorDB - productionFrame.noiseFloorDB)
            maximumNoiseDifference = max(maximumNoiseDifference, noiseDifference)
            noiseDifferenceSum += Double(noiseDifference)

            for bin in 0..<count {
                let originalMagnitude = source.magnitudes[bin]
                let experimentalMagnitude = experimentalFrame.magnitudes[bin]
                let productionMagnitude = productionFrame.magnitudes[bin]

                if changed(originalMagnitude, experimentalMagnitude) {
                    experimentalMask.insert(CellAddress(frameIndex: frameIndex, bin: bin))
                }
                if changed(originalMagnitude, productionMagnitude) {
                    productionMask.insert(CellAddress(frameIndex: frameIndex, bin: bin))
                }

                let difference = abs(experimentalMagnitude - productionMagnitude)
                maximumDifference = max(maximumDifference, difference)
                sumDifference += Double(difference)
                sumSquaredDifference += Double(difference) * Double(difference)
                sumOriginalSquared += Double(originalMagnitude) * Double(originalMagnitude)
                comparedCells += 1

                if difference > 0 {
                    differences.append(
                        RealWAVCancellerCellDifference(
                            frameIndex: frameIndex,
                            bin: bin,
                            originalMagnitude: originalMagnitude,
                            experimentalMagnitude: experimentalMagnitude,
                            productionMagnitude: productionMagnitude,
                            absoluteDifference: difference
                        )
                    )
                }
            }
        }

        let common = experimentalMask.intersection(productionMask)
        let meanDifference = comparedCells > 0 ? sumDifference / Double(comparedCells) : 0
        let rms = comparedCells > 0 ? sqrt(sumSquaredDifference / Double(comparedCells)) : 0
        let originalRMS = comparedCells > 0 ? sqrt(sumOriginalSquared / Double(comparedCells)) : 0
        let relativeRMS = originalRMS > 0 ? rms / originalRMS : 0

        let experimentalCandidates = try synchronizer.search(in: experimentalSpectrogram)
            .prefix(maximumCandidates)
            .map(candidateSummary)
        let productionCandidates = try synchronizer.search(in: productionSpectrogram)
            .prefix(maximumCandidates)
            .map(candidateSummary)

        return RealWAVCancellerEquivalenceReport(
            recording: recording,
            decodedMessage: decode.decoded.text,
            decodedStartTime: decode.candidate.startTime,
            decodedFrequencyHz: decode.candidate.frequency,
            experimentalAffectedBins: experimentalMask.count,
            productionAffectedBins: productionMask.count,
            commonAffectedBins: common.count,
            experimentalOnlyBins: experimentalMask.subtracting(productionMask).count,
            productionOnlyBins: productionMask.subtracting(experimentalMask).count,
            maximumMagnitudeDifference: maximumDifference,
            meanMagnitudeDifference: meanDifference,
            rmsMagnitudeDifference: rms,
            relativeRMSError: relativeRMS,
            experimentalReductionFraction: experimental.reductionFraction,
            productionReductionFraction: production.reductionFraction,
            maximumNoiseFloorDifferenceDB: maximumNoiseDifference,
            meanNoiseFloorDifferenceDB: original.frames.isEmpty ? 0 : noiseDifferenceSum / Double(original.frames.count),
            experimentalCandidates: experimentalCandidates,
            productionCandidates: productionCandidates,
            largestCellDifferences: Array(differences.sorted { $0.absoluteDifference > $1.absoluteDifference }.prefix(maximumCellDifferences))
        )
    }

    static func printSummary(_ report: RealWAVCancellerEquivalenceReport) {
        print("Real WAV canceller equivalence:")
        print("  message: \"\(report.decodedMessage)\" time=\(report.decodedStartTime) frequency=\(report.decodedFrequencyHz)")
        print("  affected bins: experimental=\(report.experimentalAffectedBins) production=\(report.productionAffectedBins) common=\(report.commonAffectedBins) experimental-only=\(report.experimentalOnlyBins) production-only=\(report.productionOnlyBins)")
        print("  residual magnitude: max-difference=\(report.maximumMagnitudeDifference) mean-difference=\(report.meanMagnitudeDifference) rms=\(report.rmsMagnitudeDifference) relative-rms=\(report.relativeRMSError)")
        print("  reduction: experimental=\(report.experimentalReductionFraction) production=\(report.productionReductionFraction)")
        print("  noise-floor difference: max=\(report.maximumNoiseFloorDifferenceDB) dB mean=\(report.meanNoiseFloorDifferenceDB) dB")
        print("  experimental residual candidates:")
        for candidate in report.experimentalCandidates.prefix(10) {
            print("    time=\(candidate.startTime) frequency=\(candidate.frequencyHz) confidence=\(candidate.confidence) sync=\(candidate.syncScore) snr=\(candidate.snrDB)")
        }
        print("  production residual candidates:")
        for candidate in report.productionCandidates.prefix(10) {
            print("    time=\(candidate.startTime) frequency=\(candidate.frequencyHz) confidence=\(candidate.confidence) sync=\(candidate.syncScore) snr=\(candidate.snrDB)")
        }
    }

    private static func changed(_ lhs: Float, _ rhs: Float) -> Bool {
        abs(lhs - rhs) > max(abs(lhs) * 0.000_001, 0.000_000_001)
    }

    private static func candidateSummary(_ candidate: FT8Candidate) -> RealWAVCancellerCandidateSummary {
        RealWAVCancellerCandidateSummary(
            startTime: candidate.startTime,
            frequencyHz: candidate.frequency,
            confidence: candidate.confidence,
            syncScore: candidate.syncScore,
            snrDB: candidate.snrDB
        )
    }
}

private struct CellAddress: Hashable {
    let frameIndex: Int
    let bin: Int
}
