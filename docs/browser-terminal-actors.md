# Browser terminal and Cangjie distributed actors

This note describes how to use the generated CLI driver from a **browser CLI**, including the **minimal generated backend** and the optional **Cangjie distributed actors** approach.

## Architecture

- **Browser**: A **chat-style UI** (scrollable interaction history, text input at the bottom) where users type CLI commands (e.g. `Student new Alice 1001`). Input is sent to a backend over WebSocket; stdout/stderr are appended to the history (output in grey, errors in red). Same semantics as the command-line CLI: run command, output response, env vars, refs.
- **Backend (generated)**: Clive generates **`web/cli_ws_server.js`** (Node.js). It runs a WebSocket server; for each **message** (one line) it spawns a **one-off** Cangjie process with **`cjpm run --run-args="<line>"`**, collects stdout/stderr, and sends a single JSON `{ stdout, stderr }` to the client. **One process per message**: refs and env are session-local to that message (no persistence across messages). A single message can contain **semicolon-separated commands** (e.g. `Student new Alice 1001 ; Student new Bob 1002`); the driver processes the line **segment-by-segment** (split by `;`), so each segment can be `NAME = command` or a command that may use `$NAME`; later segments see refs from earlier segments in the same line. The user can type **`exit`** to close the session (backend sends `sessionClosed`, closes the WebSocket). If the session is **idle** (no input) for **`IDLE_TIMEOUT_MS`** (default 10 minutes), the backend sends "session idle. exiting" and closes the connection. No PTY or long-lived process; no `node-pty` required.
- **Backend (optional, Cangjie actors)**: A Cangjie program using **distributed actors** can replace the Node backend: a gateway accepts WebSocket connections and assigns a session actor that holds the object store and calls **`runFromArgs(args, store, nextId)`** in-process.

## Clive’s role

Clive generates:

1. **`src/cli_driver.cj`** — The CLI driver:
   - **`main()`** — Reads `getCommandLine()`. If the only argument is `--serve-stdin`, enters **stdin mode** (see below). Otherwise splits by `;`, runs commands, prints to stdout/stderr. Used when running the CLI as a process (`cjpm run --run-args="..."`).
   - **`runFromArgs(args, store, nextId): RunFromArgsResult`** — Public library entrypoint. Takes an array of argument strings, a session-owned store, and the current next ref id. Returns nextId, exitCode, stdout, stderr.
   - **`--serve-stdin` mode** — When the driver is run with `--serve-stdin`, it reads lines from stdin and runs each line (env assignment and `$VAR` substitution), printing one line per command (stdout and stderr separated by tab; newlines become ` <NL> `). Used for interactive stdin sessions (e.g. local terminal). The **Node backend** does not use `--serve-stdin`; it spawns one process per message with the line as `--run-args="<line>"`, so refs and env are local to that message.
2. **`web/cli_ws_server.js`** — A minimal Node.js WebSocket server (port 8765, or `PORT` env). Requires **Node.js 18+** and **`npm install ws`**. Run from the package root: `node web/cli_ws_server.js`. Logs are written to **`web/logs/cli_ws_server.log`**; use **`DEBUG_LOG=1`** for extra detail. No `node-pty` required.

### Web CLI environment variables

In the browser UI (when using the generated backend), you can use:

- **`NAME = command`** — Runs the command and stores the last ref in `NAME`. Example: `STU = Student new Alice 1001`. The line is processed **segment-by-segment**, so you can use multiple assignments and multiple `$NAME` in one message (e.g. `SN1 = Student new Alice 1001 ; EV = Lesson new ; Lesson new ; $EV`). Refs and env are **local to that message**; they are not available in later messages because each message runs in a new process.
- **`$NAME`** — Substitution **within the same message**; later segments see refs set in earlier segments (e.g. `STU = Student new Alice 1001 ; someCommand $STU`). Unset names are replaced with an empty string.
- **`exit`** — Special command: backend closes the session (kills the process, sends `sessionClosed`, closes the WebSocket). The UI shows "Session closed."
- **Idle timeout**: If there is no user input for **`IDLE_TIMEOUT_MS`** (default 60000 ms = 1 minute), the backend sends the message "session idle. exiting" and closes the session. Set **`IDLE_TIMEOUT_MS=0`** to disable. Command output in the UI is shown in **grey**.

