// Local probe: PP=1 npx playwright test prefetch-probe.spec.mjs
// Does a hovered page link get prefetched, and is the next page then served from that prefetch (deliveryType)?
import { test } from '@playwright/test';
test.skip(!process.env.PP, 'probe');
test('prefetch probe', async ({ page }) => {
  const seen = [];
  page.on('request', r => { const h = r.headers(); if (h['sec-purpose'] || h['purpose']) seen.push([r.url().split('/').pop(), h['sec-purpose'] || h['purpose']]); });
  await page.goto('dashboard.php');
  await page.waitForLoadState('networkidle');
  const sup = await page.evaluate(() => HTMLScriptElement.supports && HTMLScriptElement.supports('speculationrules'));
  const link = page.locator('a[href="cases.php"]').first();
  await link.hover();
  await page.waitForTimeout(1500);
  console.log('supports:', sup, 'prefetch requests:', JSON.stringify(seen));
  await link.click();
  await page.waitForURL(/cases\.php/);
  console.log('deliveryType:', await page.evaluate(() => performance.getEntriesByType('navigation')[0].deliveryType));
  // an Inbox message link must never be prefetched
  await page.goto('inbox.php'); await page.waitForLoadState('networkidle'); seen.length = 0;
  const m = page.locator('a[href^="inbox.php?m="]').first();
  if (await m.count()) { await m.hover(); await page.waitForTimeout(1500); }
  console.log('inbox message link present:', await m.count(), 'prefetched:', JSON.stringify(seen));
});
