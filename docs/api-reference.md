# API reference

This document describes the public types and functions exposed by Clive’s parser and code generator for use by the main entrypoint (and for understanding the manifest format).

## Parser (`src/parser.cj`)

### Types

#### `Manifest`

Represents the result of parsing a Cangjie package.

| Field | Type | Description |
|-------|------|-------------|
| `packageQualifiedName` | `String` | Package name from the first `package` declaration found |
| `commands` | `ArrayList<CommandInfo>` | All discovered top-level public functions and public constructors |

**Constructor**: `Manifest(packageQualifiedName: String, commands: ArrayList<CommandInfo>)`

---

#### `CommandInfo`

Describes one CLI-invokable command (either a top-level function or a constructor).

| Field | Type | Description |
|-------|------|-------------|
| `name` | `String` | Function name, or `"init"` for constructors |
| `isConstructor` | `Bool` | True if this is a constructor |
| `className` | `String` | If constructor, the class name; otherwise `""` |
| `params` | `ArrayList<ParamInfo>` | Parameter list (name and type) |
| `returnType` | `String` | Simple type name, e.g. `"Unit"`, `"Int64"`, or class name |
| `returnIsRef` | `Bool` | True if the return type is treated as a reference type (result stored in object store, `ref:<id>` printed) |

**Constructor**: `CommandInfo(name, isConstructor, className, params, returnType, returnIsRef)`

---

#### `ParamInfo`

Describes a single parameter.

| Field | Type | Description |
|-------|------|-------------|
| `paramName` | `String` | Parameter name |
| `paramType` | `String` | Type string as parsed (e.g. `"Int64"`, `"String"`, `"Option<Int64>"`, or a class name) |

**Constructor**: `ParamInfo(paramName: String, paramType: String)`

---

### Functions

#### `parsePackage(sourcePath: String): Option<Manifest>`

Parses the Cangjie package at the given path.

- **`sourcePath`**: Directory path to the package root (or to a directory containing `.cj` files). If `sourcePath` has a `src/` subdirectory, that is scanned; otherwise `sourcePath` is scanned.
- **Returns**: `Option<Manifest>.Some(manifest)` on success, `Option<Manifest>.None` on invalid path or parse failure (e.g. exception when reading directory/files).

The parser scans all `.cj` files in the resolved directory, collects the first `package` name, and for each line looks for `public func`, `public class`, and `public init` to build the command list.

---

## Code generator (`src/codegen.cj`)

### Functions

#### `generateDriver(manifest: Manifest): String`

Generates the full Cangjie source code for the CLI driver.

- **`manifest`**: The result of `parsePackage()`.
- **Returns**: A string containing the complete source of `cli_driver.cj` (imports, object store helpers, `main()`, `_printHelp()`, and for each command key a `_runKey(args)` that tries overloads and performs argument conversion and dispatch).

The generated code is intended to be placed in the **target package’s `src/`** and compiled in the same module (no separate import of the package). It uses `std.env`, `std.io`, `std.collection`, and `std.convert`.

---

## Internal helpers (not public API)

- **Parser**: `trimSpace`, `isRefType`, `parseFileContent`, `readFileAsString`, `_resolveSourceDir` are used internally by `parsePackage`.
- **Codegen**: `_appendSafeName`, `_emitRunCommand`, `_emitOverload`, `_emitConvertAndCall`, `_emitConvert`, `_appendConvertedType`, `_emitCall` are used internally by `generateDriver`.

---

## Reference-type heuristic (parser)

The parser treats a type as a **reference type** (`returnIsRef` or ref-capable parameter) when:

- It is **not** one of: `Unit`, `Int64`, `Int32`, `Float64`, `Float32`, `Bool`, `String`
- It does **not** start with `Option<` (the optional value itself is not stored as a ref; the inner type may still be used for parameters)

All other type strings (e.g. class names like `Student`, `Lesson`) are treated as reference types for storage and `ref:<id>` argument parsing in the generated driver.
