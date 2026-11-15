// Tool, not a gate: main-thread seconds per second while a page sits idle (12 Nov 2026). MO=1 npx playwright test motion-cost.spec.mjs
import { test } from '@playwright/test';
const CASE = 'c0000000-0000-0000-0000-000000000001';
const PAGES = ['dashboard.php', 'workspace.php', 'spatial.php', 'cases.php', 'residents.php', 'personnel.php', 'summary.php', `case.php?id=${CASE}`];
test.skip(!process.env.MO, 'tool');
test('cost', async ({ page }) => {
  test.setTimeout(240000);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Performance.enable');
  const get = async () => Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m => [m.name, m.value]));
  const rows = [];
  for (const p of PAGES) {
    await page.goto(p, { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(3500);
    const a = await get(); await page.waitForTimeout(6000); const b = await get();
    const s = (b.Timestamp - a.Timestamp);
    rows.push(`${p.padEnd(34)} task ${(100 * (b.TaskDuration - a.TaskDuration) / s).toFixed(1).padStart(5)}%  script ${(100 * (b.ScriptDuration - a.ScriptDuration) / s).toFixed(1).padStart(4)}%  layout ${(100 * (b.LayoutDuration - a.LayoutDuration) / s).toFixed(1).padStart(4)}%  style ${(100 * (b.RecalcStyleDuration - a.RecalcStyleDuration) / s).toFixed(1).padStart(4)}%`);
  }
  console.log('\n' + rows.join('\n'));
});
