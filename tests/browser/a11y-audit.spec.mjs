// Local audit tool: AA=1 npx playwright test a11y-audit.spec.mjs --workers=1
// Every page, for every rung, light and dark: all axe findings (WCAG 2.1 A and AA plus best practice), moderate and minor
// included (the suite itself fails only on serious and critical). Writes one JSON and prints a summary by rule.
import { test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import fs from 'node:fs';
test.skip(!process.env.AA, 'audit tool');
test.setTimeout(900000);
const OUT = (process.env.OUT || 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/a11y') + '/';
fs.mkdirSync(OUT, { recursive: true });
const CASE = 'c0000000-0000-0000-0000-000000000003';
const ALL = ['dashboard.php', 'home.php', 'cases.php', `case.php?id=${CASE}`, 'summary.php', 'spatial.php', 'notifications.php', 'inbox.php',
  'residents.php', 'residents.php?id=u1', 'personnel.php', 'settings.php', 'profile.php', 'activity.php', 'retirement-requests.php',
  'administrative-services.php', 'control-room.php', 'login.php'];
const RUNGS = [['super', ''], ['committee', 'peace_order'], ['moderator', 'peace_order']];

test('a11y audit', async ({ browser }) => {
  const found = {};
  for (const [tier, com] of RUNGS) for (const scheme of ['light', 'dark']) {
    const ctx = await browser.newContext({ colorScheme: scheme, viewport: { width: 1440, height: 900 } });
    await ctx.addCookies([{ name: 'ss_tier', value: tier, url: 'http://127.0.0.1:8013' }, ...(com ? [{ name: 'ss_committee', value: com, url: 'http://127.0.0.1:8013' }] : [])]);
    const page = await ctx.newPage();
    for (const p of ALL) {
      const res = await page.goto('http://127.0.0.1:8013/admin/' + p, { waitUntil: 'domcontentloaded' }).catch(() => null);
      if (!res || res.status() !== 200 || !page.url().includes(p.split('?')[0])) continue;   // a page this rung does not open
      await page.waitForLoadState('networkidle', { timeout: 6000 }).catch(() => {});
      const r = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice']).analyze();
      for (const v of r.violations) {
        const k = v.impact + ' ' + v.id;
        found[k] ??= { help: v.help, pages: new Set(), sample: v.nodes[0].target.join(' '), html: (v.nodes[0].html || '').slice(0, 160) };
        found[k].pages.add(`${p.split('?')[0]} (${tier}/${scheme})`);
      }
    }
    await ctx.close();
  }
  const rows = Object.entries(found).map(([k, v]) => ({ rule: k, help: v.help, count: v.pages.size, pages: [...v.pages].slice(0, 12), sample: v.sample, html: v.html }));
  rows.sort((a, b) => b.count - a.count);
  fs.writeFileSync(OUT + 'a11y.json', JSON.stringify(rows, null, 1));
  console.log('A11Y\n' + rows.map(r => `${r.rule} · ${r.count} page views · ${r.help} · e.g. ${r.sample}`).join('\n'));
});
