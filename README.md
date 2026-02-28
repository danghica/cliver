# Clive — Cangjie package-to-CLI utility

This utility parses a Cangjie package’s source, discovers public functions and public constructors, and generates a CLI driver that exposes them as commands. No runtime reflection: the driver calls the package API directly.

## Features

- **Source as input**: Scans `.cj` files in the package (or in `src/` under the package root) for `package`, `public func`, `public class`, and `public init`.
- **One CLI command per** top-level public function; constructors are invoked as **`ClassName new arg1 arg2 ...`**.
- **Overloads**: First matching overload in manifest order (argument conversion tried in order).
- **Arguments**: Positional; class-typed parameters accept `ref:<id>` and look up in the object store.
- **Object store**: In-memory map keyed by a monotonic id; only class instances are stored; the driver prints `ref:<id>` for later use.
- **Env**: Package path can be set via `PKG_SRC` or `--pkg <path>`.

## Build and run (requires Cangjie / cjpm)

Use the Cangjie 1.0.x (cjnative) toolchain. **Source the Cangjie environment first** so the linker finds the SDK (e.g. `source /path/to/cangjie/envsetup.sh`), then:

```bash
source /path/to/cangjie/envsetup.sh   # or add to your shell profile
cjpm build
cjpm run --run-args="--pkg /path/to/your/package"
# or
PKG_SRC=/path/to/your/package cjpm run
```

The project is configured for `cjc-version = "1.0.5"` and `target.darwin_aarch64_cjnative` (bin-dependencies point to the SDK’s precompiled std).

The tool writes **`src/cli_driver.cj`** into the target package (at `<package_root>/src/cli_driver.cj`). If the package has a **`web/`** directory, it also writes **`web/cli_ws_server.js`** (the browser-terminal backend); create `web/` if you want that file.

## Testing (run before deployment)

Run the standard test suite **before deployment** to avoid runtime errors: it generates the driver for **sample_cangjie_package**, builds it, and runs Cangjie plus shell tests (ref output, CLI usage). This catches driver compile errors (e.g. missing APIs) and CLI behaviour regressions:

```bash
./scripts/build_and_test.sh
```

This script builds Clive, generates `sample_cangjie_package`’s driver, builds the sample package, runs `cjpm test` there, then runs `test_ref_output.sh`, `test_cli_usage.sh`, and the WebSocket backend tests (`test_backend.js`). Backend tests require Node.js, `npm install ws`, and `cjpm` on PATH; use `SKIP_BACKEND_TESTS=1` to skip them. To run only the sample-package test (Clive already built):

```bash
./scripts/test_sample_package.sh
```

Optional: `CANGJIE_ENVSETUP=/path/to/envsetup.sh` so `cjpm` is on `PATH`. To also smoke-test the WebSocket backend (e.g. cjpm on PATH when backend runs), use **`BACKEND_SMOKE=1`** (requires `npm install ws` in the sample package): `BACKEND_SMOKE=1 ./scripts/test_sample_package.sh`.

**Note:** The generated driver uses a stub for `--serve-stdin` (browser terminal) when `std.io.readLine()` is not available in your Cangjie toolchain, so the driver always compiles; the browser terminal then exits immediately until the toolchain provides `readLine`. See [docs/browser-terminal-actors.md](docs/browser-terminal-actors.md).

## Using the generated CLI

1. Generate the driver (as above).
2. In the **target** package, ensure there is only one `main()`: either remove/rename the existing `main()` in that package (e.g. rename to `demo()`) or use the generated driver as the sole entry point. Two `main()` in the same module will cause a build error.
3. From the target package root:
   ```bash
   cjpm build
   cjpm run
   ```
   With no arguments, the driver prints usage and the list of commands. To run a command, pass it via `--run-args`:
   ```bash
   cjpm run --run-args="help"
   cjpm run --run-args="Student new Alice 1001"
   cjpm run --run-args="Lesson new"
   ```
   Each separate `cjpm run` starts a new process, so refs reset to `ref:1`. To get **ref:1**, **ref:2**, **ref:3** in one run, pass multiple commands separated by **`;`** (e.g. `cjpm run --run-args="Student new Alice 1001 ; Lesson new ; Lesson new"`). The driver prints those ref ids for future use (e.g. instance methods).

The target package may need `std.env`, `std.io`, `std.collection`, and `std.convert` in its `cjpm.toml` dependencies for the generated driver to compile.

## Web interface (browser terminal)

You can run the generated CLI from an **interactive terminal in the browser**: type commands (e.g. `Student new Alice 1001`) and see output. Clive generates both the driver and a **minimal Node.js WebSocket backend** (`web/cli_ws_server.js`). You need **Node.js 18+** and **`npm install ws`** in the package to run the backend.

