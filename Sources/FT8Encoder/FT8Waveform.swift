import Foundation

public struct FT8WaveformConfiguration: Equatable, Sendable {
    public var sampleRate: Int
    public var baseFrequency: Double
    public var amplitude: Float
    public var padToSlot: Bool

    public init(
        sampleRate: Int = 12_000,
        baseFrequency: Double = 1_000,
        amplitude: Float = 0.8,
        padToSlot: Bool = true
    ) {
        precondition(sampleRate > 0)
        precondition(baseFrequency >= 0)
        precondition(amplitude >= 0 && amplitude <= 1)
        self.sampleRate = sampleRate
        self.baseFrequency = baseFrequency
        self.amplitude = amplitude
        self.padToSlot = padToSlot
    }
}

public enum FT8Waveform {
    public static let symbolPeriod = 0.160
    public static let slotDuration = 15.0
    public static let gaussianBT = 2.0
    private static let gfskConstant = 5.336446

    public static func generate(
        tones: [UInt8],
        configuration: FT8WaveformConfiguration = .init()
    ) -> [Float] {
        precondition(tones.count == FT8Encoder.toneCount)
        precondition(tones.allSatisfy { $0 < 8 })

        let samplesPerSymbol = Int((Double(configuration.sampleRate) * symbolPeriod).rounded())
        let waveformCount = tones.count * samplesPerSymbol
        let extendedCount = waveformCount + 2 * samplesPerSymbol
        let baseIncrement = 2 * Double.pi * configuration.baseFrequency / Double(configuration.sampleRate)
        let peakIncrement = 2 * Double.pi / Double(samplesPerSymbol)

        var phaseIncrement = [Double](repeating: baseIncrement, count: extendedCount)
        let pulse = gaussianPulse(samplesPerSymbol: samplesPerSymbol)

        for (symbolIndex, tone) in tones.enumerated() {
            let start = symbolIndex * samplesPerSymbol
            let scale = peakIncrement * Double(tone)
            for index in pulse.indices {
                phaseIncrement[start + index] += scale * pulse[index]
            }
        }

        var signal = [Float](repeating: 0, count: waveformCount)
        var phase = 0.0
        for index in 0..<waveformCount {
            signal[index] = Float(sin(phase)) * configuration.amplitude
            phase.formTruncatingRemainder(dividingBy: 2 * Double.pi)
            phase += phaseIncrement[index + samplesPerSymbol]
        }

        let rampCount = samplesPerSymbol / 8
        if rampCount > 0 {
            for index in 0..<rampCount {
                let envelope = (1 - cos(2 * Double.pi * Double(index) / Double(2 * rampCount))) / 2
                signal[index] *= Float(envelope)
                signal[signal.count - 1 - index] *= Float(envelope)
            }
        }

        guard configuration.padToSlot else { return signal }
        let slotCount = Int((Double(configuration.sampleRate) * slotDuration).rounded())
        precondition(signal.count <= slotCount)
        let leading = (slotCount - signal.count) / 2
        let trailing = slotCount - signal.count - leading
        return [Float](repeating: 0, count: leading) + signal + [Float](repeating: 0, count: trailing)
    }

    private static func gaussianPulse(samplesPerSymbol: Int) -> [Double] {
        (0..<(3 * samplesPerSymbol)).map { index in
            let time = Double(index) / Double(samplesPerSymbol) - 1.5
            let arg1 = gfskConstant * gaussianBT * (time + 0.5)
            let arg2 = gfskConstant * gaussianBT * (time - 0.5)
            return (erf(arg1) - erf(arg2)) / 2
        }
    }
}
