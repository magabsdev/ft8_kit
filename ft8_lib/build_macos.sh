#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
make clean
make CC="${CC:-clang}" CFLAGS="${CFLAGS:--std=gnu11 -O3 -DHAVE_STPCPY -I.}"
