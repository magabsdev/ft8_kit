#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-${FT8_LIB_ROOT:-}}"
if [[ -z "$ROOT" ]]; then
  echo "usage: $0 /path/to/ft8_lib" >&2
  echo "or set FT8_LIB_ROOT" >&2
  exit 2
fi

ROOT="$(cd "$ROOT" && pwd)"
if [[ ! -f "$ROOT/Makefile" || ! -f "$ROOT/demo/decode_ft8.c" ]]; then
  echo "Not an ft8_lib checkout: $ROOT" >&2
  exit 2
fi

make -C "$ROOT" decode_ft8
printf '%s\n' "$ROOT/decode_ft8"
