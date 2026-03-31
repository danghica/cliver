#!/usr/bin/env bash
# run_adapter_demo.sh — Start cli_ws_server.js, run cliver-tests/demo/agent-adapter.js, verify exit 0.
#
# Usage:
#   ./scripts/run_adapter_demo.sh
#
# Environment:
#   CLIVER_REPO       path to cliver repo (default: script's parent dir)
#   CLIVER_TESTS_REPO path to cliver-tests repo (default: ../cliver-tests)
#   PORT              WebSocket port (default: 18765)
#   CANGJIE_ENVSETUP  path to Cangjie envsetup.sh (optional)
set -e

CLIVER_REPO="${CLIVER_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIVER_TESTS_REPO="${CLIVER_TESTS_REPO:-$(cd "$CLIVER_REPO/../cliver-tests" && pwd)}"
PORT="${PORT:-18765}"

WS_SERVER="$CLIVER_REPO/sample_cangjie_package/web/cli_ws_server.js"
ADAPTER="$CLIVER_TESTS_REPO/demo/agent-adapter.js"
CLI_BIN="$CLIVER_REPO/sample_cangjie_package/target/release/bin/main"

echo "=== Adapter Demo Verification ==="
echo "CLIVER_REPO:       $CLIVER_REPO"
echo "CLIVER_TESTS_REPO: $CLIVER_TESTS_REPO"
echo "PORT:              $PORT"
echo ""

# -- Dependency checks --
if [ ! -f "$WS_SERVER" ]; then
  echo "ERROR: cli_ws_server.js not found at $WS_SERVER"
  echo "Run: PKG_SRC=sample_cangjie_package ./target/release/bin/main"
  exit 1
fi

if [ ! -f "$ADAPTER" ]; then
  echo "ERROR: agent-adapter.js not found at $ADAPTER"
  echo "Ensure cliver-tests repo is at $CLIVER_TESTS_REPO"
  exit 1
fi

if [ ! -f "$CLI_BIN" ]; then
  echo "ERROR: CLI binary not found at $CLI_BIN"
  echo "Run: cd sample_cangjie_package && cjpm build"
  exit 1
fi

if [ ! -d "$CLIVER_TESTS_REPO/node_modules/ws" ]; then
  echo "Installing ws in cliver-tests..."
  (cd "$CLIVER_TESTS_REPO" && npm install ws --silent)
fi

# -- Start server --
echo "Starting cli_ws_server.js on port $PORT..."
CLI_BIN="$CLI_BIN" PORT="$PORT" node "$WS_SERVER" &
SERVER_PID=$!

cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Wait for server to be ready
sleep 1

# -- Run demo --
echo "Running agent-adapter.js..."
if PORT="$PORT" node "$ADAPTER"; then
  echo ""
  echo "=== Adapter demo: PASSED ==="
else
  echo ""
  echo "=== Adapter demo: FAILED ==="
  exit 1
fi
