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
  # Run CLI with given run-args; stdout only (stderr kept for errors)
  cjpm run --run-args="$1" 2>/dev/null
}

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
# Check order: ref:1 must appear before ref:2, ref:2 before ref:3
pos1=$(echo "$out_multi" | grep -o -n 'ref:1' | head -1 | cut -d: -f1)
pos2=$(echo "$out_multi" | grep -o -n 'ref:2' | head -1 | cut -d: -f1)
pos3=$(echo "$out_multi" | grep -o -n 'ref:3' | head -1 | cut -d: -f1)
if [ -z "$pos1" ] || [ -z "$pos2" ] || [ -z "$pos3" ]; then
  echo "FAIL: could not find ref positions in: $out_multi"
  exit 1
fi
if [ "$pos1" -ge "$pos2" ] || [ "$pos2" -ge "$pos3" ]; then
  echo "FAIL: refs must appear in order ref:1, ref:2, ref:3 (positions $pos1 $pos2 $pos3). Got: $out_multi"
  exit 1
fi
echo "PASS: multi-command returns ref:1, ref:2, ref:3 in order"

echo "All shell ref-output tests passed."
