#!/usr/bin/env node
const http = require('http');
const https = require('https');
const crypto = require('crypto');
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
const AUTH_TOKEN = (process.env.CLIVER_AUTH_TOKEN && process.env.CLIVER_AUTH_TOKEN.length > 0) ? process.env.CLIVER_AUTH_TOKEN : crypto.randomBytes(32).toString('hex');
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
function deriveHandle(filename, handles) {
  var base = path.basename(filename, path.extname(filename))
    .toUpperCase().replace(/[^A-Z0-9]+/g, '_').replace(/^_+|_+$/g, '') || 'FILE';
  if (handles[base] === undefined) return base;
  var n = 2;
  while (handles[base + '_' + n] !== undefined) n++;
  return base + '_' + n;
}
function substituteHandles(line, handles) {
  var result = line.replace(/\$([A-Za-z_][A-Za-z0-9_]*)/g, function(_, name) {
    return handles[name] !== undefined ? handles[name] : '$' + name;
  });
  var parts = result.split(/(\s+)/);
  for (var i = 0; i < parts.length; i++) {
    if (handles[parts[i]] !== undefined) { parts[i] = handles[parts[i]]; }
  }
  return parts.join('');
}
const connHandles = new WeakMap();
function handleUpload(ws, msg) {
  try {
    if (typeof msg.filename !== 'string' || typeof msg.data !== 'string') {
      ws.send(JSON.stringify({ type: 'upload_error', message: 'Invalid upload request: filename and data are required' })); return;
    }
    var sanitized = path.basename(msg.filename).replace(/[^a-zA-Z0-9._-]/g, '_');
    var uploadDir = '/tmp/cliver/uploads';
    fs.mkdirSync(uploadDir, { recursive: true });
    var uid = Date.now() + '_' + Math.random().toString(36).slice(2);
    var filePath = path.join(uploadDir, uid + '_' + sanitized);
    fs.writeFileSync(filePath, Buffer.from(msg.data, 'base64'));
    var handles = connHandles.get(ws) || {};
    var handle = deriveHandle(msg.filename, handles);
    handles[handle] = filePath;
    logEntry({ type: 'upload', path: filePath, handle: handle });
    ws.send(JSON.stringify({ type: 'upload_result', path: filePath, handle: handle }));
  } catch (e) { try { ws.send(JSON.stringify({ type: 'upload_error', message: e.message })); } catch (_) {} }
}
function handleDownload(ws, msg) {
  try {
    if (!msg.path || typeof msg.path !== 'string') {
      ws.send(JSON.stringify({ type: 'download_error', message: 'Invalid download request: path is required' })); return;
    }
    var resolved = path.resolve(msg.path);
    if (!resolved.startsWith('/tmp/cliver/')) {
      ws.send(JSON.stringify({ type: 'download_error', message: 'Access denied: path must be under /tmp/cliver/' })); return;
    }
    var fileData = fs.readFileSync(resolved);
    var filename = path.basename(resolved);
    logEntry({ type: 'download', path: resolved });
    ws.send(JSON.stringify({ type: 'download_result', filename: filename, data: fileData.toString('base64') }));
  } catch (e) { try { ws.send(JSON.stringify({ type: 'download_error', message: e.message })); } catch (_) {} }
}
var tlsEnabled = false;
var server;
var tlsCert = process.env.CLIVER_TLS_CERT;
var tlsKey = process.env.CLIVER_TLS_KEY;
if (tlsCert && tlsKey) {
  server = https.createServer({ cert: fs.readFileSync(tlsCert), key: fs.readFileSync(tlsKey) });
  tlsEnabled = true;
} else {
  if ((tlsCert && !tlsKey) || (!tlsCert && tlsKey)) {
    process.stderr.write('Warning: only one of CLIVER_TLS_CERT/CLIVER_TLS_KEY is set, TLS disabled\n');
  }
  server = http.createServer();
}
server.on('request', (req, res) => {
  if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html' || req.url.startsWith('/?'))) {
    try {
      const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(html);
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('index.html not found');
    }
  } else {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found. Open / or /index.html for the CLI.');
  }
});
const wss = new WebSocket.Server({ server });
wss.on('connection', (ws, req) => {
  var reqUrl = new URL(req.url, 'http://localhost');
  var clientToken = reqUrl.searchParams.get('token');
  if (clientToken !== AUTH_TOKEN) {
    logEntry({ event: 'AUTH_FAILURE', reason: clientToken == null ? 'missing_token' : 'invalid_token' });
    ws.send(JSON.stringify({ type: 'auth_error', message: 'Authentication failed: invalid or missing token' }), () => ws.close(4401));
    return;
  }
  logEntry({ event: 'AUTH_SUCCESS' });
  logEntry({ event: 'NEW CONNECTION' });
  connHandles.set(ws, {});
  let idleTimer = null;
  const idleTimeoutMs = parseInt(process.env.IDLE_TIMEOUT_MS || '600000', 10);
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
      if (msg.type === 'upload') { handleUpload(ws, msg); return; }
      if (msg.type === 'download') { handleDownload(ws, msg); return; }
      let line = msg.line != null ? String(msg.line).trim() : '';
      line = normalizeWebLine(line);
      line = substituteHandles(line, connHandles.get(ws) || {});
      if (line.length === 0) return;
      logEntry({ type: 'input', line: line });
      if (line === 'exit') {
        clearIdleTimer();
        try { ws.send(JSON.stringify({ sessionClosed: true })); } catch (_) {}
        try { ws.close(); } catch (_) {}
        return;
      }
      startIdleTimer();
      let p;
      const defaultBin = path.join(cwd, 'target', 'release', 'bin', process.platform === 'win32' ? 'main.exe' : 'main');
      const useBin = process.env.CLI_BIN || (fs.existsSync && fs.existsSync(defaultBin) ? defaultBin : null);
      if (useBin) {
        p = spawn(useBin, [line], { cwd, stdio: ['ignore', 'pipe', 'pipe'], env: process.env });
      } else {
        const runArgsQuoted = JSON.stringify(line);
        const shellCmd = cjpmBin + ' run -- ' + runArgsQuoted;
        p = spawn(process.platform === 'win32' ? 'cmd' : '/bin/sh', process.platform === 'win32' ? ['/c', shellCmd] : ['-c', shellCmd], { cwd, stdio: ['ignore', 'pipe', 'pipe'], env: process.env });
      }
      let out = '';
      let err = '';
      p.stdout.setEncoding('utf8');
      p.stderr.setEncoding('utf8');
      p.stdout.on('data', (c) => { out += c; });
      p.stderr.on('data', (c) => { err += c; });
      p.on('exit', () => {
        try {
          const outClean = out.replace(/\s*cjpm run finished\s*/gi, '').trim();
          const delim = '<<<CLIVE_STDERR>>>';
          const idx = outClean.indexOf(delim);
          const stdoutPart = idx >= 0 ? outClean.substring(0, idx) : outClean;
          const stderrPart = idx >= 0 ? outClean.substring(idx + delim.length) : '';
          const outStr = unescapeLine(stdoutPart);
          const errStr = (idx >= 0 ? unescapeLine(stderrPart) : err).trim();
          logEntry({ type: 'output', stdout: outStr, stderr: errStr });
          ws.send(JSON.stringify({ stdout: outStr, stderr: errStr }));
        } catch (_) {}
      });
      p.on('error', (e) => { try { ws.send(JSON.stringify({ stderr: e.message })); } catch (_) {} });
    } catch (_) {}
  });
  ws.on('close', () => { clearIdleTimer(); });
});
server.listen(PORT, () => {
  logEntry({ event: 'SERVER_START', tlsEnabled: tlsEnabled });
  var proto = tlsEnabled ? 'wss' : 'ws';
  var httpProto = tlsEnabled ? 'https' : 'http';
  console.log('WebSocket on ' + proto + '://localhost:' + PORT);
  console.log('Auth token: ' + AUTH_TOKEN);
  console.log('Open: ' + httpProto + '://localhost:' + PORT + '/?token=' + encodeURIComponent(AUTH_TOKEN));
});
