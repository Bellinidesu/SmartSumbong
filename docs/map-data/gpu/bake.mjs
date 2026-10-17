// node bake.mjs <dir>   Runs bake.html on the graphics card in a headless browser and saves what it computes.
// <dir>/in holds the inputs bake_gpu.py wrote; the results go to <dir>/out. Needs Brave or Chrome (BROWSER=path to use another).
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const dir = path.resolve(process.argv[2] || '.');
const inDir = path.join(dir, 'in'), outDir = path.join(dir, 'out');
fs.mkdirSync(outDir, { recursive: true });
const candidates = [process.env.BROWSER, 'C:/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe', 'C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].filter(Boolean);
const browser = candidates.find(p => fs.existsSync(p));
if (!browser) { console.error('No Brave, Chrome or Edge found; set BROWSER'); process.exit(1); }
const PORT = 8766, DEBUG = 9445;
const srv = http.createServer((q, r) => {
  const u = decodeURIComponent(q.url.split('?')[0]);
  const f = u === '/' ? path.join(here, 'bake.html') : u.startsWith('/in/') ? path.join(inDir, u.slice(4)) : null;
  if (!f || !fs.existsSync(f)) { r.statusCode = 404; r.end(); return; }
  r.setHeader('content-type', f.endsWith('.html') ? 'text/html' : f.endsWith('.json') ? 'application/json' : 'application/octet-stream');
  fs.createReadStream(f).pipe(r);
}).listen(PORT);
const proc = spawn(browser, ['--headless=new', `--remote-debugging-port=${DEBUG}`, `--user-data-dir=${process.env.TEMP || '/tmp'}/gpu-bake-${Date.now()}`, '--no-first-run', '--enable-gpu-rasterization', '--ignore-gpu-blocklist', '--use-angle=d3d11', '--disable-gpu-watchdog', '--disable-background-timer-throttling', '--disable-renderer-backgrounding', 'about:blank'], { stdio: 'ignore' });
const sleep = ms => new Promise(r => setTimeout(r, ms));
let tab;
for (let i = 0; i < 60; i++) { try { tab = await (await fetch(`http://127.0.0.1:${DEBUG}/json/new?http://127.0.0.1:${PORT}/`, { method: 'PUT' })).json(); break; } catch { await sleep(250); } }
const ws = new WebSocket(tab.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r));
let id = 0; const pend = new Map();
ws.addEventListener('message', m => { const o = JSON.parse(m.data); if (o.id && pend.has(o.id)) { pend.get(o.id)(o); pend.delete(o.id); } });
const send = (method, params = {}) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async e => { const r = await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true }); return r.result && r.result.result ? r.result.result.value : undefined; };
let last = '';
const t0 = Date.now();
for (;;) {
  await sleep(1500);
  const st = await ev('window.__status'), er = await ev('window.__error');
  if (st !== last) { console.log(((Date.now() - t0) / 1000).toFixed(0) + 's  ' + st); last = st; }
  if (er) { console.error(er); proc.kill(); srv.close(); process.exit(1); }
  if (st === 'done') break;
  if (Date.now() - t0 > 40 * 60 * 1000) { console.error('timed out'); proc.kill(); srv.close(); process.exit(1); }
}
console.log('graphics card: ' + await ev('window.__gpu'));
const outs = JSON.parse(await ev('JSON.stringify(window.__outs)'));
const SIZE = 3 * 1024 * 1024;
for (const o of outs) {
  const chunks = Math.ceil(o.bytes / SIZE), parts = [];
  for (let i = 0; i < chunks; i++) parts.push(Buffer.from(await ev(`window.__get(${JSON.stringify(o.name)}, ${i}, ${SIZE})`), 'base64'));
  fs.writeFileSync(path.join(outDir, o.name), Buffer.concat(parts));
  console.log('saved ' + o.name + ' (' + (o.bytes / 1048576).toFixed(1) + ' MB)');
}
proc.kill(); srv.close(); process.exit(0);
