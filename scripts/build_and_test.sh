#!/usr/bin/env bash
# Build Clive and run the standard test suite (sample_cangjie_package).
# Use this after each compilation to verify the generator and generated CLI.
#
# Usage: ./scripts/build_and_test.sh
# Optional: CANGJIE_ENVSETUP=/path/to/envsetup.sh

set -e
cd "$(dirname "$0")/.."

if [ -n "${CANGJIE_ENVSETUP}" ]; then
  # shellcheck source=/dev/null
  . "${CANGJIE_ENVSETUP}" 2>/dev/null || true
fi

echo "=== Building Clive ==="
cjpm build

BUILD_CLIVE=0 ./scripts/test_sample_package.sh
