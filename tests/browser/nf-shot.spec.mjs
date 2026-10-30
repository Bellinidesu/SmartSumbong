// Local audit tool: NF=1 npx playwright test nf-shot.spec.mjs -> Notifications at 2048 (Ace's screen), 1440 and 1024, light and dark.
import { test } from '@playwright/test';
test.skip(!process.env.NF, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/c--Users-acele-SmartSumbong/117f062a-1bb2-459c-b509-58a1bbc686d0/scratchpad/ov/';
for (const [W, mode] of [[2048, 'dark'], [2048, 'light'], [1440, 'dark'], [1024, 'dark']]) test(`nf ${W} ${mode}`, async ({ page }) => {
  await page.setViewportSize({ width: W, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto('notifications.php'); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(1500);
  const o = await page.evaluate(() => { const g = s => { const e = document.querySelector(s); if (!e) return null; const b = e.getBoundingClientRect(); return [Math.round(b.left), Math.round(b.top + scrollY), Math.round(b.right), Math.round(b.bottom + scrollY)]; }; return { main: g('.nf-main'), rail: g('.nf-rail'), wait: g('.nf-wait'), strip: g('.ss-strip'), overflowX: document.documentElement.scrollWidth > innerWidth }; });
  console.log('NF', W, mode, JSON.stringify(o));
  await page.screenshot({ path: `${OUT}nf-${mode}-${W}.png`, fullPage: true });
});
