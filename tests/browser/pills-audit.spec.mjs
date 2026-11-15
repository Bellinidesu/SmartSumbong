// Tool, not a gate (12 Nov 2026): lists every pill-like element on the main pages in light and dark with its colours, contrast, height and width. PA=1 npx playwright test pills-audit.spec.mjs
import { test } from '@playwright/test';
import fs from 'fs';
const CASE = 'c0000000-0000-0000-0000-000000000001';
const PAGES = ['cases.php', `case.php?id=${CASE}`, 'residents.php', 'personnel.php', 'administrative-services.php?tab=roles', 'administrative-services.php', 'notifications.php', 'inbox.php', 'summary.php', 'dashboard.php', 'activity.php', 'profile.php'];
test.skip(!process.env.PA, 'tool');
test('pills', async ({ page }) => {
  test.setTimeout(280000);
  await page.setViewportSize({ width: 2048, height: 1100 });
  const out = [];
  for (const th of ['light', 'dark']) {
    for (const p of PAGES) {
      await page.goto('cases.php', { waitUntil: 'domcontentloaded' }); await page.evaluate(t => { try { localStorage.setItem('ss-theme', t); } catch (e) {} }, th);
      await page.goto(p, { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(1800);
      const rows = await page.evaluate(() => {
        const lum = c => { const m = c.match(/[\d.]+/g).map(Number); const f = v => { v /= 255; return v <= .03928 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }; return .2126 * f(m[0]) + .7152 * f(m[1]) + .0722 * f(m[2]); };
        const alpha = c => { const m = c.match(/[\d.]+/g); return m.length > 3 ? Number(m[3]) : 1; };
        const res = [];
        document.querySelectorAll('main *, aside *').forEach(e => {
          if (e.children.length > 3) return;
          const s = getComputedStyle(e), r = e.getBoundingClientRect();
          if (r.width < 10 || r.height < 14 || r.height > 40) return;
          const br = parseFloat(s.borderTopLeftRadius); if (br < r.height / 2 - 2) return;
          if (alpha(s.backgroundColor) < .5) return;
          const txt = (e.textContent || '').trim(); if (!txt || txt.length > 70) return;
          if (/^(BUTTON|A|INPUT|SELECT)$/.test(e.tagName) && !/badge|pill|chip|rank|tag/i.test(e.className)) return;
          const l1 = lum(s.color), l2 = lum(s.backgroundColor), cr = (Math.max(l1, l2) + .05) / (Math.min(l1, l2) + .05);
          const par = e.parentElement.getBoundingClientRect();
          res.push({ cls: String(e.className).trim().split(/\s+/).slice(0, 3).join('.'), txt: txt.slice(0, 40), h: Math.round(r.height), w: Math.round(r.width), bg: s.backgroundColor, fg: s.color, cr: Math.round(cr * 10) / 10, over: r.right > par.right + 1 });
        });
        return res;
      });
      rows.forEach(r => out.push({ th, p, ...r }));
    }
  }
  fs.writeFileSync(process.env.TEMP + '/pills-audit.json', JSON.stringify(out, null, 1));
});
