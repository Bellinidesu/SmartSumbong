// Local audit tool: RD2=1 npx playwright test rsd-shot.spec.mjs -> Residents, list and squares, light and dark.
import { test } from '@playwright/test';
test.skip(!process.env.RD2, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/rsd/';
for (const theme of ['light', 'dark']) test((process.env.PG || 'residents') + ' ' + theme, async ({ page }) => {
  await page.addInitScript((t) => { try { localStorage.setItem('ss-theme', t); localStorage.setItem('ss-side', 'min'); } catch (e) {} document.addEventListener('DOMContentLoaded', () => { document.documentElement.setAttribute('data-theme', t); document.documentElement.setAttribute('data-side', 'min'); }); }, theme);
  await page.setViewportSize({ width: 2048, height: 1100 });
  await page.goto(process.env.PG || 'residents.php', { waitUntil: 'networkidle' }); await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + (process.env.PG ? 'p-' : '') + theme + '-list.png', clip: { x: 80, y: 0, width: 1968, height: 760 } });
  const open = page.locator('#ss-win-open');
  if (await open.count()) { await open.click(); await page.waitForTimeout(900); await page.screenshot({ path: OUT + (process.env.PG ? 'p-' : '') + theme + '-brain.png' }); await page.locator('#ss-win-close').click(); await page.waitForTimeout(500); }
  await page.locator('.ss-viewsw [data-view="sq"]').click(); await page.waitForTimeout(500);
  await page.screenshot({ path: OUT + (process.env.PG ? 'p-' : '') + theme + '-sq.png', clip: { x: 80, y: 0, width: 1968, height: 1000 } });
});
