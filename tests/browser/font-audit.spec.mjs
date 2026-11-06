// Local audit tool: FA=1 npx playwright test font-audit.spec.mjs -> what every visible piece of text really renders with (computed
// font-family and size), on every page, tab, popup and overlay: display sizes (17px and up) belong to Inter Tight, text below it to
// Inter; anything else (a system fallback, the old Urbanist) is listed, and the fonts must actually load.
import { test } from '@playwright/test';
test.skip(!process.env.FA, 'audit tool');
test.setTimeout(900000);
const CASE = 'c0000000-0000-0000-0000-000000000001';
const PAGES = ['dashboard.php', 'summary.php', 'spatial.php', 'cases.php', `case.php?id=${CASE}`, 'workspace.php', 'notifications.php', 'inbox.php', 'residents.php',
  'residents.php?id=u1', 'personnel.php', 'personnel.php?id=u2', 'personnel.php?view=staff', 'retirement-requests.php', 'activity.php', 'administrative-services.php',
  'control-room.php', 'settings.php', 'profile.php', 'home.php', `complaint-summary.php?id=${CASE}`, 'widgets.php', 'login.php', 'request-access.php', 'error.php', 'hall.php'];
const findings = new Map();
async function scan(page, tag) {
  const rows = await page.evaluate(() => {
    const out = []; const seen = new Set();
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let n; (n = walker.nextNode());) {
      const t = n.textContent.trim(); if (!t) continue; const el = n.parentElement; if (!el || el.closest('script, style, noscript, .p-sr, svg text')) continue;
      const r = el.getBoundingClientRect(); const cs = getComputedStyle(el);
      if (!r.width || !r.height || cs.visibility === 'hidden' || cs.display === 'none') continue;
      const fam = cs.fontFamily.split(',')[0].replace(/["']/g, '').trim(); const size = parseFloat(cs.fontSize);
      const key = fam + '|' + Math.round(size) + '|' + cs.fontWeight + '|' + (el.className && el.className.baseVal === undefined ? String(el.className).split(/\s+/)[0] : el.tagName);
      if (seen.has(key)) continue; seen.add(key);
      out.push({ fam, size, w: cs.fontWeight, tag: el.tagName.toLowerCase(), cls: String(el.className || '').split(/\s+/).slice(0, 2).join('.'), txt: t.slice(0, 28), par: [el.parentElement, el.parentElement && el.parentElement.parentElement].filter(Boolean).map(x => (x.className + '').split(/\s+/)[0] || x.tagName.toLowerCase()).join(' < ') });
    }
    return out;
  });
  for (const r of rows) {
    let why = null;
    if (r.fam === 'Inter Tight' && r.size < 17) why = 'small text in Inter Tight';
    else if (r.fam === 'Inter' && r.size >= 22) why = 'display size in Inter';
    else if (r.fam !== 'Inter Tight' && r.fam !== 'Inter' && !/^(monospace|ui-monospace|Menlo|Consolas|SF Mono|Courier New|Segoe UI Emoji|Apple Color Emoji)$/i.test(r.fam)) why = 'other family: ' + r.fam;
    if (!why) continue;
    const k = why + ' | ' + r.tag + '.' + r.cls + ' ' + r.size + 'px ' + r.w + ' [in ' + r.par + ']';
    if (!findings.has(k)) findings.set(k, { pages: new Set(), txt: r.txt });
    findings.get(k).pages.add(tag);
  }
}
for (const [W, mode] of [['2048', 'light'], ['1440', 'dark']]) test(`fonts ${W} ${mode}`, async ({ page, context }) => {
  await page.setViewportSize({ width: +W, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto('dashboard.php'); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  for (const p of PAGES) {
    await page.goto(p, { waitUntil: 'domcontentloaded' }); await page.waitForLoadState('networkidle', { timeout: 6000 }).catch(() => {}); await page.waitForTimeout(1200);
    const tabs = await page.$$eval('.st-tabs [data-st]', bs => bs.map(b => b.dataset.st));
    if (tabs.length) for (const k of tabs) { await page.locator(`.st-tabs [data-st="${k}"]`).click(); await page.waitForTimeout(400); await scan(page, `${p}#${k}`); }
    else await scan(page, p);
    if (await page.locator('#ss-win-open').count()) { await page.locator('#ss-win-open').click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(600); await scan(page, p + ' [engine window]'); await page.keyboard.press('Escape'); }
  }
  const loaded = await page.evaluate(async () => { const o = {}; for (const f of ['400 16px "Inter"', '700 16px "Inter"', '400 16px "Inter Tight"', '500 16px "Inter Tight"', '600 16px "Inter Tight"', '700 16px "Inter Tight"', '800 16px "Inter Tight"']) { try { o[f] = (await document.fonts.load(f)).length > 0; } catch (e) { o[f] = false; } } return o; });
  console.log('FA loaded', W, mode, JSON.stringify(loaded));
});
test.afterAll(() => {
  console.log('FA distinct findings', findings.size);
  [...findings.entries()].sort((a, b) => b[1].pages.size - a[1].pages.size).slice(0, 90).forEach(([k, v]) => console.log('FA', String(v.pages.size).padStart(3) + 'p', k, '::', v.txt));
});
