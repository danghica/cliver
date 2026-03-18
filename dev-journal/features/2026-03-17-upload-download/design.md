---
feature: upload-download
spec_version: 1.2
date: 2026-03-17
status: final
---

# Upload/Download WebSocket Protocol — Design

## Problem

Cliver-generated CLI drivers expose Cangjie functions via WebSocket. All parameters are strings, so callers (e.g. AI agent frameworks) cannot pass large file content directly on the command line. There was no mechanism to transfer binary or text file payloads.

## Decision

- Changes confined to `_backendScriptTemplate()` in `src/main.cj` — no Cangjie parser/codegen/driver changes.
- Cangjie function signatures stay unchanged (still accept `String` file paths).
- The protocol is extended with new message types; existing `{ line: "..." }` messages are unaffected (backward compatible).
- Files stored temporarily in `/tmp/cliver/uploads/` with `<timestamp>_<random>` prefixed names.
- Download restricted to `/tmp/cliver/` to prevent path traversal.

## Scope

**In scope:**
- WebSocket protocol extension: new `upload` / `download` message types
- Server-side temp file management (`/tmp/cliver/uploads/`)
- Base64 encoding/decoding at the protocol layer
- Security: path traversal prevention, filename sanitization

**Out of scope:**
- Web UI file upload/download controls (`index.html`) — Phase 2
- Any Cangjie-side changes (parser / codegen / driver)
- File size limits or MIME type validation
- Persistent storage (temp-file semantics only)
- Per-connection cleanup on close — Phase 2

## Protocol

```
// Upload (Agent → Server)
{ type: "upload", filename: "data.csv", data: "<base64 encoded content>" }

// Upload response
{ type: "upload_result", path: "/tmp/cliver/uploads/<timestamp>_<random>_data.csv" }
{ type: "upload_error",  message: "..." }

// Download (Agent → Server)
// path may point to any file under /tmp/cliver/ (uploads or any other subdirectory)
{ type: "download", path: "/tmp/cliver/uploads/<timestamp>_<random>_result.json" }

// Download response
{ type: "download_result", filename: "result.json", data: "<base64>" }
{ type: "download_error",  message: "File not found or access denied" }

// Existing command (unchanged)
{ line: "processCSV /tmp/cliver/uploads/<timestamp>_<random>_data.csv" }
```

## Alternatives Considered

- Stdin streaming: would require changes to Cangjie driver and process spawn logic.
- Separate HTTP upload endpoint: cleaner but adds surface area; WebSocket-only keeps it simple.
- Persist files across connections: out of scope; temp-file semantics sufficient for agent use cases.

---

## Testable Behaviors

### upload

**Input fields:**

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| type | string | yes | equals `"upload"` |
| filename | string | yes | any string, including empty string `""` (empty is a valid boundary case, not an error) |
| data | string | yes | any string (base64-encoded content; empty string `""` is allowed and produces a 0-byte file) |

**Success output:**

| Field | Type | Value constraints |
|-------|------|------------------|
| type | string | equals `"upload_result"` |
| path | string | starts with `"/tmp/cliver/uploads/"`, format: `<timestamp>_<random>_<sanitized_filename>` |

**Side effects:**
- Directory `/tmp/cliver/uploads/` is created if it does not exist
- File is written at `path` with content `Buffer.from(data, 'base64')`
- Operation is passed to `logEntry({ type: 'upload', path: <path> })` (informational; not verifiable in standard test environment — not a testable invariant)

**Invariants:**
- `fs.existsSync(path) === true` after a successful upload_result response
- `fs.readFileSync(path)` bytes equal `Buffer.from(data, 'base64')`

**Error conditions:**

