/**
 * Entrypoint for the Cangjie package-to-CLI utility.
 * Accepts package source path (--pkg <path> or env PKG_SRC).
 */
package pkgcli

import std.env.*
import std.fs.*

func _backendScriptTemplate(): String {
    return "#!/usr/bin/env node\n" +
        "const http = require('http');\n" +
        "const WebSocket = require('ws');\n" +
        "const { spawn } = require('child_process');\n" +
        "const path = require('path');\n" +
        "const PORT = parseInt(process.env.PORT || '8765', 10);\n" +
        "const cwd = path.join(__dirname, '..');\n" +
        "const cjpmBin = process.env.CJPM_BIN || 'cjpm';\n" +
        "const server = http.createServer();\n" +
        "const wss = new WebSocket.Server({ server });\n" +
        "wss.on('connection', (ws) => {\n" +
        "  ws.on('message', (data) => {\n" +
        "    try {\n" +
        "      const msg = JSON.parse(data.toString());\n" +
        "      const line = msg.line != null ? String(msg.line).trim() : '';\n" +
        "      if (line.length === 0) return;\n" +
        "      const proc = spawn(cjpmBin, ['run', '--run-args=' + line], { cwd, stdio: ['ignore', 'pipe', 'inherit'] });\n" +
        "      let out = '';\n" +
        "      let err = '';\n" +
        "      proc.stdout.setEncoding('utf8');\n" +
        "      proc.stderr.setEncoding('utf8');\n" +
        "      proc.stdout.on('data', (chunk) => { out += chunk; });\n" +
        "      proc.stderr.on('data', (chunk) => { err += chunk; });\n" +
        "      proc.on('exit', () => {\n" +
        "        const stdout = out.replace(/\\\\bcjpm run finished\\\\s*\\\\n?/g, '').trimEnd();\n" +
        "        ws.send(JSON.stringify({ stdout, stderr: err }));\n" +
        "      });\n" +
        "      proc.on('error', (e) => { try { ws.send(JSON.stringify({ stderr: e.message })); } catch (_) {} });\n" +
        "    } catch (_) {}\n" +
        "  });\n" +
        "});\n" +
        "server.listen(PORT, () => console.log('WebSocket on ws://localhost:' + PORT));\n"
}

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
    if (pkgPath == "." || pkgPath == "") {
        eprintln("Error: refuse to write driver into current directory. Use --pkg <path-to-target-package> or PKG_SRC=<path>.")
        return 65
    }

    let manifestOpt: Option<Manifest> = parsePackage(pkgPath)
    if (let Option<Manifest>.None <- manifestOpt) {
        eprintln("Error: invalid package path or failed to parse: " + pkgPath)
        return 65
    }
    let manifest: Manifest = manifestOpt.getOrThrow()

    if (manifest.packageQualifiedName == "pkgcli") {
        eprintln("Error: do not generate the driver into the Clive package (would add a second main). Use --pkg <path-to-your-package> or PKG_SRC=<path>.")
        return 65
    }

    let driverSource: String = generateDriver(manifest)
    let outPath: Path = Path(pkgPath + "/src/cli_driver.cj")
    try {
        var file: File = File(outPath, Write)
        file.write(driverSource.toArray())
        file.close()
        println("Wrote " + outPath.toString())
    } catch (_) {
        eprintln("Error: failed to write " + outPath.toString())
        return 66
    }
    let backendScript: String = _backendScriptTemplate()
    let backendPath: Path = Path(pkgPath + "/web/cli_ws_server.js")
    try {
        var backendFile: File = File(backendPath, Write)
        backendFile.write(backendScript.toArray())
        backendFile.close()
        println("Wrote " + backendPath.toString())
    } catch (_) {
        eprintln("Note: could not write " + backendPath.toString() + " (create web/ if needed)")
    }
    return 0
}
