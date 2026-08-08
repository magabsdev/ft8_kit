#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

export FT8_RUN_EXPENSIVE_REAL_WAV_TESTS=1

echo "FT8Kit full real-WAV validation suite"
echo "This intentionally runs the expensive representative-WAV tests."
echo

swift test "$@"
