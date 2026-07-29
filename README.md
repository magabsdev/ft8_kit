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
