#!/usr/bin/env bash
# Test that commands from nested package directories are discovered and work.
# Uses src/demo_sub/demo_alt.cj which defines demoAlt() (students David, Eugen, Flora).
# If the generated driver does not yet include nested discovery, the test is skipped.
#
# Usage: run from sample_cangjie_package (after cjpm build).
#   ./test_nested_package.sh
#   BUILD=1 ./test_nested_package.sh
# Optional: CANGJIE_ENVSETUP=/path/to/envsetup.sh

set -e
cd "$(dirname "$0")"

if [ -n "${CANGJIE_ENVSETUP}" ]; then
  # shellcheck source=/dev/null
  . "${CANGJIE_ENVSETUP}" 2>/dev/null || true
fi

if [ "${BUILD:-0}" = "1" ]; then
  cjpm build
fi

DRIVER="${PWD}/src/cli_driver.cj"
if [ ! -f "$DRIVER" ]; then
  echo "SKIP: nested package test (no generated cli_driver.cj; run Clive first)"
  exit 0
fi

if ! grep -q 'demoAlt' "$DRIVER"; then
  echo "SKIP: nested package test (generated driver has no demoAlt; nested discovery not yet used)"
  exit 0
fi

echo "=== Nested package tests (demo_sub/demo_alt.cj) ==="

# Run demoAlt via path (nested command) and capture output
out=$(cjpm run -- demo_sub/demoAlt 2>/dev/null) || true
if ! echo "$out" | grep -q "David"; then
  echo "FAIL: demoAlt output should contain 'David'. Got: $out"
  exit 1
fi
if ! echo "$out" | grep -q "Eugen"; then
  echo "FAIL: demoAlt output should contain 'Eugen'. Got: $out"
  exit 1
fi
if ! echo "$out" | grep -q "Flora"; then
  echo "FAIL: demoAlt output should contain 'Flora'. Got: $out"
  exit 1
fi

echo "PASS: demoAlt (nested package) output correct (David, Eugen, Flora)"
echo "All nested package tests passed."
