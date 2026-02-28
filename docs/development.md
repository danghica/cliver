# Development

This document is for contributors: project layout, build, test, and conventions.

## File layout

| Path | Purpose |
|------|--------|
| `cjpm.toml` | Cangjie package config (name `pkgcli`, cjc 1.0.5, darwin_aarch64_cjnative, bin-dependencies to SDK) |
| `cjpm.lock` | Locked dependency versions |
| `src/main.cj` | Entrypoint: CLI/env parsing, call parser and codegen, write `cli_driver.cj` |
| `src/parser.cj` | Package parser: scan `.cj` files, produce `Manifest` |
| `src/codegen.cj` | Driver code generator: `Manifest` → Cangjie source string |
| `sample_cangjie_package/` | Minimal Cangjie package used to test Clive (Student, Lesson, public constructors) |
| `std_sdk/` | Placeholder/dummy std dependency entry if needed |
| `scripts/ingest_cangjie_corpus.py` | Script to ingest CangjieCorpus into ChromaDB for RAG-style docs (optional) |
| `data/` | Data directory (e.g. CangjieCorpus clone, cangjie_chroma index) — see [Cangjie and corpus](cangjie-and-corpus.md) |
| `docs/` | Documentation (this directory) |

Generated output (when running Clive on a target package):

- **`<target_package>/src/cli_driver.cj`** — generated driver; do not edit by hand.

## Build and run (development)

Requires Cangjie 1.0.x toolchain and cjpm; source the Cangjie environment first.

```bash
source /path/to/cangjie/envsetup.sh
cjpm build
cjpm run --run-args="--pkg sample_cangjie_package"
```

To run Clive on another package:

```bash
cjpm run --run-args="--pkg /path/to/other/package"
```

## Tests

Clive’s standard test suite is the **sample_cangjie_package** integration test. Run it after each compilation:

```bash
./scripts/build_and_test.sh
```

This builds Clive, generates the driver for `sample_cangjie_package`, builds the sample package, runs `cjpm test` there (Cangjie unit tests), then runs the shell scripts `test_ref_output.sh`, `test_cli_usage.sh`, and the WebSocket backend tests (`node test_backend.js` from the sample package; see `test_backend.sh`). Backend tests require Node.js, `ws`, and `cjpm` on PATH. To run only the integration test (Clive already built):

```bash
./scripts/test_sample_package.sh
```

Clive itself has no `test/` directory; the sample package contains Cangjie tests (`src/cli_driver_test.cj`), shell tests (`test_ref_output.sh`, `test_cli_usage.sh`), and WebSocket backend tests (`test_backend.js` / `test_backend.sh`). See the root [README](../README.md#testing-run-before-deployment) for details.

## Conventions

- **Cangjie**: Follow the project’s Cangjie style (see root README and CangjieCorpus/tools docs). Use `cjpm build`, `cjpm run`, `cjpm test` for build/run/test.
- **Parser**: Parser uses std.ast; when adding support for new constructs, consider edge cases (multiline, comments, generics) and document limitations in [Limitations and future](limitations-and-future.md).
- **Codegen**: Generated code is intended for the same package (same module). Do not introduce an import of the target package from the driver.
- **Docs**: Keep `docs/` up to date when changing behavior, exit codes, or manifest format. Update the [API reference](api-reference.md) when changing public types or function signatures.

## Dependencies

- **Cangjie SDK**: Provided via `target.darwin_aarch64_cjnative.bin-dependencies` in `cjpm.toml` (path to SDK modules). Adjust path for your environment if needed.
- **Standard library**: Clive uses `std.env`, `std.fs`, `std.io`, `std.collection` (and the generated driver uses `std.env`, `std.io`, `std.collection`, `std.convert`). No extra cjpm dependencies beyond the SDK.

## Optional: CangjieCorpus and ChromaDB

For RAG-style use of Cangjie docs (e.g. in AI tooling), the repo can use a Chroma index of CangjieCorpus. See [Cangjie and corpus](cangjie-and-corpus.md) for cloning the corpus and running `scripts/ingest_cangjie_corpus.py`. This is optional for building and developing Clive itself.
