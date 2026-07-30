# Phase 8.2 — Parallel Decode Engine

Phase 8.2 introduces bounded concurrent candidate decoding using Swift
structured concurrency.

## Added

- `FT8ParallelDecoder`
- `FT8ParallelSlotDecoder`
- Configurable maximum concurrent task count
- Confidence-ranked scheduling shared with the sequential engine
- Bounded `TaskGroup` execution
- Stable result collection independent of task completion order
- Existing duplicate suppression semantics
- Parallel timing and task metrics
- Sequential/parallel scheduler equivalence tests
- Generated-waveform parallel slot integration test

## Usage

```swift
let decoder = FT8ParallelSlotDecoder()
let batch = try await decoder.decode(samples: slotSamples)

for message in batch.messages {
    print(message.text)
}

print(batch.parallelMetrics.peakConcurrentTasks)
print(batch.parallelMetrics.averageCandidateLatencySeconds)
```

The worker count defaults to the machine's active processor count and can be
bounded explicitly for Signal8.
