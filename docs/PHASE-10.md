# Phase 10 — Standard WAV Validation

Phase 10 embeds the supplied WSJT-X reference corpus and adds:

- RIFF/WAVE PCM16 mono loading
- automatic 6.4 kHz to 12 kHz linear resampling
- WSJT-X decode-line parsing
- automatic WAV/TXT pairing, including `_12k` variants
- message/frequency/time tolerant matching
- an executable full-corpus validator
- deterministic fast tests covering all 31 recordings

The full decode comparison is deliberately an explicit release/benchmark command,
because decoding every crowded 15-second recording is expensive and the current
native decoder's compatibility rate is a measured product metric rather than a test
that should be falsely forced to 100%.
