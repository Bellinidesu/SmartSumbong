import { test } from '@playwright/test';
const CASE = 'c0000000-0000-0000-0000-000000000001';
const PAGES = ['dashboard.php', 'home.php', 'cases.php', `case.php?id=${CASE}`, 'summary.php', 'spatial.php', 'workspace.php', 'notifications.php', 'inbox.php', 'inbox.php?app=mail',
  'residents.php', 'personnel.php', 'activity.php', 'administrative-services.php', 'retirement-requests.php'];
test.skip(!process.env.MO, 'tool');
test('dom', async ({ page }) => {
  test.setTimeout(200000);
  for (const p of PAGES) {
    await page.goto(p, { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(900);
    const r = await page.evaluate(() => {
      const m = document.querySelector('main') || document.querySelector('.p-main');
      const d = (e) => e.tagName.toLowerCase() + (e.id ? '#' + e.id : '') + (e.className && typeof e.className === 'string' ? '.' + e.className.trim().split(/\s+/).slice(0, 2).join('.') : '');
      const kids = m ? [...m.children].map(d) : [];
      return { main: m ? d(m) : null, parent: m ? d(m.parentElement) : null, kids: kids.slice(0, 10), n: kids.length, body: document.body.className };
    });
    console.log(p, JSON.stringify(r));
  }
});
