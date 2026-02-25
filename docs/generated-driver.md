# Generated driver

This document describes how the generated **`cli_driver.cj`** works: structure, object store, command dispatch, overload resolution, and argument conversion.

## Purpose

The driver provides a single `main()` that:

1. Reads command-line arguments.
2. Treats the first token as the **command name** (function name or class name).
3. For constructors, requires the second token to be `new` and uses the rest as constructor arguments.
4. Converts positional arguments to the correct types and calls the corresponding function or constructor.
5. For reference-returning calls, stores the result and prints `ref:<id>`; for other returns, prints the value or nothing (Unit).

No reflection: every call is generated explicitly from the manifest.

## File location and module

- The file is written to **`<package_root>/src/cli_driver.cj`**.
- It is part of the **same** Cangjie package (same `package` declaration as the rest of the package). It does not import the target package; it lives inside it.

## Structure of generated code

1. **Header comment**: “Generated CLI driver for package … Do not edit by hand.”
2. **Imports**: `std.env.*`, `std.io.*`, `std.collection.*`, `std.convert.*`
3. **Object store**:
   - `_nextId: Int64` — monotonic id for stored references
   - `_store: HashMap<Int64, Any>` — map from id to instance
   - `_storeRef(obj: Any): Int64` — store object, increment id, return id
   - `_getRef(id: Int64): Option<Any>` — lookup by id
   - `_parseRefId(s: String): Option<Int64>` — parse `ref:<id>` and return id
4. **main()**:
   - Get command line via `getCommandLine()`; require at least one token.
   - First token = `command`.
   - If `command == "help"`, call `_printHelp()` and return 0.
   - For each command key (function name or class name), `if (command == "Key") return _runKey(argsList)`.
   - Else: print “Unknown command” and return 64.
5. **`_printHelp()`**: Prints “Commands:” and for each key either `Key new [args...] (constructor)` or `Key [args...]`.
6. **Per-command runner** `_runKey(args: ArrayList<String>): Int64`:
   - For constructors: require `args.get(0) == "new"` and use `args[1..]` as actual args.
   - Try each overload in manifest order: convert args; if all conversions succeed, call and handle return, then return 0.
   - If no overload matches: print “No matching overload for Key” and return 64.

## Object store

- **Storing**: When a function or constructor returns a type that is considered a reference type (e.g. a class), the driver calls `_storeRef(_result)`, then `println("ref:" + _id.toString())`.
- **Using refs**: For a parameter whose type is a class, the driver converts the CLI string with `_parseRefId(s)`. If it matches `ref:<id>`, it looks up `_getRef(id)` and casts to the parameter type; otherwise conversion fails (that overload is skipped).
- **Lifetime**: The store is in-memory only; it is lost when the process exits. No persistence.

## Overload resolution

- Commands are grouped by **CLI key**: function name for functions, class name for constructors.
- For each key, overloads are tried in **manifest order** (order in which they appeared in the parsed source).
- For each overload, the driver checks that the number of positional args is at least the number of parameters, then tries to convert each arg to the parameter type.
- **First successful conversion + call** wins. There is no “most specific” ordering; if two overloads both accept the same args (e.g. `f(Int64)` and `f(Float64)` with "42"), the first in the manifest is used.

## Argument conversion

For each parameter type, the generated code produces an `Option<T>` from the CLI string (or from `ref:<id>` for class types):

| Type | Conversion |
|------|------------|
| `Int64` | `Int64.tryParse(arg)` |
| `Float64` | `Float64.tryParse(arg)` |
| `Bool` | `Bool.tryParse(arg)` |
| `String` | `Option.Some(arg)` |
| `Option<Int64>` (etc.) | Optional: empty string or missing → `None`; otherwise tryParse inner type and wrap in `Some` |
| Class type | `_parseRefId(arg)` → if `Some(id)`, `_getRef(id)` and cast to class; else `None` |

If any conversion yields `None`, that overload is skipped and the next one is tried. If all conversions succeed, the call is emitted and the return is handled (store ref + print, or print value, or return 0 for Unit).

## Exit codes (generated CLI)

- **0** — Command executed successfully.
- **64** — Usage / unknown command / no matching overload.

(Other exit codes are not used by the generated driver.)

## Dependencies

The generated driver uses:

- `std.env.*` (e.g. `getCommandLine()`)
- `std.io.*` (e.g. `println`, `eprintln`)
- `std.collection.*` (e.g. `ArrayList`, `HashMap`)
- `std.convert.*` (e.g. `Int64.tryParse`, `Float64.tryParse`, `Bool.tryParse`)

The target package’s `cjpm.toml` should list these std modules if not already present, so the driver compiles.