## Contract for the backend

- **Input**: One command line per request (e.g. the line the user typed, split into tokens, or the full line as a single string to be tokenized by the backend). Passed to `runFromArgs` as `Array<String>` (command name first, then arguments).
- **Output**: Send `result.stdout` and `result.stderr` to the client (e.g. append to the terminal buffer). Use `result.exitCode` if the UI needs to show exit status.
- **State**: For a Cangjie actors backend: after each call, replace the session’s store and nextId with the ones passed into the next `runFromArgs` call (use `result.nextId` as the new nextId). The Node backend does not use `runFromArgs`; each message is a fresh `cjpm run --run-args="<line>"` spawn.

## How to run the web CLI

Clive generates both the driver and a minimal **Node.js WebSocket backend** (`web/cli_ws_server.js`). You need **Node.js 18+** and the **`ws`** package for the backend.

### 1. Generate the driver and backend

From the Clive project root:

```bash
PKG_SRC=sample_cangjie_package cjpm run
```

This writes **`src/cli_driver.cj`** and **`web/cli_ws_server.js`** into the target package (e.g. `sample_cangjie_package`). Ensure the target package has a **`web/`** directory (create it if needed).

### 2. Ensure cjpm is on PATH (or set CJPM_BIN)

The backend spawns `cjpm run --run-args="<line>"` for each message. **Start the backend from a terminal where `cjpm` is on your PATH** (e.g. run `source /path/to/cangjie/envsetup.sh` first). If `cjpm` is not on PATH, set `CJPM_BIN` to the full path (e.g. `CJPM_BIN=/opt/cangjie/bin/cjpm node web/cli_ws_server.js`). If you see "spawn cjpm ENOENT" in the browser, the backend could not find `cjpm`.

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

### 5. Use the web CLI

- **Chat-style UI**: Scrollable history shows each command and its output; type in the text box at the bottom and press Enter or Send. Command output is shown in **grey**.
- **Env vars**: Type `NAME = command` to run the command and store the last ref in `NAME`. Use `$NAME` in later commands to substitute.
- **Exit**: Type **`exit`** to close the session (backend kills the process and closes the WebSocket; UI shows "Session closed.").
- One browser tab = one WebSocket connection; each message runs in its own process (refs and env local to that message). You can use `;` in one message to run multiple commands in the same process (e.g. `Student new Alice 1001 ; Student new Bob 1002`). If the session is idle for too long (default 10 minutes), "session idle. exiting" is shown and the session closes.

### 6. Alternative: Cangjie backend (distributed actors)

You can replace the Node backend with a Cangjie program that:

- Listens for WebSocket connections (e.g. via Cangjie net APIs or an FFI to a WebSocket library).
- For each connection, can create a session (store, nextId) and, for each line received, call **`runFromArgs(args, store, nextId)`** and send `{ stdout, stderr }` back. The Node backend instead spawns one process per message and does not use `runFromArgs`.

## Out of scope for Clive

- **Browser UI**: xterm.js and the WebSocket client are provided in the sample package; the API contract is defined above.
- **Distributed actors**: No change to the actors framework; the session actor is a consumer of `runFromArgs` and holds (store, nextId) per connection.
- **Cangjie stdin**: The driver's `--serve-stdin` mode uses `_readLineStdin()` for interactive stdin (e.g. local terminal). The Node backend does not use `--serve-stdin`; it spawns one process per WebSocket message with `--run-args="<line>"`, so refs and env are local to each message.
- **Cangjie String API**: The generated driver uses a helper `_substring(s, start, end)` (no `String.substring` dependency). No change needed for typical toolchains.
