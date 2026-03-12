/**
 * Codegen unit tests: generateDriver(manifest) produces valid driver source.
 * Builds Manifest in code and asserts on output substrings and edge cases.
 */
package pkgcli

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

func _makeMinimalManifest(): Manifest {
    let params: ArrayList<ParamInfo> = ArrayList<ParamInfo>()
    params.add(all: [ParamInfo("name", "String")])
    let commands: ArrayList<CommandInfo> = ArrayList<CommandInfo>()
    commands.add(all: [CommandInfo("init", true, "Foo", params, "Foo", true, false, false, "/")])
    Manifest("TestPkg", commands)
}

@Test
class CodegenTests {
    @TestCase
    func generateDriverContainsPackageAndCommands() {
        let m: Manifest = _makeMinimalManifest()
        let out: String = generateDriver(m)
        @Assert(out.indexOf("package ").isSome())
        @Assert(out.indexOf("Commands:").isSome())
        @Assert(out.indexOf("TestPkg").isSome())
        @Assert(out.indexOf("ref:1").isSome())
    }

    @TestCase
    func generateDriverNonEmpty() {
        let m: Manifest = _makeMinimalManifest()
        let out: String = generateDriver(m)
        @Assert(out.size > 100)
    }

    @TestCase
    func generateDriverEmptyCommandsStillHasPrologue() {
        let commands: ArrayList<CommandInfo> = ArrayList<CommandInfo>()
        let m: Manifest = Manifest("EmptyPkg", commands)
        let out: String = generateDriver(m)
        @Assert(out.indexOf("package ").isSome())
        @Assert(out.indexOf("EmptyPkg").isSome())
        @Assert(out.indexOf("Commands:").isSome())
    }
}
