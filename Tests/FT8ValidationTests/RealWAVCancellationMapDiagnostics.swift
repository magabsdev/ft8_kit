import Foundation
import FT8Decoder
import FT8DSP
import FT8Encoder

enum RealWAVCancellationMapDiagnostics {
    static func build(
        recording: String,
        decode: FT8CompleteDecode,
        spectrogram: Spectrogram,
        binRadius: Int = 1,
        strength: Float = 1.00,
        timeTaperFloor: Float = 0.50,
        symbolPeriod: Double = 0.160,
        toneSpacing: Float = 6.25
    ) throws -> RealWAVCancellationMapReport {
        let tones = try FT8Encoder.encode(text: decode.decoded.text)
        let symbolCount = min(79, tones.count)

        let experimental = traceExperimental(
            decode: decode,
            tones: tones,
            symbolCount: symbolCount,
            spectrogram: spectrogram,
            binRadius: binRadius,
            strength: strength,
            timeTaperFloor: timeTaperFloor,
            symbolPeriod: symbolPeriod,
            toneSpacing: toneSpacing
        )

        let production = traceProduction(
            decode: decode,
            tones: tones,
            symbolCount: symbolCount,
            spectrogram: spectrogram,
            binRadius: binRadius,
            strength: strength,
            timeTaperFloor: timeTaperFloor,
            symbolPeriod: symbolPeriod,
            toneSpacing: toneSpacing
        )

        let experimentalCells = Set(experimental.map {
            Cell(frameIndex: $0.frameIndex, bin: $0.bin)
        })
        let productionCells = Set(production.map {
            Cell(frameIndex: $0.frameIndex, bin: $0.bin)
        })
        let experimentalFrames = Set(experimental.map(\.frameIndex))
        let productionFrames = Set(production.map(\.frameIndex))

        var symbolMaps: [RealWAVCancellationSymbolMap] = []
        var productionFrameTotal = 0
        var maximumProductionFrames = 0

        for symbolIndex in 0..<symbolCount {
            let experimentalForSymbol = experimental.filter {
                $0.symbolIndex == symbolIndex
            }
            let productionForSymbol = production.filter {
                $0.symbolIndex == symbolIndex
            }

            let experimentalFrameSet = Set(
                experimentalForSymbol.map(\.frameIndex)
            )
            let productionFrameSet = Set(
                productionForSymbol.map(\.frameIndex)
            )
            let commonFrames = experimentalFrameSet.intersection(
                productionFrameSet
            )

            productionFrameTotal += productionFrameSet.count
            maximumProductionFrames = max(
                maximumProductionFrames,
                productionFrameSet.count
            )

            symbolMaps.append(
                RealWAVCancellationSymbolMap(
                    symbolIndex: symbolIndex,
                    tone: tones[symbolIndex],
                    symbolStartTime: decode.candidate.startTime
                        + Double(symbolIndex) * symbolPeriod,
                    experimentalFrameIndices: experimentalFrameSet.sorted(),
                    productionFrameIndices: productionFrameSet.sorted(),
                    experimentalTouchCount: experimentalForSymbol.count,
                    productionTouchCount: productionForSymbol.count,
                    commonFrameCount: commonFrames.count,
                    experimentalOnlyFrameCount: experimentalFrameSet
                        .subtracting(productionFrameSet).count,
                    productionOnlyFrameCount: productionFrameSet
                        .subtracting(experimentalFrameSet).count,
                    productionToExperimentalTouchRatio: ratio(
                        numerator: productionForSymbol.count,
                        denominator: experimentalForSymbol.count
                    )
                )
            )
        }

        return RealWAVCancellationMapReport(
            recording: recording,
            decodedMessage: decode.decoded.text,
            decodedStartTime: decode.candidate.startTime,
            decodedFrequencyHz: decode.candidate.frequency,
            symbolCount: symbolCount,
            experimentalTouchCount: experimental.count,
            productionTouchCount: production.count,
            productionToExperimentalTouchRatio: ratio(
                numerator: production.count,
                denominator: experimental.count
            ),
            experimentalUniqueCells: experimentalCells.count,
            productionUniqueCells: productionCells.count,
            commonUniqueCells: experimentalCells.intersection(
                productionCells
            ).count,
            experimentalOnlyUniqueCells: experimentalCells
                .subtracting(productionCells).count,
            productionOnlyUniqueCells: productionCells
                .subtracting(experimentalCells).count,
            experimentalUniqueFrames: experimentalFrames.count,
            productionUniqueFrames: productionFrames.count,
            maximumProductionFramesPerSymbol: maximumProductionFrames,
            meanProductionFramesPerSymbol: symbolCount > 0
                ? Double(productionFrameTotal) / Double(symbolCount)
                : 0,
            symbols: symbolMaps,
            experimentalTouches: experimental,
            productionTouches: production
        )
    }

