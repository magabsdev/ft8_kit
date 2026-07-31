#!/usr/bin/env bash
set -euo pipefail

swift build
swift test

if [[ -n "${FT8_LIB_ROOT:-}" ]]; then
  ./validate-reference.sh "$FT8_LIB_ROOT"
else
  echo "Reference corpus validation skipped (set FT8_LIB_ROOT to enable)."
fi
