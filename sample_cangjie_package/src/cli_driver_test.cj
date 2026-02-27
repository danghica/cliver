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
        let (code, outBytes, _errBytes): (Int64, Array<Byte>, Array<Byte>) = executeWithOutput(exePath, args, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
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
        @Assert(result.stdout.indexOf("Student new").isSome())
        @Assert(result.stdout.indexOf("Lesson new").isSome())
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
}
