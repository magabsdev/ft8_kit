# Phase 3.1 — Native DSP Foundation

Adds:

- Accelerate/vDSP complex FFT on Apple platforms
- Portable radix-2 Swift fallback for cross-platform testability
- Forward and inverse transforms
- Hann, Hamming, Blackman and Blackman-Harris windows
- One-sided magnitude and power spectra
- Frequency-bin and decibel conversion
- Twelve DSP unit tests

Run:

```bash
swift build
swift test
```
