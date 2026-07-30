# Phase 8.3 — SIMD and Accelerate Optimisation

Phase 8.3 introduces a portable vector-math layer for DSP hot paths.

On Apple platforms, Accelerate/vDSP/vForce is used for vector sums, means,
scalar subtraction, window multiplication, complex magnitudes, decibel
conversion and decibel-to-linear-power conversion.

On other platforms, Swift `SIMD8<Float>` provides a portable fallback with
scalar handling for trailing elements.

Integrated paths:

- spectrum mean removal
- window application
- FFT complex magnitudes
- power generation
- spectrum decibel conversion
- Costas tone-power evaluation
- soft-symbol tone integration

The public decoder API remains unchanged.
