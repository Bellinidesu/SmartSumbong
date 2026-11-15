// Local audit tool: CR2=1 npx playwright test cr-shot.spec.mjs -> Case Reports header, chooser and list, light and dark, and the chooser mid-slide.
import { test } from '@playwright/test';
test.skip(!process.env.CR2, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/crx/';
for (const theme of ['light', 'dark']) test('cases ' + theme, async ({ page }) => {
  await page.addInitScript((t) => { try { localStorage.setItem('ss-theme', t); localStorage.setItem('ss-side', 'min'); } catch (e) {} document.addEventListener('DOMContentLoaded', () => { document.documentElement.setAttribute('data-theme', t); document.documentElement.setAttribute('data-side', 'min'); }); }, theme);
  await page.setViewportSize({ width: 2048, height: 1000 });
  await page.goto('cases.php', { waitUntil: 'networkidle' }); await page.waitForTimeout(800);
  await page.screenshot({ path: OUT + theme + '-top.png', clip: { x: 80, y: 0, width: 1968, height: 560 } });
  await page.locator('.cm-chips .cm-chip').nth(1).hover(); await page.waitForTimeout(350);
  await page.screenshot({ path: OUT + theme + '-hover.png', clip: { x: 80, y: 150, width: 1968, height: 220 } });
  await Promise.all([page.waitForURL(/com=/), page.locator('.cm-chips .cm-chip').nth(1).click()]);
  await page.waitForTimeout(220);
  await page.screenshot({ path: OUT + theme + '-mid.png', clip: { x: 80, y: 150, width: 1968, height: 220 } });
  await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + theme + '-after.png', clip: { x: 80, y: 0, width: 1968, height: 560 } });
});
