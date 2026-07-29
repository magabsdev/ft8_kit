# Phase 1 — Protocol layer

This checkpoint isolates the deterministic protocol components from the Signal8 application.

Implemented:

- `FT8BitBuffer`
- `FT8CRC`
- `FT8Message`
- `FT8MessageCodec`
- `FT8GrayCode`
- protocol constants

Scope limitations:

- Full non-standard callsign and contest message families are not yet exposed.
- LDPC, waveform generation and DSP decoding are deliberately deferred.
- C reference code is retained only for parity work and licensing traceability.
