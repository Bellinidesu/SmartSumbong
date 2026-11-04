// Local audit tool: EA=1 npx playwright test extra-audit.spec.mjs -> the rules pass over the pages rules-audit does not open (sign-in,
// password, request access, error, hall display, printouts, widget view), and the two tables that were taller at 1024.
import { test } from '@playwright/test';
import { auditScope } from './rules-lib.mjs';
test.skip(!process.env.EA, 'audit tool');
test.setTimeout(240000);
const OUT = (process.env.OUT || 'C:/Users/acele/AppData/Local/Temp/claude/c--Users-acele-SmartSumbong/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/extra') + '/';
const CASE = 'c0000000-0000-0000-0000-000000000001';
const PAGES = ['login.php', 'forgot-password.php', 'request-access.php', 'reset-password.php', 'change-password.php', 'error.php', 'hall.php', `complaint-print.php?id=${CASE}`, 'certificate.php', 'widget-view.php'];
for (const [W, mode] of [['2048', 'light'], ['1440', 'dark'], ['1024', 'light']]) test(`extra ${W} ${mode}`, async ({ page }) => {
  await page.setViewportSize({ width: +W, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto('login.php'); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  for (const p of PAGES) {
    await page.goto(p, { waitUntil: 'domcontentloaded' }); await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {}); await page.waitForTimeout(900);
    const rows = await auditScope(page, 'body');
    console.log('EA', W, mode, p, '->', new URL(page.url()).pathname.split('/').pop(), rows.length ? JSON.stringify(rows.map(r => r.rule + ' ' + r.where + ' :: ' + r.detail)) : 'clean');
    await page.screenshot({ path: `${OUT}${p.replace(/\W+/g, '_')}-${mode}-${W}.png` });
  }
  if (W === '1024') for (const p of ['summary.php', 'cases.php']) { await page.goto(p, { waitUntil: 'networkidle' }); await page.waitForTimeout(900); const rows = (await auditScope(page)).filter(r => r.rule === 'rowheight'); console.log('EA', W, p, 'rowheight', rows.length ? JSON.stringify(rows) : 'clean'); }
});
