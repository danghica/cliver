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

**Note:** The web backend runs one process per message (refs and env are session-local to each message). See [docs/browser-terminal-actors.md](docs/browser-terminal-actors.md).

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
   Each separate `cjpm run` starts a new process, so refs reset to `ref:1`. To get **ref:1**, **ref:2**, **ref:3** in one run, pass multiple commands separated by **`;`** (e.g. `cjpm run --run-args="Student new Alice 1001 ; Lesson new ; Lesson new"`). You can use **multiple** `NAME = command` and `$NAME` in the same line; the driver processes the line segment-by-segment so later segments see refs from earlier ones (e.g. `SN1 = Student new Alice 1001 ; EV = Lesson new ; Lesson new ; $EV`). The driver prints those ref ids for future use (e.g. instance methods).

The target package may need `std.env`, `std.io`, `std.collection`, and `std.convert` in its `cjpm.toml` dependencies for the generated driver to compile.

## Web interface (browser CLI)

You can run the generated CLI from a **browser UI**: a **chat-style** interface (scrollable command/response history, text input at the bottom). Clive generates **`src/cli_driver.cj`** and a **minimal Node.js WebSocket backend** **`web/cli_ws_server.js`**. You need **Node.js 18+** and **`npm install ws`**. The backend spawns **one process per message**; refs and env are local to that message. Within one message you can use multiple `NAME = command` and `$NAME` (segment-by-segment); a single message can contain semicolon-separated commands (e.g. `Student new Alice 1001 ; EV = Lesson new ; Lesson new ; $EV`). See [docs/browser-terminal-actors.md](docs/browser-terminal-actors.md) for architecture and the backend contract.

### 1. Generate the driver and backend

From the Clive project root (after `cjpm build`):

```bash
PKG_SRC=sample_cangjie_package cjpm run
```

This writes **`src/cli_driver.cj`** and **`web/cli_ws_server.js`** into the target package. Ensure the target has a **`web/`** directory (create it if needed).

### 2. Ensure cjpm is on PATH (or set CJPM_BIN)

The backend spawns `cjpm run --run-args="<line>"` per message. Start the backend from a terminal where **`cjpm`** is on your PATH (e.g. `source /path/to/cangjie/envsetup.sh`). If not, set **`CJPM_BIN`** to the full path to `cjpm`. If you see **"spawn cjpm ENOENT"** in the browser, the backend could not find `cjpm`.

### 3. Install backend deps and start the backend

From the **package root** (e.g. `sample_cangjie_package`):

```bash
cd sample_cangjie_package
npm install ws
node web/cli_ws_server.js
```

You should see `WebSocket on ws://localhost:8765`. Use **`PORT=3001`** to use another port. If you get **`EADDRINUSE`** on 8765, stop the previous backend (e.g. `kill $(lsof -t -i :8765)`).

### 4. Serve the frontend and open the browser

From the same package root (another terminal):

```bash
npx serve web
```

Open **`http://localhost:3000/`** (or the URL shown). If you get 404, ensure you ran `npx serve web` from the **package directory**, not Clive root. If you used `npx serve .`, open **`http://localhost:3000/web/`**.

### 5. Use the web CLI

- **Chat-style UI**: Scrollable history; type in the text box at the bottom, press Enter or Send. Command output is shown in **grey**.
- **Env vars**: **`NAME = command`** runs the command and stores the last ref in `NAME`. Use **`$NAME`** in later segments; within one message, multiple assignments and `$NAME` work (segment-by-segment).
- **Exit**: Type **`exit`** to close the session (backend kills the process and closes the WebSocket; UI shows "Session closed.").
- One tab = one WebSocket; each message spawns one Cangjie process (refs and env are local to that message). If the session is **idle** for longer than **`IDLE_TIMEOUT_MS`** (default 600000 ms = 10 minutes), the backend sends "session idle. exiting" and closes; set **`IDLE_TIMEOUT_MS=0`** to disable.

### Debug mode and logs

Logs are written to **`web/logs/cli_ws_server.log`** (the server creates `web/logs/` automatically). Format: one JSON object per line (NDJSON), with **`ts`** (ISO 8601). Events include **`NEW CONNECTION`**, **`input`** / **`output`**, **`PTY_USED`** / **`PTY_UNAVAILABLE`** / **`PTY_SPAWN_ERROR`**, **`PROCESS_EXIT`**, **`SESSION_IDLE_CLOSE`**. Start with **`DEBUG_LOG=1`** for extra detail (e.g. stdout/stderr chunk lengths):

```bash
DEBUG_LOG=1 node web/cli_ws_server.js
```

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

To serve the web CLI: from `sample_cangjie_package` run `npm install ws`, then `node web/cli_ws_server.js` (one terminal) and `npx serve web` (another); open `http://localhost:3000/`. See [Web interface (browser CLI)](#web-interface-browser-cli) for full steps, env vars (`NAME = command`, `$NAME`), and logs (`web/logs/cli_ws_server.log`, `DEBUG_LOG=1`).

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
