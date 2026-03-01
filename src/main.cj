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
        "let pty = null; try { pty = require('node-pty'); } catch (_) {}\n" +
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
        "  let proc = null;\n" +
        "  let procExited = false;\n" +
        "  let usedPty = false;\n" +
        "  let stdoutBuf = '';\n" +
        "  let hadStdoutLine = false;\n" +
        "  let pendingFirstLine = null;\n" +
        "  let idleTimer = null;\n" +
        "  const idleTimeoutMs = parseInt(process.env.IDLE_TIMEOUT_MS || '60000', 10);\n" +
        "  function pushChunk(chunk) {\n" +
        "    stdoutBuf += chunk;\n" +
        "    if (DEBUG_LOG) debug({ stdoutChunk: chunk.length });\n" +
        "    let idx;\n" +
        "    while ((idx = stdoutBuf.indexOf(\"\\n\")) >= 0) {\n" +
        "      hadStdoutLine = true;\n" +
        "      const line = stdoutBuf.substring(0, idx);\n" +
        "      stdoutBuf = stdoutBuf.substring(idx + 1);\n" +
        "      const tab = line.indexOf(\"\\t\");\n" +
        "      const stdoutPart = tab >= 0 ? line.substring(0, tab) : line;\n" +
        "      const stderrPart = tab >= 0 ? line.substring(tab + 1) : '';\n" +
        "      const outStr = unescapeLine(stdoutPart);\n" +
        "      const errStr = unescapeLine(stderrPart);\n" +
        "      logEntry({ type: 'output', stdout: outStr, stderr: errStr });\n" +
        "      try { ws.send(JSON.stringify({ stdout: outStr, stderr: errStr })); } catch (_) {}\n" +
        "      if (pendingFirstLine !== null) pendingFirstLine = null;\n" +
        "    }\n" +
        "  }\n" +
        "  function startIdleTimer() {\n" +
        "    if (idleTimeoutMs <= 0) return;\n" +
        "    if (idleTimer) clearTimeout(idleTimer);\n" +
        "    idleTimer = setTimeout(() => {\n" +
        "      idleTimer = null;\n" +
        "      logEntry({ event: 'SESSION_IDLE_CLOSE' });\n" +
        "      try { ws.send(JSON.stringify({ stdout: 'session idle. exiting', sessionClosed: true })); } catch (_) {}\n" +
        "      try { if (proc) { if (!usedPty && proc.stdin && proc.stdin.writable) proc.stdin.end(); proc.kill(); } } catch (_) {}\n" +
        "      proc = null;\n" +
        "      try { ws.close(); } catch (_) {}\n" +
        "    }, idleTimeoutMs);\n" +
        "  }\n" +
        "  function clearIdleTimer() { if (idleTimer) { clearTimeout(idleTimer); idleTimer = null; } }\n" +
        "  function spawnServeStdin() {\n" +
        "    if (pty && process.env.USE_PTY !== '0') {\n" +
        "      usedPty = true;\n" +
        "      logEntry({ event: 'PTY_USED' });\n" +
        "      proc = pty.spawn(cjpmBin, ['run', '--run-args=--serve-stdin'], { cwd, name: 'xterm-256color', cols: 80, rows: 24, env: process.env });\n" +
        "      proc.on('data', (chunk) => { pushChunk(chunk); });\n" +
        "      proc.on('exit', (code) => {\n" +
        "        procExited = true;\n" +
        "        logEntry({ event: 'PROCESS_EXIT', code: code });\n" +
        "        if (!hadStdoutLine) { try { ws.send(JSON.stringify({ stderr: 'Process exited.' })); } catch (_) {} }\n" +
        "      });\n" +
        "    } else {\n" +
        "      logEntry({ event: 'PTY_UNAVAILABLE' });\n" +
        "      proc = spawn(cjpmBin, ['run', '--run-args=--serve-stdin'], { cwd, stdio: ['pipe', 'pipe', 'pipe'] });\n" +
        "      proc.stdout.setEncoding('utf8');\n" +
        "      proc.stderr.setEncoding('utf8');\n" +
        "      proc.stdout.on('data', (chunk) => { pushChunk(chunk); });\n" +
        "      proc.stderr.on('data', (chunk) => { if (DEBUG_LOG) debug({ stderrChunk: chunk.length }); });\n" +
        "      proc.on('exit', (code) => {\n" +
        "        procExited = true;\n" +
        "        logEntry({ event: 'PROCESS_EXIT', code: code });\n" +
        "        if (!hadStdoutLine) { try { ws.send(JSON.stringify({ stderr: 'Process exited.' })); } catch (_) {} }\n" +
        "      });\n" +
        "      proc.on('error', (e) => { try { ws.send(JSON.stringify({ stderr: e.message })); } catch (_) {} });\n" +
        "    }\n" +
        "  }\n" +
        "  startIdleTimer();\n" +
        "  ws.on('message', (data) => {\n" +
        "    try {\n" +
        "      const msg = JSON.parse(data.toString());\n" +
        "      const line = msg.line != null ? String(msg.line).trim() : '';\n" +
        "      if (line.length === 0) return;\n" +
        "      logEntry({ type: 'input', line: line });\n" +
        "      if (line === 'exit') {\n" +
        "        clearIdleTimer();\n" +
        "        try { if (proc) { if (!usedPty && proc.stdin && proc.stdin.writable) proc.stdin.end(); proc.kill(); } } catch (_) {}\n" +
        "        proc = null;\n" +
        "        try { ws.send(JSON.stringify({ sessionClosed: true })); } catch (_) {}\n" +
        "        try { ws.close(); } catch (_) {}\n" +
        "        return;\n" +
        "      }\n" +
        "      startIdleTimer();\n" +
        "      if (proc === null) {\n" +
        "        spawnServeStdin();\n" +
        "        pendingFirstLine = line;\n" +
        "        if (usedPty) proc.write(line + \"\\n\"); else proc.stdin.write(line + \"\\n\");\n" +
        "        return;\n" +
        "      }\n" +
        "      if (procExited) { try { ws.send(JSON.stringify({ stderr: 'Process exited.' })); } catch (_) {} return; }\n" +
        "      if (usedPty) proc.write(line + \"\\n\"); else if (proc.stdin.writable) proc.stdin.write(line + \"\\n\");\n" +
        "    } catch (_) {}\n" +
        "  });\n" +
        "  ws.on('close', () => { clearIdleTimer(); try { if (proc && !usedPty && proc.stdin && proc.stdin.writable) proc.stdin.end(); if (proc) proc.kill(); } catch (_) {} });\n" +
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
