# Sample Cangjie Package (lesson_demo)

Sample Cangjie package for testing the package-to-cli utility.
Contains a **Student** class and a **Lesson** class that manages a collection of students.

## Contents

- **Student**: Data fields `studentName` (String) and `studentId` (Int64). Methods: `getName()`, `setName(name)`, `getId()`, `setId(id)`.
- **Lesson**: Holds an `ArrayList<Student>`. Methods:
  - `add(student: Student)` — add a student
  - `remove(student: Student): Bool` — remove by object reference (returns true if found and removed)
  - `printStudents()` — print each student's name and id

## Build and run

Requires the Cangjie toolchain (cjc, cjpm). From this directory, with Cangjie env loaded (e.g. `source /path/to/cangjie/envsetup.sh`):

```bash
cjpm build
cjpm run
```

**Note:** This package compiles successfully. If linking fails with "library not found for -lSystem" or similar, run `cjpm build` from a terminal where you have run `source /path/to/cangjie/envsetup.sh` so the linker gets the correct SDK paths.

Expected output:

```
=== After adding three students ===
Alice, 1001
Bob, 1002
Carol, 1003
=== After removing Bob (by reference) ===
Alice, 1001
Carol, 1003
```

## Tests

**Cangjie tests** (ref output and single/multi-command):

```bash
cjpm test
```

**Shell script** (equivalent ref-output checks, no Cangjie test harness):

```bash
./test_ref_output.sh           # use existing build
BUILD=1 ./test_ref_output.sh   # build then test
```

**CLI usage script** (runs the generated CLI as in the project README: `help`, `Student new Alice 1001`, `Lesson new`, `demo`):

```bash
./test_cli_usage.sh            # use existing build
BUILD=1 ./test_cli_usage.sh    # build then test
```

## Web CLI

This package includes a **browser CLI** in `web/`: a chat-style UI (scrollable command/response history, text input at the bottom). From the package root run `npm install ws`, then `node web/cli_ws_server.js` (backend) and `npx serve web` (frontend); open `http://localhost:3000/`. Type commands; output is shown in grey. Each message runs in its own process (refs and env are local to that message). Use semicolons in one message for multiple commands (e.g. `Student new Alice 1001 ; Student new Bob 1002`). Within one message you can use multiple assignments and `$NAME` (e.g. `SN1 = Student new Alice 1001 ; EV = Lesson new ; Lesson new ; $EV`); the line is processed segment-by-segment so later segments see earlier refs. Semantics: run command, see response, env vars (`NAME = command`, `$NAME`), refs (`ref:1`, `ref:2`, …). Type **`exit`** to close the session. If the session is idle for 1 minute (or **`IDLE_TIMEOUT_MS`**), "session idle. exiting" is shown and the session closes. **Logs** are written to **`web/logs/cli_ws_server.log`**; use **`DEBUG_LOG=1 node web/cli_ws_server.js`** for extra debug detail (e.g. stdout/stderr chunk lengths).
