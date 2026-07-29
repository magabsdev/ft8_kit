# Phase 4.2 — Soft-Symbol Extraction

Phase 4.2 converts each synchronised FT8 candidate into the 174 soft bit
metrics required by the LDPC decoder.

## Included

- Eight-tone energy integration for all 58 FT8 data symbols
- FT8 Gray-map inversion
- 174 max-log likelihood ratios
- Positive LLR means bit 0; negative LLR means bit 1
- Configurable LLR scaling and clipping
- Frequency-drift compensation
- Per-symbol and average confidence
- Hard-decision codeword generation
- Combined synchronisation and extraction pipeline
- Exact synthetic regression against the native encoder

## Example

```swift
let softSymbols = try SoftSymbolExtractor().extract(
    from: spectrogram,
    candidate: candidate
)

let llr174 = softSymbols.logLikelihoodRatios
let hardCodeword = softSymbols.hardBits
```

The output is ready for the native LDPC belief-propagation decoder in Phase 5.
