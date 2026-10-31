// Local audit tool: TS=1 [OUT=dir] [SIZES=2048:light] npx playwright test tabs-shot.spec.mjs -> every tab of Administrative Services and the Control Room (and Settings): a screenshot of each and any horizontal overflow.
import { test } from '@playwright/test';
test.skip(!process.env.TS, 'audit tool');
test.setTimeout(240000);
const OUT = (process.env.OUT || 'C:/Users/acele/AppData/Local/Temp/claude/c--Users-acele-SmartSumbong/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/ts') + '/';
const PAGES = (process.env.PAGES || 'administrative-services.php,control-room.php').split(',');
const SIZES = (process.env.SIZES || '2048:light').split(',').map(x => x.split(':'));
for (const p of PAGES) for (const [W, mode] of SIZES) test(`${p} ${W} ${mode}`, async ({ page }) => {
  await page.setViewportSize({ width: +W, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto(p); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(1200);
  const tabs = await page.$$eval('.st-tabs [data-st]', bs => bs.map(b => b.dataset.st));
  for (const t of tabs) {
    await page.locator(`.st-tabs [data-st="${t}"]`).click(); await page.waitForTimeout(500);
    const o = await page.evaluate(() => ({ overflowX: document.documentElement.scrollWidth > innerWidth, h: document.documentElement.scrollHeight }));
    console.log('TS', p, t, W, mode, JSON.stringify(o));
    await page.screenshot({ path: `${OUT}${p.replace('.php', '')}-${t}-${mode}-${W}.png`, fullPage: true });
  }
});
