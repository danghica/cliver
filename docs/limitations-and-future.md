# Limitations and future work

This document summarizes the current limitations of Clive (v1) and possible future improvements.

## Current limitations (v1)

### Scope of discovery

- **Only top-level public functions** and **public constructors** are exposed. Instance methods (e.g. `lesson.add(student)`) and static methods are **not** exposed in the first version.
- **Generic functions** are not supported; the parser and codegen assume concrete types.
- **One package path in**: Clive operates on a single package path; that package may contain nested directories and multiple Cangjie package declarations (root + subpackages). Commands are associated with a CLI directory (packagePath); the generated CLI supports path-based invocation and `cd`.

### Parser

- **AST-based**: The parser uses **std.ast** (`cangjieLex`, `parseProgram`) to build an AST from package source. Limitations come from the AST shape/API and what is extracted (package header, top-level decls), not from line-scanning.
- **Complex signatures**: Multiline function/init declarations, heavy use of generics, or unusual formatting may not be parsed correctly and may require manual adjustment of the source or the parser.
- **Package name and order**: The **first** file (in `collectCjFilesUnder` sorted order) with `packagePath == "/"` and a non-empty package declaration sets `packageQualifiedName`. If multiple root files declare different packages, only one wins; the rule is order-dependent. Subdirectory files may declare subpackages and are still processed.

### CLI and arguments

- **Positional only**: Named parameters (e.g. `--name Alice`) and default values from the manifest are not supported in v1. All arguments are positional.
- **No Option syntax**: For `Option<T>` parameters, the driver uses “empty or missing” vs “present” from position; there is no explicit `none`/`some` CLI syntax documented.
- **Ref format**: Only `ref:<id>` is supported for class-typed parameters. The id is parsed as integer (e.g. `ref:1`, `ref:2`). String parameters are never interpreted as refs.

### Object store

- **In-memory only**: The object store is process-local and is lost when the CLI process exits. No persistence or cross-process refs.
- **Monotonic id**: Stored references are keyed by a single monotonic Int64. No hashCode or string key.

### Overload resolution

- **First match in manifest order**: If multiple overloads could accept the same CLI arguments (e.g. `f(Int64)` and `f(Float64)` with "42"), the first one in the manifest is chosen. There is no “most specific” or language-defined overload ordering.

### Generated driver

- **Single main()**: The target package must have exactly one `main()`. The user must rename or remove an existing `main()` when adopting the generated driver.
- **Driver overwritten**: Each run of Clive overwrites `src/cli_driver.cj`; any hand edits are lost.
- **runFromArgs semantics**: `runFromArgs(args, store, nextId)` accepts a **single command’s argv** (one command name + arguments). It does **not** split on semicolons or support `NAME = command` / `$NAME`. The Node backend spawns a process and passes the full line to the driver’s main(), which does the full line handling. For in-process use, callers must pre-split and call once per command if they need main()-equivalent behavior.
- **Emitted “unused” helpers**: The generated driver includes `_splitArgsBySemicolon`, `_splitTokensBySemicolon`, and `runFromArgs` that may be reported unused when the driver is used only from the CLI. They are used by tests and the WebSocket backend (driver is both CLI and library); the sample package may use `-Woff unused` or document this as intentional.
- **Ref vs value types**: `isRefType` treats a fixed set of primitives (Unit, Int64, Float64, Bool, String, Option<...>) as non-ref; everything else is ref. Collection or other std types are not explicitly listed; the rule is implicit. Supported parameter types for conversion are documented in codegen; other types (e.g. nested generics, type aliases) may be unsupported or wrong.

---

## Possible future improvements

- **Instance methods**: Expose public instance methods with a syntax such as `ref:<id> methodName args...`, resolving the ref from the object store and then calling the method.
- **Static methods**: Expose public static methods, e.g. `ClassName staticMethodName args...` or `ClassName.staticMethodName args...`.
- **Named and optional parameters**: Support `--paramName value` and use default values from the manifest when a parameter is omitted; document Option handling (e.g. `--opt value` or omit for None).
- **Richer parser**: Use or integrate a proper Cangjie front-end (if available) for robust handling of multiline and generic signatures.
- **Overload resolution**: Define a deterministic “most specific” ordering (e.g. by parameter type specificity) or at least document manifest order clearly and allow user control (e.g. ordering in a config file).
- **Persistence**: Optional persistence of the object store (e.g. to a file or session id) so refs can be reused across invocations (with clear lifecycle and security considerations).
- **Package scope**: CLI directory design with path-based resolution is implemented. Optional path-based validation (e.g. consistency between file `package` declaration and directory-derived path) can be added later.
- **Multiple packages**: Support generating one CLI that aggregates several packages, or one driver per package with a single entry script.
- **Help**: Per-command help (e.g. `help Student`) showing parameter names and types, and document env vars if/when supported.
- **Config / templates**: Allow users to exclude certain functions or classes, or to customize command names, via a config file or template.

These are not committed roadmap items; they are directions that would need to be scoped and prioritized.
