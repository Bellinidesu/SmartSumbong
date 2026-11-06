// Local speed probe (7 Nov 2026): every page, every chooser on it (tabs, chips, filters, scopes, pagers that stay on the page),
// pressed once each from a fresh load. For each press: whether it swapped in place or reloaded the page, how long until the page
// settled, and the server's own account of it (Server-Timing waits plus the ?_trace=1 list of every wait).
// Start the fake with a round trip so waits cost what Mumbai makes them cost:
//   FAKE_RTT_MS=100 bash serve.sh;  CP=1 npx playwright test chooser-probe.spec.mjs --workers=1
import { test } from '@playwright/test';
import fs from 'node:fs';
test.skip(!process.env.CP, 'probe tool');
const OUT = process.env.OUT || 'chooser-probe.json';
const CASE = 'c0000000-0000-0000-0000-000000000003';
const PAGES = (process.env.PAGES || ['dashboard.php', 'summary.php', 'spatial.php', 'cases.php', 'notifications.php', 'inbox.php', 'residents.php',
  'personnel.php', 'activity.php', 'workspace.php', 'profile.php', 'administrative-services.php', 'settings.php', 'retirement-requests.php',
  `case.php?id=${CASE}`].join(',')).split(',');
const RUNGS = process.env.RUNGS ? process.env.RUNGS.split(',') : ['super', 'committee'];
const PER = +(process.env.PER || 8);

const st = h => {   // 'app;dur=12.3, db;dur=200;desc="2 waits, 9 calls", conn;...' -> {app, db, waits, calls, conns}
  if (!h) return null;
  const n = (k) => +((h.match(new RegExp(k + ';dur=([\\d.]+)')) || [])[1] || 0);
  return { app: n('app'), db: n('db'), waits: +((h.match(/(\d+) waits/) || [])[1] || 0), calls: +((h.match(/(\d+) calls/) || [])[1] || 0),
           conns: +((h.match(/(\d+) new connections/) || [])[1] || 0) };
};
const trace = body => ((body || '').match(/<!-- trace:[\s\S]*?-->/) || [''])[0].split('\n').slice(1, -1).map(l => l.trim()).filter(Boolean);
const withTrace = u => u + (u.includes('?') ? '&' : '?') + '_trace=1';

const ROWS = [];
const f = r => `${String(r.ms).padStart(5)} ms  ${r.swap ? 'swap  ' : 'RELOAD'}  waits ${r.st ? String(r.st.waits).padStart(2) : ' ?'}  calls ${r.st ? String(r.st.calls).padStart(2) : ' ?'}  app ${r.st ? String(Math.round(r.st.app)).padStart(5) : '    ?'}  ${r.tier.padEnd(9)} ${r.page.split('?')[0].padEnd(28)} ${r.label}`;
const push = r => { ROWS.push(r); console.log('ROW ' + f(r)); fs.appendFileSync(OUT, JSON.stringify(r) + '\n'); };
const settle = async (page) => {   // after a press: an in-place swap settling, or a whole page loading, whichever happens
  await Promise.race([
    page.waitForFunction(() => window.__done, null, { timeout: 15000 }).catch(() => {}),
    page.waitForEvent('load', { timeout: 15000 }).catch(() => {}),
  ]);
};

for (const tier of RUNGS) for (const p of (tier === 'super' ? PAGES : ['home.php', ...PAGES])) test(`${tier} ${p}`, async ({ browser }) => {
  test.setTimeout(300000);
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  await ctx.addCookies([{ name: 'ss_tier', value: tier, url: 'http://127.0.0.1:8013' },
    ...(tier === 'super' ? [] : [{ name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }])]);
  const page = await ctx.newPage();
  const base = 'http://127.0.0.1:8013/admin/' + p;
  const traced = async (u) => { const r = await ctx.request.get(withTrace(u)).catch(() => null); return r ? trace(await r.text()) : []; };
  const t0 = Date.now();
  const res = await page.goto(base, { waitUntil: 'load' }).catch(() => null);
  if (!res || res.status() !== 200 || !page.url().includes(p.split('?')[0])) { await ctx.close(); return; }
  push({ tier, page: p, kind: 'load', label: '(full load)', ms: Date.now() - t0, swap: false, st: st(res.headers()['server-timing']), trace: await traced(base) });
  const path = new URL(base).pathname;
  const cands = await page.evaluate(({ path, PER }) => {
    const out = [], seen = new Set();
    for (const a of document.querySelectorAll('main a[href]')) {
      const u = new URL(a.href, location.href);
      if (u.pathname !== path || u.search === location.search || a.hasAttribute('download') || /export=/.test(u.search)) continue;
      const r = a.getBoundingClientRect(); if (!r.width || !r.height) continue;
      const box = a.closest('[class*="chip"], [class*="seg"], [class*="tab"], [class*="filter"], [class*="scope"], [class*="pager"], nav, [class*="band"], thead');
      const where = box ? ((box.className.baseVal ?? box.className).toString().split(' ')[0] || box.tagName.toLowerCase()) : '(other)';
      const key = where + '|' + (a.textContent || '').trim().slice(0, 30);
      if (seen.has(key)) continue; seen.add(key);
      out.push({ href: a.getAttribute('href'), url: u.pathname + u.search, where, text: (a.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 40), pager: /pager/.test(where) });
    }
    out.sort((x, y) => (x.pager - y.pager));
    const per = {}; return out.filter(c => ((per[c.where] = (per[c.where] || 0) + 1) <= 3)).slice(0, PER);
  }, { path, PER });
  console.log('CANDS', p, cands.length);
  for (const c of cands) {
    await page.goto(base, { waitUntil: 'load' });
    const a = page.locator(`main a[href="${c.href.replace(/"/g, '\\"')}"] >> visible=true`).first();
    if (!(await a.isVisible().catch(() => false))) { console.log('SKIP hidden', c.where, c.text); continue; }
    await page.evaluate(() => { window.__stay = 1; window.__done = 0; document.addEventListener('htmx:afterSettle', () => { window.__done = 1; }, { once: true }); });
    const respP = page.waitForResponse(r => { const u = new URL(r.url()); return u.pathname + u.search === c.url && ['document', 'fetch', 'xhr'].includes(r.request().resourceType()); }, { timeout: 15000 }).catch(() => null);
    const t1 = Date.now();
    await a.click({ noWaitAfter: true, timeout: 10000 }).catch(() => {});
    const r = await respP;
    await settle(page);
    const ms = Date.now() - t1;
    const swap = await page.evaluate(() => window.__stay === 1).catch(() => false);
    push({ tier, page: p, kind: c.pager ? 'pager' : 'chooser', label: `${c.where}: ${c.text}`, ms, swap,
           hx: !!(r && r.request().headers()['hx-request']), st: r ? st(r.headers()['server-timing']) : null, trace: await traced('http://127.0.0.1:8013' + c.url) });
  }
  await ctx.close();
});
