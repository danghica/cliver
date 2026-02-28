#!/usr/bin/env node
const http = require('http');
const WebSocket = require('ws');
const { spawn } = require('child_process');
const path = require('path');
const PORT = parseInt(process.env.PORT || '8765', 10);
const cwd = path.join(__dirname, '..');
const cjpmBin = process.env.CJPM_BIN || 'cjpm';
const server = http.createServer();
const wss = new WebSocket.Server({ server });
wss.on('connection', (ws) => {
  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      const line = msg.line != null ? String(msg.line).trim() : '';
      if (line.length === 0) return;
      const proc = spawn(cjpmBin, ['run', '--run-args=' + line], { cwd, stdio: ['ignore', 'pipe', 'inherit'] });
      let out = '';
      let err = '';
      proc.stdout.setEncoding('utf8');
      proc.stderr.setEncoding('utf8');
      proc.stdout.on('data', (chunk) => { out += chunk; });
      proc.stderr.on('data', (chunk) => { err += chunk; });
      proc.on('exit', () => {
        const stdout = out.replace(/\bcjpm run finished\s*\n?/g, '').trimEnd();
        ws.send(JSON.stringify({ stdout, stderr: err }));
      });
      proc.on('error', (e) => { try { ws.send(JSON.stringify({ stderr: e.message })); } catch (_) {} });
    } catch (_) {}
  });
});
server.listen(PORT, () => console.log('WebSocket on ws://localhost:' + PORT));
