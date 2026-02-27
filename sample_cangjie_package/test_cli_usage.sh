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

run() {
  local args="$1"
  local desc="${2:-$1}"
  echo "--- $desc ---"
  if ! cjpm run --run-args="$args"; then
    echo "FAIL: cjpm run --run-args=\"$args\" exited non-zero"
    exit 1
  fi
  echo ""
}

echo "Using generated CLI as in README (cjpm run --run-args=\"...\")"
echo ""

# Help (single run)
run "help" "help"

# All constructors in ONE run so refs are ref:1, ref:2, ref:3, ref:4
echo "--- Student new Alice 1001 ; Student new Bob 1002 ; Student new Charlie 1003 ; Lesson new (one run → ref:1, ref:2, ref:3, ref:4) ---"
out=$(cjpm run --run-args="Student new Alice 1001 ; Student new Bob 1002 ; Student new Charlie 1003 ; Lesson new" 2>/dev/null)
if [ $? -ne 0 ]; then
  echo "FAIL: multi-command run exited non-zero"
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
# Check order
pos1=$(echo "$out" | grep -o -n 'ref:1' | head -1 | cut -d: -f1)
pos2=$(echo "$out" | grep -o -n 'ref:2' | head -1 | cut -d: -f1)
pos3=$(echo "$out" | grep -o -n 'ref:3' | head -1 | cut -d: -f1)
pos4=$(echo "$out" | grep -o -n 'ref:4' | head -1 | cut -d: -f1)
if [ -z "$pos1" ] || [ -z "$pos2" ] || [ -z "$pos3" ] || [ -z "$pos4" ]; then
  echo "FAIL: could not find all ref positions"
  exit 1
fi
if [ "$pos1" -ge "$pos2" ] || [ "$pos2" -ge "$pos3" ] || [ "$pos3" -ge "$pos4" ]; then
  echo "FAIL: refs must appear in order ref:1, ref:2, ref:3, ref:4 (positions $pos1 $pos2 $pos3 $pos4)"
  exit 1
fi

# Demo (standalone: uses hardcoded Alice, Bob, Carol in demo(), not the refs we created)
run "demo" "demo (standalone; shows hardcoded Alice, Bob, Carol)"

# Assert demo output is the expected one (Alice, Bob, Carol from demo())
demo_out=$(cjpm run --run-args="demo" 2>/dev/null)
for line in "Alice, 1001" "Bob, 1002" "Carol, 1003"; do
  if ! echo "$demo_out" | grep -q "$line"; then
    echo "FAIL: demo() should print $line. Got: $demo_out"
    exit 1
  fi
done

echo "All CLI usage tests passed."
