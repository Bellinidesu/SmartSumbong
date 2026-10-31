// Local audit tool: PE=1 [OUT=dir] npx playwright test pe.spec.mjs -> Personnel (the Tanod roster) at 2048, 1440 and 1024, light and dark:
// a screenshot of each and the measured lines (row heights, cell centres on the row's middle, header-to-cell left edges, overflow).
import { test } from '@playwright/test';
test.skip(!process.env.PE, 'audit tool');
test.setTimeout(240000);
const OUT = (process.env.OUT || 'C:/Users/acele/AppData/Local/Temp/claude/c--Users-acele-SmartSumbong/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/pe') + '/';
const SIZES = (process.env.SIZES || '2048:light,2048:dark,1440:light,1024:light').split(',').map(x => x.split(':'));
for (const [W, mode] of SIZES) test(`personnel ${W} ${mode}`, async ({ page }) => {
  await page.setViewportSize({ width: +W, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto('personnel.php'); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); localStorage.removeItem('ss-people-view'); } catch (e) {} }, mode);
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(1500);
  const o = await page.evaluate(() => {
    const r1 = n => Math.round(n * 10) / 10;
    const rows = [...document.querySelectorAll('#accounts-tbody tr')];
    const ths = [...document.querySelectorAll('#ss-people thead th')];
    const heads = ths.filter(th => th.offsetParent).map(th => { const r = document.createRange(); r.selectNodeContents(th); return r1(r.getBoundingClientRect().left); });
    const per = rows.map(tr => {
      const tb = tr.getBoundingClientRect(), mid = (tb.top + tb.bottom) / 2;
      const cells = [...tr.children].filter(td => td.offsetParent).map(td => {
        const k = td.firstElementChild || td; const r = document.createRange(); r.selectNodeContents(td); const b = r.getBoundingClientRect();
        return { left: r1(b.left), dy: r1((b.top + b.bottom) / 2 - mid), cut: td.scrollWidth > td.clientWidth + 1 };
      });
      return { h: Math.round(tb.height), cells };
    });
    const hdrDx = per.map(p => p.cells.map((c, i) => r1(c.left - heads[i])).join(','));
    return { heights: per.map(p => p.h), maxCentreDy: r1(Math.max(...per.flatMap(p => p.cells.slice(1).map(c => Math.abs(c.dy))))), worst: per.map(p => p.cells.map(c => Math.abs(c.dy)).indexOf(Math.max(...p.cells.slice(1).map(c => Math.abs(c.dy))))), cut: per.map(p => p.cells.map(c => c.cut ? 1 : 0).join('')), hdrDx,
      overflowX: document.documentElement.scrollWidth > innerWidth, tiles: [...document.querySelectorAll('.p-attendance > *')].map(e => Math.round(e.getBoundingClientRect().height)) };
  });
  console.log('PE', W, mode, JSON.stringify(o));
  await page.screenshot({ path: `${OUT}pe-${mode}-${W}.png`, fullPage: true });
});
