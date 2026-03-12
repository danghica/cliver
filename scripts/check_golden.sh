#!/usr/bin/env bash
# Compare current generated driver snippet to golden. Exit 0 if match, 1 if diff.
# Run from Clive repo root. Requires generated sample_cangjie_package/src/cli_driver.cj.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER="${ROOT}/sample_cangjie_package/src/cli_driver.cj"
GOLDEN="${ROOT}/test/golden/cli_driver_snippet.txt"

if [ ! -f "$DRIVER" ]; then
  echo "check_golden: generated driver not found. Run: cjpm run -- --pkg sample_cangjie_package" >&2
  exit 1
fi
if [ ! -f "$GOLDEN" ]; then
  echo "check_golden: golden file not found. Run: ./scripts/golden_extract.sh" >&2
  exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
head -n 80 "$DRIVER" > "$TMP"
if diff -q "$TMP" "$GOLDEN" >/dev/null 2>&1; then
  echo "Golden snippet matches."
  exit 0
fi
echo "Golden snippet diff (expected vs current):" >&2
diff "$GOLDEN" "$TMP" >&2 || true
exit 1
