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
        "const fs = require('fs');\n" +
        "const PORT = parseInt(process.env.PORT || '8765', 10);\n" +
        "const cwd = path.join(__dirname, '..');\n" +
        "const cjpmBin = process.env.CJPM_BIN || 'cjpm';\n" +
        "const DEBUG_LOG = process.env.DEBUG_LOG === '1';\n" +
        "const LOG_DIR = path.join(__dirname, 'logs');\n" +
        "const LOG_PATH = path.join(LOG_DIR, 'cli_ws_server.log');\n" +
        "function debug(ob) {\n" +
        "  if (!DEBUG_LOG) return;\n" +
        "  try {\n" +
        "    fs.mkdirSync(LOG_DIR, { recursive: true });\n" +
        "    fs.appendFileSync(LOG_PATH, JSON.stringify(ob) + \"\\n\");\n" +
        "  } catch (_) {}\n" +
        "}\n" +
        "function logEntry(ob) {\n" +
        "  try {\n" +
        "    fs.mkdirSync(LOG_DIR, { recursive: true });\n" +
        "    const entry = Object.assign({ ts: new Date().toISOString() }, ob);\n" +
        "    fs.appendFileSync(LOG_PATH, JSON.stringify(entry) + \"\\n\");\n" +
        "  } catch (_) {}\n" +
        "}\n" +
        "function unescapeLine(s) { return (s && s.replace) ? s.replace(/ <NL> /g, \"\\n\") : s; }\n" +
        "const server = http.createServer();\n" +
        "const wss = new WebSocket.Server({ server });\n" +
        "wss.on('connection', (ws) => {\n" +
        "  logEntry({ event: 'NEW CONNECTION' });\n" +
        "  let idleTimer = null;\n" +
        "  const idleTimeoutMs = parseInt(process.env.IDLE_TIMEOUT_MS || '600000', 10);\n" +
        "  function startIdleTimer() {\n" +
        "    if (idleTimeoutMs <= 0) return;\n" +
        "    if (idleTimer) clearTimeout(idleTimer);\n" +
        "    idleTimer = setTimeout(() => {\n" +
        "      idleTimer = null;\n" +
        "      logEntry({ event: 'SESSION_IDLE_CLOSE' });\n" +
        "      try { ws.send(JSON.stringify({ stdout: 'session idle. exiting', sessionClosed: true })); } catch (_) {}\n" +
        "      try { ws.close(); } catch (_) {}\n" +
        "    }, idleTimeoutMs);\n" +
        "  }\n" +
        "  function clearIdleTimer() { if (idleTimer) { clearTimeout(idleTimer); idleTimer = null; } }\n" +
        "  startIdleTimer();\n" +
        "  function normalizeWebLine(s) {\n" +
        "    if (!s || typeof s !== 'string') return '';\n" +
        "    var out = '';\n" +
        "    for (var i = 0; i < s.length; i++) {\n" +
        "      var c = s.charAt(i);\n" +
        "      if (c.charCodeAt(0) === 10 || c.charCodeAt(0) === 13) out += ' ';\n" +
        "      else if (c === ';') out += ' ; ';\n" +
        "      else out += c;\n" +
        "    }\n" +
        "    return out.trim();\n" +
        "  }\n" +
        "  ws.on('message', (data) => {\n" +
        "    try {\n" +
        "      const msg = JSON.parse(data.toString());\n" +
        "      let line = msg.line != null ? String(msg.line).trim() : '';\n" +
        "      line = normalizeWebLine(line);\n" +
        "      if (line.length === 0) return;\n" +
        "      logEntry({ type: 'input', line: line });\n" +
        "      if (line === 'exit') {\n" +
        "        clearIdleTimer();\n" +
        "        try { ws.send(JSON.stringify({ sessionClosed: true })); } catch (_) {}\n" +
        "        try { ws.close(); } catch (_) {}\n" +
        "        return;\n" +
        "      }\n" +
        "      startIdleTimer();\n" +
        "      const p = spawn(cjpmBin, ['run', '--run-args', line], { cwd, stdio: ['ignore', 'pipe', 'pipe'] });\n" +
        "      let out = '';\n" +
        "      let err = '';\n" +
        "      p.stdout.setEncoding('utf8');\n" +
        "      p.stderr.setEncoding('utf8');\n" +
        "      p.stdout.on('data', (c) => { out += c; });\n" +
        "      p.stderr.on('data', (c) => { err += c; });\n" +
        "      p.on('exit', () => {\n" +
        "        try {\n" +
        "          const lastLine = out.split(/\\\\r?\\\\n/).filter(function (l) { return l.trim() !== 'cjpm run finished'; }).pop() || '';\n" +
        "          const tab = lastLine.indexOf(String.fromCharCode(9));\n" +
        "          const stdoutPart = tab >= 0 ? lastLine.substring(0, tab) : lastLine;\n" +
        "          const stderrPart = tab >= 0 ? lastLine.substring(tab + 1) : '';\n" +
        "          const outStr = unescapeLine(stdoutPart);\n" +
        "          const errStr = (tab >= 0 ? unescapeLine(stderrPart) : err).trim();\n" +
        "          logEntry({ type: 'output', stdout: outStr, stderr: errStr });\n" +
        "          ws.send(JSON.stringify({ stdout: outStr, stderr: errStr }));\n" +
        "        } catch (_) {}\n" +
        "      });\n" +
        "      p.on('error', (e) => { try { ws.send(JSON.stringify({ stderr: e.message })); } catch (_) {} });\n" +
        "    } catch (_) {}\n" +
        "  });\n" +
        "  ws.on('close', () => { clearIdleTimer(); });\n" +
        "});\n" +
        "server.listen(PORT, () => { logEntry({ event: 'SERVER_START' }); console.log('WebSocket on ws://localhost:' + PORT); });\n"
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
