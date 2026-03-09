#!/usr/bin/env bash
# Build Clive and run the full test suite using Cangjie envsetup.sh.
# This script sources the given envsetup so cjc and cjpm are on PATH and
# the toolchain can find the runtime.
#
# Usage:
#   ./scripts/build_and_test_with_envsetup.sh
#   CANGJIE_ENVSETUP=/path/to/envsetup.sh ./scripts/build_and_test_with_envsetup.sh
#
# Default envsetup (if CANGJIE_ENVSETUP is not set):
#   /Users/danghica/sandbox/cjceh/cjc-eh/cangjie/envsetup.sh

set -e
cd "$(dirname "$0")/.."

CANGJIE_ENVSETUP="${CANGJIE_ENVSETUP:-/Users/danghica/sandbox/cjceh/cjc-eh/cangjie/envsetup.sh}"

if [ ! -f "${CANGJIE_ENVSETUP}" ]; then
  echo "Error: envsetup not found: ${CANGJIE_ENVSETUP}"
  echo "Set CANGJIE_ENVSETUP to the path of your cangjie/envsetup.sh"
  exit 1
fi

echo "=== Sourcing Cangjie environment: ${CANGJIE_ENVSETUP} ==="
# shellcheck source=/dev/null
source "${CANGJIE_ENVSETUP}"

if ! command -v cjpm >/dev/null 2>&1; then
  echo "Error: cjpm not found after sourcing envsetup. Check that envsetup.sh adds cjpm to PATH."
  exit 127
fi
if ! command -v cjc >/dev/null 2>&1; then
  echo "Error: cjc not found after sourcing envsetup. Check that envsetup.sh adds cjc to PATH."
  exit 127
fi

echo "Using cjpm: $(which cjpm)"
echo "Using cjc: $(which cjc)"
echo ""

./scripts/build_and_test.sh
