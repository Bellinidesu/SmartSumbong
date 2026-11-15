// Local audit tool: NF2=1 npx playwright test nf-shot.spec.mjs -> Notifications, light and dark, folded rows opened.
import { test } from '@playwright/test';
test.skip(!process.env.NF2, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/nfx/';
for (const theme of ['light', 'dark']) test('notifications ' + theme, async ({ page }) => {
  await page.addInitScript((t) => { try { localStorage.setItem('ss-theme', t); localStorage.setItem('ss-side', 'min'); } catch (e) {} document.addEventListener('DOMContentLoaded', () => { document.documentElement.setAttribute('data-theme', t); document.documentElement.setAttribute('data-side', 'min'); }); }, theme);
  await page.setViewportSize({ width: 2048, height: 1100 });
  await page.goto('notifications.php', { waitUntil: 'networkidle' }); await page.waitForTimeout(800);
  await page.screenshot({ path: OUT + theme + '-top.png', clip: { x: 80, y: 0, width: 1968, height: 700 } });
  const g = page.locator('.nf-group > summary'); const n = await g.count();
  for (let i = 0; i < n; i++) await g.nth(i).click();
  await page.waitForTimeout(600);
  await page.screenshot({ path: OUT + theme + '-open.png', clip: { x: 80, y: 300, width: 1968, height: 800 } });
});
