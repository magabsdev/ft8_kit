#!/usr/bin/env python3
"""Compare FT8Kit, ft8_lib and the supplied expected TXT corpus."""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Iterable


@dataclass(frozen=True)
class Decode:
    message: str
    frequency_hz: float
    time_seconds: float
    snr_db: float | None


def normalize_message(message: str) -> str:
    fields = message.upper().split()
    normalized: list[str] = []
    for field in fields[:3]:
        if field.startswith("<") and field.endswith(">"):
            normalized.append("<...>")
        else:
            normalized.append(field)
    return " ".join(normalized)


def parse_reference_line(line: str) -> Decode | None:
    fields = line.strip().split(maxsplit=5)
    if len(fields) < 6:
        return None
    try:
        snr = float(fields[1])
        dt = float(fields[2])
        frequency = float(fields[3])
    except ValueError:
        return None
    return Decode(fields[5].strip(), frequency, dt, snr)


def parse_expected(path: pathlib.Path) -> list[Decode]:
    return [item for line in path.read_text(encoding="utf-8").splitlines() if (item := parse_reference_line(line))]


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)


def run_c_decoder(executable: pathlib.Path, wav: pathlib.Path) -> list[Decode]:
    result = run([str(executable), str(wav)])
    if result.returncode != 0:
        raise RuntimeError(f"C decoder failed for {wav.name}:\n{result.stderr or result.stdout}")
    return [item for line in result.stdout.splitlines() if (item := parse_reference_line(line))]


def run_swift_decoder(executable: pathlib.Path, wav: pathlib.Path) -> list[Decode]:
    result = run([str(executable), "decode", "--json", str(wav)])
    if result.returncode != 0:
        raise RuntimeError(f"Swift decoder failed for {wav.name}:\n{result.stderr or result.stdout}")
    decoded: list[Decode] = []
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        payload = json.loads(line)
        decoded.append(Decode(
            message=str(payload["message"]),
            frequency_hz=float(payload["frequencyHz"]),
            time_seconds=float(payload["timeSeconds"]),
            snr_db=float(payload["snrDB"]) if payload.get("snrDB") is not None else None,
        ))
    return decoded


def match(expected: Iterable[Decode], observed: Iterable[Decode], frequency_tolerance: float, time_tolerance: float):
    remaining = list(observed)
    pairs: list[tuple[Decode, Decode]] = []
    missed: list[Decode] = []

    for target in expected:
        best_index: int | None = None
        best_score = math.inf
        for index, candidate in enumerate(remaining):
            if normalize_message(candidate.message) != normalize_message(target.message):
                continue
            df = abs(candidate.frequency_hz - target.frequency_hz)
            dt = abs(candidate.time_seconds - target.time_seconds)
            if df > frequency_tolerance or dt > time_tolerance:
                continue
            score = df / max(frequency_tolerance, 0.001) + dt / max(time_tolerance, 0.001)
            if score < best_score:
                best_score = score
                best_index = index
        if best_index is None:
            missed.append(target)
        else:
            pairs.append((target, remaining.pop(best_index)))

    return pairs, missed, remaining


def fallback_expected_path(wav: pathlib.Path) -> pathlib.Path | None:
    direct = wav.with_suffix(".txt")
    if direct.exists():
        return direct
    if wav.stem.endswith("_12k"):
        fallback = wav.with_name(wav.stem[:-4] + ".txt")
        if fallback.exists():
            return fallback
    return None


