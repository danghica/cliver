/**
 * Dir helper unit tests: normalizePath, isKnownPackagePath, packagePathFromFile.
 * Same package pkgcli — no explicit import of pkgcli needed.
 */
package pkgcli

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class DirHelperTests {
    @TestCase
    func normalizePathRoot() {
        let r: Option<String> = normalizePath("/", "/")
        @Assert(r.isSome())
        @Assert(r.getOrThrow() == "/")
    }

    @TestCase
    func normalizePathDotDotFromRoot() {
        let r: Option<String> = normalizePath("..", "/")
        @Assert(r.isNone())
    }

    @TestCase
    func normalizePathEmptyToken() {
        let r: Option<String> = normalizePath("", "/")
        @Assert(r.isSome())
        @Assert(r.getOrThrow() == "/")
    }

    @TestCase
    func normalizePathDotStaysCwd() {
        let r: Option<String> = normalizePath(".", "/")
        @Assert(r.isSome())
        @Assert(r.getOrThrow() == "/")
    }

    @TestCase
    func normalizePathRelativeA() {
        let r: Option<String> = normalizePath("a", "/")
        @Assert(r.isSome())
        @Assert(r.getOrThrow() == "a")
    }

    @TestCase
    func isKnownPackagePathDemoSub() {
        let known: ArrayList<String> = ArrayList<String>()
        known.add(all: ["demo_sub"])
        known.add(all: ["demo_sub/nested"])
        @Assert(isKnownPackagePath("demo_sub", known))
        @Assert(isKnownPackagePath("demo_sub/nested", known))
        @Assert(isKnownPackagePath("/", known))
    }

    @TestCase
    func isKnownPackagePathUnknown() {
        let known: ArrayList<String> = ArrayList<String>()
        known.add(all: ["demo_sub"])
        @Assert(isKnownPackagePath("other", known) == false)
    }

    @TestCase
    func packagePathFromFileAtRoot() {
        // File directly under scanDir -> root "/"
        let scanDir: String = "/tmp/scan"
        let fileAtRoot: Path = Path(scanDir + "/main.cj")
        let p: String = packagePathFromFile(fileAtRoot, scanDir)
        @Assert(p == "/")
    }

    @TestCase
    func packagePathFromFileInSubdir() {
        // File in subdir -> relative segment "demo_sub"
        let scanDir: String = "/tmp/scan"
        let fileInSub: Path = Path(scanDir + "/demo_sub/foo.cj")
        let p: String = packagePathFromFile(fileInSub, scanDir)
        @Assert(p == "demo_sub")
    }

    // Randomized-style: many path variants; normalizePath never crashes, result is Some or None.
    @TestCase
    func normalizePathManyVariantsNoCrash() {
        let cwds: ArrayList<String> = ArrayList<String>()
        cwds.add(all: ["/"]); cwds.add(all: ["/a"]); cwds.add(all: ["/a/b"])
        let tokens: ArrayList<String> = ArrayList<String>()
        tokens.add(all: [""]); tokens.add(all: ["."]); tokens.add(all: [".."]); tokens.add(all: ["a"]); tokens.add(all: ["b"])
        tokens.add(all: ["/"]); tokens.add(all: ["/a"]); tokens.add(all: ["a/b"]); tokens.add(all: ["a/../b"]); tokens.add(all: ["a/.."])
        var i: Int64 = 0
        while (i < cwds.size) {
            var j: Int64 = 0
            while (j < tokens.size) {
                let r: Option<String> = normalizePath(tokens.get(j).getOrThrow(), cwds.get(i).getOrThrow())
                @Assert(r.isSome() || r.isNone())
                j++
            }
            i++
        }
    }

    @TestCase
    func isKnownPackagePathDeterministic() {
        let known: ArrayList<String> = ArrayList<String>()
        known.add(all: ["x", "x/y", "x/y/z"])
        let path1: String = "x"
        let path2: String = "x"
        @Assert(isKnownPackagePath(path1, known) == isKnownPackagePath(path2, known))
    }
}
