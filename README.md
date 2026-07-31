# FT8Kit

A native Swift implementation of the FT8 protocol and signal-generation pipeline.

## Current capability

Phase 2 provides:

- 77-bit standard and free-text message packing
- CRC-14
- LDPC(174,91) encoding
- 79-symbol FT8 tone generation
- Gaussian FSK audio synthesis
- 15-second mono WAV fixture generation

## Build

```bash
swift build
swift test
```

## Modules

- `FT8Protocol` — messages, bit packing, CRC and protocol constants
- `FT8Encoder` — LDPC encoder, tone mapper, waveform and WAV output
- `FT8Kit` — umbrella product containing both modules

See `docs/PHASE-2.md` and `docs/ROADMAP.md`.

## Phase 3.2

FT8DSP now includes a platform-independent waterfall and spectrogram engine,
noise-floor estimation, normalised intensity rows, and SNR-based spectral peak
detection.


## Phase 4.1

The package now includes `FT8Decoder`, a native Costas-based synchronisation
engine that searches waterfall data for FT8 start time, base frequency and
coarse drift and returns ranked, deduplicated `FT8Candidate` values.


## Phase 4.2

`FT8Decoder` now extracts 174 log-likelihood ratios from each synchronised
candidate, including Gray-map inversion, drift compensation, confidence
measurement and hard-decision verification against the native encoder.


## Phase 5

`FT8Decoder` now includes a native Swift LDPC(174,91) decoder with
normalised min-sum and sum-product algorithms, syndrome-based early exit,
91-bit information extraction and CRC validation.


## Phase 6

The package now includes a complete native decoding path from a synchronised
candidate through soft symbols, LDPC correction, CRC validation and
`FT8Message` unpacking. `FT8CompleteDecoder` returns only validated messages.


## Phase 7

`FT8OptimizedDecoder` adds confidence-ranked candidate scheduling, bounded
per-slot LDPC work, early rejection, deterministic duplicate suppression and
decode metrics. `FT8SlotDecoder` accepts PCM samples and returns validated
messages plus performance counters.


## Phase 8.1

`FT8LiveDecoder` now accepts arbitrary PCM chunks, stores them in a fixed-size
ring buffer and emits slot decode events at a configurable stride. Streaming
state is actor-isolated for safe use from audio capture callbacks and UI tasks.


## Phase 8.2

`FT8ParallelDecoder` performs bounded candidate decoding with Swift structured
concurrency. Results remain deterministic and retain the same candidate
ranking and duplicate suppression rules as the sequential decoder.


## Phase 8.3

DSP hot paths now use Accelerate on Apple platforms and a portable
`SIMD8<Float>` fallback elsewhere. Spectrum analysis, Costas correlation and
soft-symbol extraction use the vector layer without changing the public API.


## Phase 8.3.1

Corrected the Apple Accelerate `vvpowf` argument order. The previous Phase 8.3
archive passed on the portable fallback but produced incorrect linear powers
on macOS.


## Phase 9.1

FT8Kit now supports iterative multi-pass decoding. Successfully decoded
signals are reconstructed from their LDPC codewords and conservatively
cancelled from the spectrogram before subsequent passes. The decoder exposes
per-pass candidate, message, cancellation and residual-energy metrics.

## Phase 10 — Standard WAV validation

The package now includes the standard WSJT-X WAV corpus, a portable PCM WAV loader,
6.4 kHz to 12 kHz resampling, WSJT-X reference-output parsing, tolerance-aware
matching and the `ft8-validate` command-line regression runner.

Run the complete real-recording comparison with:

```bash
swift run -c release ft8-validate Tests/FT8ValidationTests/Fixtures
```

The normal `swift test` suite validates all 31 WAV fixtures and 22 supplied reference files, reference pairing, WAV
loading, resampling, parsing and matching without making the slow full-corpus decode
a mandatory unit-test step.


## Phase 11

FT8Kit now includes a UTC-aligned real-time slot engine. Timestamped PCM
chunks are assembled into exact FT8 slots, small audio gaps are repaired,
overlaps are removed, discontinuities are tracked, and complete slots are
decoded through the multi-pass engine. The API remains independent of
AVFoundation so it can be used on macOS, iOS and Linux.

## Validate against the original C decoder

FT8Kit includes a dual-decoder regression harness. It runs every WAV/TXT pair in
`ft8_lib/test/wav` through both the original `decode_ft8` C executable and the
Swift decoder, then compares:

- each decoder against the supplied expected TXT result;
- Swift against the C reference decoder;
- message text, frequency and timing within the configured tolerances.

Run it from the FT8Kit root:

```bash
FT8_LIB_ROOT=/path/to/ft8_lib ./validate-reference.sh
```

A machine-readable report is written to:

```text
.build/ft8-reference-validation.json
```

To include the reference corpus check after the Swift unit tests:

```bash
FT8_LIB_ROOT=/path/to/ft8_lib ./test.sh
```

The standalone Swift decoder adapter emits JSON Lines for one WAV:

```bash
swift run ft8-validate decode --json /path/to/recording.wav
```
