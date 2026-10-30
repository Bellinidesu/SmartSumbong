// Local audit tool: CASES=1 npx playwright test cases-shot.spec.mjs -> Case Reports at three widths, and whether the table scrolls sideways.
import { test } from '@playwright/test';
test.skip(!process.env.CASES, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/c--Users-acele-SmartSumbong/117f062a-1bb2-459c-b509-58a1bbc686d0/scratchpad/ov/';
for (const [W, mode] of [[1440, 'dark'], [1440, 'light'], [2048, 'dark'], [1280, 'dark']]) test(`cases ${W} ${mode}`, async ({ page }) => {
  await page.setViewportSize({ width: W, height: 1000 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto('cases.php'); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(1500);
  const o = await page.evaluate(() => { const t = document.querySelector('table.ss-cases-t'), w = t.parentElement; const rows = [...t.querySelectorAll('tbody tr')].map(r => Math.round(r.getBoundingClientRect().height)); return { table: t.scrollWidth, box: w.clientWidth, over: t.scrollWidth > w.clientWidth + 1, cols: t.querySelectorAll('thead th').length, rows: rows.join(',') }; });
  console.log('CASES', W, mode, JSON.stringify(o));
  await page.screenshot({ path: `${OUT}cases-new-${mode}-${W}.png`, fullPage: true });
});
