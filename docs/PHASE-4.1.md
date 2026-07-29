# Phase 4.1 — FT8 Synchronisation

Phase 4.1 introduces the native `FT8Decoder` target and the first decoding
stage after DSP analysis.

## Included

- Canonical three-block FT8 Costas sequence model
- Costas energy correlator
- Start-time search
- Base-frequency search
- Coarse drift estimation
- SNR and synchronisation scoring
- Candidate confidence calculation
- Time/frequency duplicate suppression
- Synthetic spectrogram regression fixtures
- End-to-end test using a waveform produced by `FT8Encoder`

## Pipeline

```text
PCM samples
  -> FT8DSP.Waterfall
  -> FT8Synchronizer
  -> [FT8Candidate]
```

`FT8Candidate` contains the estimated start time, base frequency, coarse
drift, synchronisation score, SNR and confidence.

## Current boundary

This phase locates likely FT8 transmissions. It does not yet extract the
174 soft LDPC symbols or decode message bits. That is Phase 4.2.
