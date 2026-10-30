// Local audit tool: ALIGN=1 npx playwright test align.spec.mjs -> measured alignment lines on Notifications and Personnel at 2048.
import { test } from '@playwright/test';
test.skip(!process.env.ALIGN, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/c--Users-acele-SmartSumbong/117f062a-1bb2-459c-b509-58a1bbc686d0/scratchpad/ov/';
test('align', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 }); await page.emulateMedia({ colorScheme: 'light' });
  await page.goto('notifications.php'); await page.evaluate(() => { try { localStorage.setItem('ss-theme', 'light'); } catch (e) {} });
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(1200);
  await page.locator('details.nf-case summary').click(); await page.waitForTimeout(300);
  const n = await page.evaluate(() => {
    const L = s => { const e = document.querySelector(s); if (!e) return null; const r = e.getBoundingClientRect(); return Math.round(r.left * 10) / 10; };
    const C = s => { const e = document.querySelector(s); if (!e) return null; const r = e.getBoundingClientRect(); return Math.round((r.left + r.right) / 2 * 10) / 10; };
    const T = s => { const e = document.querySelector(s); if (!e) return null; const r = document.createRange(); r.selectNodeContents(e); return Math.round(r.getBoundingClientRect().left * 10) / 10; };
    return { dayLabel: T('.p-notif-list .ss-day'), iconLeft: L('.nf-case summary .p-n-ico'), iconCentre: C('.nf-case summary .p-n-ico'), dotCentre: C('.nf-case-items .nf-sev'), titleLeft: T('.nf-case summary .p-n-line b'), msgLeft: T('.nf-case-items .nf-msg'), buttonLeft: L('.nf-case-act .p-btn') };
  });
  console.log('NOTIF', JSON.stringify(n));
  await page.goto('personnel.php'); await page.waitForTimeout(1500);
  const p = await page.evaluate(() => {
    const rows = [...document.querySelectorAll('#accounts-tbody tr')];
    const out = rows.map(r => { const h = Math.round(r.getBoundingClientRect().height); const bs = [...r.querySelectorAll('td:nth-last-child(2) .p-badge')].map(b => Math.round(b.getBoundingClientRect().top)); const lines = new Set(bs).size; const pill = r.querySelector('.cm-pill'); let dotDy = null; if (pill) { const d = pill.querySelector('i') || null; const pr = pill.getBoundingClientRect(); dotDy = d ? Math.round(d.getBoundingClientRect().top - pr.top) : null; } const em = r.querySelector('td.ss-em'); return { h, statusLines: lines, dotDy, emailCut: em ? em.scrollWidth > em.clientWidth : null }; });
    return out;
  });
  console.log('PERS', JSON.stringify(p));
  await page.screenshot({ path: `${OUT}align-pers.png`, fullPage: true });
});
