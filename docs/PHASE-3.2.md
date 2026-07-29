# Phase 3.2 — Waterfall Engine

Adds:

- Overlapping FFT frame analysis
- Configurable FFT and hop sizes
- Frequency-range cropping
- Normalised waterfall intensity rows
- Median, percentile, trimmed-mean and rolling-median noise estimation
- Spectrogram time navigation
- SNR-based local spectral peak detection
- Frequency separation and per-frame peak limits

The output is platform-independent so Signal8 can apply a native colour palette
without coupling the DSP library to AppKit or UIKit.

```bash
swift build
swift test
```