def describe(items: Iterable[Decode]) -> list[str]:
    return [f"{item.message} @ {item.frequency_hz:.1f} Hz, dt={item.time_seconds:+.2f}s" for item in items]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", required=True, type=pathlib.Path)
    parser.add_argument("--c-decoder", required=True, type=pathlib.Path)
    parser.add_argument("--swift-decoder", required=True, type=pathlib.Path)
    parser.add_argument("--frequency-tolerance", type=float, default=12.5)
    parser.add_argument("--time-tolerance", type=float, default=0.35)
    parser.add_argument("--minimum-swift-recall", type=float, default=1.0)
    parser.add_argument("--report", type=pathlib.Path)
    args = parser.parse_args()

    wavs = sorted(args.corpus.glob("*.wav"))
    if not wavs:
        parser.error(f"No WAV files found in {args.corpus}")

    totals = {
        "files": 0,
        "expected": 0,
        "cMatched": 0,
        "cMissed": 0,
        "cUnexpected": 0,
        "swiftMatched": 0,
        "swiftMissed": 0,
        "swiftUnexpected": 0,
        "swiftVsCMatched": 0,
        "swiftVsCMissed": 0,
        "swiftVsCUnexpected": 0,
    }
    details: list[dict] = []

    for wav in wavs:
        expected_path = fallback_expected_path(wav)
        if expected_path is None:
            continue
        expected = parse_expected(expected_path)
        c_decodes = run_c_decoder(args.c_decoder, wav)
        swift_decodes = run_swift_decoder(args.swift_decoder, wav)

        c_pairs, c_missed, c_extra = match(expected, c_decodes, args.frequency_tolerance, args.time_tolerance)
        swift_pairs, swift_missed, swift_extra = match(expected, swift_decodes, args.frequency_tolerance, args.time_tolerance)
        cross_pairs, cross_missed, cross_extra = match(c_decodes, swift_decodes, args.frequency_tolerance, args.time_tolerance)

        totals["files"] += 1
        totals["expected"] += len(expected)
        totals["cMatched"] += len(c_pairs)
        totals["cMissed"] += len(c_missed)
        totals["cUnexpected"] += len(c_extra)
        totals["swiftMatched"] += len(swift_pairs)
        totals["swiftMissed"] += len(swift_missed)
        totals["swiftUnexpected"] += len(swift_extra)
        totals["swiftVsCMatched"] += len(cross_pairs)
        totals["swiftVsCMissed"] += len(cross_missed)
        totals["swiftVsCUnexpected"] += len(cross_extra)

        status = "PASS" if not swift_missed and not cross_missed and not cross_extra else "DIFF"
        print(f"{status:4} {wav.name}: expected={len(expected)} C={len(c_decodes)} Swift={len(swift_decodes)}")
        if swift_missed:
            print("     Swift missed:", describe(swift_missed))
        if swift_extra:
            print("     Swift unexpected:", describe(swift_extra))
        if cross_missed:
            print("     Missing versus C:", describe(cross_missed))
        if cross_extra:
            print("     Extra versus C:", describe(cross_extra))

        details.append({
            "wav": wav.name,
            "expected": len(expected),
            "c": {"decoded": len(c_decodes), "matched": len(c_pairs), "missed": describe(c_missed), "unexpected": describe(c_extra)},
            "swift": {"decoded": len(swift_decodes), "matched": len(swift_pairs), "missed": describe(swift_missed), "unexpected": describe(swift_extra)},
            "swiftVsC": {"matched": len(cross_pairs), "missing": describe(cross_missed), "extra": describe(cross_extra)},
        })

    expected_total = totals["expected"]
    swift_recall = 1.0 if expected_total == 0 else totals["swiftMatched"] / expected_total
    c_recall = 1.0 if expected_total == 0 else totals["cMatched"] / expected_total

    print("\nFT8 reference validation")
    print(f"Files:             {totals['files']}")
    print(f"Expected messages: {expected_total}")
    print(f"C recall:          {c_recall * 100:.2f}%")
    print(f"Swift recall:      {swift_recall * 100:.2f}%")
    print(f"Swift missed:      {totals['swiftMissed']}")
    print(f"Swift unexpected:  {totals['swiftUnexpected']}")
    print(f"C/Swift diffs:     {totals['swiftVsCMissed'] + totals['swiftVsCUnexpected']}")

    report = {"summary": totals | {"cRecall": c_recall, "swiftRecall": swift_recall}, "files": details}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"Report:            {args.report}")

    passed = (
        swift_recall >= args.minimum_swift_recall
        and totals["swiftVsCMissed"] == 0
        and totals["swiftVsCUnexpected"] == 0
    )
    print("Result:            " + ("PASS" if passed else "FAIL"))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
