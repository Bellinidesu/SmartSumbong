// Local audit tool, the looks sweep (16 Nov 2026): LS=1 npx playwright test look-sweep.spec.mjs
// Every role, both themes, every page the role can open, and every popup on it (each .p-scrim modal, the engine window, a dropdown's list, the case's
// SMART drawer, the chat head's panel). Checks what the 15-16 Nov looks work promised everywhere: no frosted glass, no halos (a glow is a lifted shadow now),
// no see-through popup, no text running past its box, no lone item left on a row of pills or tiles. Writes look-sweep.json and prints a summary.
import { test } from '@playwright/test';
import { writeFileSync, mkdirSync } from 'node:fs';
test.skip(!process.env.LS, 'audit tool');
test.setTimeout(900000);
test.describe.configure({ mode: 'serial' });
const B = 'http://127.0.0.1:8013';
const OUT = (process.env.OUT || 'test-results') + '/look-sweep.json';
mkdirSync(OUT.replace(/\/[^/]*$/, ''), { recursive: true });
const CASE = 'c0000000-0000-0000-0000-000000000001';
const PAGES = ['dashboard.php', 'summary.php', 'spatial.php', 'cases.php', `case.php?id=${CASE}`, 'case.php?id=c0000000-0000-0000-0000-000000000006', 'workspace.php',
  'notifications.php', 'inbox.php', 'residents.php', 'residents.php?id=u1', 'personnel.php', 'personnel.php?id=u2', 'personnel.php?view=staff', 'retirement-requests.php',
  'activity.php', 'administrative-services.php', 'committee-editor.php', 'committee-editor.php?key=peace_order', 'control-room.php', 'settings.php', 'profile.php', `complaint-summary.php?id=${CASE}`];
const ROLES = [
  ['super', [['ss_tier', 'super']]],
  ['kagawad', [['ss_tier', 'committee'], ['ss_committee', 'peace_order'], ['ss_role', 'kagawad']]],
  ['staff', [['ss_tier', 'moderator'], ['ss_committee', 'peace_order']]],
  ['captain', [['ss_tier', 'captain'], ['ss_role', 'chairman']]],
];
const all = [];

// what is checked on a scope (the page, or one popup)
async function check(page, scope, popup) {
  return page.evaluate(([sel, isPop]) => {
    const root = sel ? document.querySelector(sel) : document.body; if (!root) return [];
    const out = [], name = e => (e.id ? '#' + e.id : '') + (typeof e.className === 'string' && e.className.trim() ? '.' + e.className.trim().split(/\s+/).slice(0, 2).join('.') : e.tagName.toLowerCase());
    const els = [root, ...root.querySelectorAll('*')];
    for (const e of els) {
      const r = e.getBoundingClientRect(); if (r.width < 6 || r.height < 6) continue;
      const c = getComputedStyle(e); if (c.display === 'none' || c.visibility === 'hidden' || +c.opacity === 0) continue;
      if (c.backdropFilter && c.backdropFilter !== 'none') out.push(['frosted', name(e)]);
      for (const part of (c.boxShadow || '').split(/,(?![^(]*\))/)) {
        const m = part.trim().match(/^(rgba?\([^)]*\))\s+(-?[\d.]+)px\s+(-?[\d.]+)px\s+(-?[\d.]+)px/); if (!m) continue;
        const n = m[1].match(/[\d.]+/g).map(Number), black = n[0] < 40 && n[1] < 60 && n[2] < 90, inset = /inset/.test(part);
        if (!inset && +m[2] === 0 && +m[3] === 0 && +m[4] >= 10 && !black && (n[3] === undefined || n[3] > .15)) out.push(['halo', name(e)]);
      }
      // text past its box: a single-line chip or button whose words are wider than it
      if (/^(BUTTON|A|SPAN|LABEL)$/.test(e.tagName) && c.whiteSpace === 'nowrap' && c.overflow !== 'hidden' && e.scrollWidth > e.clientWidth + 2 && e.clientWidth > 0) out.push(['text past its edge', name(e)]);
    }
    // a popup must be a solid card
    if (isPop) { const c = getComputedStyle(root); const a = (c.backgroundColor.match(/[\d.]+/g) || []).map(Number); const alpha = a.length === 4 ? a[3] : 1;
      if (c.backgroundImage === 'none' && alpha < .85) out.push(['see-through popup', name(root) + ' bg ' + c.backgroundColor]); }
    // a lone item on the last row of a wrapping row of pills / chips / tiles
    for (const row of root.querySelectorAll('.p-acc-flags, .p-badges, .cc-tiles, .pf-presets, .ss-ladder, .cf-chips, .p-chips, .st-tabs')) {
      const kids = [...row.children].filter(k => { const kr = k.getBoundingClientRect(); return kr.width > 0 && kr.height > 0 && getComputedStyle(k).position !== 'absolute'; });
      if (kids.length < 3) continue;
      const tops = kids.map(k => Math.round(k.getBoundingClientRect().top)); const rows = [...new Set(tops)];
      if (rows.length > 1) { const last = tops.filter(t => t === rows[rows.length - 1]).length, first = tops.filter(t => t === rows[0]).length; if (last === 1 && first >= 3) out.push(['lone item on a row', name(row) + ' ' + first + '+1']); }
    }
    return out;
  }, [scope, !!popup]);
}

