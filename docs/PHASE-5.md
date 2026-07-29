# Phase 5 — Native FT8 LDPC Decoder

Phase 5 adds a native Swift decoder for the systematic FT8 LDPC(174,91)
code.

## Included

- Sparse parity-check graph derived from the encoder generator matrix
- Syndrome calculation and parity validation
- Normalised min-sum belief propagation
- Sum-product belief propagation
- Configurable iteration limit, damping, clipping and normalisation
- Early termination on a zero syndrome
- Extraction of the 91 information bits
- CRC-14 validation
- Candidate-to-soft-symbol-to-LDPC pipeline
- Encoder/decoder regression tests

## Usage

```swift
let result = try FT8LDPCDecoder().decode(softSymbols)

guard result.parityPassed, result.crcPassed else {
    return
}

let message91 = result.informationBits
```

Phase 6 will unpack the validated 77-bit payload into native FT8 message
types and decoded display text.
