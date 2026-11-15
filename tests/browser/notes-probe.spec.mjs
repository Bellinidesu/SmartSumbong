// Local audit tool: NP=1 npx playwright test notes-probe.spec.mjs -> the notes Ace relayed (Rose, Sir Kiko, the panel), each checked in
// the running portal: prints PASS/FAIL per note.
import { test, expect } from '@playwright/test';
test.skip(!process.env.NP, 'audit tool');
test.setTimeout(300000);
const CASE = 'c0000000-0000-0000-0000-000000000001';
const res = [];
const check = async (id, what, fn) => { try { const ok = await fn(); res.push(`${ok ? 'PASS' : 'FAIL'} ${id} ${what}${ok === true ? '' : ' :: ' + ok}`); } catch (e) { res.push(`FAIL ${id} ${what} :: ${String(e.message).split('\n')[0].slice(0, 120)}`); } };
test('notes', async ({ page, browser }) => {
  page.setDefaultTimeout(8000);
  await page.setViewportSize({ width: 2048, height: 1100 });
  await page.goto('dashboard.php', { waitUntil: 'networkidle' });
  await check('B1', 'no Download PDF on the Dashboard', async () => (await page.getByText(/download pdf/i).count()) === 0);
  await check('D3', 'resolution efficiency offers every category, Others included', async () => { const o = await page.$$eval('#eff_category option', os => os.map(x => x.textContent.trim())); return o.some(x => /Others/.test(x)) || JSON.stringify(o); });
  await page.goto('notifications.php', { waitUntil: 'networkidle' });
  const before = await page.locator('.p-notif-card, .nf-row, [data-nid]').count();
  await check('B3', 'Notifications search narrows the list', async () => { await page.goto('notifications.php?nq=ZZZZnotfound', { waitUntil: 'networkidle' }); const n = await page.locator('.p-notif-card, .nf-row').count(); return (n < before) || `before ${before} after ${n}`; });
  await check('B2', 'Notifications sort oldest/newest changes the order', async () => {
    await page.goto('notifications.php?nsort=newest', { waitUntil: 'networkidle' }); const a = await page.locator('.p-notif-card, .nf-row').allTextContents();
    await page.goto('notifications.php?nsort=oldest', { waitUntil: 'networkidle' }); const b = await page.locator('.p-notif-card, .nf-row').allTextContents();
    return (a.length > 1 && a[0] !== b[0]) || `rows ${a.length}`; });
  await page.goto('spatial.php', { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(2500);
  await check('D7', 'no Hotspots checkbox on the map', async () => (await page.locator('#f-hotspots').count()) === 0);
  await check('D5', 'legend lists complaint types by colour', async () => (await page.locator('#map-legend .lg-cat').count()) >= 7);
  await check('Rose 2 Nov', 'layers in the floating tab, lock holds', async () => (await page.locator('#map-search .p-row-lyr').count()) === 1);
  await page.goto('cases.php', { waitUntil: 'networkidle' });
  await check('F7', 'Case Reports filters Overdue and Escalated', async () => { const h = await page.content(); return (/status=overdue|value="overdue"/.test(h) && /status=escalated|value="escalated"/.test(h)) || 'missing'; });
  await check('P4', 'Case Reports is paged', async () => (await page.locator('.ss-pager, .p-pager, nav[aria-label*="age"]').count()) > 0);
  await check('P6', 'filter by the specific complaint under a category', async () => (await page.locator('select[name="issue"]').count()) > 0 || 'no issue filter');
  await check('P9', 'filter by what the tanod is doing', async () => /tanod=needs|tanod=active|name="tanod"/.test(await page.content()));
  await check('P1', 'notifications are not in the case register', async () => (await page.locator('.ss-cases-t .p-notif-card').count()) === 0);
  await page.goto(`case.php?id=${CASE}`, { waitUntil: 'networkidle' });
  await check('F4', 'outside offices are the five from the certificate', async () => { const o = await page.$$eval('select[name="agency"] option', os => os.map(x => x.value).filter(Boolean)); return o.length === 5 || JSON.stringify(o); });
  await check('F9', 'a case prints on its own', async () => (await page.locator('a[href^="complaint-print.php"]').count()) > 0);
  await check('F8', 'one Update status form (no separate Post an update)', async () => (await page.getByText('Post an update', { exact: true }).count()) === 0);
  await check('P8/G1', 'Update status takes proof photos', async () => (await page.locator('input[type=file][name="photos[]"]').count()) > 0);
  await check('P5', 'the case lists its concerns, each with its own status', async () => (await page.locator('.cn-row, .p-cn, [data-concern]').count()) > 0 || 'no concern rows found by selector');
  await page.goto('activity.php', { waitUntil: 'networkidle' });
  await check('P4b', 'Activity is paged', async () => (await page.locator('.ss-pager, .p-pager, nav[aria-label*="age"]').count()) > 0);
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } }); const lp = await ctx.newPage(); lp.setDefaultTimeout(8000);
  await lp.goto('http://127.0.0.1:8013/admin/login.php');
  await check('D2a', 'blank password: "Please input the correct password"', async () => { await lp.fill('input[name=email]', 'a@b.co'); await lp.locator('form button[type=submit]').first().click(); await lp.waitForLoadState(); return /input the correct password/i.test(await lp.content()); });
  await check('D2b', 'blank email: "Please input a valid email address"', async () => { await lp.fill('input[name=email]', ''); await lp.fill('input[name=password]', 'x'); await lp.locator('form button[type=submit]').first().click(); await lp.waitForLoadState(); return /input a valid email/i.test(await lp.content()); });
  await ctx.close();
  console.log('\n' + res.join('\n'));
});
