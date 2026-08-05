#!/usr/bin/env python3
from pathlib import Path
import sys

package = Path("Package.swift")
main = Path("Sources/ft8-validate/main.swift")

if not package.exists() or not main.exists():
    sys.exit("Run from the FT8Kit repository root.")

package_source = package.read_text()
main_source = main.read_text()

old = '.executableTarget(name: "ft8-validate", dependencies: ["FT8Decoder", "FT8Validation"])'
new = '.executableTarget(name: "ft8-validate", dependencies: ["FT8Decoder", "FT8Validation", "FT8Encoder", "FT8Protocol"])'

if old in package_source:
    package_source = package_source.replace(old, new, 1)
elif new not in package_source:
    sys.exit("ft8-validate dependency declaration not found.")

old = '''    var auditDirectory: String?
    var wavPath: String?
'''
new = '''    var auditDirectory: String?
    var expectedMessages: [String] = []
    var expectedFrequencyHz: Double?
    var expectedTimeSeconds: Double?
    var wavPath: String?
'''
if old not in main_source:
    sys.exit("DecodeOptions block not found.")
main_source = main_source.replace(old, new, 1)

old = '''        case "--audit-dir":
            index += 1
            guard index < arguments.count else {
                throw CLIError.missingValue(argument)
            }
            options.auditDirectory = arguments[index]
'''
new = '''        case "--audit-dir":
            index += 1
            guard index < arguments.count else {
                throw CLIError.missingValue(argument)
            }
            options.auditDirectory = arguments[index]
        case "--expected-message":
            index += 1
            guard index < arguments.count else {
                throw CLIError.missingValue(argument)
            }
            options.expectedMessages.append(arguments[index])
        case "--expected-frequency":
            index += 1
            guard index < arguments.count,
                  let value = Double(arguments[index]) else {
                throw CLIError.missingValue(argument)
            }
            options.expectedFrequencyHz = value
        case "--expected-time":
            index += 1
            guard index < arguments.count,
                  let value = Double(arguments[index]) else {
                throw CLIError.missingValue(argument)
            }
            options.expectedTimeSeconds = value
'''
if old not in main_source:
    sys.exit("Audit option parser not found.")
main_source = main_source.replace(old, new, 1)

old = '''        try FT8AuditWriter().write(
            batch: auditBatch,
            to: URL(fileURLWithPath: directory, isDirectory: true)
        )

        FileHandle.standardError.write(
            Data("[ft8-validate] Audit written to \\(directory)\\n".utf8)
        )
'''
new = '''        let auditURL = URL(
            fileURLWithPath: directory,
            isDirectory: true
        )

        try FT8AuditWriter().write(
            batch: auditBatch,
            to: auditURL
        )

        if !options.expectedMessages.isEmpty {
            let expectations = options.expectedMessages.map {
                FT8ReferenceExpectation(
                    message: $0,
                    frequencyHz: options.expectedFrequencyHz,
                    timeSeconds: options.expectedTimeSeconds
                )
            }
            let comparator = FT8ReferenceComparator()
            let comparison = try comparator.compare(
                traces: auditBatch.candidateTraces,
                expectations: expectations
            )
            try comparator.write(comparison, to: auditURL)
            comparator.printSummary(comparison)
        }

        FileHandle.standardError.write(
            Data("[ft8-validate] Audit written to \\(directory)\\n".utf8)
        )
'''
if old not in main_source:
    sys.exit("Audit write block not found.")
main_source = main_source.replace(old, new, 1)

package.write_text(package_source)
main.write_text(main_source)
print("Patched Package.swift")
print("Patched Sources/ft8-validate/main.swift")
