#!/usr/bin/env node
/**
 * Tests the WebSocket backend (web/cli_ws_server.js): connects, sends commands,
 * and asserts expected stdout/stderr. Run from sample_cangjie_package.
 * Requires: npm install ws (or run after test_sample_package.sh which uses the package).
 *
 * Usage: node test_backend.js [--port 18765]
 *        PORT=18765 node test_backend.js
 * Exit: 0 on success, 1 on failure.
 */

const { spawn } = require('child_process');
const path = require('path');

const PORT = parseInt(process.env.PORT || String(19000 + Math.floor(Math.random() * 999)), 10);
const cwd = path.join(__dirname);
const serverPath = path.join(cwd, 'web', 'cli_ws_server.js');

function runTests(port) {
  return new Promise((resolve, reject) => {
    let WebSocket;
    try {
      WebSocket = require('ws');
    } catch (e) {
      reject(new Error('ws module not found. Run: npm install ws'));
      return;
    }

    const tests = [
      {
        name: 'help returns commands list (and strips cjpm run finished)',
        line: 'help',
        check: (stdout) => {
          if (!stdout || !stdout.includes('Commands:')) return false;
          if (!stdout.includes('Student new')) return false;
          if (!stdout.includes('Lesson new')) return false;
          if (!stdout.includes('demo')) return false;
          if (stdout.includes('cjpm run finished')) return false;
          return true;
        },
      },
      {
        name: 'Student new Alice 1001 returns ref:1',
        line: 'Student new Alice 1001',
        check: (stdout) => stdout && stdout.includes('ref:1'),
      },
      {
        name: 'Lesson new returns ref:1',
        line: 'Lesson new',
        check: (stdout) => stdout && stdout.includes('ref:1'),
      },
      {
        name: 'demo returns Alice, Bob, Carol',
        line: 'demo',
        check: (stdout) => {
          if (!stdout) return false;
          if (!stdout.includes('Alice, 1001')) return false;
          if (!stdout.includes('Bob, 1002')) return false;
          if (!stdout.includes('Carol, 1003')) return false;
          return true;
        },
      },
      {
        name: 'empty line is ignored (no crash)',
        line: '',
        expectNoResponse: true,
        check: () => true,
      },
      {
        name: 'unknown command returns error',
        line: 'UnknownCommand x',
        check: (stdout, stderr) => {
          const out = (stdout + stderr);
          return out.includes('Unknown') || out.includes('unknown') || out.includes('command');
        },
      },
    ];

    let failed = null;
    let index = 0;

    function runNext() {
      if (failed) {
        resolve(failed);
        return;
      }
      if (index >= tests.length) {
        resolve(null);
        return;
      }

      const t = tests[index++];
      const ws = new WebSocket(`ws://127.0.0.1:${port}`);

      const timeout = setTimeout(() => {
        if (!done) {
          done = true;
          ws.close();
          resolve(new Error(`Test "${t.name}" timed out (15s)`));
        }
      }, 15000);

      let done = false;
      ws.on('open', () => {
        if (t.expectNoResponse) {
          ws.send(JSON.stringify({ line: t.line }));
          setTimeout(() => {
            if (!done) {
              done = true;
              clearTimeout(timeout);
              ws.close();
              runNext();
            }
          }, 300);
        } else {
          ws.send(JSON.stringify({ line: t.line }));
        }
      });

      ws.on('message', (data) => {
        if (done) return;
        try {
          const j = JSON.parse(data.toString());
          const stdout = (j.stdout || '').toString();
          const stderr = (j.stderr || '').toString();
          if (t.expectNoResponse) {
            done = true;
            clearTimeout(timeout);
            ws.close();
            runNext();
            return;
          }
          if (!t.check(stdout, stderr)) {
            done = true;
            clearTimeout(timeout);
            ws.close();
            resolve(new Error(`Test "${t.name}" failed. stdout: ${JSON.stringify(stdout.slice(0, 200))} stderr: ${JSON.stringify(stderr.slice(0, 200))}`));
            return;
          }
          done = true;
          clearTimeout(timeout);
          ws.close();
          runNext();
        } catch (e) {
          done = true;
          clearTimeout(timeout);
          ws.close();
          resolve(new Error(`Test "${t.name}" error: ${e.message}`));
        }
      });

      ws.on('error', (e) => {
        if (!done) {
          done = true;
          clearTimeout(timeout);
          resolve(new Error(`Test "${t.name}" WebSocket error: ${e.message}`));
        }
      });
    }

    runNext();
  });
}

function main() {
  const proc = spawn(process.execPath, [serverPath], {
    cwd,
    env: { ...process.env, PORT: String(PORT) },
    stdio: ['ignore', 'pipe', 'inherit'],
  });

  let serverReady = false;
  proc.stdout.on('data', (chunk) => {
    if (chunk.toString().includes('WebSocket on')) serverReady = true;
  });

  function killServer() {
    try {
      proc.kill('SIGTERM');
    } catch (_) {}
  }

  const waitForServer = new Promise((resolve, reject) => {
    const t = setTimeout(() => {
      killServer();
      reject(new Error('Backend did not start within 5s'));
    }, 5000);
    const interval = setInterval(() => {
      if (serverReady) {
        clearTimeout(t);
        clearInterval(interval);
        resolve();
      }
    }, 100);
  });

  waitForServer
    .then(() => new Promise((r) => setTimeout(r, 1500)))
    .then(() => runTests(PORT))
    .then((err) => {
      killServer();
      if (err) {
        console.error('FAIL:', err.message);
        process.exit(1);
      }
      console.log('All backend tests passed.');
      process.exit(0);
    })
    .catch((err) => {
      killServer();
      console.error('FAIL:', err.message);
      process.exit(1);
    });
}

main();
