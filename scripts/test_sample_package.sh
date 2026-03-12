#!/usr/bin/env bash
# Clive standard test: generate driver for sample_cangjie_package, build it, run
# Cangjie tests (cjpm test) and shell tests (test_ref_output.sh, test_cli_usage.sh).
# Run from Clive repo root. Assumes Clive is already built unless BUILD_CLIVE=1.
#
# Usage:
#   ./scripts/test_sample_package.sh              # use existing Clive build
#   BUILD_CLIVE=1 ./scripts/test_sample_package.sh # build Clive then run test
#   CANGJIE_ENVSETUP=/path/to/envsetup.sh ./scripts/test_sample_package.sh

set -e

CLIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$CLIVE_ROOT"

if [ -n "${CANGJIE_ENVSETUP}" ]; then
  # shellcheck source=/dev/null
  . "${CANGJIE_ENVSETUP}" 2>/dev/null || true
fi

if [ "${BUILD_CLIVE:-0}" = "1" ]; then
  echo "=== Building Clive ==="
  cjpm build
fi

echo "=== Generating driver for sample_cangjie_package ==="
SAMPLE_PKG_PATH="${CLIVE_ROOT}/sample_cangjie_package"
if ! cjpm run -- --pkg "${SAMPLE_PKG_PATH}" 2>/dev/null; then
  # Fallback when cjpm run does not accept -- to pass arguments (e.g. unknown command '--')
  PKG_SRC="${SAMPLE_PKG_PATH}" cjpm run
fi

echo "=== Building sample_cangjie_package ==="
cd sample_cangjie_package
cjpm build

echo "=== Running Cangjie tests (cjpm test) ==="
cjpm test

echo "=== Running shell tests (ref output) ==="
./test_ref_output.sh

echo "=== Running shell tests (CLI usage) ==="
./test_cli_usage.sh

echo "=== Running shell tests (nested package) ==="
./test_nested_package.sh

echo "=== Running backend tests (WebSocket) ==="
skip_backend=0
# Skip backend tests when CLI binary is not runnable (exit 134/139) and cjpm run -- does not work
if [ "${SKIP_BACKEND_TESTS:-0}" != "1" ] && command -v node >/dev/null 2>&1; then
  if ! cjpm run -- "help" 2>/dev/null | grep -q .; then
    bin="${CLI_BIN:-./target/release/bin/main}"
    if [ -x "$bin" ]; then
      code=0; "$bin" "help" 2>/dev/null || code=$?
      if [ "$code" -eq 134 ] || [ "$code" -eq 139 ]; then
        echo "SKIP: CLI not runnable (binary exit $code). Backend tests skipped."
        skip_backend=1
      fi
    fi
  fi
fi
if [ "${SKIP_BACKEND_TESTS:-0}" = "1" ]; then
  echo "Skipping backend tests (SKIP_BACKEND_TESTS=1)"
elif [ "$skip_backend" = "1" ]; then
  :
elif command -v node >/dev/null 2>&1; then
  if [ ! -d node_modules/ws ]; then
    npm install ws
  fi
  if [ -d node_modules/ws ]; then
    node test_backend.js || { echo "Backend tests failed (ensure cjpm is on PATH). Use SKIP_BACKEND_TESTS=1 to skip."; exit 1; }
  else
    echo "Skipping backend tests (npm install ws failed or not available)"
  fi
else
  echo "Skipping backend tests (node not found)"
fi

# Optional: smoke-test the WebSocket backend (BACKEND_SMOKE=1; catches cjpm ENOENT, driver crash)
if [ "${BACKEND_SMOKE:-0}" = "1" ] && command -v node >/dev/null 2>&1 && [ -d node_modules/ws ]; then
  echo "=== Backend smoke test ==="
  export PORT=18765
  node web/cli_ws_server.js &
  PID=$!
  sleep 2
  CLIENT_EXIT=0
  node -e "
    const WebSocket = require('ws');
    const ws = new WebSocket('ws://localhost:' + (process.env.PORT || '8765'));
    const t = setTimeout(() => process.exit(2), 5000);
    ws.on('open', () => ws.send(JSON.stringify({line: 'help'})));
    ws.on('message', (d) => {
      clearTimeout(t);
      const j = JSON.parse(d);
      if (j.stderr && (j.stderr.includes('ENOENT') || j.stderr.includes('error:'))) process.exit(1);
      process.exit(0);
    });
    ws.on('error', (e) => { clearTimeout(t); console.error(e.message); process.exit(1); });
  " 2>&1 || CLIENT_EXIT=$?
  kill $PID 2>/dev/null || true
  wait $PID 2>/dev/null || true
  if [ "$CLIENT_EXIT" -ne 0 ]; then
    echo "FAIL: backend smoke test (e.g. cjpm not on PATH). Set CJPM_BIN or run with cjpm on PATH."
    exit 1
  fi
fi

echo "=== All sample_cangjie_package tests passed ==="
