// A local audit tool, not part of CI: SHOTS=1 npx playwright test shots.spec.mjs -> screenshots of every page in light and dark.
import { test } from '@playwright/test';
import fs from 'node:fs';

const CASE = 'c0000000-0000-0000-0000-000000000001';
const OUT = process.env.SHOTS_DIR || 'shots';
const PAGES = ['dashboard.php', 'cases.php', `case.php?id=${CASE}`, 'summary.php', 'notifications.php', 'inbox.php', 'residents.php', 'personnel.php', 'personnel.php?view=staff',
  'settings.php', 'profile.php', 'profile.php?edit=1', 'activity.php', 'administrative-services.php', 'control-room.php', 'inbox.php?new=1', 'inbox.php?m=41'];
test.skip(!process.env.SHOTS, 'audit tool');
fs.mkdirSync(OUT, { recursive: true });
for (const mode of ['light', 'dark']) {
  for (const path of PAGES) {
    test(`${mode} ${path}`, async ({ page }) => {
      await page.emulateMedia({ colorScheme: mode });
      await page.goto(path); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
      await page.reload({ waitUntil: 'domcontentloaded' }); await page.waitForTimeout(1500);
      await page.screenshot({ path: `${OUT}/${mode}-${path.replace(/[^a-z0-9]+/gi, '_')}.png`, fullPage: true });
    });
  }
}
