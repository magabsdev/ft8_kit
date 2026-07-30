# Phase 11 — Real-Time UTC Slot Engine

Phase 11 adds the production-facing real-time ingestion layer required by
Signal8 and other live FT8 applications.

## New components

### `FT8SlotClock`

Provides deterministic UTC-aligned 15-second FT8 slot calculations:

- current slot start
- next slot start
- slot index
- progress through the current slot

### `FT8RealtimeDecoder`

Accepts timestamped PCM chunks and:

- aligns audio to UTC FT8 boundaries
- assembles complete 15-second slots
- invokes the Phase 9 multi-pass decoder
- fills small capture gaps with silence
- drops overlapping samples
- resets cleanly after large discontinuities
- emits timestamped decode events
- provides capture-health diagnostics

## Example

```swift
let realtime = try FT8RealtimeDecoder()

let events = try await realtime.append(
    samples: audioChunk,
    sampleRate: 12_000,
    startingAt: captureTimestamp
)

for event in events {
    print(event.slotStart)

    for decode in event.batch.messages {
        print(decode.text)
    }
}
```

## Diagnostics

Each event includes cumulative diagnostics for:

- received samples
- inserted silence
- dropped overlap
- discarded partial slots
- decoded slots

These counters allow Signal8 to report audio-device glitches and timing
quality without coupling the decoder to AVFoundation.
