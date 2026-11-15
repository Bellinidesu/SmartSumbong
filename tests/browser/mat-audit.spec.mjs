// Local audit tool: MAT=1 npx playwright test mat-audit.spec.mjs -> how Material (flat, lifted by shadow, no glass or glow) each page is, light and dark.
import { test } from '@playwright/test';
import fs from 'fs';
test.skip(!process.env.MAT, 'audit tool');
test.setTimeout(300000);
const OUT = (process.env.OUT || 'test-results') + '/mat.json';
fs.mkdirSync(OUT.replace(/\/[^/]*$/, ''), { recursive: true });
const B = 'http://127.0.0.1:8013';
const PAGES = ['dashboard.php', 'cases.php', 'summary.php', 'residents.php', 'notifications.php', 'inbox.php', 'workspace.php', 'personnel.php', 'administrative-services.php', 'settings.php', 'profile.php', 'spatial.php'];
const res = {};
for (const mode of ['light', 'dark']) test(`mat ${mode}`, async ({ page, context }) => {
  await context.addCookies([{ name: 'ss_tier', value: 'super', url: B }, { name: 'ss_committee', value: '', url: B }, { name: 'ss_role', value: '', url: B }]);
  await page.setViewportSize({ width: 2048, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
  res[mode] = {};
  for (const p of PAGES) {
    await page.goto(p, { waitUntil: 'domcontentloaded' });
    await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} document.documentElement.setAttribute('data-theme', m); }, mode);
    await page.waitForTimeout(1500);
    res[mode][p] = await page.evaluate(() => {
      const out = { blur: {}, glow: {}, sheen: {}, grad: {}, border: {}, total: 0 };
      const name = e => (e.id ? '#' + e.id : '') + (typeof e.className === 'string' && e.className.trim() ? '.' + e.className.trim().split(/\s+/).slice(0, 2).join('.') : e.tagName.toLowerCase());
      const bump = (o, k) => { o[k] = (o[k] || 0) + 1; };
      for (const e of document.querySelectorAll('body *')) {
        const r = e.getBoundingClientRect(); if (r.width < 6 || r.height < 6) continue;
        const c = getComputedStyle(e); if (c.display === 'none' || c.visibility === 'hidden') continue;
        out.total++;
        const bf = c.backdropFilter || c.webkitBackdropFilter; if (bf && bf !== 'none') bump(out.blur, name(e));
        const sh = c.boxShadow;
        if (sh && sh !== 'none') {
          for (const part of sh.split(/,(?![^(]*\))/)) {
            const m = part.trim().match(/^(rgba?\([^)]*\)|#[0-9a-f]+)?\s*(inset)?\s*(-?[\d.]+)px\s+(-?[\d.]+)px\s+(-?[\d.]+)px(?:\s+(-?[\d.]+)px)?\s*(inset)?\s*(rgba?\([^)]*\)|#[0-9a-f]+)?/i);
            if (!m) continue;
            const col = m[1] || m[8] || '', inset = !!(m[2] || m[7]), x = +m[3], y = +m[4], b = +m[5];
            const nums = (col.match(/[\d.]+/g) || []).map(Number); const isBlack = nums.length >= 3 && nums[0] < 40 && nums[1] < 60 && nums[2] < 90;
            if (inset && /255, 255, 255/.test(col) && b <= 1 && y >= 0 && x === 0) bump(out.sheen, name(e));
            else if (!inset && x === 0 && y === 0 && b >= 8 && !isBlack) bump(out.glow, name(e));
          }
        }
        if (/gradient/.test(c.backgroundImage) && (e.tagName === 'BUTTON' || e.tagName === 'A' || /btn|card|pill|tile/.test(typeof e.className === 'string' ? e.className : ''))) bump(out.grad, name(e));
      }
      return out;
    });
  }
  fs.writeFileSync(OUT.replace('.json', '-' + mode + '.json'), JSON.stringify(res[mode], null, 1));
});