for (const [role, cookies] of ROLES) for (const mode of ['light', 'dark']) test(`looks ${role} ${mode}`, async ({ browser }) => {
  const ctx = await browser.newContext({ baseURL: B + '/admin/', viewport: { width: 2048, height: 1100 }, colorScheme: mode });
  await ctx.addCookies(cookies.map(([n, v]) => ({ name: n, value: v, url: B })));
  const page = await ctx.newPage();
  const push = (where, rows) => rows.forEach(([rule, what]) => all.push({ role, mode, where, rule, what }));
  for (const p of PAGES) {
    try {
      const res = await page.goto(p, { waitUntil: 'domcontentloaded' });
      if (!res || res.status() !== 200 || !page.url().includes(p.split('?')[0])) continue;   // the role cannot open it (redirected)
      await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} document.documentElement.setAttribute('data-theme', m); }, mode);
      await page.waitForTimeout(900);
      push(p, await check(page, null, false));
      for (const id of (await page.$$eval('.p-scrim[id]', s => s.map(x => x.id))).filter(x => x !== 'p-m-confirm')) {
        await page.evaluate(i => window.pOpen && window.pOpen(i), id); await page.waitForTimeout(250);
        push(`${p} [modal ${id}]`, await check(page, `#${id} .p-modal`, true));
        await page.keyboard.press('Escape'); await page.evaluate(i => { const s = document.getElementById(i); s && s.classList.remove('p-on', 'on', 'open'); }, id);
      }
      if (await page.locator('#ss-win-open').count()) { await page.locator('#ss-win-open').click({ timeout: 3000 }).catch(() => {}); await page.waitForTimeout(450); push(`${p} [engine window]`, await check(page, '#ss-panel', true)); await page.keyboard.press('Escape'); await page.waitForTimeout(200); }
      if (await page.locator('[data-smart-open]').count()) { await page.locator('[data-smart-open]').first().click({ timeout: 3000 }).catch(() => {}); await page.waitForTimeout(400); push(`${p} [SMART drawer]`, await check(page, '#smart-card', true)); await page.keyboard.press('Escape'); await page.waitForTimeout(200); }
      if (await page.locator('#ch-fab').count()) { await page.locator('#ch-fab').click({ timeout: 3000 }).catch(() => {}); await page.waitForTimeout(400); if (await page.locator('#ch-panel:not([hidden])').count()) push(`${p} [chat panel]`, await check(page, '#ch-panel', true)); await page.keyboard.press('Escape'); await page.waitForTimeout(200); }
      const pick = page.locator('.sdp-btn:visible').first();
      if (await pick.count()) { await pick.click({ timeout: 3000 }).catch(() => {}); await page.waitForTimeout(300); if (await page.locator('.sdp-pop:visible').count()) push(`${p} [dropdown]`, await check(page, '.sdp-pop', true)); await page.keyboard.press('Escape'); await page.waitForTimeout(150); }
    } catch (e) { all.push({ role, mode, where: p, rule: 'error', what: String(e.message).slice(0, 100) }); }
  }
  await ctx.close();
  writeFileSync(OUT, JSON.stringify(all, null, 1));
});

test.afterAll(() => {
  if (!all.length) { console.log('LS no findings'); return; }
  const g = {};
  for (const f of all) { const k = f.rule + ' | ' + f.what; (g[k] = g[k] || new Set()).add(f.role + '/' + f.mode + ' ' + f.where.replace(/\?id=[^ ]+/, '')); }
  console.log('LS findings ' + all.length + ', distinct ' + Object.keys(g).length);
  Object.entries(g).sort((a, b) => b[1].size - a[1].size).forEach(([k, s]) => console.log('LS ' + s.size + 'x  ' + k + '  :: ' + [...s].slice(0, 3).join('; ')));
});
