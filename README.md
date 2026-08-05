# FT8Kit Checkpoint 7.3.1G

This archive contains replacement/addition files for the next diagnostic
pipeline checkpoint.

## Changes

- Records the exact 174-bit corrected LDPC codeword.
- Records the exact 91 information bits.
- Records LDPC iteration count, parity result, CRC result and syndrome weight.
- Preserves every previously captured tone, hard-bit and LLR stage.
- Adds structural validation for the new stages.
- Adds focused tests for LDPC-result attachment and validation.

## Apply

Copy the `Sources` and `Tests` directories into the root of FT8Kit, replacing
the two existing source files when prompted.

Then run:

```bash
rm -rf .build
swift package clean
swift build --product ft8-validate
swift test
```

This package does not push or modify the GitHub repository.
