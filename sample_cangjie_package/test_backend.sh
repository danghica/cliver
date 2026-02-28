#!/usr/bin/env bash
# Run WebSocket backend tests (test_backend.js). Uses a random free port (19000–19999).
# Run from sample_cangjie_package. Requires Node.js, npm install ws, and cjpm on PATH.
#
# Usage:
#   ./test_backend.sh              # run backend tests
#   BUILD=1 ./test_backend.sh      # build package first (cjpm build)
#   SKIP_BACKEND_TESTS=1 ...       # (not used here; use when running full test suite)

set -e
cd "$(dirname "$0")"

if [ -n "${CANGJIE_ENVSETUP}" ]; then
  # shellcheck source=/dev/null
  . "${CANGJIE_ENVSETUP}" 2>/dev/null || true
fi

if [ "${BUILD:-0}" = "1" ]; then
  cjpm build
fi

if [ ! -d node_modules/ws ]; then
  echo "Installing ws for backend tests..."
  npm install ws
fi

echo "=== Backend tests (WebSocket) ==="
if ! node test_backend.js; then
  echo "Backend tests failed. Ensure cjpm is on PATH (e.g. source your Cangjie envsetup.sh)."
  exit 1
fi
echo "All backend tests passed."
