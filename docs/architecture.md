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

### 2. Parser (`src/parser.cj`)

- **Role**: Turn package source into a structured **manifest** (package name + list of commands).
- **Scope**: One Cangjie package at a time (one `package` declaration; all `.cj` files under the resolved source directory).
- **Resolve source dir**: If the given path has a `src/` subdirectory, scan `src/`; otherwise scan the path itself.
- **Line-based parsing**: Iterates over lines looking for:
  - `package <name>` → package name (first one wins)
  - `public func <Name>(...)` → top-level function; extracts name, parameter list (name: type), and return type
  - `public class <ClassName>` → current class context
  - `public init(...)` → constructor of current class; parameters and “return” (the class) recorded
- **Output**: `Manifest` containing:
  - `packageQualifiedName: String`
  - `commands: ArrayList<CommandInfo>` (each item is either a function or a constructor)

No full Cangjie AST: the parser is pattern-based and handles a subset of syntax. Complex signatures (e.g. multiline, heavy generics) may need manual adjustment.

### 3. Code generator (`src/codegen.cj`)

- **Role**: From a `Manifest`, emit the full Cangjie source of the CLI driver.
- **Assumptions**: The generated file will live in the **same** package’s `src/`, so it does not import the target package (same module).
- **Structure of generated code**:
  - Imports: `std.env`, `std.io`, `std.collection`, `std.convert`
  - Object store: `_nextId`, `_store: HashMap<Int64, Any>`, `_storeRef`, `_getRef`, `_parseRefId`
  - `main()`: get args, dispatch by first token (command name); `help` prints commands from manifest
  - For each command key (function name or class name): `if (command == "Key") return _runKey(argsList)`
  - For each key: `_runKey(args)` that tries overloads in order; for constructors, requires second token `new` and then passes remaining args
  - Argument conversion: for each parameter type (Int64, Float64, Bool, String, Option&lt;T&gt;, or class type), emit code that parses the CLI string (or `ref:<id>` for class types) into an `Option&lt;T&gt;`; if all conversions succeed, emit the call and then handle return (store ref + print `ref:<id>`, or print value, or return 0 for Unit)

Overload resolution is **first match wins** in manifest order (no “most specific” ordering).

## Data structures (manifest)

- **Manifest**: Package name + list of commands.
- **CommandInfo**: name (function name or `"init"`), isConstructor, className (if constructor), params (ParamInfo list), returnType, returnIsRef (true if result is stored in object store).
- **ParamInfo**: paramName, paramType (string representation of type).

Reference-type detection for parameters and return types uses a simple heuristic in the parser (not primitive, not Unit, not Option&lt;…&gt; as value) to decide “class type” and thus ref storage and `ref:<id>` parsing.

## Design decisions (summary)

- **No reflection**: Generated code uses only static calls and explicit types.
- **One package**: One package path in, one `cli_driver.cj` out for that package.
- **Driver in package**: Generated file is placed inside the target package’s `src/` so a single `cjpm build` in the target builds both package and driver.
- **Monotonic object store id**: Int64 id; no hashCode as key (collision risk).
- **Positional args only (v1)**: No named/optional CLI flags in the first version.
- **First overload wins**: Deterministic but not “most specific” overload resolution.

For limitations and possible future extensions, see [Limitations and future](limitations-and-future.md). For the exact behavior of the generated driver, see [Generated driver](generated-driver.md).
