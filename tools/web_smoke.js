// Drives the exported web build in headless Chrome: serves export/web, taps
// through the game, captures the browser console, and screenshots each step.
//
//   node tools/web_smoke.js                      # local export/web
//   node tools/web_smoke.js --url https://...    # the deployed site
//   node tools/web_smoke.js --mic deny           # refuse the microphone
//
// Screenshots land in tools/.web_smoke/ (gitignored).
//
// This exists because the GDScript suite has no browser and the JS harness has
// no engine, so a whole class of failure was only observable on a phone. Both
// bugs it caught were invisible to every other check:
//   - the bridge readiness probe rejected its own JS answer over a type
//     mismatch, so the microphone was dead on every device;
//   - an autowrapping Label with no width floor blew the record dialog up to
//     several times the screen height, showing nothing but background.
//
// Godot writes GDScript errors and print() to the browser console, so the
// captured output is the real diagnostic channel for a deployed build.

const { spawn } = require('child_process');
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');

const args = process.argv.slice(2);
const argOf = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};

const ROOT = path.join(__dirname, '..', 'export', 'web');
const OUT_DIR = path.join(__dirname, '.web_smoke');
const PORT = Number(argOf('--port', 8765));
const MIC = argOf('--mic', 'allow');
const BOOT_MS = Number(argOf('--boot', 45000));
const CHROME = argOf('--chrome', 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe');
let url = argOf('--url', null);

// Tap sequence: buy a chicken, open the Studio, open its record dialog, then
// tap once more - which is what actually triggers the permission prompt, since
// the tap that opened the dialog is consumed before the request is armed.
const TAPS = (argOf('--taps', '440,1417;530,39;235,185;450,600'))
  .split(';').filter(Boolean).map((p) => p.split(',').map(Number));

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm', '.pck': 'application/octet-stream',
  '.png': 'image/png', '.json': 'application/json',
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function serve() {
  return new Promise((resolve, reject) => {
    if (!fs.existsSync(path.join(ROOT, 'index.html'))) {
      reject(new Error(`no export at ${ROOT} - run the Web export first`));
      return;
    }
    const srv = http.createServer((req, res) => {
      let rel = decodeURIComponent(req.url.split('?')[0]);
      if (rel === '/') rel = '/index.html';
      const file = path.join(ROOT, rel);
      if (!file.startsWith(ROOT)) { res.writeHead(403).end(); return; }
      fs.readFile(file, (err, data) => {
        if (err) { res.writeHead(404).end('not found'); return; }
        // application/wasm is mandatory: instantiateStreaming rejects anything else.
        res.writeHead(200, {
          'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
          'Cache-Control': 'no-store',
        });
        res.end(data);
      });
    });
    srv.listen(PORT, () => resolve(srv));
  });
}

(async () => {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  let server = null;
  if (!url) { server = await serve(); url = `http://localhost:${PORT}/?debug=1`; }
  console.log(`target: ${url}  (mic: ${MIC})`);

  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'vzsmoke-'));
  const chromeArgs = [
    '--headless=new', `--remote-debugging-port=9336`, `--user-data-dir=${profile}`,
    '--window-size=900,1900',
    // SwiftShader supplies the WebGL2 context Godot needs without a GPU.
    '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
    '--no-first-run', '--mute-audio', '--use-fake-device-for-media-stream',
  ];
  if (MIC === 'allow') chromeArgs.push('--use-fake-ui-for-media-stream');
  chromeArgs.push(url);
  const chrome = spawn(CHROME, chromeArgs, { stdio: 'ignore' });

  const cleanup = () => { try { chrome.kill(); } catch {} if (server) server.close(); };

  try {
    let wsUrl;
    for (let i = 0; i < 60 && !wsUrl; i++) {
      try {
        const list = await (await fetch('http://127.0.0.1:9336/json/list')).json();
        const p = list.find((t) => t.type === 'page' && t.webSocketDebuggerUrl);
        if (p) wsUrl = p.webSocketDebuggerUrl;
      } catch { /* not up yet */ }
      if (!wsUrl) await sleep(500);
    }
    if (!wsUrl) throw new Error('Chrome never exposed a debuggable page');

    const ws = new WebSocket(wsUrl);
    let id = 0;
    const pending = new Map();
    const log = [];
    const send = (method, params = {}) => new Promise((res) => {
      const mid = ++id; pending.set(mid, res);
      ws.send(JSON.stringify({ id: mid, method, params }));
    });
    ws.onmessage = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); return; }
      if (m.method === 'Runtime.consoleAPICalled') {
        log.push(`[${m.params.type}] ${(m.params.args || [])
          .map((a) => (a.value !== undefined ? a.value : a.description)).join(' ')}`);
      } else if (m.method === 'Runtime.exceptionThrown') {
        log.push(`[EXCEPTION] ${m.params.exceptionDetails.text}`);
      }
    };
    await new Promise((r) => { ws.onopen = r; });
    await send('Runtime.enable');

    const shot = async (name) => {
      const r = await send('Page.captureScreenshot', { format: 'png' });
      fs.writeFileSync(path.join(OUT_DIR, name), Buffer.from(r.data, 'base64'));
    };

    console.log(`booting (${Math.round(BOOT_MS / 1000)}s)...`);
    await sleep(BOOT_MS);
    await shot('step0.png');

    for (let i = 0; i < TAPS.length; i++) {
      const [x, y] = TAPS[i];
      console.log(`tap ${i + 1} at ${x},${y}`);
      for (const type of ['mousePressed', 'mouseReleased']) {
        await send('Input.dispatchMouseEvent', {
          type, x, y, button: 'left', clickCount: 1, buttons: type === 'mousePressed' ? 1 : 0,
        });
        await sleep(120);
      }
      await sleep(7000);
      await shot(`step${i + 1}.png`);
    }

    console.log(`\nscreenshots -> ${OUT_DIR}`);
    console.log('\n===== BROWSER CONSOLE =====');
    console.log(log.length ? log.join('\n') : '(nothing)');

    const bad = log.filter((l) => /SCRIPT ERROR|EXCEPTION|bridge unavailable/i.test(l));
    console.log(bad.length ? `\nFAIL: ${bad.length} error line(s) above` : '\nOK: no script errors or bridge failures');
    ws.close();
    cleanup();
    process.exit(bad.length ? 1 : 0);
  } catch (e) {
    console.error('web_smoke failed:', e.message);
    cleanup();
    process.exit(1);
  }
})();
