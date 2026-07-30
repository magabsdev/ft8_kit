# Phase 8.1 — Streaming Engine

Phase 8.1 adds continuous PCM ingestion and slot-based live decoding.

## Added

- `PCMFloatRingBuffer`
- Fixed-capacity PCM storage
- Newest-sample retention on overflow
- `FT8LiveDecoder`
- Actor-isolated streaming state
- Arbitrary audio chunk ingestion
- Configurable slot duration
- Configurable decode stride
- Sliding-window decoding
- Explicit flush and reset operations
- Decode event sequencing
- Slot start sample tracking

## Example

```swift
let liveDecoder = try FT8LiveDecoder()

let events = try await liveDecoder.append(samples: audioChunk)

for event in events {
    for decode in event.batch.messages {
        print(decode.text)
    }
}
```

The live decoder accepts chunks of any size. Once enough PCM is buffered and
the configured decode stride has elapsed, it runs the existing native slot
decoder and returns one or more `FT8LiveDecodeEvent` values.
