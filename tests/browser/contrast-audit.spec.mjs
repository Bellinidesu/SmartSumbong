// Local audit tool: CA=1 npx playwright test contrast-audit.spec.mjs -> axe's colour-contrast rule over every main page, light and dark,
// as a super admin and as a Kagawad (the rules pass measures layout, not contrast).
import { test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
test.skip(!process.env.CA, 'audit tool');
test.setTimeout(600000);
const CASE = 'c0000000-0000-0000-0000-000000000001';
const SUPER = ['dashboard.php', 'summary.php', 'spatial.php', 'cases.php', `case.php?id=${CASE}`, 'notifications.php', 'inbox.php', 'residents.php', 'personnel.php',
  'personnel.php?view=staff', 'administrative-services.php', 'control-room.php', 'settings.php', 'profile.php', 'activity.php'];
const KAG = ['home.php', 'settings.php', 'personnel.php'];
for (const mode of ['light', 'dark']) for (const [tier, pages] of [['super', SUPER], ['committee', KAG]]) test(`contrast ${tier} ${mode}`, async ({ page, context }) => {
  if (tier !== 'super') await context.addCookies([{ name: 'ss_tier', value: tier, url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  await page.setViewportSize({ width: 2048, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto(pages[0]); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  for (const p of pages) {
    await page.goto(p, { waitUntil: 'domcontentloaded' }); await page.waitForLoadState('networkidle', { timeout: 6000 }).catch(() => {}); await page.waitForTimeout(1500);
    const r = await new AxeBuilder({ page }).withRules(['color-contrast']).analyze();
    for (const v of r.violations) for (const n of v.nodes.slice(0, 8)) console.log('CA', tier, mode, p, '::', n.target.join(' ').slice(0, 90), '::', (n.any[0]?.message || '').replace(/\s+/g, ' ').slice(0, 140));
  }
});
