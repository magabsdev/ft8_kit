# Phase 9.1 — Multi-Pass Signal Cancellation

Phase 9.1 introduces iterative FT8 decoding with spectrogram-domain
successive interference cancellation.

## Components

- `FT8SignalSynthesizer`
  - reconstructs all 79 FT8 tones from a decoded LDPC codeword
  - includes the three Costas sync blocks

- `FT8SignalCanceller`
  - identifies the time/frequency bins occupied by decoded signals
  - applies configurable tapered attenuation
  - rebuilds decibel, intensity and noise-floor data
  - reports affected bins and removed energy

- `FT8MultiPassDecoder`
  - performs configurable decode/cancel passes
  - carries a residual spectrogram into the next pass
  - suppresses duplicate messages across passes
  - stops when no new messages or insufficient energy improvement occurs

- `FT8MultiPassSlotDecoder`
  - accepts a complete PCM FT8 slot

## Usage

```swift
let decoder = FT8MultiPassSlotDecoder(
    decoder: FT8MultiPassDecoder(
        configuration: .init(
            maximumPasses: 3,
            maximumSignalsPerPass: 12
        )
    )
)

let batch = try decoder.decode(samples: slotSamples)

for message in batch.messages {
    print(message.text)
}

for pass in batch.metrics.passes {
    print(
        pass.pass,
        pass.newMessages,
        pass.energyReductionFraction
    )
}
```

## Cancellation model

Cancellation is intentionally conservative. It attenuates the reconstructed
tone path in the spectrogram rather than attempting phase-coherent PCM
subtraction. This provides deterministic multi-pass behaviour without
inventing unavailable carrier phase information.

A later phase can add phase-aware time-domain cancellation when complex IQ or
phase estimates are available.