    static func printSummary(_ report: RealWAVCancellationMapReport) {
        print("Real WAV cancellation map:")
        print(
            "  message: \"\(report.decodedMessage)\""
                + " time=\(report.decodedStartTime)"
                + " frequency=\(report.decodedFrequencyHz)"
        )
        print(
            "  touches: experimental=\(report.experimentalTouchCount)"
                + " production=\(report.productionTouchCount)"
                + " ratio=\(String(format: "%.3f", report.productionToExperimentalTouchRatio))"
        )
        print(
            "  unique cells: experimental=\(report.experimentalUniqueCells)"
                + " production=\(report.productionUniqueCells)"
                + " common=\(report.commonUniqueCells)"
                + " experimental-only=\(report.experimentalOnlyUniqueCells)"
                + " production-only=\(report.productionOnlyUniqueCells)"
        )
        print(
            "  unique frames: experimental=\(report.experimentalUniqueFrames)"
                + " production=\(report.productionUniqueFrames)"
        )
        print(
            "  production frames/symbol: mean="
                + String(format: "%.3f", report.meanProductionFramesPerSymbol)
                + " max=\(report.maximumProductionFramesPerSymbol)"
        )

        print("  symbols with different frame footprints:")
        let divergent = report.symbols.filter {
            $0.productionOnlyFrameCount > 0
                || $0.experimentalOnlyFrameCount > 0
        }

        if divergent.isEmpty {
            print("    none")
        } else {
            for symbol in divergent.prefix(20) {
                print(
                    "    #\(symbol.symbolIndex)"
                        + " tone=\(symbol.tone)"
                        + " expFrames=\(symbol.experimentalFrameIndices)"
                        + " prodFrames=\(symbol.productionFrameIndices)"
                        + " expTouches=\(symbol.experimentalTouchCount)"
                        + " prodTouches=\(symbol.productionTouchCount)"
                )
            }
            if divergent.count > 20 {
                print("    ... \(divergent.count - 20) more symbols")
            }
        }
    }

    private static func traceExperimental(
        decode: FT8CompleteDecode,
        tones: [UInt8],
        symbolCount: Int,
        spectrogram: Spectrogram,
        binRadius: Int,
        strength: Float,
        timeTaperFloor: Float,
        symbolPeriod: Double,
        toneSpacing: Float
    ) -> [RealWAVCancellationTouch] {
        var touches: [RealWAVCancellationTouch] = []

        for symbolIndex in 0..<symbolCount {
            let symbolStart = decode.candidate.startTime
                + Double(symbolIndex) * symbolPeriod

            guard let frameIndex = nearestFrameIndex(
                in: spectrogram.frames,
                time: symbolStart
            ) else {
                continue
            }

            let frame = spectrogram.frames[frameIndex]
            let elapsed = Float(
                symbolStart - decode.candidate.startTime
            )
            let toneFrequency = decode.candidate.frequency
                + Float(tones[symbolIndex]) * toneSpacing
                + decode.candidate.driftHzPerSecond * elapsed
            let centreBin = nearestBin(
                frequency: toneFrequency,
                frame: frame
            )
            let taper = timeTaper(
                symbolIndex: symbolIndex,
                symbolCount: symbolCount,
                floor: timeTaperFloor
            )

            appendTouches(
                implementation: .experimental,
                symbolIndex: symbolIndex,
                tone: tones[symbolIndex],
                symbolStart: symbolStart,
                frameIndex: frameIndex,
                frame: frame,
                spectrogram: spectrogram,
                toneFrequency: toneFrequency,
                centreBin: centreBin,
                binRadius: binRadius,
                taper: taper,
                strength: strength,
                to: &touches
            )
        }

        return touches
    }

