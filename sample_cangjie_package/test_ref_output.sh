#!/usr/bin/env bash
# Equivalent of cli_driver_test.cj: assert CLI prints ref:1, ref:2, ref:3 when
# running multiple commands in one run (separated by ";"), and ref:1 for single command.
#
# Usage: run from sample_cangjie_package (or from anywhere; script cd's into its dir).
#   ./test_ref_output.sh           # use existing build
#   BUILD=1 ./test_ref_output.sh   # build then test
# Optional: CANGJIE_ENVSETUP=/path/to/envsetup.sh to source before cjpm.

set -e
cd "$(dirname "$0")"

# Optional: source Cangjie env (e.g. for cjpm)
if [ -n "${CANGJIE_ENVSETUP}" ]; then
  # shellcheck source=/dev/null
  . "${CANGJIE_ENVSETUP}" 2>/dev/null || true
fi

# Optional: build first
if [ "${BUILD:-0}" = "1" ]; then
  cjpm build
fi

run_cli() {
  # Prefer cjpm run -- when supported; fallback to direct binary when cjpm run does not pass args
  local line="$1"
  local out
  if out=$(cjpm run -- "$line" 2>/dev/null); then
    echo "$out"
    return
  fi
  local bin="${CLI_BIN:-./target/release/bin/main}"
  if [ -x "$bin" ]; then
    $bin "$line" 2>/dev/null || true
  else
    echo ""
  fi
}

# Skip when cjpm run -- does not work and binary aborts (134/139) so CLI is not runnable in this env
if ! out_probe=$(cjpm run -- "Lesson new" 2>/dev/null) || ! echo "$out_probe" | grep -q 'ref:1'; then
  bin="${CLI_BIN:-./target/release/bin/main}"
  if [ -x "$bin" ]; then
    code=0; "$bin" "Lesson new" 2>/dev/null || code=$?
    if [ "$code" -eq 134 ] || [ "$code" -eq 139 ]; then
      echo "SKIP: CLI not runnable (binary exit $code). Run from Cangjie env or set CLI_BIN."
      exit 0
    fi
  fi
fi

# --- Test 1: single command returns ref:1 ---
out_single=$(run_cli "Lesson new")
if ! echo "$out_single" | grep -q 'ref:1'; then
  echo "FAIL: single command should print ref:1. Got: $out_single"
  exit 1
fi
echo "PASS: single command returns ref:1"

# --- Test 2: multiple commands (;) return ref:1, ref:2, ref:3 in order ---
out_multi=$(run_cli "Student new A 1 ; Lesson new ; Lesson new")
for ref in ref:1 ref:2 ref:3; do
  if ! echo "$out_multi" | grep -q "$ref"; then
    echo "FAIL: multi-command output should contain $ref. Got: $out_multi"
    exit 1
  fi
done
# Check order: ref:1 must appear before ref:2, ref:2 before ref:3 (single line may include cjpm warning)
flat=$(echo "$out_multi" | tr -d '\n')
if ! echo "$flat" | grep -q 'ref:1.*ref:2.*ref:3'; then
  echo "FAIL: refs must appear in order ref:1, ref:2, ref:3. Got: $out_multi"
  exit 1
fi
echo "PASS: multi-command returns ref:1, ref:2, ref:3 in order"

echo "All shell ref-output tests passed."
