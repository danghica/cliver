# Browser terminal and Cangjie distributed actors

This note describes how to use the generated CLI driver from a **browser terminal**, including the **minimal generated backend** and the optional **Cangjie distributed actors** approach.

## Architecture

- **Browser**: A terminal UI (e.g. [xterm.js](https://xtermjs.org/)) where users type CLI commands (e.g. `Student new Alice 1001`). Input is sent to a backend over WebSocket; stdout/stderr are displayed in the terminal.
- **Backend (generated)**: Clive generates **`web/cli_ws_server.js`** (Node.js). It runs a WebSocket server; for each connection it spawns **one** Cangjie process with **`--serve-stdin`**, forwards each command line to the process stdin, and sends JSON `{ stdout, stderr }` from the process stdout back to the client. The driver outputs one line per command (stdout and stderr separated by tab, newlines replaced by ` <NL> `). **One process per connection = one session**: the generated driver uses `getStdIn().readln()` so the process stays alive and the object store, ref IDs, and env vars persist for the lifetime of that connection. For **interactive** behavior (one line in → command runs immediately → output appears), the backend uses a **pseudo-terminal (PTY)** when the **`node-pty`** package is installed; without it, the backend falls back to pipes and input may be buffered until the connection closes. The user can type **`exit`** to close the session; if the session is **idle** (no input) for longer than **`IDLE_TIMEOUT_MS`** (default 1 minute), the backend sends "session idle. exiting" and closes the connection. There is no response-timeout fallback (if the process does not respond, the user sees no output or "Process exited.").
- **Backend (optional, Cangjie actors)**: A Cangjie program using **distributed actors** can replace the Node backend: a gateway accepts WebSocket connections and assigns a session actor that holds the object store and calls **`runFromArgs(args, store, nextId)`** in-process.

## Clive’s role

Clive generates:

1. **`src/cli_driver.cj`** — The CLI driver:
   - **`main()`** — Reads `getCommandLine()`. If the only argument is `--serve-stdin`, enters **stdin mode** (see below). Otherwise splits by `;`, runs commands, prints to stdout/stderr. Used when running the CLI as a process (`cjpm run --run-args="..."`).
   - **`runFromArgs(args, store, nextId): RunFromArgsResult`** — Public library entrypoint. Takes an array of argument strings, a session-owned store, and the current next ref id. Returns nextId, exitCode, stdout, stderr.
   - **`--serve-stdin` mode** — When the driver is run with `--serve-stdin`, it reads lines from stdin via **`_readLineStdin()`** (which calls `getStdIn().readln()`) and runs each line (env assignment and `$VAR` substitution), printing one line per command (stdout and stderr separated by tab; newlines become ` <NL> `). The Node backend parses that and sends JSON `{ stdout, stderr }` to the client. One process per connection gives a **single persistent session** (refs and env vars across commands). If the process exits right after connect (e.g. toolchain without std.env getStdIn/readln), the backend falls back to one process per command so the terminal still works but refs do not persist.
2. **`web/cli_ws_server.js`** — A minimal Node.js WebSocket server (port 8765, or `PORT` env). Requires **Node.js 18+** and **`npm install ws`**. For an interactive terminal (line-by-line input and immediate output), also install **`node-pty`** (`npm install node-pty`). Run from the package root: `node web/cli_ws_server.js`.

### Web terminal environment variables

In the browser terminal (when using the generated backend), you can use:

- **`NAME = command`** — Runs the command and stores the last ref printed (e.g. `ref:1`) in `NAME`. Example: `STU = Student new Alice 1001`.
- **`$NAME`** — Substitution in a later command. Example: after `STU = Student new Alice 1001`, use `$STU` in a command that expects a ref. Unset names are replaced with an empty string.
- **`exit`** — Special command: backend closes the session (kills the process, sends `sessionClosed`, closes the WebSocket). The terminal shows "Session closed."
- **Idle timeout**: If there is no user input for **`IDLE_TIMEOUT_MS`** (default 60000 ms = 1 minute), the backend sends the message "session idle. exiting" and closes the session. Set **`IDLE_TIMEOUT_MS=0`** to disable. Command output in the terminal is shown in **grey**.

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
npm install ws node-pty   # node-pty for interactive (line-by-line) session
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

- **Streamlined syntax**: Type a command and press Enter (e.g. `Student new Alice 1001`). Command output is shown in **grey**. No `cjpm run --run-args="..."` in the browser.
- **Env vars**: Type `NAME = command` to run the command and store the last ref in `NAME`. Use `$NAME` in later commands to substitute.
- **Exit**: Type **`exit`** to close the session (backend kills the process and closes the WebSocket; terminal shows "Session closed.").
- One browser tab = one WebSocket connection = one Cangjie process (one store, nextId, env). Closing the tab kills that process. If the session is idle for too long (default 1 minute), "session idle. exiting" is shown and the session closes.

### 6. Alternative: Cangjie backend (distributed actors)

You can replace the Node backend with a Cangjie program that:

- Listens for WebSocket connections (e.g. via Cangjie net APIs or an FFI to a WebSocket library).
- For each connection, creates a session (store, nextId) and, for each line received, tokenizes it, calls **`runFromArgs(args, store, nextId)`**, and sends `{ stdout, stderr }` back. The contract is the same as the JSON lines produced by the driver in `--serve-stdin` mode.

## Out of scope for Clive

- **Browser UI**: xterm.js and the WebSocket client are provided in the sample package; the API contract is defined above.
- **Distributed actors**: No change to the actors framework; the session actor is a consumer of `runFromArgs` and holds (store, nextId) per connection.
- **Cangjie stdin**: The driver's `--serve-stdin` mode uses `_readLineStdin()` implemented with `getStdIn().readln()` (std.env) so one process per connection keeps refs persistent. If your toolchain does not provide `getStdIn().readln()`, the backend falls back to one process per command. **Interactive session**: When `node-pty` is installed, the backend spawns the Cangjie process under a PTY so the process sees a TTY; `readln()` then returns line-by-line and output is line-buffered, so each command runs immediately. Without `node-pty`, the session may buffer input until the WebSocket closes.
- **Cangjie String API**: The generated driver uses a helper `_substring(s, start, end)` (no `String.substring` dependency). No change needed for typical toolchains.
