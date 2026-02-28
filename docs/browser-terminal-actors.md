# Browser terminal and Cangjie distributed actors

This note describes how to use the generated CLI driver from a **browser terminal**, including the **minimal generated backend** and the optional **Cangjie distributed actors** approach.

## Architecture

- **Browser**: A terminal UI (e.g. [xterm.js](https://xtermjs.org/)) where users type CLI commands (e.g. `Student new Alice 1001`). Input is sent to a backend over WebSocket; stdout/stderr are displayed in the terminal.
- **Backend (generated)**: Clive generates **`web/cli_ws_server.js`** (Node.js). It runs a WebSocket server; for each connection it spawns one Cangjie process with **`--serve-stdin`**, forwards each line to the process stdin, and sends JSON `{ stdout, stderr }` from the process stdout back to the client. The driver outputs one line per response (stdout and stderr separated by tab, newlines replaced by ` <NL> `) to avoid backslash/double-quote in Cangjie source. One process per connection = one session (store, nextId, env vars).
- **Backend (optional, Cangjie actors)**: A Cangjie program using **distributed actors** can replace the Node backend: a gateway accepts WebSocket connections and assigns a session actor that holds the object store and calls **`runFromArgs(args, store, nextId)`** in-process.

## Clive’s role

Clive generates:

1. **`src/cli_driver.cj`** — The CLI driver:
   - **`main()`** — Reads `getCommandLine()`. If the only argument is `--serve-stdin`, enters **stdin mode** (see below). Otherwise splits by `;`, runs commands, prints to stdout/stderr. Used when running the CLI as a process (`cjpm run --run-args="..."`).
   - **`runFromArgs(args, store, nextId): RunFromArgsResult`** — Public library entrypoint. Takes an array of argument strings, a session-owned store, and the current next ref id. Returns nextId, exitCode, stdout, stderr.
   - **`--serve-stdin` mode** — When the driver is run with `--serve-stdin`, it should read lines from stdin and run each line (env assignment and `$VAR` substitution). On toolchains that do not provide `std.io.readLine()`, the generated driver uses a **stub** that returns immediately, so the driver always compiles; the browser terminal will not accept input until the toolchain provides `readLine`. When available, the driver prints one line per command (stdout and stderr separated by tab; newlines become ` <NL> `). The Node backend parses that and sends JSON `{ stdout, stderr }` to the client.
2. **`web/cli_ws_server.js`** — A minimal Node.js WebSocket server (port 8765, or `PORT` env). Requires **Node.js 18+** and **`npm install ws`**. Run from the package root: `node web/cli_ws_server.js`.

### Web terminal environment variables

In the browser terminal (when using the generated backend), you can use:

- **`NAME = command`** — Runs the command and stores the last ref printed (e.g. `ref:1`) in `NAME`. Example: `STU = Student new Alice 1001`.
- **`$NAME`** — Substitution in a later command. Example: after `STU = Student new Alice 1001`, use `$STU` in a command that expects a ref. Unset names are replaced with an empty string.
- **`exit`** or **`quit`** — Exits the stdin loop (backend closes the process when the WebSocket disconnects anyway).

## Contract for the backend

- **Input**: One command line per request (e.g. the line the user typed, split into tokens, or the full line as a single string to be tokenized by the backend). Passed to `runFromArgs` as `Array<String>` (command name first, then arguments).
- **Output**: Send `result.stdout` and `result.stderr` to the client (e.g. append to the terminal buffer). Use `result.exitCode` if the UI needs to show exit status.
- **State**: After each call, replace the session’s store and nextId with the ones passed into the next `runFromArgs` call (store is mutated in place; use `result.nextId` as the new nextId).

## How to run the remote terminal

Clive generates both the driver and a minimal **Node.js WebSocket backend** (`web/cli_ws_server.js`). You need **Node.js 18+** and the **`ws`** package for the backend.

### 1. Generate the driver and backend

From the Clive project root:

```bash
PKG_SRC=sample_cangjie_package cjpm run
```

This writes **`src/cli_driver.cj`** and **`web/cli_ws_server.js`** into the target package (e.g. `sample_cangjie_package`). Ensure the target package has a **`web/`** directory (create it if needed).

### 2. Ensure cjpm is on PATH (or set CJPM_BIN)

The backend spawns `cjpm run --run-args=--serve-stdin` for each connection. **Start the backend from a terminal where `cjpm` is on your PATH** (e.g. run `source /path/to/cangjie/envsetup.sh` first). If `cjpm` is not on PATH, set `CJPM_BIN` to the full path to the `cjpm` executable (e.g. `CJPM_BIN=/opt/cangjie/bin/cjpm node web/cli_ws_server.js`). If you see "spawn cjpm ENOENT" in the browser, the backend could not find `cjpm`.

### 3. Install backend dependency and start the backend

From the **package root** (e.g. `sample_cangjie_package`):

```bash
cd sample_cangjie_package
npm install ws
node web/cli_ws_server.js
```

You should see `WebSocket on ws://localhost:8765`. Use `PORT=3001 node web/cli_ws_server.js` to use a different port.

### 4. Start the frontend and open the browser

From the same package root (in another terminal):

```bash
npx serve web
```

Open **`http://localhost:3000/`** (or the URL shown). If you get 404, ensure you ran `npx serve web` from the **sample package directory** (`sample_cangjie_package`), not from the Clive root. If you used `npx serve .` instead, open **`http://localhost:3000/web/`**.

### 5. Use the terminal

- **Streamlined syntax**: Type a command and press Enter (e.g. `Student new Alice 1001`). No `cjpm run --run-args="..."` in the browser.
- **Env vars**: Type `NAME = command` to run the command and store the last ref in `NAME`. Use `$NAME` in later commands to substitute.
- One browser tab = one WebSocket connection = one Cangjie process (one store, nextId, env). Closing the tab kills that process.

### 6. Alternative: Cangjie backend (distributed actors)

You can replace the Node backend with a Cangjie program that:

- Listens for WebSocket connections (e.g. via Cangjie net APIs or an FFI to a WebSocket library).
- For each connection, creates a session (store, nextId) and, for each line received, tokenizes it, calls **`runFromArgs(args, store, nextId)`**, and sends `{ stdout, stderr }` back. The contract is the same as the JSON lines produced by the driver in `--serve-stdin` mode.

## Out of scope for Clive

- **Browser UI**: xterm.js and the WebSocket client are provided in the sample package; the API contract is defined above.
- **Distributed actors**: No change to the actors framework; the session actor is a consumer of `runFromArgs` and holds (store, nextId) per connection.
- **Cangjie std.io readLine**: The driver's `--serve-stdin` mode uses `readLine()` from std.io to read lines from stdin. If your Cangjie environment does not provide it, the generated backend may not work until the API is available or you use a Cangjie-only backend that calls `runFromArgs` directly.
- **Cangjie String API**: The generated driver uses `String.substring(start, end)`. If your toolchain reports that `substring` (or `slice`) is not a member of `String`, the standard library may use a different method name for slicing; you may need to align with the Cangjie version the driver was generated for.
