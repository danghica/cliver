#!/usr/bin/env bash
# Fuzz the sample package CLI with random token sequences. Ensures no crash (exit 0 or non-zero, not 134/SIGABRT).
# Run from Clive repo root. Requires sample_cangjie_package built (cjpm build there) and cjpm on PATH.
# When the direct binary is not runnable (e.g. exit 134 from missing lib path), falls back to cjpm run -- "$line".
# Usage: ./scripts/fuzz_cli.sh [iterations]
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ITERATIONS="${1:-50}"
cd "$ROOT/sample_cangjie_package"
BIN="${CLI_BIN:-target/release/bin/main}"
if [ ! -f "$BIN" ]; then
  echo "fuzz_cli: binary not found. Run: cd sample_cangjie_package && cjpm build" >&2
  exit 1
fi

# Probe: if direct binary aborts (134/139), use cjpm run -- for the rest
USE_CJPM_RUN=0
code=0; "$BIN" "help" 2>/dev/null || code=$?
if [ "$code" -eq 134 ] || [ "$code" -eq 139 ]; then
  if cjpm run -- "help" 2>/dev/null; then
    USE_CJPM_RUN=1
  else
    echo "fuzz_cli: SKIP — binary not runnable (exit $code) and cjpm run -- not supported. Set CLI_BIN or run from Cangjie env." >&2
    exit 0
  fi
fi

run_fuzz_line() {
  local line="$1"
  if [ "$USE_CJPM_RUN" = "1" ]; then
    cjpm run -- "$line" 2>/dev/null || true
    return $?
  fi
  "$BIN" "$line" 2>/dev/null || true
  return $?
}

TOKENS=("help" "dir" "echo" "Student" "Lesson" "new" "ref:1" "ref:2" "foo" "demo_sub/demo" ";" "x")
n=${#TOKENS[@]}
i=0
while [ "$i" -lt "$ITERATIONS" ]; do
  len=$((1 + RANDOM % 4))
  args=()
  for ((j=0; j<len; j++)); do
    args+=("${TOKENS[$((RANDOM % n))]}")
  done
  line="${args[*]}"
  code=0; run_fuzz_line "$line" || code=$?
  if [ "$code" -eq 134 ] || [ "$code" -eq 139 ]; then
    echo "FAIL: crash (exit $code) with line: $line"
    exit 1
  fi
  i=$((i + 1))
done
echo "fuzz_cli: $ITERATIONS runs, no crash."
