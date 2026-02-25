# Clive overview

## What Clive does

Clive reads the **source code** of a single Cangjie package (`.cj` files under the package root or its `src/` directory), extracts:

- The **package** name
- **Public top-level functions** (`public func Name(...)`)
- **Public classes** and their **public constructors** (`public init(...)`)

It then **generates** a Cangjie source file `cli_driver.cj` that:

- Implements a `main()` entrypoint
- Parses command-line arguments to select a command (function name or `ClassName new`)
- Converts positional arguments to the correct types (Int64, Float64, Bool, String, Option&lt;T&gt;, or class references via `ref:<id>`)
- Dispatches to the appropriate function or constructor
- For reference-returning calls, stores the result in an in-memory **object store** and prints `ref:<id>` for use in later commands

No runtime reflection is used: the generated driver calls the package API directly.

## Features

- **Source as input**: Scans `.cj` files for `package`, `public func`, `public class`, and `public init`.
- **One CLI command per** top-level public function; constructors are invoked as **`ClassName new arg1 arg2 ...`**.
- **Overloads**: First matching overload in manifest order (argument conversion tried in order).
- **Arguments**: Positional; class-typed parameters accept `ref:<id>` and look up in the object store.
- **Object store**: In-memory map keyed by a monotonic id; only class instances are stored; the driver prints `ref:<id>` for later use.
- **Environment**: Package path can be set via `PKG_SRC` or `--pkg <path>`.

## High-level workflow

1. **Run Clive** (from the Clive project root, with Cangjie env sourced):
   ```bash
   cjpm run --run-args="--pkg /path/to/your/package"
   # or: PKG_SRC=/path/to/your/package cjpm run
   ```
2. Clive writes **`src/cli_driver.cj`** into the target package directory.
3. In the **target** package: ensure only one `main()` (rename or remove the existing one if present).
4. From the target package root: **build and run** the generated CLI:
   ```bash
   cjpm build
   cjpm run --run-args="help"
   cjpm run --run-args="Student new Alice 1001"
   cjpm run --run-args="Lesson new"
   ```

## Exit codes (Clive binary)

| Code | Meaning |
|------|--------|
| 0 | Success; driver written |
| 64 | Usage / unknown command (when running the *generated* CLI) |
| 65 | Invalid package path or parse failure |
| 66 | Failed to write `cli_driver.cj` |

## Related docs

- [User guide](user-guide.md) — detailed usage and options
- [Architecture](architecture.md) — how parsing and code generation fit together
