#!/usr/bin/env bash
# Run Clive in-package unit tests (dir, codegen, parser, etc.).
# Use from Clive repo root. Requires Cangjie env (source envsetup.sh or cjpm on PATH).
# Exports CLIVE_REPO_ROOT so parser tests can find test/fixtures/minimal_package.
set -e
cd "$(dirname "$0")/.."
export CLIVE_REPO_ROOT="$PWD"
cjpm test
