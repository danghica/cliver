# Testing

This document describes Clive’s test strategy: unit tests (Clive core and sample package), golden/snapshot tests, randomized tests, and integration/system tests. It also explains how to add tests, how they are discovered, and how to run them in CI.

## Phase 0 (policy)

**Verified:** `cjpm test` in the Clive package can run test files that belong to the same package (`pkgcli`). No separate import of `pkgcli` is needed; test files in `src/` with `package pkgcli` are compiled and run by `cjpm test`.

**Policy:** Clive core unit tests are **in-package**. Place test files in `src/` (e.g. `src/dir_test.cj`, `src/codegen_test.cj`). Randomized dir/codegen tests can therefore live in Clive and use `std.unittest` and `std.random` as needed.

---

## What is tested


| Layer             | What                                                                      | Where                                                         | How to run                                                          |
| ----------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------- |
| **Unit (Clive)**  | Codegen output, parser Manifest, dir helpers, main.cj exit codes          | `src/*_test.cj`, `scripts/`                                   | `cjpm test` (in Clive repo); `./scripts/run_unit_tests.sh` if added |
| **Unit (sample)** | runFromArgs, ref output, echo/help/dir, subpackages, error paths (stderr) | `sample_cangjie_package/src/cli_driver_test.cj`               | `cjpm test` (in sample_cangjie_package)                             |
| **Golden**        | Generated driver snippet                                                  | `test/golden/`, `scripts/golden_extract.sh`                   | Diff after generate; run in CI                                      |
| **Randomized**    | Dir/codegen (if Phase 0 allows), CLI/backend fuzz                         | Clive `src/*_test.cj` or `scripts/`                           | `cjpm test` or fuzz script                                          |
| **Integration**   | Full pipeline: generate → build sample → run CLI and backend              | `scripts/build_and_test.sh`, `scripts/test_sample_package.sh` | `./scripts/build_and_test.sh`                                       |


---

## How to add a new test

- **Clive core (Cangjie):** Add a `*_test.cj` file in `src/` with `package pkgcli`. Use `@Test`, `@TestCase`, `@Assert` / `@Expect` / `@Fail` from `std.unittest` and `std.unittest.testmacro`. For error paths, assert exit code and `result.stderr` where applicable.
- **Sample package (Cangjie):** Add test methods to existing test classes in `src/cli_driver_test.cj`, or add a new `@Test` class. Use `runFromArgs` and assert on `result.stdout`, `result.stderr`, `result.exitCode`.
- **Scripts:** Add a script under `scripts/` (e.g. for exit-code or golden checks) and invoke it from `build_and_test.sh` or document it in this file.

**Naming:** Test files in Cangjie are typically named `*_test.cj`. Test classes and methods are arbitrary; use descriptive names (e.g. `normalizePathRoot`, `isKnownPackagePathDemoSub`).

---

## Test discovery

- **Cangjie:** `cjpm test` discovers and runs all test files in the package. Test files are those that define types/functions annotated with `@Test` / `@TestCase`. Output is under `target/release/unittest_bin` and includes per-case pass/fail and timing.
- **Shell / Node:** Scripts and `test_backend.js` are run explicitly by `scripts/build_and_test.sh` and `scripts/test_sample_package.sh`.

---

## Acceptance criteria

- Each layer has at least one test: unit (Clive), unit (sample), golden (once added), randomized (optional), integration.
- CI runs the full suite (e.g. `./scripts/build_and_test.sh`) and is green.
- Before release or major changes, run the full suite locally.

---

## Golden tests

- **Location:** `test/golden/cli_driver_snippet.txt`
- **Extraction:** Defined in `scripts/golden_extract.sh` (e.g. lines 1–80 of generated `cli_driver.cj` plus the first full `func _run...` block).
- **How to update:** Re-run the generator on the target package, run `scripts/golden_extract.sh`, commit the updated snippet.
- **Relationship:** Substring assertion (in codegen/dir tests or a script) is a fast smoke test; golden diff is the regression gate. Both run in CI.

---

## Randomized tests

- **How to run:** `cjpm test` (includes parameterized/random tests). For external fuzz (CLI/backend), run the fuzz script (e.g. from `scripts/`).
- **Reproducibility:** Use `@Configure[randomSeed: <UInt64>]` for parameterized tests; for manual `Random(seed)` loops, use a constant or `TEST_SEED` env. On failure, the framework reports the seed; add it to the test to lock the regression.
- **Regression policy:** For deterministic bugs, add a dedicated `@TestCase` with the exact failing input. For bugs found by random test, add `@Configure[randomSeed: <reported seed>]`; optionally add a `@TestCase` with the minimal failing input.

---

## Expected exit codes (Clive binary)


| Code | Meaning                                                                                    |
| ---- | ------------------------------------------------------------------------------------------ |
| 0    | Success; driver (and optionally backend/index) written.                                    |
| 65   | Bad path, parse failure, or refusal (e.g. current dir, or package name `pkgcli`).          |
| 66   | Write failure (e.g. cannot write `cli_driver.cj`).                                         |
| 67   | Backend write failure (e.g. cannot write `web/cli_ws_server.js`; create `web/` if needed). |


Documented for scripting and CI. Tests should assert these where applicable.

---

## System / integration

- **Backend tests** (`sample_cangjie_package/test_backend.js`): Run with **CLI_BIN** set to the built binary (e.g. `target/release/bin/main`) when `cjpm run` does not pass arguments. Use a dedicated **PORT** (e.g. 18765) to avoid clashes. Timeout per message: 15s. Require **Node 18+** and `ws`. See test file header for usage.
- **Second fixture** (`test/fixtures/single_file_package/`): Minimal single-file package (one class, one constructor). Run Clive on it, build with cjpm, run one command to catch "only works for one package" regressions. Optional in CI.
- **Shell scripts**: Require cjpm on PATH and Cangjie env; fail fast with a clear message if cjpm or the binary is missing.

## CI

- Add a CI workflow (e.g. `.github/workflows/test.yml`) that runs `./scripts/build_and_test.sh` on push/PR.
- Set a timeout (e.g. 15 min).
- Use `SKIP_BACKEND_TESTS=1` if Node/ws are unavailable.
- Pin or document Cangjie/cjc version: see `cjpm.toml` in the repo root (e.g. `cjc-version = "1.0.5"`). Backend tests require **Node 18+** and `ws`.

---

## Coverage (optional)

If the toolchain supports it, measure line/branch coverage for Clive `src/` and the sample package; consider failing CI if coverage drops below a threshold. Document as future work here if not implemented.