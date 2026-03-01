#!/usr/bin/env node
const http = require('http');
const WebSocket = require('ws');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
let pty = null; try { pty = require('node-pty'); } catch (_) {}
const PORT = parseInt(process.env.PORT || '8765', 10);
const cwd = path.join(__dirname, '..');
const cjpmBin = process.env.CJPM_BIN || 'cjpm';
const DEBUG_LOG = process.env.DEBUG_LOG === '1';
const LOG_DIR = path.join(__dirname, 'logs');
const LOG_PATH = path.join(LOG_DIR, 'cli_ws_server.log');
function debug(ob) {
  if (!DEBUG_LOG) return;
  try {
    fs.mkdirSync(LOG_DIR, { recursive: true });
    fs.appendFileSync(LOG_PATH, JSON.stringify(ob) + "\n");
  } catch (_) {}
}
function logEntry(ob) {
  try {
    fs.mkdirSync(LOG_DIR, { recursive: true });
    const entry = Object.assign({ ts: new Date().toISOString() }, ob);
    fs.appendFileSync(LOG_PATH, JSON.stringify(entry) + "\n");
  } catch (_) {}
}
function unescapeLine(s) { return (s && s.replace) ? s.replace(/ <NL> /g, "\n") : s; }
const server = http.createServer();
const wss = new WebSocket.Server({ server });
wss.on('connection', (ws) => {
  logEntry({ event: 'NEW CONNECTION' });
  let proc = null;
  let procExited = false;
  let usedPty = false;
  let stdoutBuf = '';
  let hadStdoutLine = false;
  let pendingFirstLine = null;
  let idleTimer = null;
  const idleTimeoutMs = parseInt(process.env.IDLE_TIMEOUT_MS || '60000', 10);
  function pushChunk(chunk) {
    stdoutBuf += chunk;
    if (DEBUG_LOG) debug({ stdoutChunk: chunk.length });
    let idx;
    while ((idx = stdoutBuf.indexOf("\n")) >= 0) {
      hadStdoutLine = true;
      const line = stdoutBuf.substring(0, idx);
      stdoutBuf = stdoutBuf.substring(idx + 1);
      const tab = line.indexOf("\t");
      const stdoutPart = tab >= 0 ? line.substring(0, tab) : line;
      const stderrPart = tab >= 0 ? line.substring(tab + 1) : '';
      const outStr = unescapeLine(stdoutPart);
      const errStr = unescapeLine(stderrPart);
      logEntry({ type: 'output', stdout: outStr, stderr: errStr });
      try { ws.send(JSON.stringify({ stdout: outStr, stderr: errStr })); } catch (_) {}
      if (pendingFirstLine !== null) pendingFirstLine = null;
    }
  }
  function startIdleTimer() {
    if (idleTimeoutMs <= 0) return;
    if (idleTimer) clearTimeout(idleTimer);
    idleTimer = setTimeout(() => {
      idleTimer = null;
      logEntry({ event: 'SESSION_IDLE_CLOSE' });
      try { ws.send(JSON.stringify({ stdout: 'session idle. exiting', sessionClosed: true })); } catch (_) {}
      try { if (proc) { if (!usedPty && proc.stdin && proc.stdin.writable) proc.stdin.end(); proc.kill(); } } catch (_) {}
      proc = null;
      try { ws.close(); } catch (_) {}
    }, idleTimeoutMs);
  }
  function clearIdleTimer() { if (idleTimer) { clearTimeout(idleTimer); idleTimer = null; } }
  function spawnServeStdin() {
    if (pty && process.env.USE_PTY !== '0') {
      usedPty = true;
      logEntry({ event: 'PTY_USED' });
      proc = pty.spawn(cjpmBin, ['run', '--run-args=--serve-stdin'], { cwd, name: 'xterm-256color', cols: 80, rows: 24, env: process.env });
      proc.on('data', (chunk) => { pushChunk(chunk); });
      proc.on('exit', (code) => {
        procExited = true;
        logEntry({ event: 'PROCESS_EXIT', code: code });
        if (!hadStdoutLine) { try { ws.send(JSON.stringify({ stderr: 'Process exited.' })); } catch (_) {} }
      });
    } else {
      logEntry({ event: 'PTY_UNAVAILABLE' });
      proc = spawn(cjpmBin, ['run', '--run-args=--serve-stdin'], { cwd, stdio: ['pipe', 'pipe', 'pipe'] });
      proc.stdout.setEncoding('utf8');
      proc.stderr.setEncoding('utf8');
      proc.stdout.on('data', (chunk) => { pushChunk(chunk); });
      proc.stderr.on('data', (chunk) => { if (DEBUG_LOG) debug({ stderrChunk: chunk.length }); });
      proc.on('exit', (code) => {
        procExited = true;
        logEntry({ event: 'PROCESS_EXIT', code: code });
        if (!hadStdoutLine) { try { ws.send(JSON.stringify({ stderr: 'Process exited.' })); } catch (_) {} }
      });
      proc.on('error', (e) => { try { ws.send(JSON.stringify({ stderr: e.message })); } catch (_) {} });
    }
  }
  startIdleTimer();
  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      const line = msg.line != null ? String(msg.line).trim() : '';
      if (line.length === 0) return;
      logEntry({ type: 'input', line: line });
      if (line === 'exit') {
        clearIdleTimer();
        try { if (proc) { if (!usedPty && proc.stdin && proc.stdin.writable) proc.stdin.end(); proc.kill(); } } catch (_) {}
        proc = null;
        try { ws.send(JSON.stringify({ sessionClosed: true })); } catch (_) {}
        try { ws.close(); } catch (_) {}
        return;
      }
      startIdleTimer();
      if (proc === null) {
        spawnServeStdin();
        pendingFirstLine = line;
        if (usedPty) proc.write(line + "\n"); else proc.stdin.write(line + "\n");
        return;
      }
      if (procExited) { try { ws.send(JSON.stringify({ stderr: 'Process exited.' })); } catch (_) {} return; }
      if (usedPty) proc.write(line + "\n"); else if (proc.stdin.writable) proc.stdin.write(line + "\n");
    } catch (_) {}
  });
  ws.on('close', () => { clearIdleTimer(); try { if (proc && !usedPty && proc.stdin && proc.stdin.writable) proc.stdin.end(); if (proc) proc.kill(); } catch (_) {} });
});
server.listen(PORT, () => console.log('WebSocket on ws://localhost:' + PORT));