| Condition | Response |
|-----------|----------|
| `filename` field missing | `{ type: "upload_error", message: "Invalid upload request: filename and data are required" }` |
| `filename` is not a string | `{ type: "upload_error", message: "Invalid upload request: filename and data are required" }` |
| `data` field missing | `{ type: "upload_error", message: "Invalid upload request: filename and data are required" }` |
| `data` is not a string | `{ type: "upload_error", message: "Invalid upload request: filename and data are required" }` |
| file write fails (e.g. disk full) | `{ type: "upload_error", message: <err.message> }` (Node.js error object's `.message` property, e.g. `"ENOSPC: no space left on device"`) |

**Input boundary cases:**

| Input | Expected behavior |
|-------|------------------|
| `filename` contains path separators (e.g. `"../../evil.sh"`) | `path.basename()` strips directory components; sanitized name written under `/tmp/cliver/uploads/` only |
| `filename` is empty string `""` | `path.basename("")` returns `""` (empty string, not `"."`). After regex sanitization, sanitized name is `""`. Full path is `/tmp/cliver/uploads/<timestamp>_<random>_` (trailing underscore only). File written successfully, returns `upload_result`. |
| `data` is empty string `""` | 0-byte file written, returns `upload_result` |
| `data` contains invalid base64 characters | Node.js `Buffer.from(s, 'base64')` silently ignores non-base64 characters and decodes remaining valid groups; returns `upload_result` (no error). Test can assert file exists and is non-empty for non-trivial inputs; exact byte content is not contractually specified. |

---

### download

**Input fields:**

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| type | string | yes | equals `"download"` |
| path | string | yes | non-empty string |

**Success output:**

| Field | Type | Value constraints |
|-------|------|------------------|
| type | string | equals `"download_result"` |
| filename | string | equals `path.basename(path)` of the requested path |
| data | string | base64 encoding of the file's bytes |

**Side effects:**
- None (read-only operation)

**Invariants:**
- `Buffer.from(data, 'base64')` bytes equal the actual file content at `path`
- `filename` field equals `path.basename(requestedPath)` (the basename of the path sent in the request)

**Error conditions:**

| Condition | Response |
|-----------|----------|
| `path` field missing | `{ type: "download_error", message: "Invalid download request: path is required" }` |
| `path` is not a string | `{ type: "download_error", message: "Invalid download request: path is required" }` |
| resolved path does not start with `"/tmp/cliver/"` (checked via `path.resolve()` + `startsWith`; covers `..` components, relative paths, and similar-prefix paths like `/tmp/cliver_evil/`) | `{ type: "download_error", message: "Access denied: path must be under /tmp/cliver/" }` |
| `path` resolves to a directory under `/tmp/cliver/` (e.g. `"/tmp/cliver/uploads/"`) | `{ type: "download_error", message: <err.message> }` — `fs.readFileSync` on a directory throws `EISDIR`. Note: `/tmp/cliver/` itself resolves to `/tmp/cliver` which fails the security check first (Access denied), not EISDIR. |
| file does not exist | `{ type: "download_error", message: <err.message> }` (Node.js error `.message`, e.g. `"ENOENT: no such file or directory, open '/tmp/cliver/x.txt'"`) |
| file read fails (e.g. permission denied) | `{ type: "download_error", message: <err.message> }` (Node.js error `.message`) |

**Input boundary cases:**

| Input | Expected behavior |
|-------|------------------|
| `path` = `"/etc/passwd"` | Absolute path outside `/tmp/cliver/` → `download_error` (Access denied) |
| `path` = `"../../etc/passwd"` (relative) | `path.resolve` from server cwd; result won't start with `/tmp/cliver/` → `download_error` |
| `path` = `"/tmp/cliver/../etc/passwd"` | `path.resolve` collapses `..` → `/tmp/etc/passwd` (not `/etc/passwd`); `/tmp/etc/passwd` doesn't start with `/tmp/cliver/` → `download_error` |
| `path` = `"/tmp/cliver_evil/file"` (similar prefix, no trailing slash match) | Does not start with `"/tmp/cliver/"` → `download_error` |
| `path` = `"/tmp/cliver/nonexistent.txt"` | File not found → `download_error` with ENOENT message |
| `path` points to a valid uploaded file | Returns `download_result` with correct base64 content |

---

## Security Constraints

- Upload: filename sanitized via `path.basename()` (strips directory components) then regex `[^a-zA-Z0-9._-]` → `_`. Prefixed with `Date.now()_<random>` to prevent collisions.
- Download: `path.resolve()` canonicalizes the path (eliminates `..`), then `startsWith('/tmp/cliver/')` check.
- Symlink attacks: not protected (would require local write access to `/tmp/cliver/`; outside current threat model).

---

## Known Limitations

- No file size limit (not in scope for this version)
- Invalid base64 in `data` is silently written as partial content (Node.js behavior)
- Files are not cleaned up when the WebSocket connection closes (Phase 2)
- No MIME type validation
- Symlink attacks are out of threat model (requires local write access)
