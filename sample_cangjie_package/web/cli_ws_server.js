#!/usr/bin/env node
const http = require('http');
const WebSocket = require('ws');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
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
  let idleTimer = null;
  const idleTimeoutMs = parseInt(process.env.IDLE_TIMEOUT_MS || '60000', 10);
  function startIdleTimer() {
    if (idleTimeoutMs <= 0) return;
    if (idleTimer) clearTimeout(idleTimer);
    idleTimer = setTimeout(() => {
      idleTimer = null;
      logEntry({ event: 'SESSION_IDLE_CLOSE' });
      try { ws.send(JSON.stringify({ stdout: 'session idle. exiting', sessionClosed: true })); } catch (_) {}
      try { ws.close(); } catch (_) {}
    }, idleTimeoutMs);
  }
  function clearIdleTimer() { if (idleTimer) { clearTimeout(idleTimer); idleTimer = null; } }
  startIdleTimer();
  function normalizeWebLine(s) {
    if (!s || typeof s !== 'string') return '';
    var out = '';
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i);
      if (c.charCodeAt(0) === 10 || c.charCodeAt(0) === 13) out += ' ';
      else if (c === ';') out += ' ; ';
      else out += c;
    }
    return out.trim();
  }
  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      let line = msg.line != null ? String(msg.line).trim() : '';
      line = normalizeWebLine(line);
      if (line.length === 0) return;
      logEntry({ type: 'input', line: line });
      if (line === 'exit') {
        clearIdleTimer();
        try { ws.send(JSON.stringify({ sessionClosed: true })); } catch (_) {}
        try { ws.close(); } catch (_) {}
        return;
      }
      startIdleTimer();
      const p = spawn(cjpmBin, ['run', '--run-args', line], { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
      let out = '';
      let err = '';
      p.stdout.setEncoding('utf8');
      p.stderr.setEncoding('utf8');
      p.stdout.on('data', (c) => { out += c; });
      p.stderr.on('data', (c) => { err += c; });
      p.on('exit', () => {
        try {
          const lastLine = out.split(/\\r?\\n/).filter(function (l) { return l.trim() !== 'cjpm run finished'; }).pop() || '';
          const tab = lastLine.indexOf(String.fromCharCode(9));
          const stdoutPart = tab >= 0 ? lastLine.substring(0, tab) : lastLine;
          const stderrPart = tab >= 0 ? lastLine.substring(tab + 1) : '';
          const outStr = unescapeLine(stdoutPart);
          const errStr = (tab >= 0 ? unescapeLine(stderrPart) : err).trim();
          logEntry({ type: 'output', stdout: outStr, stderr: errStr });
          ws.send(JSON.stringify({ stdout: outStr, stderr: errStr }));
        } catch (_) {}
      });
      p.on('error', (e) => { try { ws.send(JSON.stringify({ stderr: e.message })); } catch (_) {} });
    } catch (_) {}
  });
  ws.on('close', () => { clearIdleTimer(); });
});
server.listen(PORT, () => { logEntry({ event: 'SERVER_START' }); console.log('WebSocket on ws://localhost:' + PORT); });
