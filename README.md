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
