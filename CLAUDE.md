# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Agent dev-journal entry point:** `dev-journal/AGENT.md` — read this first when starting any feature work. It contains current status, navigation guide, and a new-feature checklist.

## What This Project Does

**Clive** generates a CLI driver for a Cangjie package. Given a path to Cangjie source files, it:
1. Parses `.cj` files using `std.ast` to extract public functions/classes/constructors
2. Generates a `cli_driver.cj` that exposes them as CLI commands (no runtime reflection—all dispatch is compile-time static)
3. Optionally generates a Node.js WebSocket backend (`cli_ws_server.js`) and browser UI

## Commands

```bash
# Build Clive
cjpm build

# Run Clive (generate CLI driver for a target package)
# NOTE: `cjpm run -- --pkg` does NOT work in this environment ("unknown command '--'")
# Use the built binary directly instead:
PKG_SRC=/path/to/package ./target/release/bin/main
# (cjpm run -- --pkg /path/to/package is kept in scripts as a fallback for other envs)

# Run all tests (build + integration + unit)
./scripts/build_and_test.sh

# Unit tests only (cjpm test on src/*_test.cj)
./scripts/run_unit_tests.sh
cjpm test

# Integration tests only (requires Clive already built)
./scripts/test_sample_package.sh

# Exit code validation tests
./scripts/test_exit_codes.sh

# Backend smoke test
BACKEND_SMOKE=1 ./scripts/test_sample_package.sh

# Skip backend tests
SKIP_BACKEND_TESTS=1 ./scripts/test_sample_package.sh
```

Cangjie toolchain must be sourced before building: `source /home/gloria/cangjie/envsetup.sh`

## Architecture

The pipeline is strictly linear: **parse → codegen → write files**

```
--pkg path
    │
    ▼
parsePackage()        [parser.cj]   → Manifest (packageQualifiedName + []CommandInfo)
    │
    ▼
generateDriver()      [codegen.cj]  → cli_driver.cj source string
    │
    ▼
write files           [main.cj]     → <target>/src/cli_driver.cj
                                       <target>/web/cli_ws_server.js
                                       <target>/web/index.html
```

### Key Modules

**`src/main.cj`** — Entrypoint. Resolves `--pkg`/`PKG_SRC`, calls parser then codegen, writes output files. Exit codes: `0` success, `65` invalid path/parse failure, `66` write driver failed, `67` write backend failed.

**`src/parser.cj`** — Uses `std.ast` (`cangjieLex`, `parseProgram`) to scan `.cj` files and extract `Manifest`. If `src/` subdirectory exists in the target, scans that instead. Handles nested packages (multi-level dirs). Outputs `CommandInfo` records with fields including `packagePath` (the CLI directory path for the command).

**`src/codegen.cj`** — Takes `Manifest`, emits the full `cli_driver.cj` source. The generated driver:
- Maintains an in-memory object store (`HashMap<Int64, Any>`) for class instances, referenced as `ref:1`, `ref:2`, etc.
- Tracks current directory `_cwd` for namespace navigation (commands are organized under their source package path)
- Supports `cd`, `help`, `echo` as built-in commands
- Uses first-match overload resolution (manifest order)
- Separates stdout/stderr with `<<<CLIVE_STDERR>>>` delimiter for the web backend

**`src/dir.cj`** — All path normalization and file collection logic lives here. Both parser and the generated driver share this logic (generated driver inlines its own `_normalizePath`). Key functions: `collectCjFilesUnder`, `packagePathFromFile`, `normalizePath`, `isKnownPackagePath`.

### Data Types

- **`Manifest`**: `packageQualifiedName: String` + `commands: ArrayList<CommandInfo>`
- **`CommandInfo`**: `name`, `isConstructor`, `className`, `params: ArrayList<ParamInfo>`, `returnType`, `returnIsRef`, `isInstanceMethod`, `isStaticMethod`, `packagePath`
- **`ParamInfo`**: `paramName`, `paramType`

### Generated Driver Structure

The generated `cli_driver.cj` lives in the same Cangjie package as the target (same module, no import needed). It has:
- Session state + output buffers (`_outBuf`, `_errBuf`)
- Object store with monotonic ref IDs
- `main()` → `_runSegments()` → per-command `_run<Name>(args)` functions
- Each command function tries overloads in order, converts string args to typed values, calls target function/constructor

## Testing

- **Unit tests** are in `src/*_test.cj` (dir_test, parser_test, codegen_test) — run with `cjpm test`
- **Integration tests** generate a driver for `sample_cangjie_package/`, build it, then run:
  - Cangjie tests: `cjpm test` in sample package
  - Shell tests: `test_ref_output.sh`, `test_cli_usage.sh`, `test_nested_package.sh`
  - Backend tests: `test_backend.js` (Node.js + `npm install ws`)
- Sample package (`sample_cangjie_package/`) contains `Student`/`Lesson` classes plus nested subpackages for testing multi-level package navigation

## Environment Variables

| Variable | Purpose |
|---|---|
| `PKG_SRC` | Target package path (alternative to `--pkg`) |
| `CANGJIE_ENVSETUP` | Path to Cangjie `envsetup.sh` |
| `CLIVE_REPO_ROOT` | Repo root (for locating web backend template) |
| `CLI_BIN` | Override path to generated CLI binary |
| `CJPM_BIN` | Override cjpm path for backend |
| `DEBUG_LOG=1` | Enable debug logging in WebSocket backend |
| `IDLE_TIMEOUT_MS` | WebSocket session idle timeout (default 600000ms) |
| `SKIP_BACKEND_TESTS=1` | Skip Node.js backend tests |
| `BACKEND_SMOKE=1` | Run backend smoke test |

## Important Constraints

- Parser only handles **public top-level functions** and **public constructors** (no instance/static methods in v1; the fields exist in CommandInfo but aren't fully exercised)
- Generic functions are not supported
- Complex multi-line signatures may not parse correctly
- Object store is **in-memory only**—no persistence between CLI invocations (the web backend maintains session state per WebSocket connection)
- The generated driver assumes it lives in the same Cangjie package as the target (no cross-package import)
