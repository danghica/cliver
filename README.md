# Clive — Cangjie package-to-CLI utility

This utility parses a Cangjie package’s source, discovers public functions and public constructors, and generates a CLI driver that exposes them as commands. No runtime reflection: the driver calls the package API directly.

## Features

- **Source as input**: Scans `.cj` files in the package (or in `src/` under the package root) for `package`, `public func`, `public class`, and `public init`.
- **One CLI command per** top-level public function; constructors are invoked as **`ClassName new arg1 arg2 ...`**.
- **Overloads**: First matching overload in manifest order (argument conversion tried in order).
- **Arguments**: Positional; class-typed parameters accept `ref:<id>` and look up in the object store.
- **Object store**: In-memory map keyed by a monotonic id; only class instances are stored; the driver prints `ref:<id>` for later use.
- **Env**: Package path can be set via `PKG_SRC` or `--pkg <path>`.

## Build and run (requires Cangjie / cjpm)

Use the Cangjie 1.0.x (cjnative) toolchain. **Source the Cangjie environment first** so the linker finds the SDK (e.g. `source /path/to/cangjie/envsetup.sh`), then:

```bash
source /path/to/cangjie/envsetup.sh   # or add to your shell profile
cjpm build
cjpm run -- --pkg /path/to/your/package
# or
PKG_SRC=/path/to/your/package cjpm run
```

The project is configured for `cjc-version = "1.0.5"` and `target.darwin_aarch64_cjnative` (bin-dependencies point to the SDK’s precompiled std).

The tool writes **`src/cli_driver.cj`** into the target package directory (if you pass the package root, it writes to `<root>/src/cli_driver.cj`).

## Using the generated CLI

1. Generate the driver (as above).
2. In the **target** package, ensure there is only one `main()`: either remove/rename the existing `main()` in that package (e.g. rename to `demo()`) or use the generated driver as the sole entry point. Two `main()` in the same module will cause a build error.
3. From the target package root:
   ```bash
   cjpm build
   cjpm run -- help
   cjpm run -- Student new Alice 1001
   cjpm run -- Lesson new
   cjpm run -- Lesson new   # ref:2
   # use ref:1, ref:2 in later commands if the driver exposes instance methods (future)
   ```

The target package may need `std.env`, `std.io`, `std.collection`, and `std.convert` in its `cjpm.toml` dependencies for the generated driver to compile.

## Exit codes

- `0` — success  
- `64` — usage / unknown command  
- `65` — invalid package path or parse failure  
- `66` — failed to write `cli_driver.cj`

## Sample package

`sample_cangjie_package/` contains a minimal package (`lesson_demo`) with `Student` and `Lesson` and public constructors. To try the tool (with cjpm available):

```bash
cjpm build
cjpm run -- --pkg sample_cangjie_package
# Then in sample_cangjie_package: comment out or rename main() in src/main.cj, then:
cd sample_cangjie_package && cjpm build && cjpm run -- help
cd sample_cangjie_package && cjpm run -- Student new Bob 2000
cd sample_cangjie_package && cjpm run -- Lesson new
```

## File layout

- `src/main.cj` — entrypoint: parse args/env, call parser, codegen, write driver.
- `src/parser.cj` — reads `.cj` files, extracts package name and command manifest.
- `src/codegen.cj` — from manifest, emits `cli_driver.cj` (object store, arg conversion, dispatch).
- Generated **`cli_driver.cj`** — lives in the target package’s `src/`; user runs `cjpm build` and `cjpm run` from the target root.

## Limitations (v1)

- Only top-level public functions and public constructors; no instance or static methods.
- Parser is line-based; complex signatures (e.g. multiline, heavy generics) may need manual adjustment.
- Generic functions are not supported in the first version.
- Object store is in-memory only; no persistence across runs.
