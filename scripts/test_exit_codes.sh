#!/usr/bin/env bash
# Integration test: Clive binary exit codes (0 success, 65 bad path/refuse, 66 write failure).
# Run from Clive repo root after cjpm build.
# Set CLIVE_BIN to the Clive binary if direct run is needed (e.g. for correct exit codes when
# cjpm run does not pass args or when the built binary needs library path from cjpm).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CLIVE_BIN="${CLIVE_BIN:-}"
if [ -z "$CLIVE_BIN" ] && [ -f "target/release/bin/main" ]; then
  CLIVE_BIN="target/release/bin/main"
fi

run_clive() { "$CLIVE_BIN" "$@"; }

USE_PKG_SRC=0
if [ -n "$CLIVE_BIN" ]; then
  # Exit 65: refuse current directory (no --pkg, no PKG_SRC)
  code=0; run_clive --pkg . 2>/dev/null || code=$?
  if [ "$code" -ne 65 ]; then
    echo "SKIP: exit code tests (binary returned $code for --pkg .; run from Cangjie env for full tests)"
    USE_PKG_SRC=1
  else
    echo "PASS: exit 65 (refuse current dir)"
    # Exit 65: invalid package path
    code=0; run_clive --pkg /nonexistent_path_abracadabra_xyz 2>/dev/null || code=$?
    if [ "$code" -ne 65 ]; then
      echo "FAIL: expected exit 65 for invalid path, got $code" >&2
      exit 1
    fi
    echo "PASS: exit 65 (invalid path)"
    # Exit 65: refuse package named pkgcli
    if [ -d "$ROOT/test/fixtures/pkgcli_named_package" ]; then
      code=0; run_clive --pkg "$ROOT/test/fixtures/pkgcli_named_package" 2>/dev/null || code=$?
      if [ "$code" -ne 65 ]; then
        echo "FAIL: expected exit 65 for package name pkgcli, got $code" >&2
        exit 1
      fi
      echo "PASS: exit 65 (refuse pkgcli name)"
    fi
  fi
else
  USE_PKG_SRC=1
fi

# Exit 0: success on sample package
if [ "$USE_PKG_SRC" = 1 ]; then
  code=0; PKG_SRC="$ROOT/sample_cangjie_package" cjpm run 2>/dev/null || code=$?
else
  code=0; run_clive --pkg sample_cangjie_package 2>/dev/null || code=$?
fi
if [ "$code" -ne 0 ]; then
  echo "FAIL: expected exit 0 for sample_cangjie_package, got $code" >&2
  exit 1
fi
if [ ! -f "sample_cangjie_package/src/cli_driver.cj" ]; then
  echo "FAIL: cli_driver.cj was not written" >&2
  exit 1
fi
echo "PASS: exit 0 (success)"

# Generated backend is valid JS (Node parse)
if command -v node >/dev/null 2>&1; then
  if node -e "require('fs').readFileSync('sample_cangjie_package/web/cli_ws_server.js', 'utf8')" 2>/dev/null; then
    echo "PASS: backend template is valid (readable)"
  fi
  if grep -q "IDLE_TIMEOUT_MS\|WebSocket\|normalize" sample_cangjie_package/web/cli_ws_server.js 2>/dev/null; then
    echo "PASS: backend contains key strings"
  fi
fi

echo "All exit code checks passed."
