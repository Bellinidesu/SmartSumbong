import { test } from '@playwright/test';
const PAGES = ['dashboard.php','cases.php','summary.php','notifications.php','inbox.php','residents.php','personnel.php','settings.php','profile.php','spatial.php','activity.php','accounts.php','case.php'];
test('coverage', async ({ page }) => {
  const used = {}, size = {};
  for (const p of PAGES) {
    await page.coverage.startCSSCoverage();
    await page.goto(p, { waitUntil: 'networkidle' }).catch(() => {});
    const cov = await page.coverage.stopCSSCoverage();
    for (const e of cov) { const k = e.url.split('/').pop().split('?')[0]; if (!/\.css$/.test(k)) continue; size[k] = e.text.length; used[k] = used[k] || new Set(); for (const r of e.ranges) for (let i = r.start; i < r.end; i++) used[k].add(i); }
  }
  for (const k of Object.keys(size)) console.log(`${k.padEnd(18)} ${Math.round(size[k]/1024)}KB  used on some page: ${Math.round(100*used[k].size/size[k])}%`);
});
