#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for relative in \
  "Sources/FT8Decoder/FT8AuditWriter.swift" \
  "Tests/FT8DecoderTests/FT8AuditWriterTests.swift"
do
  source_file="$SCRIPT_DIR/files/$relative"
  target_file="$ROOT/$relative"

  if [[ ! -f "$target_file" ]]; then
    echo "Cannot find target: $target_file" >&2
    exit 1
  fi

  cp "$source_file" "$target_file"
done

echo "Checkpoint 7.3.1I applied."
echo "Run: ./test.sh"
