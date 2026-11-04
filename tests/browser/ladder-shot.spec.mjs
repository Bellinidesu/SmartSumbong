// Local audit tool: LS=1 [OUT=dir] [PAGES=...] [SIZES=2048:light] npx playwright test ladder-shot.spec.mjs -> the portal as each rung sees it
// (super admin; a Kagawad of a committee with a logo and of one without; a staff member): each page, a screenshot and any horizontal overflow.
import { test } from '@playwright/test';
test.skip(!process.env.LS, 'audit tool');
test.setTimeout(240000);
const OUT = (process.env.OUT || 'C:/Users/acele/AppData/Local/Temp/claude/c--Users-acele-SmartSumbong/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/ls') + '/';
const PAGES = (process.env.PAGES || 'notifications.php,personnel.php,personnel.php?view=staff').split(',');
const SIZES = (process.env.SIZES || '2048:light').split(',').map(x => x.split(':'));
const RUNGS = [['super', ''], ['committee', 'peace_order'], ['committee', 'environment'], ['moderator', 'peace_order']];
for (const [tier, com] of RUNGS) for (const p of PAGES) for (const [W, mode] of SIZES) test(`${tier} ${com} ${p} ${W} ${mode}`, async ({ page, context }) => {
  await context.addCookies([{ name: 'ss_tier', value: tier, url: 'http://127.0.0.1:8013' }, ...(com ? [{ name: 'ss_committee', value: com, url: 'http://127.0.0.1:8013' }] : [])]);
  await page.setViewportSize({ width: +W, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto(p); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(1000);
  const o = await page.evaluate(() => ({ url: location.pathname + location.search, overflowX: document.documentElement.scrollWidth > innerWidth,
    nav: [...document.querySelectorAll('.p-nav a span:first-of-type')].map(s => s.textContent.trim()).join('|'),
    forms: document.querySelectorAll('.p-main form').length }));
  console.log('LS', tier, com, p, W, mode, JSON.stringify(o));
  await page.screenshot({ path: `${OUT}${tier}-${com || 'all'}-${p.replace(/\W+/g, '_')}-${mode}-${W}.png`, fullPage: true });
});
