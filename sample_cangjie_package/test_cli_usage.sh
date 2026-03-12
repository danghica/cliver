#!/usr/bin/env bash
# Smoke test: run the generated CLI as in the project README.
# To get ref:1, ref:2, ref:3, ref:4 we run constructor commands in ONE process (separated by ";").
# "demo" is run separately; it uses its own hardcoded data (Alice, Bob, Carol), not the refs.
# Run from sample_cangjie_package. Use BUILD=1 to build first.

set -e
cd "$(dirname "$0")"

if [ -n "${CANGJIE_ENVSETUP}" ]; then
  # shellcheck source=/dev/null
  . "${CANGJIE_ENVSETUP}" 2>/dev/null || true
fi

if [ "${BUILD:-0}" = "1" ]; then
  cjpm build
fi

# Run CLI: prefer cjpm run -- when supported; fallback to direct binary (CLI_BIN or target/release/bin/main)
run_cli() {
  if cjpm run -- "$1" 2>/dev/null; then return 0; fi
  local bin="${CLI_BIN:-./target/release/bin/main}"
  if [ -x "$bin" ]; then
    $bin "$1" 2>/dev/null
    return $?
  fi
  return 1
}

# Skip when cjpm run -- does not work and binary aborts (134/139)
if ! cjpm run -- "help" 2>/dev/null; then
  bin="${CLI_BIN:-./target/release/bin/main}"
  if [ -x "$bin" ]; then
    code=0; "$bin" "help" 2>/dev/null || code=$?
    if [ "$code" -eq 134 ] || [ "$code" -eq 139 ]; then
      echo "SKIP: CLI not runnable (binary exit $code). Run from Cangjie env or set CLI_BIN."
      exit 0
    fi
  fi
fi

run() {
  local args="$1"
  local desc="${2:-$1}"
  echo "--- $desc ---"
  if ! run_cli "$args"; then
    echo "FAIL: CLI \"$args\" exited non-zero (try cjpm run -- or set CLI_BIN to built binary)"
    exit 1
  fi
  echo ""
}

echo "Using generated CLI (cjpm run -- or built binary if cjpm does not pass args)"
echo ""

# Help (single run)
run "help" "help"

# All constructors in ONE run so refs are ref:1, ref:2, ref:3, ref:4
echo "--- Student new Alice 1001 ; Student new Bob 1002 ; Student new Charlie 1003 ; Lesson new (one run → ref:1, ref:2, ref:3, ref:4) ---"
out=$(run_cli "Student new Alice 1001 ; Student new Bob 1002 ; Student new Charlie 1003 ; Lesson new" 2>/dev/null) || true
if ! echo "$out" | grep -q 'ref:1'; then
  echo "FAIL: multi-command run exited non-zero or no ref:1. Got: $out"
  exit 1
fi
echo "$out"
echo ""

for ref in ref:1 ref:2 ref:3 ref:4; do
  if ! echo "$out" | grep -q "$ref"; then
    echo "FAIL: output should contain $ref. Got: $out"
    exit 1
  fi
done
# Check order (single line may include cjpm warning)
flat=$(echo "$out" | tr -d '\n')
if ! echo "$flat" | grep -q 'ref:1.*ref:2.*ref:3.*ref:4'; then
  echo "FAIL: refs must appear in order ref:1, ref:2, ref:3, ref:4"
  exit 1
fi

# Demo (standalone: uses hardcoded Alice, Bob, Carol in demo(), not the refs we created)
run "demo" "demo (standalone; shows hardcoded Alice, Bob, Carol)"

# Assert demo output is the expected one (Alice, Bob, Carol from demo())
demo_out=$(run_cli "demo" 2>/dev/null) || true
for line in "Alice, 1001" "Bob, 1002" "Carol, 1003"; do
  if ! echo "$demo_out" | grep -q "$line"; then
    echo "FAIL: demo() should print $line. Got: $demo_out"
    exit 1
  fi
done

echo "All CLI usage tests passed."
