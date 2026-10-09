// node shoot.mjs <outdir> <url> [<url> ...]   one PNG a url, taken from the bench page once it says it is ready (the real GPU, headless Brave or Chrome).
import fs from 'node:fs';
import { spawn } from 'node:child_process';

const [, , out, ...urls] = process.argv;
const exe = [process.env.BROWSER, 'C:/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe', 'C:/Program Files/Google/Chrome/Application/chrome.exe'].find((p) => p && fs.existsSync(p));
const port = 9400 + Math.floor(Math.random() * 400);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
fs.mkdirSync(out, { recursive: true });
const proc = spawn(exe, ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${process.env.TEMP || '/tmp'}/bench-${Date.now()}`, '--no-first-run', '--enable-gpu-rasterization', '--ignore-gpu-blocklist', '--use-angle=d3d11', '--window-size=760,560', 'about:blank'], { stdio: 'ignore' });
let tab;
for (let i = 0; i < 60; i++) { try { tab = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json(); break; } catch { await sleep(200); } }
const ws = new WebSocket(tab.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let id = 0; const pending = new Map();
ws.addEventListener('message', (m) => { const g = JSON.parse(m.data); if (g.id && pending.has(g.id)) { pending.get(g.id)(g); pending.delete(g.id); } });
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ method, params, id: i })); });
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true })).result.result?.value;
await send('Page.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 720, height: 520, deviceScaleFactor: 1, mobile: false });
let i = 0;
for (const u of urls) {
  await send('Page.navigate', { url: u });
  for (let k = 0; k < 100; k++) { await sleep(150); if (await ev('!!(window.__ready || window.__error)')) break; }
  const err = await ev('window.__error || ""');
  if (err) console.error('bench error:', err);
  const shot = await send('Page.captureScreenshot', { format: 'png' });
  fs.writeFileSync(`${out}/${String(i++).padStart(2, '0')}.png`, Buffer.from(shot.result.data, 'base64'));
}
ws.close(); proc.kill(); process.exit(0);
