#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

echo "FT8Kit fast test suite"
echo "Representative real-WAV integration tests are skipped."
echo "Use ./test-real-wav.sh for the expensive validation suite."
echo

swift test "$@"
