// Local audit tool: PS=1 PAGES="inbox.php,personnel.php" npx playwright test pages-shot.spec.mjs -> each page at 2048 (Ace's screen), 1440 and 1024, dark and light; prints horizontal overflow.
import { test } from '@playwright/test';
test.skip(!process.env.PS, 'audit tool');
test.setTimeout(240000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/c--Users-acele-SmartSumbong/117f062a-1bb2-459c-b509-58a1bbc686d0/scratchpad/ov/';
const PAGES = (process.env.PAGES || 'inbox.php').split(',');
const SIZES = (process.env.SIZES || '2048:dark,2048:light,1440:dark,1024:dark').split(',').map(x => x.split(':'));
for (const p of PAGES) for (const [W, mode] of SIZES) test(`${p} ${W} ${mode}`, async ({ page }) => {
  await page.setViewportSize({ width: +W, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto(p); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(1500);
  const o = await page.evaluate(() => ({ overflowX: document.documentElement.scrollWidth > innerWidth, h: document.documentElement.scrollHeight, wide: [...document.querySelectorAll('.p-main table, .p-main .p-card')].filter(e => e.scrollWidth > e.clientWidth + 2).length }));
  console.log('PS', p, W, mode, JSON.stringify(o));
  await page.screenshot({ path: `${OUT}${p.replace(/\W+/g, '_')}-${mode}-${W}.png`, fullPage: true });
});
