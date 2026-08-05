#!/usr/bin/env python3
from pathlib import Path
import sys

path = Path("Sources/ft8-validate/main.swift")
if not path.exists():
    sys.exit(f"Missing {path}")

source = path.read_text()

replacements = [
(
'''    var dumpDirectory: String?
    var wavPath: String?
''',
'''    var dumpDirectory: String?
    var auditDirectory: String?
    var wavPath: String?
'''
),
(
'''        case "--dump-debug":
            index += 1
            guard index < arguments.count else {
                throw CLIError.missingValue(argument)
            }
            options.dumpDirectory = arguments[index]
''',
'''        case "--dump-debug":
            index += 1
            guard index < arguments.count else {
                throw CLIError.missingValue(argument)
            }
            options.dumpDirectory = arguments[index]
        case "--audit-dir":
            index += 1
            guard index < arguments.count else {
                throw CLIError.missingValue(argument)
            }
            options.auditDirectory = arguments[index]
'''
),
(
'''    if let directory = options.dumpDirectory {
        try dumpDebug(directoryPath: directory, recording: recording, spectrogram: spectrogram, report: report)
    }

    if options.diagnostics {
''',
'''    if let directory = options.dumpDirectory {
        try dumpDebug(directoryPath: directory, recording: recording, spectrogram: spectrogram, report: report)
    }

    if let directory = options.auditDirectory {
        var configuration = FT8OptimizedDecoderConfiguration()
        configuration.captureCandidateTraces = true

        let auditBatch = try FT8OptimizedDecoder(
            configuration: configuration
        ).decode(spectrogram: spectrogram)

        try FT8AuditWriter().write(
            batch: auditBatch,
            to: URL(fileURLWithPath: directory, isDirectory: true)
        )

        FileHandle.standardError.write(
            Data("[ft8-validate] Audit written to \\(directory)\\n".utf8)
        )
    }

    if options.diagnostics {
'''
)
]

for old, new in replacements:
    if old not in source:
        sys.exit("Expected main.swift block was not found.")
    source = source.replace(old, new, 1)

path.write_text(source)
print(f"Patched {path}")
