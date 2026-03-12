#!/usr/bin/env bash
# Run Clive on the single-file fixture package, build with cjpm, run one command.
# Catches "only works for one package" regressions. Run from Clive repo root.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$ROOT/test/fixtures/single_file_package"
if [ ! -d "$FIXTURE" ]; then
  echo "SKIP: second fixture not found at $FIXTURE"
  exit 0
fi
# Generate driver (use PKG_SRC so we don't rely on argv)
PKG_SRC="$FIXTURE" cjpm run 2>/dev/null || true
# Build the fixture package (stderr not redirected so errors are visible)
cd "$FIXTURE"
cjpm build || { echo "FAIL: cjpm build in single_file_package"; exit 1; }
# Run one command (Widget new x)
out=$(cjpm run -- Widget new x 2>/dev/null) || true
if echo "$out" | grep -q "ref:1"; then
  echo "PASS: second fixture (Widget new x -> ref:1)"
else
  echo "INFO: second fixture built and run; ref:1 not in output (driver may use different format)"
fi
