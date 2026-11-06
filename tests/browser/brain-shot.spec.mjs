// Local audit tool: BS=1 npx playwright test brain-shot.spec.mjs -> the brain button's window, as each rung, on each page that has it.
import { test } from '@playwright/test';
test.skip(!process.env.BS, 'audit tool');
test.setTimeout(240000);
const OUT = (process.env.OUT || 'C:/Users/acele/AppData/Local/Temp/claude/c--Users-acele-SmartSumbong/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/bs') + '/';
const PAGES = (process.env.PAGES || 'cases.php,notifications.php,summary.php,home.php').split(',');
const RUNGS = [['super', ''], ['committee', 'peace_order'], ['moderator', 'peace_order']];
for (const [tier, com] of RUNGS) for (const p of PAGES) test(`${tier} ${p}`, async ({ page, context }) => {
  await context.addCookies([{ name: 'ss_tier', value: tier, url: 'http://127.0.0.1:8013' }, ...(com ? [{ name: 'ss_committee', value: com, url: 'http://127.0.0.1:8013' }] : [])]);
  await page.setViewportSize({ width: 2048, height: 1100 });
  await page.goto(p, { waitUntil: 'networkidle' });
  if (!(await page.locator('#ss-win-open').count())) { console.log('BS', tier, p, 'no brain'); return; }
  await page.locator('#ss-win-open').click(); await page.waitForTimeout(900);
  console.log('BS', tier, p, JSON.stringify({ name: await page.locator('#ss-panel .ss-win-ttl small').textContent(), sec: await page.locator('#ss-panel .mb-sec').count() }));
  await page.screenshot({ path: `${OUT}${tier}-${p.replace('.php', '')}.png` });
});
