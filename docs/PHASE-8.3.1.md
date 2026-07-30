# Phase 8.3.1 — Apple Accelerate Fix

This corrective release fixes the argument ordering used with Apple's
`vvpowf` function.

`vvpowf` expects:

1. output
2. exponent vector
3. base vector
4. element count

The previous implementation passed the base and exponent vectors in reverse
order. Linux used the scalar fallback and therefore did not expose the
problem. On macOS, the incorrect Accelerate path corrupted decibel-to-linear
power conversion, which then caused failures in:

- `VectorMathTests.testDecibelPowerRoundTrip`
- soft-symbol extraction
- Costas correlation
- synchronizer candidate detection and drift estimation

The corrected call is:

```swift
vvpowf(&output, scaled, base, &count)
```
