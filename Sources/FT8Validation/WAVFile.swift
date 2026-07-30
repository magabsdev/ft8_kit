import Foundation

public enum WAVError: Error, Equatable, Sendable {
    case invalidHeader
    case unsupportedFormat(audioFormat: UInt16, channels: UInt16, bitsPerSample: UInt16)
    case missingDataChunk
    case malformedChunk
}

public struct WAVRecording: Equatable, Sendable {
    public let sampleRate: Int
    public let samples: [Float]
    public init(sampleRate: Int, samples: [Float]) { self.sampleRate = sampleRate; self.samples = samples }
}

public enum WAVFile {
    public static func load(url: URL, targetSampleRate: Int? = 12_000) throws -> WAVRecording {
        let data = try Data(contentsOf: url)
        guard data.count >= 12, data.ascii(0..<4) == "RIFF", data.ascii(8..<12) == "WAVE" else { throw WAVError.invalidHeader }
        var offset = 12
        var format: (UInt16, UInt16, UInt32, UInt16)?
        var pcm: Data?
        while offset + 8 <= data.count {
            let id = data.ascii(offset..<(offset + 4))
            let size = Int(data.u32(offset + 4))
            let start = offset + 8
            guard start + size <= data.count else { throw WAVError.malformedChunk }
            if id == "fmt " {
                guard size >= 16 else { throw WAVError.malformedChunk }
                format = (data.u16(start), data.u16(start + 2), data.u32(start + 4), data.u16(start + 14))
            } else if id == "data" { pcm = data.subdata(in: start..<(start + size)) }
            offset = start + size + (size & 1)
        }
        guard let f = format else { throw WAVError.invalidHeader }
        guard f.0 == 1, f.1 == 1, f.3 == 16 else { throw WAVError.unsupportedFormat(audioFormat: f.0, channels: f.1, bitsPerSample: f.3) }
        guard let pcm else { throw WAVError.missingDataChunk }
        var samples = [Float](); samples.reserveCapacity(pcm.count / 2)
        var i = 0
        while i + 1 < pcm.count {
            let value = Int16(bitPattern: UInt16(pcm[i]) | UInt16(pcm[i + 1]) << 8)
            samples.append(Float(value) / 32768)
            i += 2
        }
        let sourceRate = Int(f.2)
        guard let targetSampleRate, targetSampleRate != sourceRate else { return WAVRecording(sampleRate: sourceRate, samples: samples) }
        return WAVRecording(sampleRate: targetSampleRate, samples: LinearResampler.resample(samples, from: sourceRate, to: targetSampleRate))
    }
}

public enum LinearResampler {
    public static func resample(_ input: [Float], from sourceRate: Int, to targetRate: Int) -> [Float] {
        guard !input.isEmpty, sourceRate > 0, targetRate > 0, sourceRate != targetRate else { return input }
        let outputCount = Int((Double(input.count) * Double(targetRate) / Double(sourceRate)).rounded())
        var output = [Float](repeating: 0, count: outputCount)
        let ratio = Double(sourceRate) / Double(targetRate)
        for index in output.indices {
            let position = Double(index) * ratio
            let lower = min(Int(position), input.count - 1)
            let upper = min(lower + 1, input.count - 1)
            let fraction = Float(position - Double(lower))
            output[index] = input[lower] + (input[upper] - input[lower]) * fraction
        }
        return output
    }
}

private extension Data {
    func ascii(_ range: Range<Int>) -> String { String(decoding: self[range], as: UTF8.self) }
    func u16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24 }
}
