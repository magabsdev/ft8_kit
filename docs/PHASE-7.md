# Phase 7 — Optimised Decoder Pipeline

Phase 7 adds a production-oriented decode scheduler around the complete native
FT8 pipeline.

## Added

- Confidence-ranked candidate scheduling
- Configurable candidate budget
- Early candidate-confidence rejection
- Early soft-symbol-confidence rejection
- Bounded LDPC work per slot
- Decode-stage metrics
- Deterministic output ordering
- Duplicate message suppression
- Direct PCM slot decoder
- End-to-end generated-waveform message test

## Usage

```swift
let decoder = FT8SlotDecoder()
let batch = try decoder.decode(samples: slotSamples)

for decode in batch.messages {
    print(decode.text)
}

print(batch.metrics.elapsedSeconds)
print(batch.metrics.candidatesFound)
print(batch.metrics.crcPassed)
```

## Metrics

`FT8DecodeMetrics` reports:

- candidates found
- candidates scheduled
- soft-symbol extractions
- LDPC attempts
- parity successes
- CRC successes
- returned messages
- elapsed decode time

This gives Signal8 enough information to display decoder performance and tune
candidate limits without changing the lower-level protocol implementation.
