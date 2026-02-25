# User guide

This guide explains how to build and run Clive, how to point it at a package, and how to use the generated CLI.

## Prerequisites

- **Cangjie 1.0.x (cjnative)** toolchain and **cjpm**
- **Environment**: Source the Cangjie environment so the linker finds the SDK, e.g.:
  ```bash
  source /path/to/cangjie/envsetup.sh
  ```
  (Or add this to your shell profile.)

The project is configured for `cjc-version = "1.0.5"` and target `darwin_aarch64_cjnative` in `cjpm.toml`; bin-dependencies point to the SDK’s precompiled std.

## Building Clive

From the **Clive project root** (where `cjpm.toml` lives):

```bash
source /path/to/cangjie/envsetup.sh
cjpm build
```

## Specifying the target package

Clive needs the path to the **Cangjie package** for which to generate the CLI driver. You can pass it in two ways:

1. **Command line**: `--pkg <path>`
   ```bash
   cjpm run --run-args="--pkg /absolute/or/relative/path/to/package"
   ```
2. **Environment variable**: `PKG_SRC`
   ```bash
   PKG_SRC=/path/to/package cjpm run
   ```

If neither is set, the code falls back to `"."` (current directory). The path should be the **package root** (directory that contains `src/` with `.cj` files, or the directory that directly contains `.cj` files).

## Generating the driver

After building Clive, run it with the target package path:

```bash
cjpm run --run-args="--pkg sample_cangjie_package"
# or
PKG_SRC=sample_cangjie_package cjpm run
```

On success you should see:

```
Wrote <pkgPath>/src/cli_driver.cj
```

The file **`src/cli_driver.cj`** is written into the **target** package’s `src/` directory. Do not edit it by hand; it is overwritten each time you run Clive.

## Using the generated CLI

1. **Single `main()`**: The target package must have exactly one `main()`. If it already has a `main()` (e.g. for a demo), rename or remove it (e.g. rename to `demo()`) so the generated driver’s `main()` is the only entry point. Two `main()` in the same module will cause a build error.

2. **Build the target package**: From the **target** package root:
   ```bash
   cd /path/to/target/package
   cjpm build
   ```

3. **Run the CLI**:
   ```bash
   cjpm run --run-args="help"
   cjpm run --run-args="Student new Alice 1001"
   cjpm run --run-args="Lesson new"
   ```

   Constructors are invoked as **`ClassName new arg1 arg2 ...`**. If the return type is a class, the driver prints `ref:<id>`; you can use that id in later commands for parameters that expect a class reference, e.g. `ref:1`.

4. **Dependencies**: The target package may need `std.env`, `std.io`, `std.collection`, and `std.convert` in its `cjpm.toml` for the generated driver to compile. Add them if you get missing-import errors.

## Sample package

The repo includes **`sample_cangjie_package/`**, a minimal Cangjie package with `Student` and `Lesson` and public constructors. To try Clive end-to-end:

```bash
# From Clive root
cjpm build
cjpm run --run-args="--pkg sample_cangjie_package"
```

Then in the sample package, comment out or rename `main()` in `src/main.cj`, and from `sample_cangjie_package/`:

```bash
cjpm build
cjpm run --run-args="help"
cjpm run --run-args="Student new Bob 2000"
cjpm run --run-args="Lesson new"
```

## Exit codes

When you run **Clive** (the generator):

| Code | Meaning |
|------|--------|
| 0 | Driver written successfully |
| 65 | Invalid package path or parse failure |
| 66 | Failed to write `cli_driver.cj` |

When you run the **generated CLI**:

| Code | Meaning |
|------|--------|
| 0 | Command executed successfully |
| 64 | Usage error or unknown command |

## Troubleshooting

- **“Invalid package path or failed to parse”**: Ensure the path points to a directory that contains `.cj` files (or a `src/` subdirectory with `.cj` files) and that the parser can find a `package` declaration and at least one `public func` or `public init`.
- **“Failed to write cli_driver.cj”**: Check permissions and that `src/` exists under the target path (Clive does not create `src/`).
- **Duplicate `main()`**: Remove or rename the existing `main()` in the target package so only the generated driver defines `main()`.
- **Linker / SDK errors**: Run `cjpm build` (and `cjpm run`) from a shell where you have run `source /path/to/cangjie/envsetup.sh` so the linker gets the correct SDK paths.

For more detail on what the generated driver does (object store, overloads, argument conversion), see [Generated driver](generated-driver.md).
