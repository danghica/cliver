/**
 * Parser unit tests: parsePackage on fixture package; failure cases.
 * Run from Clive repo root so fixture path test/fixtures/minimal_package is valid.
 */
package pkgcli

import std.collection.*
import std.env.*
import std.unittest.*
import std.unittest.testmacro.*

// Path to minimal fixture (relative to repo root). Set CLIVE_REPO_ROOT if running from elsewhere.
func _fixturePath(): String {
    match (getVariable("CLIVE_REPO_ROOT")) {
        case Option<String>.Some(root) => root + "/test/fixtures/minimal_package"
        case _ => "test/fixtures/minimal_package"
    }
}

@Test
class ParserTests {
    @TestCase
    func parsePackageMinimalFixture() {
        let path: String = _fixturePath()
        let outcome: ParseOutcome = parsePackage(path)
        if (outcome.manifest.isNone()) {
            @Fail("parsePackage should succeed for minimal_package fixture at " + path + ": " + outcome.errorMessage)
        }
        let m: Manifest = outcome.manifest.getOrThrow()
        @Assert(m.commands.size >= 2)
        var hasHello: Bool = false
        var hasBox: Bool = false
        var i: Int64 = 0
        while (i < m.commands.size) {
            let cmd: CommandInfo = m.commands.get(i).getOrThrow()
            if (cmd.name == "hello") { hasHello = true }
            if (cmd.isConstructor && cmd.className == "Box") { hasBox = true }
            i++
        }
        @Assert(hasHello)
        @Assert(hasBox)
        // Package name is minimal_pkg when parser extracts it; otherwise default
        @Assert(m.packageQualifiedName.size > 0)
    }

    @TestCase
    func parsePackageInvalidPathReturnsNoneOrEmpty() {
        // Invalid path: expect failure (manifest None and errorMessage set) or empty commands
        let outcome: ParseOutcome = parsePackage("/nonexistent_path_abracadabra_12345")
        if (outcome.manifest.isSome()) {
            let m: Manifest = outcome.manifest.getOrThrow()
            @Assert(m.commands.size == 0)
        } else {
            @Assert(outcome.errorMessage.size > 0)
        }
    }
}
