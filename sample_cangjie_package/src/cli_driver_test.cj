/**
 * Tests that the generated CLI driver returns correct ref:1, ref:2, ref:3
 * when multiple constructor commands are run in one invocation (separated by ";").
 * Also tests the library entrypoint runFromArgs (for browser terminal / session actors).
 * Requires: build the package first (cjpm build); executable at target/release/bin/main
 * or set env CLI_DRIVER_EXE to the driver path.
 */
package lesson_demo

import std.collection.*
import std.process.*
import std.unittest.*
import std.unittest.testmacro.*
import std.env.*
import std.fs.*

func _getCliDriverPath(): Option<String> {
    match (getVariable("CLI_DRIVER_EXE")) {
        case Option<String>.Some(p) => Option<String>.Some(p)
        case _ => Option<String>.Some("target/release/bin/main")
    }
}

func _runCliAndGetStdout(args: Array<String>): Option<String> {
    let pathOpt: Option<String> = _getCliDriverPath()
    if (let Option<String>.None <- pathOpt) {
        return Option<String>.None
    }
    let exePath: String = pathOpt.getOrThrow()
    try {
        let (code, outBytes, _): (Int64, Array<Byte>, Array<Byte>) = executeWithOutput(exePath, args, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
        if (code != 0) {
            return Option<String>.None
        }
        let s: String = String.fromUtf8(outBytes)
        return Option<String>.Some(s)
    } catch (_) {
        return Option<String>.None
    }
}

@Test
class CliRefOutputTests {
    @TestCase
    func multiCommandReturnsRef1Ref2Ref3() {
        // Run three ref-returning commands in one invocation: Student new A 1 ; Lesson new ; Lesson new
        let args: Array<String> = ["Student", "new", "A", "1", ";", "Lesson", "new", ";", "Lesson", "new"]
        let outOpt: Option<String> = _runCliAndGetStdout(args)
        if (let Option<String>.None <- outOpt) {
            @Fail("CLI driver failed or not found. Build with: cjpm build. Set CLI_DRIVER_EXE if the executable is elsewhere.")
        }
        let out: String = outOpt.getOrThrow()
        let o1: Option<Int64> = out.indexOf("ref:1")
        let o2: Option<Int64> = out.indexOf("ref:2")
        let o3: Option<Int64> = out.indexOf("ref:3")
        @Assert(o1.isSome())
        @Assert(o2.isSome())
        @Assert(o3.isSome())
        let i1: Int64 = o1.getOrThrow()
        let i2: Int64 = o2.getOrThrow()
        let i3: Int64 = o3.getOrThrow()
        @Assert(i1 < i2)
        @Assert(i2 < i3)
    }

    @TestCase
    func singleCommandReturnsRef1() {
        let args: Array<String> = ["Lesson", "new"]
        let outOpt: Option<String> = _runCliAndGetStdout(args)
        if (let Option<String>.None <- outOpt) {
            @Fail("CLI driver failed or not found. Build with: cjpm build.")
        }
        let out: String = outOpt.getOrThrow()
        @Assert(out.indexOf("ref:1").isSome())
    }
}

/** Tests for runFromArgs (library entrypoint for session actors / browser terminal). */
@Test
class RunFromArgsTests {
    @TestCase
    func helpReturnsExitZeroAndCommandsInStdout() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        let args: Array<String> = ["help"]
        let result: RunFromArgsResult = runFromArgs(args, store, 1)
        @Assert(result.exitCode == 0)
        @Assert(result.stdout.indexOf("Commands:").isSome())
        @Assert(result.stdout.indexOf("Student").isSome())
        @Assert(result.stdout.indexOf("Lesson").isSome())
        @Assert(result.stdout.indexOf(" new ").isSome())
    }

    @TestCase
    func helpJsonIncludesCommandListAndFileProcessorSchema() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        let result: RunFromArgsResult = runFromArgs(["help", "--json"], store, 1)
        @Assert(result.exitCode == 0)
        @Assert(result.stdout.indexOf("\"commands\":[").isSome())
        @Assert(result.stdout.indexOf("\"name\":\"buildUploadReport\"").isSome())
        @Assert(result.stdout.indexOf("\"name\":\"inputPath\"").isSome())
        @Assert(result.stdout.indexOf("\"packagePath\":\"/\"").isSome())
        // Task 2 (agent-backend-hardening): verify commandKind and paramRole fields
        @Assert(result.stdout.indexOf("\"commandKind\":\"function\"").isSome())
        @Assert(result.stdout.indexOf("\"commandKind\":\"constructor\"").isSome())
        @Assert(result.stdout.indexOf("\"commandKind\":\"method\"").isSome())
        @Assert(result.stdout.indexOf("\"role\":\"path\"").isSome())
        @Assert(result.stdout.indexOf("\"role\":\"ref\"").isSome())
        @Assert(result.stdout.indexOf("\"className\":\"Student\"").isSome())
    }

    @TestCase
    func buildUploadReportCreatesDownloadableFileUnderTmpCliver() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        let inputDir: String = "/tmp/cliver/uploads"
        try { Directory.create(inputDir, recursive: true) } catch (_) { }
        let inputPath: String = inputDir + "/demo-upload.txt"
        var inputFile: File = File(Path(inputPath), Write)
        inputFile.write("alpha\nbeta\ngamma\n".toArray())
        inputFile.close()

        let result: RunFromArgsResult = runFromArgs(["buildUploadReport", inputPath], store, 1)
        @Assert(result.exitCode == 0)
        @Assert(result.stdout.indexOf("/tmp/cliver/outputs/demo-upload.txt.report.txt").isSome())

        let reportBytes: Array<Byte> = File.readFrom(Path("/tmp/cliver/outputs/demo-upload.txt.report.txt"))
        let report: String = String.fromUtf8(reportBytes)
        @Assert(report.indexOf("INPUT_PATH=/tmp/cliver/uploads/demo-upload.txt").isSome())
        @Assert(report.indexOf("LINE_COUNT=3").isSome())
        @Assert(report.indexOf("CHAR_COUNT=17").isSome())
        @Assert(report.indexOf("UPPERCASE_PREVIEW=ALPHA").isSome())
    }

    @TestCase
    func firstConstructorReturnsRef1() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        let args: Array<String> = ["Student", "new", "Alice", "1001"]
        let result: RunFromArgsResult = runFromArgs(args, store, 1)
        @Assert(result.exitCode == 0)
        @Assert(result.stdout.indexOf("ref:1").isSome())
        @Assert(result.nextId == 2)
    }

    @TestCase
    func secondCallWithSameStoreReturnsRef2() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        let args1: Array<String> = ["Student", "new", "Alice", "1001"]
        let r1: RunFromArgsResult = runFromArgs(args1, store, 1)
        @Assert(r1.exitCode == 0)
        @Assert(r1.stdout.indexOf("ref:1").isSome())
        let args2: Array<String> = ["Lesson", "new"]
        let r2: RunFromArgsResult = runFromArgs(args2, store, r1.nextId)
        @Assert(r2.exitCode == 0)
        @Assert(r2.stdout.indexOf("ref:2").isSome())
        @Assert(r2.nextId == 3)
    }

    @TestCase
    func addStudentToLessonAndPrintLessonStudentNames() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        let r1: RunFromArgsResult = runFromArgs(["Student", "new", "Alice", "1001"], store, 1)
        @Assert(r1.exitCode == 0)
        @Assert(r1.stdout.indexOf("ref:1").isSome())
        let r2: RunFromArgsResult = runFromArgs(["Lesson", "new"], store, r1.nextId)
        @Assert(r2.exitCode == 0)
        @Assert(r2.stdout.indexOf("ref:2").isSome())
        let r3: RunFromArgsResult = runFromArgs(["addStudentToLesson", "ref:1", "ref:2"], store, r2.nextId)
        @Assert(r3.exitCode == 0)
        let r4: RunFromArgsResult = runFromArgs(["printLessonStudentNames", "ref:2"], store, r3.nextId)
        @Assert(r4.exitCode == 0)
        // printLessonStudentNames uses println(); runFromArgs only captures _out(), so we assert success only.
    }

    @TestCase
    func echoBuiltInPrintsArgsToStdout() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        let r: RunFromArgsResult = runFromArgs(["echo", "ref:1"], store, 1)
        @Assert(r.exitCode == 0)
        @Assert(r.stdout.indexOf("ref:1").isSome())
    }

    @TestCase
    func dirBuiltInListsPaths() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        let r: RunFromArgsResult = runFromArgs(["dir"], store, 1)
        @Assert(r.exitCode == 0)
        @Assert(r.stdout.indexOf("demo_sub").isSome() || r.stdout.indexOf("Student").isSome() || r.stdout.indexOf("Lesson").isSome())
    }

    @TestCase
    func subpackageDemoSubExitsZero() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        let r: RunFromArgsResult = runFromArgs(["demo_sub/demo"], store, 1)
        @Assert(r.exitCode == 0)
    }

    @TestCase
    func subpackageDemoSubNestedExitsZero() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        let r: RunFromArgsResult = runFromArgs(["demo_sub/nested/demo"], store, 1)
        @Assert(r.exitCode == 0)
    }

    @TestCase
    func unknownCommandNonZeroAndStderr() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        let r: RunFromArgsResult = runFromArgs(["unknowncommandxyz"], store, 1)
        @Assert(r.exitCode != 0)
        @Assert(r.stderr.indexOf("Unknown command").isSome())
    }

    @TestCase
    func noMatchingOverloadStudentStderr() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        let r: RunFromArgsResult = runFromArgs(["Student", "new", "onlyOneArg"], store, 1)
        @Assert(r.exitCode != 0)
        @Assert(r.stderr.indexOf("No matching overload").isSome())
        @Assert(r.stderr.indexOf("Student").isSome())
    }

    @TestCase
    func invalidRefNonZeroStderr() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        let r: RunFromArgsResult = runFromArgs(["printLessonStudentNames", "ref:99"], store, 1)
        @Assert(r.exitCode != 0)
        @Assert(r.stderr.size > 0)
    }

    // Task 1 (agent-backend-hardening): in-process session proof
    // Proves that object store persists across multiple runFromArgs() calls and that
    // instance method calls (getName/setName) read and mutate the stored object.
    @TestCase
    func sessionStoreAndInstanceMethodsWorkAcrossMultipleCalls() {
        let store: HashMap<Int64, Any> = HashMap<Int64, Any>()
        // Step 1: create Student → ref:1 stored in object store
        let r1: RunFromArgsResult = runFromArgs(["Student", "new", "Alice", "1001"], store, 1)
        @Assert(r1.exitCode == 0)
        @Assert(r1.stdout.indexOf("ref:1").isSome())
        @Assert(r1.nextId == 2)
        // Step 2: read name via instance method → store must still hold ref:1
        let r2: RunFromArgsResult = runFromArgs(["Student", "getName", "ref:1"], store, r1.nextId)
        @Assert(r2.exitCode == 0)
        @Assert(r2.stdout.indexOf("Alice").isSome())
        // Step 3: mutate name via instance method
        let r3: RunFromArgsResult = runFromArgs(["Student", "setName", "ref:1", "Bob"], store, r2.nextId)
        @Assert(r3.exitCode == 0)
        // Step 4: re-read name → mutation must be visible through the same store
        let r4: RunFromArgsResult = runFromArgs(["Student", "getName", "ref:1"], store, r3.nextId)
        @Assert(r4.exitCode == 0)
        @Assert(r4.stdout.indexOf("Bob").isSome())
    }
}
