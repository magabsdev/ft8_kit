#!/usr/bin/env python3
"""Validate an FT8 decoder against ft8_lib WAV/TXT corpus and optional C oracle.

The decoder command must print one decode per line in WSJT-X-like form, e.g.:
000000 -17 -0.6 309 ~ G4CUS SP4FCA +10

Use {wav} in command templates. Example:
  --swift-command '.build/debug/ft8-validate decode --wsjtx {wav}'
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True, order=True)
class Decode:
    message: str
    frequency_hz: float | None = None
    time_seconds: float | None = None
    snr_db: float | None = None


def normalise_message(text: str) -> str:
    return " ".join(text.strip().split())


def parse_wsjtx_line(line: str) -> Decode | None:
    fields = line.strip().split()
    if not fields or "~" not in fields:
        return None
    marker = fields.index("~")
    if marker < 4 or marker + 1 >= len(fields):
        return None
    try:
        snr = float(fields[1])
        time_offset = float(fields[2])
        frequency = float(fields[3])
    except ValueError:
        return None
    message = normalise_message(" ".join(fields[marker + 1 :]))
    if not message:
        return None
    return Decode(message=message, frequency_hz=frequency, time_seconds=time_offset, snr_db=snr)


def parse_json_line(line: str) -> Decode | None:
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        return None
    if not isinstance(obj, dict):
        return None
    text = obj.get("message") or obj.get("text") or obj.get("decodedText")
    if not isinstance(text, str) or not text.strip():
        return None
    def number(*names: str) -> float | None:
        for name in names:
            value = obj.get(name)
            if isinstance(value, (int, float)):
                return float(value)
        return None
    return Decode(
        message=normalise_message(text),
        frequency_hz=number("frequencyHz", "frequency", "freqHz"),
        time_seconds=number("timeSeconds", "timeOffset", "dt"),
        snr_db=number("snrDb", "snr"),
    )


def parse_output(text: str) -> list[Decode]:
    decodes: list[Decode] = []
    for line in text.splitlines():
        item = parse_json_line(line) or parse_wsjtx_line(line)
        if item is not None:
            decodes.append(item)
    return decodes


def run_command(template: str, wav: Path, cwd: Path | None = None) -> list[Decode]:
    command = template.replace("{wav}", shlex.quote(str(wav)))
    completed = subprocess.run(
        command,
        shell=True,
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"Command failed ({completed.returncode}): {command}\n"
            f"STDOUT:\n{completed.stdout}\nSTDERR:\n{completed.stderr}"
        )
    return parse_output(completed.stdout)


def load_expected(path: Path) -> list[Decode]:
    return parse_output(path.read_text(encoding="utf-8", errors="replace"))


def message_key(message: str) -> str:
    parts = normalise_message(message).split()
    # ft8_lib expected files sometimes append a country name after CQ call grid.
    # Protocol messages are at most three principal fields for the supported corpus.
    return " ".join(parts[:3])


def canonical(decodes: Iterable[Decode]) -> dict[str, list[Decode]]:
    result: dict[str, list[Decode]] = {}
    for decode in decodes:
        result.setdefault(message_key(decode.message), []).append(decode)
    return result


def nearest_match(actual: Decode, candidates: list[Decode]) -> Decode:
    def distance(candidate: Decode) -> float:
        score = 0.0
        if actual.frequency_hz is not None and candidate.frequency_hz is not None:
            score += abs(actual.frequency_hz - candidate.frequency_hz)
        if actual.time_seconds is not None and candidate.time_seconds is not None:
            score += 100.0 * abs(actual.time_seconds - candidate.time_seconds)
        return score
    return min(candidates, key=distance)


def compare(
    expected: list[Decode],
    actual: list[Decode],
    frequency_tolerance: float,
    time_tolerance: float,
    snr_tolerance: float | None,
) -> dict:
    exp = canonical(expected)
    act = canonical(actual)
    expected_messages = set(exp)
    actual_messages = set(act)
    missing = sorted(expected_messages - actual_messages)
    extra = sorted(actual_messages - expected_messages)
    matched = sorted(expected_messages & actual_messages)

    timing_failures: list[dict] = []
    frequency_failures: list[dict] = []
    snr_failures: list[dict] = []
    for key in matched:
        for actual_decode in act[key]:
            reference = nearest_match(actual_decode, exp[key])
            if actual_decode.frequency_hz is not None and reference.frequency_hz is not None:
                error = abs(actual_decode.frequency_hz - reference.frequency_hz)
                if error > frequency_tolerance:
                    frequency_failures.append({"message": key, "errorHz": error})
            if actual_decode.time_seconds is not None and reference.time_seconds is not None:
                error = abs(actual_decode.time_seconds - reference.time_seconds)
                if error > time_tolerance:
                    timing_failures.append({"message": key, "errorSeconds": error})
            if (
                snr_tolerance is not None
                and actual_decode.snr_db is not None
                and reference.snr_db is not None
            ):
                error = abs(actual_decode.snr_db - reference.snr_db)
                if error > snr_tolerance:
                    snr_failures.append({"message": key, "errorDb": error})

    return {
        "expected": len(expected_messages),
        "actual": len(actual_messages),
        "matched": len(matched),
        "missing": missing,
        "extra": extra,
        "frequencyFailures": frequency_failures,
        "timingFailures": timing_failures,
        "snrFailures": snr_failures,
    }


def discover(corpus: Path) -> list[tuple[Path, Path]]:
    pairs: list[tuple[Path, Path]] = []
    for wav in sorted(corpus.rglob("*.wav")):
        expected = wav.with_suffix(".txt")
        if expected.exists():
            pairs.append((wav, expected))
    return pairs


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus", type=Path, help="Directory containing paired .wav/.txt files")
    parser.add_argument("--swift-command", required=True, help="Command template containing {wav}")
    parser.add_argument("--swift-cwd", type=Path)
    parser.add_argument("--c-command", help="Optional C decoder command template containing {wav}")
    parser.add_argument("--c-cwd", type=Path)
    parser.add_argument("--frequency-tolerance", type=float, default=6.25)
    parser.add_argument("--time-tolerance", type=float, default=0.16)
    parser.add_argument("--snr-tolerance", type=float)
    parser.add_argument("--minimum-recall", type=float, default=1.0)
    parser.add_argument("--allow-extra", action="store_true")
    parser.add_argument("--json-report", type=Path)
    args = parser.parse_args()

    pairs = discover(args.corpus)
    if not pairs:
        print(f"No paired WAV/TXT files found under {args.corpus}", file=sys.stderr)
        return 2

    reports: list[dict] = []
    total_expected = total_matched = total_extra = 0
    failed_files = 0

    for wav, expected_path in pairs:
        expected = load_expected(expected_path)
        swift = run_command(args.swift_command, wav, args.swift_cwd)
        swift_result = compare(
            expected,
            swift,
            args.frequency_tolerance,
            args.time_tolerance,
            args.snr_tolerance,
        )
        record = {
            "wav": str(wav),
            "expectedFile": str(expected_path),
            "swift": swift_result,
        }

        if args.c_command:
            c_decodes = run_command(args.c_command, wav, args.c_cwd)
            record["cReference"] = compare(
                expected,
                c_decodes,
                args.frequency_tolerance,
                args.time_tolerance,
                args.snr_tolerance,
            )
            record["swiftVsC"] = compare(
                c_decodes,
                swift,
                args.frequency_tolerance,
                args.time_tolerance,
                args.snr_tolerance,
            )

        reports.append(record)
        total_expected += swift_result["expected"]
        total_matched += swift_result["matched"]
        total_extra += len(swift_result["extra"])

        file_failed = bool(
            swift_result["missing"]
            or swift_result["frequencyFailures"]
            or swift_result["timingFailures"]
            or swift_result["snrFailures"]
            or (swift_result["extra"] and not args.allow_extra)
        )
        if file_failed:
            failed_files += 1
            print(f"FAIL {wav}")
            if swift_result["missing"]:
                print("  Missing:", "; ".join(swift_result["missing"]))
            if swift_result["extra"]:
                print("  Extra:  ", "; ".join(swift_result["extra"]))
            if swift_result["timingFailures"]:
                print("  Timing failures:", swift_result["timingFailures"])
            if swift_result["frequencyFailures"]:
                print("  Frequency failures:", swift_result["frequencyFailures"])
        else:
            print(f"PASS {wav} ({swift_result['matched']}/{swift_result['expected']})")

    recall = total_matched / total_expected if total_expected else 1.0
    summary = {
        "files": len(pairs),
        "failedFiles": failed_files,
        "expectedMessages": total_expected,
        "matchedMessages": total_matched,
        "extraMessages": total_extra,
        "recall": recall,
        "configuration": {
            "frequencyToleranceHz": args.frequency_tolerance,
            "timeToleranceSeconds": args.time_tolerance,
            "snrToleranceDb": args.snr_tolerance,
            "minimumRecall": args.minimum_recall,
            "allowExtra": args.allow_extra,
        },
        "filesReport": reports,
    }
    print("\nSummary")
    print(f"  Files:    {len(pairs)}")
    print(f"  Failed:   {failed_files}")
    print(f"  Messages: {total_matched}/{total_expected}")
    print(f"  Recall:   {recall * 100:.2f}%")
    print(f"  Extra:    {total_extra}")

    if args.json_report:
        args.json_report.parent.mkdir(parents=True, exist_ok=True)
        args.json_report.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    if recall < args.minimum_recall:
        return 1
    if failed_files > 0:
        return 1
    if total_extra > 0 and not args.allow_extra:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
