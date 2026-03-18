# Upload/Download WebSocket Protocol — Implementation Notes

**Date:** 2026-03-17
**Status:** Verified ✓

## Files Changed

| File | Change |
|------|--------|
| `src/main.cj` | Added `handleUpload` + `handleDownload` JS functions to `_backendScriptTemplate()`; added `msg.type` dispatch in message handler |
| `sample_cangjie_package/test_backend.js` | Added `uploadedPath` state variable; added 3 new test cases; updated test runner to support `sendMsg`/`getMsg`/raw-JSON `j` in `check` |
| `test/fixtures/minimal_package/src/minimal.cj` | Created missing unit test fixture (was causing `parsePackageMinimalFixture` to fail) |

## Key Implementation Details

### `_backendScriptTemplate()` changes (src/main.cj)

Two JS functions injected after `unescapeLine`, before `const server`:

- **`handleUpload(ws, msg)`**: validates `filename`+`data` fields, sanitizes filename with `path.basename` + regex, generates `<timestamp>_<random>_<sanitized>` prefix, writes `Buffer.from(msg.data, 'base64')` to `/tmp/cliver/uploads/`.
- **`handleDownload(ws, msg)`**: resolves path, rejects anything outside `/tmp/cliver/`, reads file, returns `data.toString('base64')`.

Message dispatch added inside `ws.on('message', ...)` before the existing `msg.line` logic:
```js
if (msg.type === 'upload') { handleUpload(ws, msg); return; }
if (msg.type === 'download') { handleDownload(ws, msg); return; }
```

### test_backend.js changes

- `uploadedPath` variable captures path from upload test for use in download test.
- Test runner extended: `t.sendMsg` (static message object) and `t.getMsg()` (lazy getter, for state-dependent messages) replace the hardcoded `{ line: t.line }`.
- `t.check` now receives `(stdout, stderr, j)` where `j` is the raw parsed response JSON.

### New tests

1. `upload CSV file returns path under /tmp/cliver/uploads/` — sends base64-encoded CSV, asserts `upload_result` with correct prefix.
2. `download uploaded file round-trip` — downloads previously uploaded path, decodes base64, asserts byte-for-byte match.
3. `download path traversal blocked` — sends `/etc/passwd` path, asserts `download_error`.

## Regeneration Required

After building Clive, regenerate the sample package backend:
```bash
cjpm run -- --pkg sample_cangjie_package
```
This overwrites `sample_cangjie_package/web/cli_ws_server.js` with the new template.

## Bug Fix During Independent Testing

**Bug:** `handleUpload` used `!msg.filename` and `!msg.data` as falsy guards. Empty string `''` is falsy → empty filename or empty data was incorrectly rejected with `upload_error`.

**Fix:** Changed guard to `typeof msg.filename !== 'string' || typeof msg.data !== 'string'`. This correctly allows empty strings (boundary cases per spec) while still rejecting `undefined`/`null`/non-string values.

**Spec alignment:** The spec explicitly documents that `filename: ""` → `path.basename("") === "."` returns `upload_result`, and `data: ""` → 0-byte file returns `upload_result`. Both are valid boundary inputs, not error conditions.

## Independent Testing (cliver-tests/)

**Repo:** `/home/gloria/tianyue/cliver-tests/`

**Test run result:** 36/36 passed after bug fix.

**Gap report decisions (from Agent B):**
- P1 added: `[upload][security] filename with special characters is sanitized by regex to underscores` → added, passes
- P2 added: `[upload][invariant] two uploads of the same filename produce distinct paths` → added, passes
- P1 accepted: server log side-effect test — logging call exists in code but no log file assertion added (low risk)
- P1 accepted: file write failure (disk full) — environment doesn't support disk-full simulation
- P1 accepted: download read failure (permission denied) — same environment limitation
- P2 accepted: explicit `path.resolve()` structural test — covered implicitly by `..` tests 25-26
- P3 accepted: all P3 gaps as documented known limitations

**Ambiguous items:** Exact error message text assertions are verified (tests use `assertEqual` on message field). Tests 22/24 overlap intentionally — distinct but redundant inputs; left as-is.

## Testing

```bash
# Rebuild Clive, regenerate sample package, run independent tests
source /home/gloria/cangjie/envsetup.sh
cjpm build
PKG_SRC=sample_cangjie_package ./target/release/bin/main
cd /home/gloria/tianyue/cliver-tests && ./run_tests.sh
```
