import Foundation

public enum FT8WAVEncoderError: Error, Equatable, Sendable {
    case sampleCountTooLarge
}

public enum FT8WAVEncoder {
    public static func pcm16Data(samples: [Float], sampleRate: Int = 12_000) throws -> Data {
        let dataByteCount = samples.count.multipliedReportingOverflow(by: 2)
        guard !dataByteCount.overflow, dataByteCount.partialValue <= Int(UInt32.max) - 36 else {
            throw FT8WAVEncoderError.sampleCountTooLarge
        }

        var output = Data()
        output.reserveCapacity(44 + dataByteCount.partialValue)
        output.appendASCII("RIFF")
        output.appendLE(UInt32(36 + dataByteCount.partialValue))
        output.appendASCII("WAVE")
        output.appendASCII("fmt ")
        output.appendLE(UInt32(16))
        output.appendLE(UInt16(1))
        output.appendLE(UInt16(1))
        output.appendLE(UInt32(sampleRate))
        output.appendLE(UInt32(sampleRate * 2))
        output.appendLE(UInt16(2))
        output.appendLE(UInt16(16))
        output.appendASCII("data")
        output.appendLE(UInt32(dataByteCount.partialValue))

        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let scaled = clamped < 0 ? clamped * 32_768 : clamped * 32_767
            output.appendLE(Int16(scaled.rounded()))
        }
        return output
    }

    public static func writePCM16(samples: [Float], sampleRate: Int = 12_000, to url: URL) throws {
        try pcm16Data(samples: samples, sampleRate: sampleRate).write(to: url, options: .atomic)
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) { append(contentsOf: string.utf8) }
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
