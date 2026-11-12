// Local audit tool: SD=1 npx playwright test sd-shot.spec.mjs -> Spatial Distribution at 2048, light and dark: at rest and with each panel open.
import { test } from '@playwright/test';
test.skip(!process.env.SD, 'audit tool');
test.setTimeout(180000);
const OUT = process.env.SDOUT || 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/sd/';
const TAG = process.env.SDTAG || 'now';
for (const mode of ['light', 'dark']) test(`sd ${mode}`, async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto('spatial.php'); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(2500);
  const shot = async (n) => { await page.waitForTimeout(700); await page.screenshot({ path: `${OUT}${TAG}-${mode}-${n}.png` }); };
  await shot('1rest');
  for (const [id, n] of [['#layers-btn', '2layers'], ['#smart-toggle', '3smart'], ['#cc-toggle', '4command'], ['#incident-toggle', '5cases'], ['#legend-toggle', '6legend']]) {
    const el = page.locator(id); if (await el.count() === 0) continue;
    await el.click({ timeout: 4000 }).catch(() => {}); await shot(n);
    await page.keyboard.press('Escape'); await el.click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(300);
  }
});
