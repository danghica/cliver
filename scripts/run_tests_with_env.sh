#!/usr/bin/env bash
# Run Clive build and sample_package tests, using Cangjie from PATH or CANGJIE_HOME.
# Use this if cjpm is not on your default PATH.
#
# Usage:
#   ./scripts/run_tests_with_env.sh
#   CANGJIE_HOME=/path/to/cangjie ./scripts/run_tests_with_env.sh
#   CANGJIE_ENVSETUP=/path/to/envsetup.sh ./scripts/run_tests_with_env.sh

set -e
cd "$(dirname "$0")/.."

if [ -n "${CANGJIE_ENVSETUP}" ]; then
  # shellcheck source=/dev/null
  . "${CANGJIE_ENVSETUP}" 2>/dev/null || true
fi

if [ -n "${CANGJIE_HOME}" ]; then
  # Add both bin (cjc) and tools/bin (cjpm) so cjpm can invoke cjc
  for d in "${CANGJIE_HOME}/bin" "${CANGJIE_HOME}/tools/bin"; do
    [ -d "$d" ] && export PATH="${d}:${PATH}"
  done
fi

if ! command -v cjpm >/dev/null 2>&1; then
  echo "Error: cjpm not found. Set CANGJIE_HOME or CANGJIE_ENVSETUP, or add cjpm to PATH."
  exit 127
fi

./scripts/build_and_test.sh
