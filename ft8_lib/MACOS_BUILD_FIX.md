# macOS build fix

`demo/decode_ft8.c` now defines `_POSIX_C_SOURCE` as `200809L` rather than `199309L`.

On modern macOS SDKs, the older feature-test level hides the C99 `snprintf` declaration even when `<stdio.h>` is included. Using POSIX.1-2008 exposes the declaration and allows current Apple Clang to compile the decoder.

Build with:

```sh
./build_macos.sh
```
