// Local audit tool: RS2=1 npx playwright test rs-shot.spec.mjs -> Report Summary top, tabs, a list and the calendar, light and dark.
import { test } from '@playwright/test';
test.skip(!process.env.RS2, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/rsx/';
for (const theme of ['light', 'dark']) test('summary ' + theme, async ({ page }) => {
  await page.addInitScript((t) => { try { localStorage.setItem('ss-theme', t); localStorage.setItem('ss-side', 'min'); } catch (e) {} document.addEventListener('DOMContentLoaded', () => document.documentElement.setAttribute('data-side', 'min')); document.documentElement.setAttribute('data-theme', t); }, theme);
  await page.setViewportSize({ width: 2048, height: 1000 });
  await page.goto('summary.php?range=month', { waitUntil: 'networkidle' });
  await page.evaluate((t) => document.documentElement.setAttribute('data-theme', t), theme);
  await page.waitForTimeout(500);
  await page.screenshot({ path: OUT + theme + '-top.png', clip: { x: 80, y: 0, width: 1968, height: 760 } });
  await page.locator('#ss-jump a').nth(3).hover(); await page.waitForTimeout(400);
  await page.locator('#ss-jump a').nth(3).click(); await page.waitForTimeout(250);
  await page.screenshot({ path: OUT + theme + '-tabmid.png', clip: { x: 80, y: 380, width: 1968, height: 140 } });
  await page.waitForTimeout(600);
  await page.screenshot({ path: OUT + theme + '-tl.png', clip: { x: 80, y: 380, width: 1968, height: 600 } });
  await page.locator('#ss-jump a').nth(0).click(); await page.waitForTimeout(700);
  await page.screenshot({ path: OUT + theme + '-ledger.png', clip: { x: 80, y: 380, width: 1968, height: 500 } });
  const b = page.locator('.p-period-band .sdp-btn.sdp-month').first(); await b.click(); await page.waitForTimeout(500);
  await page.locator('.sdp-rng .sdp-d[data-d]').nth(2).click(); await page.locator('.sdp-rng .sdp-d[data-d]').nth(12).click(); await page.waitForTimeout(500);
  await page.screenshot({ path: OUT + theme + '-cal.png', clip: { x: 80, y: 80, width: 900, height: 700 } });
});
