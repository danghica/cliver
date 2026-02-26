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
