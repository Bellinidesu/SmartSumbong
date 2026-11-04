// Local audit tool: RS=1 npx playwright test rose-shot.spec.mjs -> Rose's 2 Nov notes: the Spatial floating tab with its layers row and its lock,
// and the Report Summary range picker taking back the first day.
import { test, expect } from '@playwright/test';
test.skip(!process.env.RS, 'audit tool');
test.setTimeout(120000);
const OUT = (process.env.OUT || 'C:/Users/acele/AppData/Local/Temp/claude/c--Users-acele-SmartSumbong/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/rs') + '/';
for (const [W, mode] of [['2048', 'light'], ['1440', 'dark']]) test(`spatial ${W} ${mode}`, async ({ page }) => {
  await page.setViewportSize({ width: +W, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto('spatial.php'); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); localStorage.setItem('ss-map-pinned', '1'); } catch (e) {} }, mode);
  await page.reload(); await page.waitForTimeout(4000);
  await page.mouse.move(W / 2, 900); await page.mouse.down(); await page.mouse.move(W / 2 + 60, 860, { steps: 6 }); await page.mouse.up();   // press and drag on the map, outside the tab
  await page.waitForTimeout(700);
  const rows = await page.evaluate(() => [...document.querySelectorAll('#map-search .p-row')].map(r => Math.round(r.getBoundingClientRect().height)));
  console.log('RS', W, mode, 'locked rows after a drag', JSON.stringify(rows), 'layers btn hidden', await page.locator('#layers-btn').isHidden());
  await page.screenshot({ path: `${OUT}spatial-${mode}-${W}.png` });
});
test('summary range take-back', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto('summary.php'); await page.waitForTimeout(800);
  await page.locator('#period-form .sdp-btn').first().click();
  const day = page.locator('.sdp-rng .sdp-d[data-d]').nth(9);
  await day.click(); await page.waitForTimeout(200);
  console.log('RS after one press', await page.locator('.sdp-rng .sdp-rt').textContent());
  await page.screenshot({ path: `${OUT}summary-picked.png` });
  await day.click(); await page.waitForTimeout(200);
  console.log('RS after the same day again', await page.locator('.sdp-rng .sdp-rt').textContent(), 'apply disabled', await page.locator('.sdp-rng [data-go]').isDisabled());
  await day.click(); await page.locator('.sdp-rng .sdp-d[data-d]').nth(14).click(); await page.waitForTimeout(200);
  console.log('RS range', await page.locator('.sdp-rng .sdp-rt').textContent());
  await page.locator('.sdp-rng [data-clear]').click(); await page.waitForTimeout(200);
  console.log('RS after Clear', await page.locator('.sdp-rng .sdp-rt').textContent());
  await page.screenshot({ path: `${OUT}summary-cleared.png` });
});
