// Local audit tool: SYM=1 npx playwright test sym.spec.mjs -> the lines Notifications and the Inbox should share, at 2048 px.
import { test } from '@playwright/test';
test.skip(!process.env.SYM, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/c--Users-acele-SmartSumbong/117f062a-1bb2-459c-b509-58a1bbc686d0/scratchpad/ov/';
test('sym', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 }); await page.emulateMedia({ colorScheme: 'light' });
  await page.goto('notifications.php'); await page.evaluate(() => { try { localStorage.setItem('ss-theme', 'light'); } catch (e) {} });
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(1200);
  await page.locator('details.nf-case summary').click(); await page.waitForTimeout(300);
  const r = await page.evaluate(() => {
    const b = s => { const e = document.querySelector(s); if (!e) return null; const r = e.getBoundingClientRect(); return { l: Math.round(r.left), t: Math.round(r.top + scrollY), r: Math.round(r.right), b: Math.round(r.bottom + scrollY) }; };
    return { toolbar: b('.nf-main .p-band--calm'), rail: b('.nf-rail'), wait: b('.nf-wait'), chev: b('.nf-case summary .nf-chev'), tickRow: b('.p-notif.fr:not(summary) .p-n-x'), tickItem: b('.nf-case-items .p-n-x'),
      titleText: b('.nf-case summary .p-n-line b'), itemText: b('.nf-case-items .nf-msg'), icon: b('.nf-case summary .p-n-ico') };
  });
  console.log('SYM', JSON.stringify(r));
  await page.screenshot({ path: `${OUT}sym-notifs.png`, fullPage: true });
  await page.goto('inbox.php?new=1'); await page.waitForTimeout(800); await page.screenshot({ path: `${OUT}sym-write.png`, fullPage: true });
});
