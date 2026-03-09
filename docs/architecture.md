# Architecture

This document describes the design and data flow of Clive.

## Pipeline

Clive’s pipeline is linear:

```
Package path (--pkg / PKG_SRC)
        │
        ▼
┌───────────────────┐
│  Parse package    │  parser.cj: parsePackage()
│  (.cj files)      │  → Manifest
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  Generate driver  │  codegen.cj: generateDriver(manifest)
│  (Cangjie source) │  → String (full cli_driver.cj source)
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  Write file       │  main.cj: File(outPath, Write).write(...)
│  src/cli_driver.cj│  → target package’s src/
└───────────────────┘
```

- **Input**: A filesystem path to a Cangjie package (directory with `.cj` files, or package root containing `src/`).
- **Output**: A single generated file `src/cli_driver.cj` in that package, which the user then compiles and runs with `cjpm` in the target package.

## Components

### 1. Entrypoint (`src/main.cj`)

- Reads command line and environment: `--pkg <path>` or `PKG_SRC`.
- Calls `parsePackage(pkgPath)` → `Option<Manifest>`.
- On success, calls `generateDriver(manifest)` → driver source string.
- Writes the string to `<pkgPath>/src/cli_driver.cj`.
- Returns exit code 0, 65 (parse/path error), or 66 (write error).

### 2. Directory structure (`src/dir.cj`)

- **Role**: Centralizes path and directory logic used by the parser and codegen.
- **Recursive collection**: `collectCjFilesUnder(scanDir)` returns all `.cj` paths under the resolved source directory (excluding `cli_driver.cj`), in stable sorted order.
- **Package path from file**: `packagePathFromFile(filePath, scanDir)` returns the CLI directory path for a file: `"/"` for files directly under `scanDir`, or the relative directory (e.g. `demo_sub`) for nested files.
- **Path normalization**: `normalizePath(pathToken, cwd)` resolves absolute (`/`) and relative paths (`.` and `..`), with root always `"/"`.
- **Known paths**: `isKnownPackagePath(path, knownPaths)` supports `cd` validation (any package path that appears in at least one command).

### 3. Parser (`src/parser.cj`)

- **Role**: Turn package source into a structured **manifest** (package name + list of commands).
- **Scope**: Recursively scans **all** `.cj` files under the resolved source directory (using the dir module). Multiple Cangjie packages (root + subpackages) are allowed; each command carries a **packagePath** (CLI directory).
- **Resolve source dir**: If the given path has a `src/` subdirectory, scan `src/`; otherwise scan the path itself.
- **Line-based parsing**: Iterates over lines looking for:
  - `package <name>` → package name (first one at root wins for `packageQualifiedName`)
  - `public func <Name>(...)` → top-level function; extracts name, parameter list (name: type), and return type
  - `public class <ClassName>` → current class context
  - `public init(...)` → constructor of current class; parameters and “return” (the class) recorded
- **Output**: `Manifest` containing:
  - `packageQualifiedName: String`
  - `commands: ArrayList<CommandInfo>` (each item has a **packagePath** and is either a function or a constructor)

No full Cangjie AST: the parser is pattern-based and handles a subset of syntax. Complex signatures (e.g. multiline, heavy generics) may need manual adjustment.

### 4. Code generator (`src/codegen.cj`)

- **Role**: From a `Manifest`, emit the full Cangjie source of the CLI driver.
- **Assumptions**: The generated file will live in the **same** package’s `src/`, so it does not import the target package (same module). Uses the dir module's path semantics (normalization, known paths) when emitting the driver.
- **CLI directory and path resolution**: Current directory `_cwd` (initial `"/"`); first token may be a path (e.g. `demo_sub/demoAlt`) or bare name; `cd <path>` changes directory (validated against known paths); dispatch by `(resolvedDir, command)`.
- **Structure of generated code**:
  - Imports: `std.env`, `std.io`, `std.collection`, `std.convert`
  - Object store and current directory (`_cwd`); path helpers: `_substring`, `_pathSegments`, `_normalizePath`, `_isKnownPath`
  - `main()` / `_runSegments`: resolve first token to `(resolvedDir, command)`; handle `cd`, `help`, `echo`, then dispatch by `(resolvedDir, command)`
  - For each `(packagePath, key)`: `if (resolvedDir == "…" && command == "Key") return _runKey(argsList)`
  - For each key: `_runKey(args)` that tries overloads in order; for constructors, requires second token `new` and then passes remaining args
  - Argument conversion: for each parameter type (Int64, Float64, Bool, String, Option&lt;T&gt;, or class type), emit code that parses the CLI string (or `ref:<id>` for class types) into an `Option&lt;T&gt;`; if all conversions succeed, emit the call and then handle return (store ref + print `ref:<id>`, or print value, or return 0 for Unit)

Overload resolution is **first match wins** in manifest order (no “most specific” ordering).

## Data structures (manifest)

- **Manifest**: Package name + list of commands.
- **CommandInfo**: name (function name or `"init"`), isConstructor, className (if constructor), params (ParamInfo list), returnType, returnIsRef (true if result is stored in object store), **packagePath** (CLI directory: `"/"` for root, or e.g. `demo_sub` for a subdirectory).
- **ParamInfo**: paramName, paramType (string representation of type).

Reference-type detection for parameters and return types uses a simple heuristic in the parser (not primitive, not Unit, not Option&lt;…&gt; as value) to decide “class type” and thus ref storage and `ref:<id>` parsing.

## Design decisions (summary)

- **No reflection**: Generated code uses only static calls and explicit types.
- **One package path in**: One package path in, one `cli_driver.cj` out; that package may contain nested directories and multiple Cangjie package declarations (root + subpackages); each command is associated with a CLI directory (packagePath).
- **Driver in package**: Generated file is placed inside the target package’s `src/` so a single `cjpm build` in the target builds both package and driver.
- **Monotonic object store id**: Int64 id; no hashCode as key (collision risk).
- **Positional args only (v1)**: No named/optional CLI flags in the first version.
- **First overload wins**: Deterministic but not “most specific” overload resolution.

For limitations and possible future extensions, see [Limitations and future](limitations-and-future.md). For the exact behavior of the generated driver, see [Generated driver](generated-driver.md).
