/**
 * Entrypoint for the Cangjie package-to-CLI utility.
 * Accepts package source path (--pkg <path> or env PKG_SRC).
 */
package pkgcli

import std.env.*
import std.fs.*
import std.io.*

main(): Int64 {
    let allArgs: Array<String> = getCommandLine()
    var pkgPath: String = "."
    var i: Int64 = 0
    while (i < allArgs.size) {
        if (allArgs[i] == "--pkg" && i + 1 < allArgs.size) {
            pkgPath = allArgs[i + 1]
            break
        }
        i++
    }
    if (pkgPath == ".") {
        match (getVariable("PKG_SRC")) {
            case Option<String>.Some(p) => pkgPath = p
            case _ => ()
        }
    }

    let manifestOpt: Option<Manifest> = parsePackage(pkgPath)
    if (let Option<Manifest>.None <- manifestOpt) {
        eprintln("Error: invalid package path or failed to parse: " + pkgPath)
        return 65
    }
    let manifest: Manifest = manifestOpt.getOrThrow()

    let driverSource: String = generateDriver(manifest)
    let outPath: Path = Path(pkgPath + "/src/cli_driver.cj")
    try {
        var file: File = File(outPath, Write)
        file.write(driverSource.toArray())
        file.close()
        println("Wrote " + outPath.toString())
        return 0
    } catch (_) {
        eprintln("Error: failed to write " + outPath.toString())
        return 66
    }
}
