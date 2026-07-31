#!/bin/zsh
set -euo pipefail

# Adjust these three paths for your machine.
FT8KIT_ROOT="${FT8KIT_ROOT:-$HOME/Developer/FT8Kit}"
FT8_LIB_ROOT="${FT8_LIB_ROOT:-$HOME/Developer/ft8_lib}"
SWIFT_COMMAND="${SWIFT_COMMAND:-$FT8KIT_ROOT/.build/debug/ft8-validate decode --wsjtx {wav}}"

SCRIPT_DIR="${0:A:h}"

python3 "$SCRIPT_DIR/validate_ft8_corpus.py" \
  "$FT8_LIB_ROOT/test/wav" \
  --swift-command "$SWIFT_COMMAND" \
  --swift-cwd "$FT8KIT_ROOT" \
  --c-command "$FT8_LIB_ROOT/decode_ft8 {wav}" \
  --c-cwd "$FT8_LIB_ROOT" \
  --frequency-tolerance 6.25 \
  --time-tolerance 0.16 \
  --minimum-recall 1.0 \
  --json-report "$FT8KIT_ROOT/.build/ft8-validation-report.json"
