// Local audit tool: MEASURE=1 npx playwright test measure.spec.mjs -> where every dashboard card sits.
import { test } from '@playwright/test';
test.skip(!process.env.MEASURE, 'audit tool');
test.setTimeout(120000);
for (const W of [1440, 2048]) test(`dashboard ${W}`, async ({ page }) => {
  await page.setViewportSize({ width: W, height: 1100 });
  await page.emulateMedia({ colorScheme: process.env.THEME || 'light' });
  await page.goto('dashboard.php'); await page.evaluate(t => { try { localStorage.setItem('ss-theme', t); } catch (e) {} }, process.env.THEME || 'light');
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(1500);
  const r = await page.evaluate(() => {
    const q = s => [...document.querySelectorAll(s)].map(e => { const b = e.getBoundingClientRect(); return [Math.round(b.left), Math.round(b.top + scrollY), Math.round(b.right), Math.round(b.bottom + scrollY)]; });
    const o = {};
    for (const [k, s] of Object.entries({ engine: '#ss-panel', hero: '.dh-hero', status: '.dh-status', kpi: '.dh-kpi', tiles: '.dh-kpi .ss-tile', cat: '.dh-cat', com: '.dh-com', feed: '.dh-feed', eff: '.dh-grid + .p-card', 'h2 hero': '.dh-hero h2', 'h2 status': '.dh-status h2', 'h2 cat': '.dh-cat h2', 'h2 com': '.dh-com h2', 'h2 feed': '.dh-feed h2', stats: '.dh-stats', donuts: '.p-donut', lastfeed: '.dh-feedl li:last-child', lastcom: '.dh-ctab tbody tr:last-child', legend: '.dh-status .p-legend, .dh-cat .p-legend' })) o[k] = q(s);
    return o;
  });
  console.log('W', W); for (const [k, v] of Object.entries(r)) console.log(' ', k.padEnd(10), JSON.stringify(v));
  await page.screenshot({ path: `C:/Users/acele/AppData/Local/Temp/claude/c--Users-acele-SmartSumbong/117f062a-1bb2-459c-b509-58a1bbc686d0/scratchpad/dash-${process.env.THEME || 'light'}-${W}.png`, fullPage: true });
});
