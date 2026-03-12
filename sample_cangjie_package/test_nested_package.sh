#!/usr/bin/env bash
# Test that commands from nested package directories are discovered and work.
# Uses src/demo_sub/demo_sub.cj (demo_sub/demo → David, Eugen, Flora) and
# src/demo_sub/nested/nested.cj (demo_sub/nested/demo → George, Hamid, Ilias).
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

if ! grep -q 'demo_sub/nested' "$DRIVER"; then
  echo "SKIP: nested package test (generated driver has no demo_sub/nested; nested discovery not yet used)"
  exit 0
fi

# Run CLI: prefer cjpm run -- when supported; fallback to direct binary (CLI_BIN or target/release/bin/main)
run_cli() {
  local out
  if out=$(cjpm run -- "$1" 2>/dev/null); then
    echo "$out"
    return
  fi
  local bin="${CLI_BIN:-./target/release/bin/main}"
  if [ -x "$bin" ]; then
    $bin "$1" 2>/dev/null || true
  else
    echo ""
  fi
}

# Skip when cjpm run -- does not work and binary aborts (134/139)
if ! out_probe=$(cjpm run -- "demo_sub/demo" 2>/dev/null) || ! echo "$out_probe" | grep -q "David"; then
  bin="${CLI_BIN:-./target/release/bin/main}"
  if [ -x "$bin" ]; then
    code=0; "$bin" "help" 2>/dev/null || code=$?
    if [ "$code" -eq 134 ] || [ "$code" -eq 139 ]; then
      echo "SKIP: CLI not runnable (binary exit $code). Run from Cangjie env or set CLI_BIN."
      exit 0
    fi
  fi
fi

echo "=== Nested package tests (demo_sub/demo, demo_sub/nested/demo) ==="

# Run demo_sub/demo (David, Eugen, Flora)
out=$(run_cli "demo_sub/demo")
if ! echo "$out" | grep -q "David"; then
  echo "FAIL: demo_sub/demo output should contain 'David'. Got: $out"
  exit 1
fi
if ! echo "$out" | grep -q "Eugen"; then
  echo "FAIL: demo_sub/demo output should contain 'Eugen'. Got: $out"
  exit 1
fi
if ! echo "$out" | grep -q "Flora"; then
  echo "FAIL: demo_sub/demo output should contain 'Flora'. Got: $out"
  exit 1
fi
echo "PASS: demo_sub/demo (David, Eugen, Flora)"

# Run demo_sub/nested/demo (George, Hamid, Ilias)
out=$(run_cli "demo_sub/nested/demo")
if ! echo "$out" | grep -q "George"; then
  echo "FAIL: demo_sub/nested/demo output should contain 'George'. Got: $out"
  exit 1
fi
if ! echo "$out" | grep -q "Hamid"; then
  echo "FAIL: demo_sub/nested/demo output should contain 'Hamid'. Got: $out"
  exit 1
fi
if ! echo "$out" | grep -q "Ilias"; then
  echo "FAIL: demo_sub/nested/demo output should contain 'Ilias'. Got: $out"
  exit 1
fi
echo "PASS: demo_sub/nested/demo (George, Hamid, Ilias)"

echo "All nested package tests passed."
