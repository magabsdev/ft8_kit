#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
FT8_LIB_ROOT="${FT8_LIB_ROOT:-${1:-}}"

if [[ -z "$FT8_LIB_ROOT" ]]; then
  if [[ -d "$PROJECT_ROOT/../ft8_lib" ]]; then
    FT8_LIB_ROOT="$PROJECT_ROOT/../ft8_lib"
  else
    echo "Set FT8_LIB_ROOT or pass the ft8_lib directory:" >&2
    echo "  FT8_LIB_ROOT=/path/to/ft8_lib ./validate-reference.sh" >&2
    exit 2
  fi
fi

FT8_LIB_ROOT="$(cd "$FT8_LIB_ROOT" && pwd)"
CORPUS="${FT8_CORPUS:-$FT8_LIB_ROOT/test/wav}"
REPORT="${FT8_VALIDATION_REPORT:-$PROJECT_ROOT/.build/ft8-reference-validation.json}"

C_DECODER="$($PROJECT_ROOT/Tools/build_reference_decoder.sh "$FT8_LIB_ROOT" | tail -n 1)"
swift build --package-path "$PROJECT_ROOT" --product ft8-validate
SWIFT_DECODER="$(swift build --package-path "$PROJECT_ROOT" --show-bin-path)/ft8-validate"

python3 "$PROJECT_ROOT/Tools/validate_reference_corpus.py" \
  --corpus "$CORPUS" \
  --c-decoder "$C_DECODER" \
  --swift-decoder "$SWIFT_DECODER" \
  --report "$REPORT" \
  "${@:2}"
