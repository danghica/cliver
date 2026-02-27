# Browser terminal and Cangjie distributed actors

This note describes how to use the generated CLI driver from a **browser terminal** with the **terminal side** implemented using Cangjie distributed actors.

## Architecture

- **Browser**: A terminal UI (e.g. [xterm.js](https://xtermjs.org/)) where users type CLI commands. Input is sent to a backend over a WebSocket (or similar); stdout/stderr from the backend are displayed in the terminal.
- **Backend**: A Cangjie program using **distributed actors**. A **gateway** accepts WebSocket connections; for each connection it spawns or assigns a **session actor**. The session actor holds the CLI’s object store (`HashMap<Int64, Any>`) and the next ref id (`Int64`). For each command line received from the client, the session actor calls the generated **`runFromArgs(args, store, nextId)`** and gets back a **`RunFromArgsResult`** (nextId, exitCode, stdout, stderr). It updates its state and sends the output to the gateway, which forwards it to the browser.
- **No subprocess**: The same Cangjie package that contains the generated driver is used as a library; the session actor calls `runFromArgs` in-process. Refs (e.g. `ref:1`, `ref:2`) are preserved for the lifetime of the session.

## Clive’s role

Clive generates a driver that:

1. **`main()`** — Unchanged: reads `getCommandLine()`, splits by `;`, runs commands, prints to stdout/stderr. Used when running the CLI as a process (`cjpm run --run-args="..."`).
2. **`runFromArgs(args, store, nextId): RunFromArgsResult`** — Public library entrypoint. Takes an array of argument strings (e.g. `["Student", "new", "Alice", "1001"]`), a session-owned store, and the current next ref id. Runs the same command dispatch as `main()` but with output captured into buffers. Returns:
   - **nextId** — Updated ref id for the next `runFromArgs` call.
   - **exitCode** — 0 on success, 64 for usage/unknown command, etc.
   - **stdout** / **stderr** — Captured output as strings.

The generated file also defines **`RunFromArgsResult`** (public class with fields `nextId`, `exitCode`, `stdout`, `stderr`).

## Contract for the backend

- **Input**: One command line per request (e.g. the line the user typed, split into tokens, or the full line as a single string to be tokenized by the backend). Passed to `runFromArgs` as `Array<String>` (command name first, then arguments).
- **Output**: Send `result.stdout` and `result.stderr` to the client (e.g. append to the terminal buffer). Use `result.exitCode` if the UI needs to show exit status.
- **State**: After each call, replace the session’s store and nextId with the ones passed into the next `runFromArgs` call (store is mutated in place; use `result.nextId` as the new nextId).

## Out of scope for Clive

- **WebSocket server**: Not implemented in Clive. Implement it in your Cangjie backend (or a thin bridge in another language that forwards to the actor node).
- **Browser UI**: xterm.js and the WebSocket client are separate; only the API contract above is defined.
- **Distributed actors**: No change to the actors framework; the session actor is a consumer of `runFromArgs` and holds (store, nextId) per connection.
