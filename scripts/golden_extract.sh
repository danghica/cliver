#!/usr/bin/env bash
# Extract golden snippet from generated cli_driver.cj for regression testing.
# Output: test/golden/cli_driver_snippet.txt
# Usage: run from Clive repo root. Pass driver path or use default sample_cangjie_package.
#   ./scripts/golden_extract.sh
#   ./scripts/golden_extract.sh /path/to/package/src/cli_driver.cj
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER="${1:-${ROOT}/sample_cangjie_package/src/cli_driver.cj}"
GOLDEN_DIR="${ROOT}/test/golden"
GOLDEN_FILE="${GOLDEN_DIR}/cli_driver_snippet.txt"

if [ ! -f "$DRIVER" ]; then
  echo "golden_extract: driver not found: $DRIVER" >&2
  echo "Generate it first with: cjpm run -- --pkg sample_cangjie_package" >&2
  exit 1
fi

mkdir -p "$GOLDEN_DIR"
# Lines 1-80: prologue, imports, session state, store, core helpers
head -n 80 "$DRIVER" > "$GOLDEN_FILE"
echo "Wrote $GOLDEN_FILE (lines 1-80 of $DRIVER)"
