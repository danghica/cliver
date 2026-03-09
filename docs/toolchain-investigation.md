# Toolchain investigation: "failed to parse package import information"

This document summarizes the investigation into why `cjpm build` fails with:

```text
Error: failed to parse package import information, please execute 'cjc -p <path>/src --scan-dependency' to check
<JSON output>
Error: cjpm build failed
```

**cjpm source (for reference):** [Cangjie/cangjie_tools – cjpm](https://gitcode.com/Cangjie/cangjie_tools/tree/main/cjpm)

## 1. What we know

### 1.1 cjc output is valid JSON

- **Command:** `cjc -p /Users/danghica/cliver/src --scan-dependency`
- **Exit code:** 0 (success)
- **stderr:** Empty (all output is on stdout)
- **stdout:** Single line of JSON; parses successfully with `json.loads()`.

### 1.2 JSON structure produced by cjc

| Key | Type | Example |
|-----|------|---------|
| `package` | string | `"pkgcli"` |
| `isMacro` | bool | `false` |
| `accessLevel` | string | `"public"` |
| `dependencies` | array | `[{"package":"std.ast","isStd":true,"imports":[...]}, ...]` |
| `std-dependencies` | **array** | `[{"std.ast":["std.collection","std.core","std.sort"]}, {"std.binary":["std.core"]}, ...]` |
| `features` | array | `[]` |
| `product` | bool | `true` |

Important detail: **`std-dependencies` is an array of single-key objects**, e.g.:

```json
[
  {"std.ast": ["std.collection", "std.core", "std.sort"]},
  {"std.binary": ["std.core"]},
  ...
]
```

### 1.3 Where the error comes from

- The message **"failed to parse package import information"** appears in the **cjpm** binary (from `strings` on `cangjie/tools/bin/cjpm`).
- Related strings in cjpm: `"failed to obtain package import information"`, `"ScanDependencyError"`, `"scanDependency"`, `"collectJsonInformation"`, `"getPackageInfo"`, `"deserialize"`.
- cjpm is written in Cangjie. Its source lives in the **cangjie_tools** repo: [Cangjie/cangjie_tools – cjpm](https://gitcode.com/Cangjie/cangjie_tools/tree/main/cjpm) (e.g. `cjpm/src/implement/dep_model.cj`, `cjpm/src/config/cjc_dependency.cj`, `cjpm/src/config/history.cj`).

### 1.4 Environment

- **envsetup.sh** correctly sets `PATH` (both `cangjie/bin` and `cangjie/tools/bin`) and `DYLD_LIBRARY_PATH`.
- **cjpm.toml** `path-option` points to the sandbox modules path:  
  `/Users/danghica/sandbox/cjceh/cjc-eh/cangjie/modules/darwin_aarch64_cjnative`
- **Compiler version:** `cjc -v` reports `Cangjie Compiler: 0.0.1 (cjnative)`; **cjpm.toml** has `cjc-version = "1.0.5"` (version mismatch is possible but not proven as the cause).

## 2. cjpm source-code flow (from cangjie_tools/cjpm)

1. **Entry:** `dep_model.cj` → `scanDependency(packagePath: Path, ...)` (around line 1556). Builds arguments `["-p", "${packagePath}", "--scan-dependency", ...]`, runs `execWithOutput(COMPILE_TOOL, arguments)`, then:
2. **Parse:** `Ok(RequiresPackages.deserialize(DataModel.fromJson(JsonValue.fromStr(out))))` (line 1574). So: stdout → `JsonValue.fromStr(out)` → `DataModel.fromJson(...)` → `RequiresPackages.deserialize(...)`.
3. **Errors:** Any exception is caught and turned into `FailedToParse(cmd, out)` (lines 1575–1583), which prints the "failed to parse package import information" message and the raw `out`.
4. **RequiresPackages.deserialize** (`cjc_dependency.cj`, ~97–128): `result.stdDependencies = StdDeps.deserialize((dms.get("std-dependencies") as DataModelSeq) ?? DataModelSeq())` (line 127).
5. **StdDeps type** (`history.cj`, line 18): `public type StdDeps = ArrayList<HashMap<String, Array<String>>>`. So **std-dependencies** is expected to be a sequence (array); each element is a map (one key → array of strings). That matches what cjc emits (array of single-key objects).

So on paper the **std-dependencies** shape matches cjpm's `StdDeps`. The failure can still be: **path** (cjpm may pass package root vs `src`), **another field** (e.g. `dependencies`, `features`), or **exception not shown** (generic catch only prints raw stdout).

## 3. Likely cause (refined)

The failure is **inside cjpm** during `JsonValue.fromStr(out)` / `DataModel.fromJson(...)` or `RequiresPackages.deserialize(...)`. The most plausible causes are:

1. **Path difference:** cjpm invokes cjc with a different `-p` path (e.g. project root vs `src`), leading to different or empty output.
2. **Schema/parsing mismatch:** Some field (possibly not `std-dependencies`) or the way JSON is converted to DataModel does not match what `RequiresPackages` / `FullName` / `ImportInfo` expect.
3. **Library behavior:** `stdx.encoding.json` or `stdx.serialization` may treat the JSON differently and cause deserialize to throw.


## 4. How to clarify further

1. **Run cjc with the same path cjpm uses**  
   Add debug in cjpm (or run the same `execWithOutput` locally) to log the exact `-p` path and capture stdout/stderr. Run `cjc -p <that path> --scan-dependency` and compare the JSON with the format in section 1.2. If the path is the package root (e.g. `.../cliver`) instead of `.../cliver/src`, try running cjc with the root and see if the output or behavior changes.

2. **Surface the real exception**  
   In `dep_model.cj` around 1582, change `catch (_: Exception)` to `catch (e: Exception)` and log `e.toString()` (or the exception type/message) so the actual parse/deserialize error is visible.

3. **Check version compatibility**  
   Confirm which cjc version this cjpm is designed to work with. Try a cjc/cjpm pair from the same release or from known-compatible versions.

4. **Inspect JSON → DataModel**  
   If you have a dump of the exact stdout from cjpm’s run, pass it through the same `JsonValue.fromStr` / `DataModel.fromJson` pipeline (e.g. in a small Cangjie or script) and see which step throws (fromStr, fromJson, or a specific field in deserialize).

## 5. Reproducing the scan-dependency output

From the Clive repo root, with envsetup sourced:

```bash
source /Users/danghica/sandbox/cjceh/cjc-eh/cangjie/envsetup.sh
cjc -p /Users/danghica/cliver/src --scan-dependency > /tmp/cliver-scan.json 2>/dev/null
python3 -c "import json; d=json.load(open('/tmp/cliver-scan.json')); print('Keys:', list(d.keys())); print('std-dependencies type:', type(d['std-dependencies'])); print('First std-dep:', d['std-dependencies'][0])"
```

This saves the exact JSON cjpm receives and prints the structure of `std-dependencies` for comparison with cjpm’s expected format.