### Quick start

1. **Generate the driver and backend** — From the Clive project root, after building Clive (`cjpm build`):
   ```bash
   PKG_SRC=sample_cangjie_package cjpm run
   ```
   This writes **`src/cli_driver.cj`** into the target package and **`web/cli_ws_server.js`** into the target’s **`web/`** directory (create `web/` if it doesn’t exist).

2. **Start the backend** (from the package root, e.g. `sample_cangjie_package`). **`cjpm` must be on your PATH** in this terminal (e.g. run `source /path/to/cangjie/envsetup.sh` first), or set `CJPM_BIN` to the full path to the `cjpm` executable:
   ```bash
   cd sample_cangjie_package
   npm install ws    # install the ws package (use npm, not node)
   node web/cli_ws_server.js
   ```
   If you see **"spawn cjpm ENOENT"** in the browser, the backend cannot find `cjpm`; start the backend from a shell where Cangjie is on PATH, or run `CJPM_BIN=/path/to/cjpm node web/cli_ws_server.js`. You should see `WebSocket on ws://localhost:8765`.

3. **Serve the terminal page** (in another terminal). You must run this **from the sample package directory** (`sample_cangjie_package`), not from the Clive root:
   ```bash
   cd sample_cangjie_package
   npx serve web
   ```
   This serves the `web/` folder so the terminal is at the root URL. Alternatively, `npx serve .` from `sample_cangjie_package` serves the whole package; then open **`http://localhost:3000/web/`**.

4. **Open in the browser**: `http://localhost:3000/` (or the URL shown by `serve`). Type a command (e.g. `Student new Alice 1001`) and press Enter. Use **`NAME = command`** to set an env var (stores the last ref), and **`$NAME`** in later commands to substitute. See [docs/browser-terminal-actors.md](docs/browser-terminal-actors.md) for details.

## Exit codes

- `0` — success  
- `64` — usage / unknown command  
- `65` — invalid package path, parse failure, or attempt to generate into Clive itself  
- `66` — failed to write `cli_driver.cj`  

(Exit codes 65 and 66 are from Clive; 64 is from the **generated** driver when you run it.)

## Sample package

`sample_cangjie_package/` contains a minimal package (`lesson_demo`) with `Student`, `Lesson`, and a `demo()` function. It also includes a **browser terminal UI** in `web/`. To try Clive and the generated CLI:

```bash
# From the Clive project root: generate the driver
cjpm build
PKG_SRC=sample_cangjie_package cjpm run

# From the sample package: build and run the CLI
cd sample_cangjie_package
cjpm build
cjpm run
cjpm run --run-args="help"
cjpm run --run-args="Student new Bob 2000"
cjpm run --run-args="Lesson new"
```

To serve the web terminal: from `sample_cangjie_package` run `npm install ws`, then `node web/cli_ws_server.js` (in one terminal) and `npx serve web` (in another, from `sample_cangjie_package`); open `http://localhost:3000/` in the browser. In the terminal you can type commands directly (e.g. `Student new Alice 1001`) and use `NAME = command` / `$NAME` for env vars.

## File layout

- `src/main.cj` — entrypoint: parse args/env, call parser, codegen, write driver.
- `src/parser.cj` — reads `.cj` files, extracts package name and command manifest.
- `src/codegen.cj` — from manifest, emits `cli_driver.cj` (object store, arg conversion, dispatch).
- Generated **`cli_driver.cj`** — lives in the target package’s `src/`; user runs `cjpm build` and `cjpm run` from the target root.

## Documentation

Detailed documentation lives in the **`docs/`** directory:

- [docs/README.md](docs/README.md) — index and quick links
- [docs/overview.md](docs/overview.md) — what Clive does and high-level workflow
- [docs/user-guide.md](docs/user-guide.md) — build, run, environment, and using the generated CLI
- [docs/architecture.md](docs/architecture.md) — design and component responsibilities
- [docs/generated-driver.md](docs/generated-driver.md) — how the generated CLI driver works
- [docs/browser-terminal-actors.md](docs/browser-terminal-actors.md) — browser terminal, runFromArgs, and backend contract
- [docs/api-reference.md](docs/api-reference.md) — parser/codegen types and public APIs
- [docs/limitations-and-future.md](docs/limitations-and-future.md) — v1 limitations and possible improvements
- [docs/development.md](docs/development.md) — contributing and file layout
- [docs/cangjie-and-corpus.md](docs/cangjie-and-corpus.md) — Cangjie toolchain and CangjieCorpus

## Limitations (v1)

- Only top-level public functions and public constructors; no instance or static methods.
- Parser uses std.ast; complex signatures may need manual adjustment.
- Generic functions are not supported in the first version.
- Object store is in-memory only; no persistence across runs.
