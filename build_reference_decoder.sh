#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/ft8_lib" >&2
  exit 2
fi

ROOT="$1"
cd "$ROOT"
make clean
make decode_ft8
printf 'Reference decoder built: %s/decode_ft8\n' "$ROOT"
