import Foundation

public struct ReferenceCase: Equatable, Sendable {
    public let name: String
    public let wavURL: URL
    public let expectedURL: URL?
}

public enum ReferenceCorpus {
    public static func discover(in directory: URL) throws -> [ReferenceCase] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let wavs = files.filter { $0.pathExtension.lowercased() == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let byStem = Dictionary(uniqueKeysWithValues: files.filter { $0.pathExtension.lowercased() == "txt" }.map { ($0.deletingPathExtension().lastPathComponent, $0) })
        return wavs.map { wav in
            let stem = wav.deletingPathExtension().lastPathComponent
            let fallbackStem = stem.hasSuffix("_12k") ? String(stem.dropLast(4)) : stem
            return ReferenceCase(name: stem, wavURL: wav, expectedURL: byStem[stem] ?? byStem[fallbackStem])
        }
    }
}
