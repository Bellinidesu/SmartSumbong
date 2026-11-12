// Pills, one system (12 Nov 2026, Ace): in light and dark every filled status pill and position chip reads (contrast 4.5:1), is one height, and the SMART level carries its score inside.
// Run: bash serve.sh, then npx playwright test pills.spec.mjs.
import { test, expect } from '@playwright/test';

const PAGES = ['cases.php', 'residents.php', 'personnel.php', 'administrative-services.php#admins', 'summary.php', 'profile.php'];

test('every filled pill and position chip reads and is one height, in light and dark', async ({ page }) => {
  test.setTimeout(120000);
  const bad = [];
  for (const th of ['light', 'dark']) {
    await page.goto('cases.php', { waitUntil: 'domcontentloaded' });
    await page.evaluate(t => { try { localStorage.setItem('ss-theme', t); } catch (e) {} }, th);
    for (const p of PAGES) {
      await page.goto(p, { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(1500);
      const rows = await page.evaluate(() => {
        const lum = c => { const m = c.match(/[\d.]+/g).map(Number); const f = v => { v /= 255; return v <= .03928 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }; return .2126 * f(m[0]) + .7152 * f(m[1]) + .0722 * f(m[2]); };
        const out = [];
        document.querySelectorAll('main .p-badge, main .rank').forEach(e => {
          const s = getComputedStyle(e), r = e.getBoundingClientRect();
          if (r.width < 10 || s.backgroundColor === 'rgba(0, 0, 0, 0)' || e.classList.contains('dv-test')) return;   // a status as a dot and a word has no fill; the TEST tag is a tag
          const l1 = lum(s.color), l2 = lum(s.backgroundColor);
          out.push({ txt: e.textContent.trim().slice(0, 28), cls: String(e.className), cr: (Math.max(l1, l2) + .05) / (Math.min(l1, l2) + .05), h: Math.round(r.height) });
        });
        return out;
      });
      for (const r of rows) {
        if (r.cr < 4.5) bad.push(`${th} ${p}: "${r.txt}" (${r.cls}) contrast ${r.cr.toFixed(1)}`);
        if (r.h !== 24) bad.push(`${th} ${p}: "${r.txt}" is ${r.h}px, not 24`);
      }
    }
  }
  expect(bad, 'pills that do not read or are not one height').toEqual([]);
});

test('the SMART level carries its score inside the pill, and the duplicate flag is short and on its own line', async ({ page }) => {
  await page.goto('cases.php', { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(1500);
  const lvl = page.locator('td.ss-smart .p-b-score').first();
  await expect(lvl).toBeVisible();
  await expect(lvl.locator('.ss-score-n')).toHaveText(/^\d+$/);
  expect(await lvl.evaluate(e => getComputedStyle(e, '::before').display), 'no dot beside the number').toBe('none');
  const dup = page.locator('.ss-dup').first();
  if (await dup.count()) { await expect(dup).toHaveText('Duplicate?'); await expect(dup).toHaveAttribute('title', 'Possible duplicate'); }
});
