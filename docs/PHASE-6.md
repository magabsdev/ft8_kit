# Phase 6 — CRC and Message Decoding

Phase 6 completes the native bit-to-message path.

## Added

- `FT8MessageDecoder`
- `FT8DecodedMessage`
- Mandatory parity and CRC validation before unpacking
- Native 77-bit payload extraction
- Standard-message unpacking
- Free-text unpacking
- Telemetry and unsupported-type preservation through `FT8Message`
- Complete waterfall-to-message pipeline
- Duplicate decoded-message suppression
- Confidence propagation from soft symbols and LDPC iterations
- End-to-end encoder → LLR → LDPC → message tests

## Complete pipeline

```text
PCM
  -> waterfall
  -> synchronisation candidates
  -> 174 soft bits
  -> LDPC(174,91)
  -> CRC-14
  -> 77-bit payload
  -> FT8Message
```

## Usage

```swift
let decoder = FT8CompleteDecoder()
let messages = try decoder.decode(spectrogram: spectrogram)

for result in messages {
    print(result.text)
    print(result.candidate.frequency)
    print(result.decoded.confidence)
}
```

Only candidates that pass both LDPC parity and CRC validation are returned by
the complete decoder.
