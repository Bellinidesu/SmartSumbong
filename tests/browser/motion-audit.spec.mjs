// Tool, not a gate: lists what animates on every page (12 Nov 2026). MO=1 npx playwright test motion-audit.spec.mjs
import { test } from '@playwright/test';
import fs from 'fs';
const CASE = 'c0000000-0000-0000-0000-000000000001';
const PAGES = ['dashboard.php', 'home.php', 'cases.php', `case.php?id=${CASE}`, 'summary.php', 'spatial.php', 'workspace.php', 'notifications.php', 'inbox.php', 'inbox.php?app=mail',
  'residents.php', 'personnel.php', 'settings.php', 'profile.php', 'activity.php', 'administrative-services.php', 'control-room.php', 'retirement-requests.php'];
test.skip(!process.env.MO, 'tool');
test('motion audit', async ({ page }) => {
  test.setTimeout(240000);
  const out = {};
  for (const p of PAGES) {
    await page.goto(p, { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(2500);
    out[p] = await page.evaluate(() => document.getAnimations().map(a => {
      const e = a.effect, t = e && e.target, kf = e && e.getKeyframes ? e.getKeyframes() : [];
      const props = [...new Set(kf.flatMap(k => Object.keys(k).filter(x => !['offset', 'easing', 'composite', 'computedOffset'].includes(x))))];
      const id = t ? (t.tagName.toLowerCase() + (t.id ? '#' + t.id : '') + (t.className && typeof t.className === 'string' ? '.' + t.className.trim().split(/\s+/).slice(0, 2).join('.') : '')) : '?';
      return { kind: a.constructor.name, name: a.animationName || a.transitionProperty || '', props, inf: e ? e.getComputedTiming().iterations === Infinity : false, target: id, state: a.playState };
    }));
  }
  fs.writeFileSync(process.env.TEMP + '/motion-audit.json', JSON.stringify(out, null, 1));
});