    private static func traceProduction(
        decode: FT8CompleteDecode,
        tones: [UInt8],
        symbolCount: Int,
        spectrogram: Spectrogram,
        binRadius: Int,
        strength: Float,
        timeTaperFloor: Float,
        symbolPeriod: Double,
        toneSpacing: Float
    ) -> [RealWAVCancellationTouch] {
        var touches: [RealWAVCancellationTouch] = []

        for symbolIndex in 0..<symbolCount {
            let symbolStart = decode.candidate.startTime
                + Double(symbolIndex) * symbolPeriod
            let symbolEnd = symbolStart + symbolPeriod
            let taper = timeTaper(
                symbolIndex: symbolIndex,
                symbolCount: symbolCount,
                floor: timeTaperFloor
            )

            for frameIndex in spectrogram.frames.indices {
                let frame = spectrogram.frames[frameIndex]
                let frameCentre = frame.time
                    + Double(spectrogram.fftSize)
                    / Double(spectrogram.sampleRate) / 2

                guard frameCentre >= symbolStart,
                      frameCentre < symbolEnd else {
                    continue
                }

                let elapsed = Float(
                    frameCentre - decode.candidate.startTime
                )
                let toneFrequency = decode.candidate.frequency
                    + Float(tones[symbolIndex]) * toneSpacing
                    + decode.candidate.driftHzPerSecond * elapsed
                let centreBin = nearestBin(
                    frequency: toneFrequency,
                    frame: frame
                )

                appendTouches(
                    implementation: .production,
                    symbolIndex: symbolIndex,
                    tone: tones[symbolIndex],
                    symbolStart: symbolStart,
                    frameIndex: frameIndex,
                    frame: frame,
                    spectrogram: spectrogram,
                    toneFrequency: toneFrequency,
                    centreBin: centreBin,
                    binRadius: binRadius,
                    taper: taper,
                    strength: strength,
                    to: &touches
                )
            }
        }

        return touches
    }

    private static func appendTouches(
        implementation: RealWAVCancellationImplementation,
        symbolIndex: Int,
        tone: UInt8,
        symbolStart: Double,
        frameIndex: Int,
        frame: WaterfallFrame,
        spectrogram: Spectrogram,
        toneFrequency: Float,
        centreBin: Int,
        binRadius: Int,
        taper: Float,
        strength: Float,
        to touches: inout [RealWAVCancellationTouch]
    ) {
        let frameCentre = frame.time
            + Double(spectrogram.fftSize)
            / Double(spectrogram.sampleRate) / 2
        let sigma = max(Float(binRadius) / 2, 0.75)

        for offset in -binRadius...binRadius {
            let bin = centreBin + offset
            guard frame.magnitudes.indices.contains(bin) else {
                continue
            }

            let frequencyWeight = expf(
                -Float(offset * offset)
                / (2 * sigma * sigma)
            )
            let appliedStrength = min(
                max(strength * taper * frequencyWeight, 0),
                1
            )

            touches.append(
                RealWAVCancellationTouch(
                    implementation: implementation,
                    symbolIndex: symbolIndex,
                    tone: tone,
                    symbolStartTime: symbolStart,
                    frameIndex: frameIndex,
                    frameTime: frame.time,
                    frameCentreTime: frameCentre,
                    frameTimingOffset: frameCentre - symbolStart,
                    toneFrequencyHz: toneFrequency,
                    centreBin: centreBin,
                    bin: bin,
                    binOffset: offset,
                    originalMagnitude: frame.magnitudes[bin],
                    originalDecibels: frame.decibels[bin],
                    frameNoiseFloorDB: frame.noiseFloorDB,
                    timeTaper: taper,
                    frequencyWeight: frequencyWeight,
                    appliedStrength: appliedStrength
                )
            )
        }
    }

    private static func nearestFrameIndex(
        in frames: [WaterfallFrame],
        time: Double
    ) -> Int? {
        guard !frames.isEmpty else { return nil }

        var bestIndex = 0
        var bestDistance = abs(frames[0].time - time)

        for index in 1..<frames.count {
            let distance = abs(frames[index].time - time)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    private static func nearestBin(
        frequency: Float,
        frame: WaterfallFrame
    ) -> Int {
        Int(
            (
                (frequency - frame.minimumFrequency)
                / frame.binWidth
            ).rounded()
        )
    }

    private static func timeTaper(
        symbolIndex: Int,
        symbolCount: Int,
        floor: Float
    ) -> Float {
        guard symbolCount > 1 else { return 1 }

        let midpoint = Float(symbolCount - 1) / 2
        let distance = abs(Float(symbolIndex) - midpoint)
            / max(midpoint, 1)

        return max(floor, 1 - distance * distance)
    }

    private static func ratio(
        numerator: Int,
        denominator: Int
    ) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }
}

private struct Cell: Hashable {
    let frameIndex: Int
    let bin: Int
}
