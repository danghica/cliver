# Limitations and future work

This document summarizes the current limitations of Clive (v1) and possible future improvements.

## Current limitations (v1)

### Scope of discovery

- **Only top-level public functions** and **public constructors** are exposed. Instance methods (e.g. `lesson.add(student)`) and static methods are **not** exposed in the first version.
- **Generic functions** are not supported; the parser and codegen assume concrete types.
- **One package**: Clive operates on a single Cangjie package at a time. Multi-package projects would require running Clive per package or extending the design.

### Parser

- **Line-based and pattern-based**: The parser scans lines for `package`, `public func`, `public class`, and `public init`. It does not build a full Cangjie AST.
- **Complex signatures**: Multiline function/init declarations, heavy use of generics, or unusual formatting may not be parsed correctly and may require manual adjustment of the source or the parser.
- **Single package name**: The first `package` declaration found is used; multiple or conditional package declarations are not handled specially.

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

---

## Possible future improvements

- **Instance methods**: Expose public instance methods with a syntax such as `ref:<id> methodName args...`, resolving the ref from the object store and then calling the method.
- **Static methods**: Expose public static methods, e.g. `ClassName staticMethodName args...` or `ClassName.staticMethodName args...`.
- **Named and optional parameters**: Support `--paramName value` and use default values from the manifest when a parameter is omitted; document Option handling (e.g. `--opt value` or omit for None).
- **Richer parser**: Use or integrate a proper Cangjie front-end (if available) for robust handling of multiline and generic signatures.
- **Overload resolution**: Define a deterministic “most specific” ordering (e.g. by parameter type specificity) or at least document manifest order clearly and allow user control (e.g. ordering in a config file).
- **Persistence**: Optional persistence of the object store (e.g. to a file or session id) so refs can be reused across invocations (with clear lifecycle and security considerations).
- **Multiple packages**: Support generating one CLI that aggregates several packages, or one driver per package with a single entry script.
- **Help**: Per-command help (e.g. `help Student`) showing parameter names and types, and document env vars if/when supported.
- **Config / templates**: Allow users to exclude certain functions or classes, or to customize command names, via a config file or template.

These are not committed roadmap items; they are directions that would need to be scoped and prioritized.
