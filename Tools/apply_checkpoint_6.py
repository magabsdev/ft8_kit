#!/usr/bin/env python3
from pathlib import Path
import sys

path = Path("Sources/ft8-validate/main.swift")
if not path.exists():
    sys.exit(f"Missing {path}")

source = path.read_text()

old_signature = (
    "private func analyseWAV(at url: URL) throws -> "
    "(WAVRecording, Spectrogram, FT8MultiPassDecodeBatch) {"
)
new_signature = (
    "private func analyseWAV(at url: URL) async throws -> "
    "(WAVRecording, Spectrogram, FT8MultiPassDecodeBatch) {"
)
if old_signature not in source:
    sys.exit("Could not find analyseWAV signature.")
source = source.replace(old_signature, new_signature, 1)

old_call = '''    let result = try slotDecoder.decoder.decode(
        spectrogram: spectrogram
    )
'''

new_call = '''    let parallelDecoder = FT8ParallelMultiPassDecoder(
        configuration: slotDecoder.decoder.configuration,
        decoder: FT8ParallelDecoder(
            optimizedConfiguration:
                slotDecoder.decoder.decoder.configuration,
            synchronizer:
                slotDecoder.decoder.decoder.synchronizer,
            extractor:
                slotDecoder.decoder.decoder.extractor,
            ldpcDecoder:
                slotDecoder.decoder.decoder.ldpcDecoder,
            messageDecoder:
                slotDecoder.decoder.decoder.messageDecoder
        ),
        canceller: slotDecoder.decoder.canceller
    )

    let result = try await parallelDecoder.decode(
        spectrogram: spectrogram
    )
'''
if old_call not in source:
    sys.exit("Could not find sequential decoder call.")
source = source.replace(old_call, new_call, 1)

source = source.replace(
    "private func runDecode(arguments: [String]) throws {",
    "private func runDecode(arguments: [String]) async throws {",
    1
)
source = source.replace(
    "let (recording, spectrogram, result) = try analyseWAV(at: wavURL)",
    "let (recording, spectrogram, result) = "
    "try await analyseWAV(at: wavURL)",
    1
)
source = source.replace(
    "private func runCorpus(directory: URL) throws {",
    "private func runCorpus(directory: URL) async throws {",
    1
)
source = source.replace(
    "let (_, _, result) = try analyseWAV(at: item.wavURL)",
    "let (_, _, result) = try await analyseWAV(at: item.wavURL)",
    1
)
source = source.replace(
    "try runDecode(arguments: Array(arguments.dropFirst()))",
    "try await runDecode(arguments: Array(arguments.dropFirst()))",
    1
)
source = source.replace(
    "try runCorpus(directory: URL(fileURLWithPath: arguments[1]))",
    "try await runCorpus(directory: URL(fileURLWithPath: arguments[1]))",
    1
)
source = source.replace(
    'try runCorpus(directory: URL(fileURLWithPath: arguments.first ?? '
    '"Tests/FT8ValidationTests/Fixtures"))',
    'try await runCorpus(directory: URL(fileURLWithPath: '
    'arguments.first ?? "Tests/FT8ValidationTests/Fixtures"))',
    1
)

path.write_text(source)
print(f"Patched {path}")
