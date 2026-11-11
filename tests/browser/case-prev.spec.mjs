// Local audit tool: CP=1 npx playwright test case-prev.spec.mjs -> the case page, top to bottom, at 2048 px, light and dark.
import { test } from '@playwright/test';
test.skip(!process.env.CP, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/cp/';
for (const [W, mode] of [[2048, 'light'], [2048, 'dark'], [1440, 'light']]) test(`case ${W} ${mode}`, async ({ page }) => {
  await page.setViewportSize({ width: W, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto('case.php?id=c0000000-0000-0000-0000-000000000001');
  await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(1500);
  await page.screenshot({ path: `${OUT}case-${mode}-${W}.png`, fullPage: true });
});
