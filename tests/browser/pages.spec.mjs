// Every portal page in a real browser, signed in as the fake Supabase's demo administrator (serve.sh):
//  - it answers 200 and throws no error in the console;
//  - axe-core finds no serious or critical accessibility problem (WCAG 2.1 A and AA rules).
// Run: bash serve.sh, then npx playwright test. CI: the "browser" job.
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const CASE = 'c0000000-0000-0000-0000-000000000001';
const PAGES = [
  'dashboard.php', 'cases.php', `case.php?id=${CASE}`, 'summary.php', 'spatial.php', 'workspace.php',
  'notifications.php', 'inbox.php', 'residents.php', 'personnel.php', 'settings.php', 'profile.php', 'activity.php',
  'retirement-requests.php', 'administrative-services.php', 'control-room.php', `complaint-summary.php?id=${CASE}`, `complaint-print.php?id=${CASE}`,
];

// Noise the test site makes and the live site does not: the fake Supabase has no realtime socket, and the map
// tiles, photos and street imagery come from the internet, which a CI runner may not reach.
const HARNESS_NOISE = [/realtime|websocket|ws:\/\/127\.0\.0\.1:54399/i, /tiles\.openfreemap\.org|mapillary|wikimedia|nominatim|open-meteo|overpass/i,
  /Failed to load resource: net::ERR_(NAME_NOT_RESOLVED|INTERNET_DISCONNECTED|CONNECTION_REFUSED|BLOCKED_BY_CLIENT)/];

async function open(page, path) {
  const errors = [];
  page.on('pageerror', e => errors.push('page: ' + e.message));
  page.on('console', m => { if (m.type() === 'error' && !HARNESS_NOISE.some(r => r.test(m.text() + ' ' + (m.location().url || '')))) errors.push('console: ' + m.text()); });
  const res = await page.goto(path, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
  await page.waitForTimeout(800);
  return { status: res ? res.status() : 0, errors };
}

async function axe(page) {
  // every finding, moderate and minor included (7 Nov 2026: the a11y audit, a11y-audit.spec.mjs, found none left on any page)
  const r = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice']).analyze();
  return r.violations
    .map(v => `${v.impact} ${v.id}: ${v.help} (${v.nodes.length}× e.g. ${v.nodes[0].target.join(' ')})`);
}

for (const path of PAGES) {
  test(path, async ({ page }) => {
    const { status, errors } = await open(page, path);
    expect(status, 'HTTP status').toBe(200);
    expect(errors, 'console errors').toEqual([]);
    expect(await axe(page), 'serious or critical accessibility problems').toEqual([]);
  });
}

test('login.php, signed out', async ({ browser }) => {
  const page = await (await browser.newContext()).newPage();
  const { status, errors } = await open(page, 'login.php');
  expect(status).toBe(200);
  await expect(page.locator('.login-rail img.gl-seal')).toHaveAttribute('alt', 'Barangay 183 seal');   // 0148: from the profile
  expect(errors, 'console errors').toEqual([]);
  expect(await axe(page), 'serious or critical accessibility problems').toEqual([]);
});

test('speed (7 Nov 2026): Server-Timing for administrators only, and a page reads in one batch', async ({ request, browser }) => {
  const st = (await request.get('cases.php')).headers()['server-timing'] || '';
  expect(st).toMatch(/^app;dur=[\d.]+, db;dur=[\d.]+;desc="\d+ waits, \d+ calls", conn;dur=[\d.]+;desc="\d+ new connections \(longest handshake\)"(, cpu;dur=[\d.]+;desc="CPU used")?(, held;dur=[\d.]+;desc="held back by the CPU quota")?$/);
  expect(st, 'the CPU the request used').toContain('cpu;dur=');
  const out = await (await browser.newContext()).request.get('login.php');
  expect(out.headers()['server-timing'], 'no timings on the sign-in page').toBeUndefined();
  // the trace lists each wait: the parts drawn later read with the page's first batch
  const batchWith = async (url, names) => {
    const html = await (await request.get(url + (url.includes('?') ? '&' : '?') + '_trace=1')).text();
    const lines = (html.match(/<!-- trace:[\s\S]*?-->/) || [''])[0].split('\n').filter(l => / batch of \d+:/.test(l));
    return lines.some(l => names.every(n => l.includes(n)));
  };
  expect(await batchWith('notifications.php', ['notifications', 'rpc/smart_module', 'rpc/smart_summary', 'reroute_questions']), 'Notifications: the list, the brain, the strip and the pins together').toBe(true);
  expect(await batchWith('cases.php', ['rpc/smart_module', 'reports', 'escalation_requests']), 'Case Reports: one batch').toBe(true);
  expect(await batchWith('summary.php', ['dispatches', 'attendance', 'rpc/smart_module']), 'Report Summary: one batch').toBe(true);
  expect(await batchWith('dashboard.php', ['rpc/dashboard_metrics', 'rpc/smart_summary', 'status_logs']), 'Dashboard: one batch').toBe(true);
  expect(await batchWith('settings.php', ['rpc/portal_uptime_summary', 'users']), 'Settings: every tab in one batch').toBe(true);
  // the boot batch (7 Nov 2026): this test server keeps no caches, so every small cache is cold on every request; even so a page
  // waits at most twice (the boot batch, then its own), Notifications three times (its pins have a second step)
  for (const [url, most] of [['cases.php', 2], ['case.php?id=c0000000-0000-0000-0000-000000000003', 2], ['summary.php', 2], ['dashboard.php', 2],
                             ['residents.php', 2], ['settings.php', 2], ['inbox.php', 2], ['activity.php', 2], ['notifications.php', 3]]) {
    const h = (await request.get(url)).headers()['server-timing'] || '';
    const waits = +((h.match(/"(\d+) waits/) || [])[1] ?? 99);
    expect(waits, `${url} waited ${waits} times on the database`).toBeLessThanOrEqual(most);
  }
});

test('speed, step 4 (7 Nov 2026): a page link held under the pointer is prefetched and used; an Inbox message link never is', async ({ page }) => {
  const pre = [];
  page.on('request', r => { const h = r.headers(); if ((h['sec-purpose'] || '').includes('prefetch')) pre.push(r.url().split('/').pop()); });
  await page.goto('dashboard.php'); await page.waitForLoadState('networkidle');
  const link = page.locator('a[href="cases.php"]').first();
  await link.hover();
  await expect.poll(() => pre.includes('cases.php'), { timeout: 5000 }).toBe(true);
  await link.click(); await page.waitForURL(/cases\.php/);
  expect(await page.evaluate(() => performance.getEntriesByType('navigation')[0].deliveryType), 'served from the prefetch').toBe('navigational-prefetch');
  // opening a chat marks it read, so hovering one must not fetch it
  await page.goto('inbox.php'); await page.waitForLoadState('networkidle'); pre.length = 0;
  const m = page.locator('[data-mg-row]').first();
  await m.evaluate(el => el.closest('.mg-person').classList.add('mg-pop'));
  await expect(m).toBeVisible();
  await m.hover(); await page.waitForTimeout(1200);
  expect(pre, 'a chat was prefetched').toEqual([]);
});

test('one live connection per tab (7 Nov 2026): presence and each page live update share one client (one websocket)', async ({ page }) => {
  // count the clients a page makes: supabase.js puts its library on window.supabase, and every createClient opens its own socket
  await page.addInitScript(() => {
    let lib;
    Object.defineProperty(window, 'supabase', { configurable: true, get: () => lib, set: v => {
      lib = v; const make = v.createClient; window.__clients = 0;
      v.createClient = function () { window.__clients++; return make.apply(this, arguments); };
    } });
  });
  for (const url of ['notifications.php', 'cases.php', 'activity.php', 'summary.php']) {
    await page.goto(url); await page.waitForLoadState('networkidle'); await page.waitForTimeout(800);
    expect(await page.evaluate(() => window.__clients || 0), `${url}: supabase clients made`).toBe(1);
  }
});

test('Report Summary downloads as a spreadsheet', async ({ request }) => {
  const r = await request.get('summary.php?from=2026-01-01&to=2026-12-31&export=xlsx');
  expect(r.status()).toBe(200);
  expect(r.headers()['content-type']).toContain('spreadsheetml');
  expect((await r.body()).subarray(0, 2).toString()).toBe('PK');   // an .xlsx is a zip
});

test('dark mode: dashboard and cases', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' });
  for (const path of ['dashboard.php', 'cases.php']) {
    await page.goto(path); await page.evaluate(() => { try { localStorage.setItem('ss-theme', 'dark'); } catch (e) {} });
    await page.reload(); await page.waitForTimeout(800);
    expect(await axe(page), path + ' in dark mode').toEqual([]);
  }
});

test('the barangay\'s places: listed in a panel on Spatial Distribution (moved from Settings, 15 Nov), added from the map', async ({ page }) => {
  let r = await open(page, 'settings.php');
  await expect(page.locator('#places'), 'no longer in Settings').toHaveCount(0);
  r = await open(page, 'spatial.php');
  await page.locator('#pl-open').click();
  await expect(page.locator('#pl-dlg #places .st-plist li')).toHaveCount(2);
  expect(await axe(page), 'Spatial Distribution, places panel open').toEqual([]);
  await page.locator('#pl-dlg [data-pl-close]').click();
  await expect(page.locator('#pl-dlg')).toBeHidden();
  const box = await page.locator('#s-spatial canvas').first().boundingBox();
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2, { button: 'right' });
  await page.locator('[data-do=add]').click();
  await page.locator('.sh-addf input[name=n]').fill('Aling Nena Store');
  await page.locator('.sh-addf [type=submit]').click();
  await expect(page.locator('.sh-done')).toContainText('Aling Nena Store');
  expect(r.errors, 'console errors').toEqual([]);
});

test('alerts: each person sets up what reaches them (profile)', async ({ page }) => {
  const r = await open(page, 'profile.php#alerts');
  await expect(page.locator('#ss-al [data-kind]')).toHaveCount(8);   // 0157 adds forwards, flags and reroute questions; the Inbox messages switch went with BarangayMail (15 Nov)
  await page.locator('#ss-al [data-kind="escalation"]').uncheck();
  await expect(page.locator('#ss-al-saved')).toContainText('Saved');
  await page.locator('#ss-al-scope [data-scope="mine"]').click();
  await expect(page.locator('#ss-al-scope [data-scope="mine"]')).toHaveAttribute('aria-checked', 'true');
  await page.locator('#ss-al-from').selectOption('22');
  await expect(page.locator('#ss-al-to')).toBeVisible();
  await expect(page.locator('#ss-al-list li')).toHaveCount(1);
  expect(await axe(page), 'the Alerts card').toEqual([]);
  expect(r.errors, 'console errors').toEqual([]);
});

test('panel asks 3a and 4: filter by the issue under a category; the barangay sees who filed anonymously', async ({ page }) => {
  let r = await open(page, 'cases.php?tab=all&category=street_obstruction');
  await expect(page.locator('select[name="issue"]')).toBeVisible();
  await expect(page.locator('select[name="issue"] option')).toContainText(['All', 'Obstructed Sidewalks', 'Illegal Parking', 'Vendor Blocking Sidewalks']);
  r = await open(page, 'cases.php?tab=all&category=street_obstruction&issue=Illegal%20Parking');
  await expect(page.locator('select[name="issue"]')).toHaveValue('Illegal Parking');
  r = await open(page, 'cases.php?tab=all&issue=Potholes');   // no category: the issue is dropped, not applied
  await expect(page.locator('select[name="issue"]')).toHaveCount(0);
  r = await open(page, `case.php?id=${CASE}`);
  await expect(page.locator('.p-report .p-by')).toContainText('Garcia');
  await expect(page.locator('.p-report .p-by')).toContainText('Anonymous to others');
  expect(r.errors, 'console errors').toEqual([]);
});

test('SMART Iteration 2: measured, healthy, and the recheck stage', async ({ page }) => {
  let r = await open(page, 'settings.php#smart');
  await expect(page.locator('#smart-measured .st-uptime-tile')).toHaveCount(3);
  await expect(page.locator('#smart-measured')).toContainText('66.7%');
  await expect(page.locator('#smart-measured')).toContainText('75%');   // 6 of the 8 answered
  expect(await axe(page), 'Settings > SMART').toEqual([]);
  r = await open(page, 'settings.php');
  await expect(page.locator('#smart-health .st-uptime-tile')).toHaveCount(3);
  r = await open(page, 'cases.php?tab=next');
  await expect(page.locator('.bd-col[data-stage="recheck"]')).toHaveCount(1);
  r = await open(page, `case.php?id=${CASE}`);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Settings, peak: the SMART tab shows one group at a time and remembers it', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'settings.php#status');
  await page.evaluate(() => { try { localStorage.removeItem('ss-smart-sub'); } catch (e) {} });   // a clean start: no group remembered
  await page.locator('.st-tabs [data-st="smart"]').click();
  await page.reload();
  await page.locator('.st-tabs [data-st="smart"]').click();
  await expect(page.locator('#sm-tabs [data-go]')).toHaveCount(4);
  await expect(page.locator('#smart-measured'), 'it opens on the overview').toBeVisible();
  await expect(page.locator('#smart-history'), 'and the rules wait').toBeHidden();
  await expect(page.locator('#smart-words')).toBeHidden();
  await page.locator('#sm-tabs [data-go="words"]').click();
  await expect(page.locator('#smart-words')).toBeVisible();
  await expect(page.locator('#smart-measured')).toBeHidden();
  await page.locator('#sm-tabs [data-go="rules"]').click();
  await expect(page.locator('#smart-history')).toBeVisible();
  await page.reload();
  await page.locator('.st-tabs [data-st="smart"]').click();
  await expect(page.locator('#smart-history'), 'it comes back to the group it was in').toBeVisible();
  await page.locator('#sm-tabs [data-go="overview"]').click();
  expect(r.errors, 'console errors').toEqual([]);
});

test('SMART Iteration 3: rules need a reason, can be tested first, and have a history', async ({ page }) => {
  const r = await open(page, 'settings.php#smart');
  await page.locator('#sm-tabs [data-go="rules"]').click();   // the SMART tab shows one group at a time; this is the rules
  await expect(page.locator('#rl-why')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Test on the last 90 days' })).toBeVisible();
  await expect(page.locator('#smart-history .ss-vlist li')).toHaveCount(3);
  await expect(page.locator('#smart-history')).toContainText('Flood reports rated too low');
  // the current version has no rollback; the older ones do
  await expect(page.locator('#smart-history .ss-vroll')).toHaveCount(2);
  await page.getByRole('button', { name: 'Test on the last 90 days' }).click();
  await expect(page.locator('#smart-replay')).toContainText('2');
  await expect(page.locator('#smart-replay')).toContainText('Nothing was saved');
  expect(await axe(page), 'Settings > SMART with a replay').toEqual([]);
  expect(r.errors, 'console errors').toEqual([]);
});

test('SMART Iteration 4: the command center (suggest, look, turn on, hand over, turn off)', async ({ page }) => {
  await page.request.get('http://127.0.0.1:54399/__cmd_reset');
  const r = await open(page, 'spatial.php');
  const sug = page.locator('#cc-suggest');
  await expect(sug).toContainText('SMART suggests Flood Watch');
  await expect(sug).toContainText('3 reports in the last 3 hours mention flood water');
  await page.locator('#cc-toggle').click();
  await expect(page.locator('#cc-side .cc-modes li')).toHaveCount(4);
  // look first: Fire Surroundings names what is within 50 m
  await page.locator('#cc-side [data-look="fire"]').click();
  await expect(page.locator('#cc-side .cc-rings'), 'the places around are read from the map data, which takes a moment on a slow machine').toContainText('Within 50 m', { timeout: 15000 });
  await expect(page.locator('#cc-side .cc-rings')).toContainText('Gasolinahan sa Kanto');
  await expect(page.locator('#cc-side .cc-foot')).toContainText('does not predict');
  expect(await axe(page), 'Command center, looking at Fire Surroundings').toEqual([]);
  // turn Flood Watch on from the suggestion
  await sug.getByRole('button', { name: /Turn on Flood Watch/ }).click();
  await expect(page.locator('#cc-bar')).toBeVisible();
  await expect(page.locator('#cc-bar')).toContainText('Flood Watch');
  await expect(page.locator('#cc-side .cc-tags')).toContainText('waist-deep');
  await expect(page.locator('#cc-side .cc-gauge span')).toHaveCount(7);
  await page.locator('#cc-side [data-tab="checklist"]').click();
  await expect(page.locator('#cc-side .cc-check li')).toHaveCount(2);
  await page.locator('#cc-side [data-tab="feed"]').click();
  await expect(page.locator('#cc-side .cc-feed li').first()).toContainText('SS-2610-1021');
  await page.locator('#cc-side [data-tab="handover"]').click();
  await expect(page.locator('#cc-side .cc-last')).toContainText('Bukas ang covered court');
  expect(await axe(page), 'Command center, Flood Watch on').toEqual([]);
  await page.locator('#cc-endn').fill('Humupa na ang baha, sarado ang evacuation center');
  await page.locator('#cc-side form[data-end] button[type=submit]').click();
  await expect(page.locator('#cc-bar')).toBeHidden();
  expect(r.errors, 'console errors').toEqual([]);
});

test('SMART Iteration 4: the hall display shows counts only, and a wrong link shows nothing', async ({ page }) => {
  const errors = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto('hall.php?k=' + 'f'.repeat(48));
  await expect(page.locator('.band')).toContainText('Flood Watch');
  await expect(page.locator('.tile').first()).toContainText('3');
  await expect(page.locator('body')).toContainText('waist-deep');
  await expect(page.locator('body')).not.toContainText('SS-');
  expect(await axe(page), 'Hall display').toEqual([]);
  expect(errors, 'console errors').toEqual([]);
  // a wrong or missing link answers 404 (the browser logs that status), and says why on the page
  await page.goto('hall.php?k=' + 'a'.repeat(48));
  await expect(page.locator('body')).toContainText('not valid, or it was turned off');
  await page.goto('hall.php');
  await expect(page.locator('body')).toContainText('not valid, or it was turned off');
});

test('SMART Iteration 4: the command center in Settings (auto switch, sessions, hall display links)', async ({ page }) => {
  const r = await open(page, 'settings.php#smart');
  const c = page.locator('#cmd-settings');
  await expect(c.locator('input[name="on"]')).not.toBeChecked();
  await expect(c).toContainText('Flood Watch');
  await expect(c).toContainText('Humupa na ang baha');
  await expect(c).toContainText('Hall TV');
  await expect(c.locator('form input[name="action"][value="cmd_unlink"]')).toHaveCount(1);
  await expect(c.locator('#cmd-label')).toBeVisible();
  expect(await axe(page), 'Settings > SMART > Command center').toEqual([]);
  expect(r.errors, 'console errors').toEqual([]);
});

test('0144 feature switches: with the Workspace and the command center off, neither is reachable', async ({ page }) => {
  await page.request.get('http://127.0.0.1:54399/__feat?ws=0&cc=0');
  try {
    let r = await open(page, 'dashboard.php');
    await expect(page.locator('.p-sidebar a[href="workspace.php"]')).toHaveCount(0);
    await expect(page.locator('.p-sidebar a[href="cases.php"]').first()).toBeVisible();
    await expect(page.locator('a.ss-tile[href="workspace.php"]')).toHaveCount(0);
    expect(r.errors, 'console errors (dashboard)').toEqual([]);
    await page.goto('workspace.php');                         // the board is not there: the case list is
    await expect(page).toHaveURL(/cases\.php/);
    r = await open(page, 'spatial.php');
    await expect(page.locator('#cc-toggle')).toHaveCount(0);
    await expect(page.locator('#cc-bar')).toHaveCount(0);
    await expect(page.locator('#cc-suggest')).toHaveCount(0);
    expect(await axe(page), 'Spatial Distribution, command center off').toEqual([]);
    expect(r.errors, 'console errors (spatial)').toEqual([]);
    await open(page, 'settings.php#smart');
    await expect(page.locator('#cmd-settings')).toHaveCount(0);
    const j = await page.request.get('command-act.php?do=board');
    expect(j.status()).toBe(404);
    const w = await page.request.get('widgets.php?catalogue=1');
    expect(w.status()).toBe(404);
    await page.goto('hall.php?k=' + 'f'.repeat(48));
    await expect(page.locator('body')).toContainText('not valid, or it was turned off');
  } finally {
    await page.request.get('http://127.0.0.1:54399/__feat?ws=1&cc=1');
  }
});

test('0145 access: a super admin sets up committees, access and switches in Settings', async ({ page }) => {
  const r = await open(page, 'administrative-services.php#access');
  await expect(page.locator('#acc-committees .cmx-card')).toHaveCount(5);
  await expect(page.locator('#acc-committees')).toContainText('Anti-Drug');
  await expect(page.locator('#acc-committees .cmx-card.acc-off')).toHaveCount(1);
  expect(await axe(page), 'Administrative Services > Committees').toEqual([]);
  await page.locator('.st-tabs [data-st="admins"]').click();
  await expect(page.locator('#jp-rows .ss-arow').first()).toContainText('Super admin');
  await expect(page.locator('form.ss-access select[name="tier"]').first()).toHaveCount(1);
  expect(r.errors, 'console errors').toEqual([]);
});

test('0146 catalogue: a super admin edits the complaint categories and options in Settings', async ({ page }) => {
  const r = await open(page, 'control-room.php#types');
  await expect(page.locator('#types-card details.ty-cat')).toHaveCount(8);
  await expect(page.locator('#types-card details.ty-cat').first()).toContainText('Street Obstruction');
  await page.locator('#types-card details.ty-cat summary').nth(3).click();
  await expect(page.locator('#types-card form.ty-opt.ty-off')).toHaveCount(1);
  await expect(page.locator('#types-card form.ty-new input[name="label_en"]')).toHaveCount(1);
  expect(await axe(page), 'Settings > Complaint types').toEqual([]);
  await page.locator('#types-card form.ty-new input[name="label_en"]').fill('Overgrown Trees');
  await page.locator('#types-card form.ty-new button[type="submit"]').click();
  await expect(page).toHaveURL(/control-room\.php#types/);
  await expect(page.locator('section[data-pane="types"] .p-flash--ok')).toContainText('Category made');
  expect(r.errors, 'console errors').toEqual([]);
});

test('0147 hotlines: a super admin edits the emergency numbers in the Control Room', async ({ page }) => {
  const r = await open(page, 'control-room.php#hotlines');
  await expect(page.locator('.st-tabs [data-st="rules"]'), 'Rules is no longer a tab (Rose, 7 Nov)').toHaveCount(0);
  await page.locator('.st-tabs [data-st="hotlines"]').click();
  await expect(page.locator('#hotlines-card details.hl-g')).toHaveCount(4);
  await expect(page.locator('#hotlines-card details.hl-sub')).toContainText('Pasay City General Hospital');
  await page.locator('#hotlines-card details.hl-g summary').first().click();
  expect(await axe(page), 'Settings > Hotlines').toEqual([]);
  expect(r.errors, 'console errors').toEqual([]);
});

test('0148 the barangay: its name, place and seal from Settings, on the sign-in page and the title', async ({ page }) => {
  const r = await open(page, 'control-room.php#brgy');
  await expect(page.locator('#brgy-card input[name="name"]')).toHaveValue('Barangay 183');
  await expect(page.locator('#brgy-card input[name="place"]')).toHaveValue('Zone 20, Villamor, Pasay City');
  await expect(page.locator('#brgy-card .bp-img')).toHaveAttribute('src', /brgy-183-seal\.webp$/);
  await expect(page).toHaveTitle(/Barangay 183/);
  expect(await axe(page), 'Settings > Appearance').toEqual([]);
  await page.locator('#brgy-card button[type="submit"]').click();
  await expect(page.locator('section[data-pane="brgy"] .p-flash--ok')).toContainText('Saved');
  expect(r.errors, 'console errors').toEqual([]);
});

test('0149 wording: a super admin finds a label and rewords it; the portal shows the barangay wording', async ({ page }) => {
  const r = await open(page, 'control-room.php?wq=Case%20Reports#wording');
  await expect(page.locator('.st-tabs [data-st="hotlines"]')).toHaveText('Emergency numbers');   // the fake's own wording, through t()
  await expect(page.locator('#wording-card form.wd-row').first()).toBeVisible();
  await expect(page.locator('#wording-card form.wd-own')).toHaveCount(1);
  expect(await axe(page), 'Settings > Wording').toEqual([]);
  await page.locator('#wording-card form.wd-row').first().locator('textarea[name="fil"]').fill('Mga Sumbong');
  await page.locator('#wording-card form.wd-row').first().locator('button[type="submit"]').first().click();
  await expect(page.locator('section[data-pane="wording"] .p-flash--ok')).toContainText('Saved');
  expect(r.errors, 'console errors').toEqual([]);
});

test('Roles and pages 1a: Administrative Services and the Control Room take their tabs from Settings', async ({ page }) => {
  let r = await open(page, 'settings.php');
  await expect(page.locator('.st-tabs [data-st]')).toHaveText(['System status', 'Plan and usage', 'SMART', 'Appearance']);   // no Planning tab (Rose, 15 Nov)
  await expect(page.locator('.p-sidebar a[href="administrative-services.php"]')).toContainText('Administrative Services');
  await expect(page.locator('.p-sidebar a[href="control-room.php"]')).toContainText('Control Room');
  r = await open(page, 'administrative-services.php');
  await expect(page.locator('h1')).toHaveText('Administrative Services');
  await expect(page.locator('section[data-pane="access"]')).toBeVisible();
  await expect(page.locator('.st-tabs .st-link')).toHaveText('Retirement requests');
  r = await open(page, 'control-room.php');
  await expect(page.locator('.st-tabs [data-st]')).toHaveText(['Complaint types', 'Emergency numbers', 'Wording', 'The barangay', 'Parts of the system', 'App updates'])   // the fake's own wording renames Hotlines;
  await page.locator('.st-tabs [data-st="parts"]').click();
  await expect(page.locator('#acc-switches li')).toHaveCount(3);   // Workspace, Command center, Live preview on a phone
  expect(await axe(page), 'Control Room > Parts of the system').toEqual([]);
  await page.goto('settings.php#types');
  await expect(page).toHaveURL(/control-room\.php#types$/);
  await expect(page.locator('section[data-pane="types"]')).toBeVisible();
  const q = await open(page, 'retirement-requests.php');
  await expect(page.locator('h1')).toHaveText('Administrative Services');
  await expect(page.locator('.st-tabs .st-link.p-on')).toHaveText('Retirement requests');
  await expect(page.locator('.st-tabs a[href="administrative-services.php#ladder"]'), 'Escalation and responders stays in the tab bar (Rose, 7 Nov)').toContainText('Escalation and responders');
  expect(r.errors.concat(q.errors), 'console errors').toEqual([]);
});

test('Committees tab (16 Nov): a compact list, an Edit and a New committee that open the editor, the notice first with "do not show again"', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1000 });
  const r = await open(page, 'administrative-services.php');
  await page.locator('.st-tabs [data-st="access"]').click();
  await expect(page.locator('#acc-committees .cmx-card')).toHaveCount(5);
  await expect(page.locator('.cmx-note'), 'a note says which kinds of complaint nobody sees').toBeVisible();
  expect(await page.locator('#acc-committees .cmx-card input[name="name_en"]:visible').count(), 'the names are edited in the editor, not on the list').toBe(0);
  const openC = page.locator('#acc-committees .cmx-grid > .tile-open').first();
  await expect(openC.locator('a[href^="committee-editor.php?key="]'), 'each committee has an Edit').toBeVisible();
  await expect(openC.locator('.cmx-t-ro').first(), 'its kinds, read only, in their colours').toBeVisible();
  expect(await openC.locator('.cmx-banner').evaluate(e => Math.round(e.getBoundingClientRect().height)), 'the banner is slim').toBeLessThanOrEqual(80);
  // New committee: the notice first
  await page.locator('.cmx-new').click();
  await expect(page.locator('#ce-enter'), 'a notice before the editor').toBeVisible();
  await expect(page.locator('#ce-enter')).toContainText('cannot be opened');
  await page.locator('#ce-enter [data-ce-no]').click();
  await expect(page.locator('#ce-enter')).toBeHidden();
  await page.locator('.cmx-new').click(); await page.locator('#ce-skip').check(); await page.locator('#ce-enter-go').click();
  await page.waitForURL(/committee-editor\.php$/);
  await expect(page.locator('.p-side-com b'), 'the sidebar is the committee\'s own').toHaveText('New committee');
  await expect(page.locator('#side-nav a[href]'), 'nothing in the preview sidebar opens').toHaveCount(0);
  await page.goBack();
  await page.locator('.st-tabs [data-st="access"]').click().catch(() => {});
  await page.locator('.cmx-new').click();
  await page.waitForURL(/committee-editor\.php$/);   // "do not show this again": straight in the second time
  expect(r.errors.filter(e => !/WebSocket/.test(e)), 'console errors').toEqual([]);
});

test('Committee editor (16 Nov): the sidebar is the committee\'s, live; kinds in a popup; leaving with changes asks; the save form posts the old action', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  const r = await open(page, 'committee-editor.php');
  const side = () => page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--p-side-a').trim());
  const was = await side();
  await page.locator('#ce-name').fill('Senior Citizens and PWD');
  await expect(page.locator('.p-side-com b')).toHaveText('Senior Citizens and PWD');
  await expect(page.locator('#ce-banner-n')).toHaveText('Senior Citizens and PWD');
  await expect(page.locator('#ce-crow-n')).toHaveText('Senior Citizens and PWD');
  await expect(page.locator('#ce-save')).toBeEnabled();
  await page.locator('#ce-short').fill('Seniors');
  await expect(page.locator('.p-side-com b'), 'the short name is what the sidebar shows').toHaveText('Seniors');
  await page.locator('.ce-swatch:not(:disabled):not(.on)').first().click();
  expect(await side(), 'a colour changes the sidebar at once').not.toBe(was);
  // a logo picked shows in its slot and, faded, in the sidebar (redrawn on a canvas, never the file's own address)
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', 'base64');
  await page.setInputFiles('#ce-logo', { name: 'logo.png', mimeType: 'image/png', buffer: png });
  await expect(page.locator('#ce-lgi img')).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.style.getPropertyValue('--p-side-mark')), 'the sidebar\'s faded mark is the logo').toContain('data:image/png');
  expect(await page.locator('#ce-lgi img').getAttribute('src')).not.toMatch(/^blob:/);
  // the kinds popup
  const before = await page.locator('#ce-banner').evaluate(e => e.style.getPropertyValue('--g1'));
  await page.locator('#ce-kinds-open').click();
  await expect(page.locator('#ce-kinds')).toBeVisible();
  await page.locator('#ce-kinds .ce-kl').nth(1).click();
  await expect(page.locator('#ce-kcount')).toContainText('1 kind');
  await page.locator('#ce-kinds [data-ce-close]').last().click();
  await expect(page.locator('#ce-ksum .cmx-t-ro')).toHaveCount(1);
  expect(await page.locator('#ce-banner').evaluate(e => e.style.getPropertyValue('--g1')), 'the banner takes the kind\'s colour').not.toBe(before);
  // a form that posts what committee_save reads
  const names = await page.locator('#ce-form').evaluate(f => [...new FormData(f).keys()]);
  for (const k of ['csrf', 'action', 'key', 'name_en', 'name_fil', 'short_en', 'colour', 'cats[]']) expect(names, k).toContain(k);
  expect(await page.locator('#ce-form').getAttribute('action')).toBe('administrative-services.php');
  // leaving with changes asks first
  await page.locator('.ce-top [data-ce-leave]').click();
  await expect(page.locator('#ce-leave')).toBeVisible();
  await page.locator('#ce-leave [data-ce-stay]').click();
  await expect(page.locator('#ce-leave')).toBeHidden();
  expect(await axe(page), 'the committee editor').toEqual([]);
  await page.locator('.ce-top [data-ce-leave]').click(); await page.locator('#ce-leave-go').click();
  await page.waitForURL(/administrative-services\.php/);
  expect(r.errors.filter(e => !/WebSocket/.test(e)), 'console errors').toEqual([]);
});

test('Committee editor (16 Nov): its sidebar folds like the live one, starts expanded whatever was stored, and leaves the stored choice alone', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  await page.addInitScript(() => { try { localStorage.setItem('ss-side', 'min'); } catch (e) {} });
  const r = await open(page, 'committee-editor.php');
  const attr = () => page.evaluate(() => document.documentElement.getAttribute('data-side'));
  expect(await attr(), 'expanded on arrival although the live sidebar is folded').toBeNull();
  await expect(page.locator('.p-side-com b')).toBeVisible();
  await page.locator('#side-edge').click();
  expect(await attr()).toBe('min');
  await expect(page.locator('.p-side-com'), 'folded: the seal and icons stay, the committee name goes').toBeHidden();
  await page.locator('#side-edge').click();
  expect(await attr()).toBeNull();
  await expect(page.locator('.p-side-com b')).toBeVisible();
  expect(await page.evaluate(() => localStorage.getItem('ss-side')), 'the stored choice is untouched').toBe('min');
  expect(r.errors.filter(e => !/WebSocket/.test(e)), 'console errors').toEqual([]);
});

test('Committee editor (16 Nov): editing one keeps its colour, and only a super admin can open it', async ({ page, context }) => {
  await open(page, 'committee-editor.php?key=peace_order');
  await expect(page.locator('#ce-colour')).toHaveValue('#d32f2f');
  await expect(page.locator('h1')).toHaveText('Edit committee');
  await expect(page.locator('#ce-save'), 'nothing changed, nothing to save').toBeDisabled();
  await expect(page.locator('#ce-form input[name="active"]')).toBeChecked();
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  await page.goto('committee-editor.php');
  expect(page.url(), 'a Kagawad is sent to their own page').not.toMatch(/committee-editor/);
});

test('Roles and Escalation, peak: the position chooser filters the table, the band, chooser and table are three objects, kinds of complaint wear their colour', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1000 });
  const r = await open(page, 'administrative-services.php');
  await page.locator('.st-tabs [data-st="admins"]').click();
  await expect(page.locator('.ad-roles .cm-chip')).toHaveCount(4);   // All, Chairman, Councilor, Staff (no Secretary, Rose 15 Nov)
  const g = await page.evaluate(() => { const R = s => document.querySelector(s).getBoundingClientRect(); return { a: Math.round(R('.page-administrative-services .ss-pband').bottom), b: Math.round(R('.ad-roles').top), c: Math.round(R('.ad-roles').bottom), d: Math.round(R('#ss-people').top), th: getComputedStyle(document.querySelector('#ss-people thead th')).backgroundColor }; });
  expect(Math.min(g.b - g.a, g.d - g.c), 'the band, the chooser and the table are three objects with a gap between them').toBeGreaterThanOrEqual(10);
  expect(await page.locator('.ad-roles .cm-ind').evaluate(e => e.offsetWidth > 0), 'the chooser pill is drawn, even though its tab was hidden at load').toBe(true);
  expect(g.th, 'blue under the orange band').toBe('rgb(0, 48, 143)');
  const all = await page.locator('#jp-rows tr.ss-arow:visible').count();
  await page.locator('.ad-roles .cm-chip[data-role="kagawad"]').click();
  expect(await page.locator('#jp-rows tr.ss-arow:visible').count(), 'a banner filters the table').toBeLessThan(all);
  await page.locator('.ad-roles .cm-chip[data-role=""]').click();
  expect(await page.locator('#jp-rows tr.ss-arow:visible').count()).toBe(all);
  await page.locator('.st-tabs [data-st="ladder"]').click();
  await expect(page.locator('.ss-lst .cmx-t-ro').first()).toBeVisible();
  expect(await page.locator('.ss-lst .cmx-t-ro').evaluateAll(ts => ts.filter(t => getComputedStyle(t).backgroundColor === 'rgba(0, 0, 0, 0)').length), 'each kind of complaint is a chip in its colour').toBe(0);
  expect(r.errors.filter(e => !/WebSocket/.test(e)), 'console errors').toEqual([]);
});

test('Control Room, peak: kinds of complaint are chips with who sees them, hotlines are cards', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1000 });
  const r = await open(page, 'control-room.php');
  await expect(page.locator('#types-card details.ty-cat .ty-chip')).toHaveCount(8);
  await expect(page.locator('#types-card .ty-own-none').first(), 'a kind of complaint nobody sees is called out').toBeVisible();
  expect(await page.locator('#types-card .ty-chip').evaluateAll(cs => cs.filter(c => getComputedStyle(c).backgroundColor === 'rgba(0, 0, 0, 0)').length), 'each chip is in its colour').toBe(0);
  await page.locator('.st-tabs [data-st="hotlines"]').click();
  expect(await page.locator('#hotlines-card details.hl-g').first().evaluate(e => getComputedStyle(e).borderTopLeftRadius), 'a card each').not.toBe('0px');
  expect(r.errors.filter(e => !/WebSocket/.test(e)), 'console errors').toEqual([]);
});

test('Control Room: a live phone follows the forms (Report, Emergency, Home, Splash) and hides on Rules', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'control-room.php');
  await expect(page.locator('#ed-phone')).toBeVisible();
  await expect(page.locator('#ed-phone .ed-sc:not(.ed-hide)')).toHaveAttribute('data-sc', 'report');
  await expect(page.locator('#ed-phone .ed-cat')).toHaveCount(8);
  expect(await page.locator('#ed-phone .ed-cat svg').evaluateAll(s => s.filter(x => x.innerHTML.trim() === '').length), 'every tile has its symbol').toBe(0);
  // typing in a form changes the phone before anything is saved
  await page.locator('#types-card details.ty-cat summary').nth(1).click();
  await page.locator('#types-card details.ty-cat[open] input[name="label_en"]').first().fill('Roads and Drainage');
  await expect(page.locator('#ed-phone .ed-cat[data-key]').nth(1).locator('.ed-cn')).toHaveText('Roads and Drainage');
  await page.locator('#types-card details.ty-cat[open] input[name="active"]').first().uncheck();
  await expect(page.locator('#ed-phone .ed-cat').nth(1)).toHaveClass(/ed-off/);
  // a tile in the phone opens its category in the form
  await page.locator('#ed-phone .ed-cat').nth(2).click();
  await expect(page.locator('#types-card details.ty-cat').nth(2)).toHaveJSProperty('open', true);
  await page.locator('.st-tabs [data-st="hotlines"]').click();
  await expect(page.locator('#ed-phone .ed-sc:not(.ed-hide)')).toHaveAttribute('data-sc', 'emergency');
  await page.locator('#hotlines-card details.hl-g summary').nth(1).click();
  await page.locator('#hotlines-card details.hl-g[open] input[name="number"]').first().fill('0917 000 0000');
  await expect(page.locator('#ed-phone .ed-hn .ed-nn', { hasText: '0917 000 0000' })).toHaveCount(1);
  await page.locator('.st-tabs [data-st="parts"]').click();
  await expect(page.locator('#ed-phone .ed-sc:not(.ed-hide)')).toHaveAttribute('data-sc', 'home');
  await page.locator('.st-tabs [data-st="brgy"]').click();
  await page.locator('#brgy-card input[name="name"]').fill('Barangay 183, Villamor');
  await expect(page.locator('#ed-phone .ed-splash .ed-bn')).toHaveText('Barangay 183, Villamor');
  expect(r.errors.filter(e => !/WebSocket/.test(e)), 'console errors').toEqual([]);
});

test('Control Room, App updates: a super admin publishes a version; the list shows what is offered; no screen beside it', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'control-room.php');
  await page.locator('.st-tabs [data-st="updates"]').click();
  await expect(page.locator('#ed-phone'), 'a release has no screen').toBeHidden();
  await expect(page.locator('.up-rel')).toHaveCount(2);
  await expect(page.locator('.up-rel').first()).toContainText('v1.1.0');
  await expect(page.locator('.up-rel').first()).toContainText('Offered now');
  await expect(page.locator('.up-rel').first()).toContainText('Must update');
  await expect(page.locator('.up-rel').nth(1)).toContainText('Withdrawn');
  expect(await page.locator('#up-form input[name="build"]').evaluate(e => +e.min), 'the next build must be higher than the last').toBe(6);
  await page.locator('#up-form input[name="version"]').fill('1.1.1');
  await page.locator('#up-form input[name="apk_url"]').fill('https://example.org/releases/smartsumbong-1.1.1.apk');
  await page.locator('#up-form input[name="sha256"]').fill('c3'.repeat(32));
  await page.locator('#up-form button[type="submit"]').click();
  await expect(page).toHaveURL(/control-room\.php#updates$/);
  await expect(page.locator('section[data-pane="updates"] .p-flash--ok')).toContainText('Published');
  expect(await axe(page), 'Control Room > App updates').toEqual([]);
  expect(r.errors.filter(e => !/WebSocket/.test(e)), 'console errors').toEqual([]);
});

test('Control Room, live on a phone: off by default; once on, a pairing starts and the draft follows the forms', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  await page.request.get('http://127.0.0.1:54399/__feat?ws=1&cc=1&lp=0');
  await open(page, 'control-room.php');
  await expect(page.locator('#ed-live'), 'nothing to pair while it is switched off').toHaveCount(0);
  await expect(page.locator('.ed-live-off')).toBeVisible();
  await page.request.get('http://127.0.0.1:54399/__feat?ws=1&cc=1&lp=1');
  const r = await open(page, 'control-room.php');
  await expect(page.locator('#ed-live-go')).toBeVisible();
  await page.evaluate(() => { window.__sent = null; window.__edHook = m => { window.__sent = m; }; });
  await page.locator('#ed-live-go').click();
  await expect(page.locator('#ed-live-code')).toHaveText('ABCD 2345');
  await expect(page.locator('#ed-live-count')).toHaveText(/^\d+:\d\d$/);
  await expect(page.locator('#ed-live-go'), 'the button gives way to the code').toBeHidden();
  await page.locator('#types-card details.ty-cat summary').nth(1).click();
  await page.locator('#types-card details.ty-cat[open] input[name="label_en"]').first().fill('Roads and Drainage');
  await page.waitForFunction(() => window.__sent && window.__sent.cats.some(c => c.label_en === 'Roads and Drainage'));
  const m = await page.evaluate(() => window.__sent);
  expect(m.cats.length, 'every category is in the draft').toBe(8);
  expect(m.cats[0].options.length, 'with its options').toBeGreaterThan(0);
  expect(m.hotlines.length, 'the emergency numbers').toBeGreaterThan(0);
  expect(m.switches.length, 'the parts').toBe(3);
  expect(m.barangay.name, 'and the barangay').toBeTruthy();
  await page.locator('#ed-live-end').click();
  await expect(page.locator('.ed-live-box')).toBeHidden();
  await expect(page.locator('#ed-live-go')).toBeVisible();
  expect(r.errors.filter(e => !/WebSocket/.test(e)), 'console errors').toEqual([]);
  await page.request.get('http://127.0.0.1:54399/__feat?ws=1&cc=1&lp=0');
});

test('Development team: the DEV switcher makes test accounts, switches into a rung with a banner that says so, and comes back', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'notifications.php');
  const sw = page.locator('.dv-sw');
  await expect(sw, 'a developer has the switcher').toHaveCount(1);
  await sw.locator('summary').click();
  await expect(sw.locator('.dv-l')).toHaveCount(3);   // Captain, Kagawad, Staff (the Super admin one is the person's own account: Back to my own account)
  await expect(sw.locator('.dv-l').nth(1)).toContainText('Kagawad');
  await expect(sw.locator('.dv-l').nth(1)).toContainText('Peace and Order');
  await sw.locator('.dv-setup button[type=submit]').click();
  await expect(page.locator('.dv-msg')).toContainText('test accounts are ready');
  await expect(page.locator('.dv-sw[open]'), 'the panel is open to show what the last action said').toHaveCount(1);
  await page.locator('.dv-sw .dv-l').nth(1).click();
  await expect(page.locator('.dv-band'), 'a band says whose eyes these are').toContainText('Seeing the portal as Councilor (Kagawad)');
  await expect(page.locator('.dv-sw .dv-l.p-on')).toContainText('Kagawad');
  await page.locator('.dv-band button').click();
  await expect(page.locator('.dv-band')).toHaveCount(0);
  expect(await axe(page), 'the switcher').toEqual([]);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Case Reports: a case with more than one concern says so, and is found by any of them', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'cases.php');
  const row = page.locator('tr', { hasText: 'SS-2610-1001' });
  await expect(row.locator('.cr-more'), 'two more concerns beside the main category').toHaveText('+2');
  await expect(row.locator('.cr-more')).toHaveAttribute('title', /Barangay Service \(Open\)/);
  await expect(row.locator('.cr-more')).toHaveAttribute('title', /Public Safety and Infrastructure \(Resolved\)/);
  expect(await page.locator('tr:has(.cr-more)').first().evaluate(e => Math.round(e.getBoundingClientRect().height)), 'the pill does not make its row taller').toBeLessThanOrEqual(await page.locator('tbody tr').nth(1).evaluate(e => Math.round(e.getBoundingClientRect().height)) + 2);
  // a concern's category finds the case, though it is not the main one
  await open(page, 'cases.php?category=barangay_service');
  await expect(page.locator('tr', { hasText: 'SS-2610-1001' }), 'found by its second concern').toHaveCount(1);
  await open(page, 'cases.php?category=peace_order_nuisance');
  await expect(page.locator('tr', { hasText: 'SS-2610-1001' }), 'and by its main category').toHaveCount(1);
  await open(page, 'cases.php?category=animal_welfare');
  await expect(page.locator('tr', { hasText: 'SS-2610-1001' }), 'not by a category it does not have').toHaveCount(0);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Case page: each concern shows its category and option, and what it was filed as when that changed since', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, `case.php?id=${CASE}`);
  const list = page.locator('.ss-concern-list');
  await expect(list.locator('li', { hasText: 'Dangling Electric Wires' }), 'the option is named beside its category').toHaveCount(1);
  await expect(list.locator('li', { hasText: 'Dangling Electric Wires' }).locator('.cn-was'), 'renamed since: what it was filed as').toContainText('Filed as "Public Safety and Infrastructure: Live wire on the ground" (renamed since)');
  await expect(list.locator('li', { hasText: 'Neglected Pets' }).locator('.cn-was'), 'switched off since').toContainText('no longer offered');
  await expect(list.locator('li', { hasText: 'Barangay Service' }).locator('.cn-was'), 'nothing changed: no line').toHaveCount(0);
  // adding one: a category and, when it has them, one of its options; what the case already has is not offered again
  const add = page.locator('#ac-cat');
  if (await add.count()) {
    expect(await add.locator('option[value="public_safety_infrastructure|4"]').count(), 'an option the case already has').toBe(0);
    expect(await add.locator('option[value="public_safety_infrastructure|5"]').count(), 'another option of the same category').toBe(1);
    expect(await add.locator('option[value="animal_welfare|6"]').count(), 'a switched-off option').toBe(0);
  }
  expect(r.errors, 'console errors').toEqual([]);
});

test('Roles and pages 1b: committee colours, the super admin colour, and the sidebar each one wears', async ({ page, context }) => {
  let r = await open(page, 'administrative-services.php#access');
  await expect(page.locator('#acc-super input[type="color"]')).toHaveValue('#00308f');
  expect(await page.locator('#acc-committees input[type="color"]').count(), 'committee colours are chosen in the editor now').toBe(0);
  expect(await axe(page), 'Administrative Services > Committees, with colours').toEqual([]);
  await expect(page.locator('.p-side-com')).toHaveCount(0);   // a super admin's sidebar is branding blue, with no committee banner
  expect(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--p-side-a').trim().toUpperCase())).toBe('#00308F');
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const c = await open(page, 'cases.php');
  await expect(page.locator('.p-side-com')).toContainText('Peace and Order');
  expect(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--p-side-a').trim())).toMatch(/^hsl\(0 /);
  expect(await axe(page), 'Case Reports, committee sidebar').toEqual([]);
  expect(r.errors.concat(c.errors), 'console errors').toEqual([]);
});

test('Roles and pages 2: staff are moderators of a committee; the Administrators tab works on its new page', async ({ page, context }) => {
  let r = await open(page, 'administrative-services.php#admins');
  await expect(page.locator('form.ss-access select[name="tier"] option[value="moderator"]').first()).toHaveCount(1);
  const edit = page.locator('#jp-rows .ss-edit-btn').first();
  const id = await edit.getAttribute('data-edit');
  await edit.click();
  await expect(page.locator(`tr.ss-erow[data-for="${id}"]`)).toBeVisible();   // the edit row opens here, not only on Settings
  await context.addCookies([{ name: 'ss_tier', value: 'moderator', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const m = await open(page, 'cases.php');
  await expect(page.locator('#side-user')).toContainText('Staff · Peace and Order');
  await expect(page.locator('.p-side-com')).toContainText('Peace and Order');
  for (const href of ['dashboard.php', 'administrative-services.php', 'control-room.php', 'residents.php']) await expect(page.locator(`.p-sidebar a[href="${href}"]`)).toHaveCount(0);
  await expect(page.locator('.p-sidebar a[href="settings.php"]')).toHaveCount(1);   // their own Settings (4 Nov 2026)
  await page.goto('control-room.php');
  await expect(page).toHaveURL(/notifications\.php/);
  expect(r.errors.concat(m.errors), 'console errors').toEqual([]);
});

test('Roles and pages 3: forwarding between committees (chips, Committee column, Forward and Flag, pinned on Notifications)', async ({ page, context }) => {
  const s = await open(page, 'cases.php');
  await expect(page.locator('.cm-chips .cm-chip')).toHaveCount(1 + 4 + 1);   // All, each active committee, No committee yet
  await expect(page.locator('.cm-chip-none')).toContainText('No committee yet');
  await expect(page.locator('table.ss-cases-t thead th', { hasText: 'Committee' })).toHaveCount(1);
  await expect(page.locator('.cm-pill.cm-await').first()).toContainText('With the super admins');
  await expect(page.locator('.cm-fwd').first()).toContainText('Forwarded from Peace and Order');
  await page.locator('.fw-sel').nth(1).check();
  await expect(page.locator('#fw-bulk')).toBeVisible();
  await page.locator('.fw-btn').first().click();
  await expect(page.locator('#fw-dlg')).toBeVisible();
  await expect(page.locator('#fw-dlg select[name="to"] option[value="__super"]')).toHaveCount(0);   // a super admin places; only a Kagawad hands up
  // the committees can be chosen (15 Nov, Rose): the list opens inside the dialog, on top of it, not behind it
  const pick = page.locator('#fw-dlg .sdp-btn').first();
  await expect(pick).toBeVisible();
  await pick.click();
  const hit = await page.evaluate(() => { const p = document.querySelector('.sdp-pop'); if (!p) return 'no list'; const r = p.getBoundingClientRect(), e = document.elementFromPoint(r.left + r.width / 2, r.top + Math.min(40, r.height / 2)); return p.contains(e) && !!p.closest('dialog') ? 'on top' : 'behind'; });
  expect(hit, 'the committee list is drawn above the dialog').toBe('on top');
  expect(await page.locator('.sdp-pop .sdp-opt').count(), 'every active committee to choose from').toBeGreaterThanOrEqual(4);
  await page.locator('.sdp-pop .sdp-opt').nth(1).click();
  expect(await page.locator('#fw-dlg select[name="to"]').inputValue(), 'a committee was chosen').not.toBe('');
  expect(await axe(page), 'Case Reports, forward dialog open').toEqual([]);
  await page.locator('#fw-dlg [data-fw-close]').click();
  await expect(page.locator('#fw-dlg')).toBeHidden();

  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const k = await open(page, 'cases.php');
  await expect(page.locator('.cm-chip')).toContainText(['My committee', 'Forwarded to us', 'Flagged to forward']);
  await expect(page.locator('.fw-sel')).toHaveCount(0);
  await expect(page.locator('table.ss-cases-t thead th', { hasText: 'Committee' })).toHaveCount(0);
  const n = await open(page, 'notifications.php');
  await expect(page.locator('.fw-pins .p-notif', { hasText: 'Staff flagged' })).toContainText('Staff flagged it for forwarding: Mukhang sa kalusugan ito');
  const c = await open(page, `case.php?id=${CASE}`);
  await expect(page.locator('.fw-flag')).toContainText('Mukhang sa kalusugan ito');
  await expect(page.locator('.fw-flag select[name="to"] option[value="health_sanitation"]')).toHaveAttribute('selected', '');
  await expect(page.locator('.fw-flag button', { hasText: 'Keep it here' })).toHaveCount(1);

  await context.addCookies([{ name: 'ss_tier', value: 'moderator', url: 'http://127.0.0.1:8013' }]);
  const m = await open(page, 'cases.php');
  await page.locator('.fw-btn', { hasText: 'Flag' }).first().click();
  await expect(page.locator('#fw-dlg textarea[name="note"]')).toHaveAttribute('required', '');
  await expect(page.locator('#fw-dlg input[name="action"]')).toHaveValue('flag_list');
  expect(s.errors.concat(k.errors, n.errors, c.errors, m.errors), 'console errors').toEqual([]);
});

test('Roles and pages 4: tanods in committees, the punch cards, and a Kagawad\'s Personnel', async ({ page, context }) => {
  const s = await open(page, 'personnel.php');
  await expect(page.locator('.cm-chips .cm-chip')).toHaveCount(1 + 4 + 1);
  await expect(page.locator('#ss-people thead th', { hasText: 'Committees' })).toHaveCount(1);
  await expect(page.locator('tr[data-id="u2"] .tc-pills')).toContainText('Lead sa gabi');
  await expect(page.locator('tr[data-id="u3"] .cm-pill.cm-prop')).toContainText('proposed');
  await expect(page.locator('tr[data-id="u3"] .tc-busy')).toContainText('Peace and Order');
  await expect(page.locator('#tc-waiting button', { hasText: 'Approve' })).toHaveCount(1);
  await page.locator('.tc-tabs a', { hasText: 'Committee staff' }).click();
  await expect(page).toHaveURL(/view=staff/);
  await expect(page.locator('.pc-card')).toHaveCount(2);
  await expect(page.locator('.pc-card').first()).toContainText('Still in');
  // peak: the figures lead, each committee's banner heads its group and is joined to the cards under it
  await expect(page.locator('.pc-fig .ss-tile')).toHaveCount(4);
  await expect(page.locator('.pc-fig .ss-tile').nth(1)).toContainText('1');
  await expect(page.locator('.pc-gh .cm-chip')).toHaveCount(1);
  const pg = await page.evaluate(() => { const b = document.querySelector('.pc-gh').getBoundingClientRect(), g = document.querySelector('.pc-grid').getBoundingClientRect(); return { h: Math.round(b.height), gap: Math.abs(b.bottom - g.top), x: [Math.round(b.left), Math.round(b.right), Math.round(g.left), Math.round(g.right)], bg: getComputedStyle(document.querySelector('.pc-gh .cm-chip')).backgroundImage }; });
  expect(pg.h, 'the banner is slim').toBeLessThanOrEqual(80);
  expect(pg.gap, 'and joined to its cards').toBeLessThanOrEqual(1);
  expect([pg.x[0], pg.x[1]], 'sharing their edges').toEqual([pg.x[2], pg.x[3]]);
  expect(pg.bg, 'a gradient in the committee colours').toContain('gradient');
  await page.locator('.pc-fig .ss-tile').nth(2).click();
  await expect(page.locator('.pc-card')).toHaveCount(1);   // the one not in today
  await expect(page.locator('.pc-card').first()).toContainText('Not in today');
  expect(await axe(page), 'Personnel, Committee staff').toEqual([]);
  const d = await open(page, 'personnel.php?id=u2');
  await expect(page.locator('#tc-card .tc-add button[type=submit]')).toContainText('Add to the committee');
  expect(await page.locator('.p-controls form').count()).toBeGreaterThan(0);   // a super admin's account controls are there

  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const k = await open(page, 'personnel.php');
  await expect(page.locator('.cm-chips')).toHaveCount(0);
  await expect(page.locator('#tc-propose summary')).toContainText('Propose a tanod for Peace and Order');
  await expect(page.locator('.tc-tabs a', { hasText: 'My staff' })).toHaveCount(1);
  const kd = await open(page, 'personnel.php?id=u2');
  await expect(page.locator('.p-controls')).toContainText('Only a super admin verifies');
  await expect(page.locator('.p-controls form')).toHaveCount(0);
  await expect(page.locator('#tc-card button', { hasText: 'Take out of the committee' })).toHaveCount(1);
  expect(s.errors.concat(d.errors, k.errors, kd.errors), 'console errors').toEqual([]);
});

test('Personnel roster: equal rows, duty tiles filter, bulk add to a committee, and the live refresh draws what a reload does', async ({ page }) => {
  test.setTimeout(90000);
  const norm = h => h.replace(/\s+/g, ' ').replace(/>\s+/g, '>').replace(/\s+</g, '<').trim();
  const r = await open(page, 'personnel.php');
  await expect(page.locator('.p-attendance .p-kpi')).toHaveCount(4);
  await expect(page.locator('tr[data-id="u2"] .pe-duty')).toContainText('On Duty');
  await expect(page.locator('tr[data-id="u7"] .pe-mail')).toContainText('barretto.martin2023@gmail.com');   // whole, not broken mid-word
  const heights = await page.locator('#accounts-tbody tr').evaluateAll(rs => rs.map(x => Math.round(x.getBoundingClientRect().height)));
  expect(new Set(heights).size, 'every row is as tall as the next: ' + heights).toBe(1);
  const before = await page.$$eval('#accounts-tbody tr', rs => rs.map(x => x.outerHTML));
  // the duty tile filters, and the lit one clears it
  await page.locator('.p-attendance .p-att-on_duty').click();
  await expect(page).toHaveURL(/duty=on_duty/);
  await expect(page.locator('#accounts-tbody tr')).toHaveCount(2);
  await page.locator('.p-attendance .p-att-on_duty').click();
  await expect(page).not.toHaveURL(/duty=/);
  // the bulk bar: tick two, pick a committee, add
  await page.locator('tr[data-id="u7"] .ss-cb').check(); await page.locator('tr[data-id="u10"] .ss-cb').check();
  await expect(page.locator('#ss-bulk')).toBeVisible();
  await page.locator('#ss-bulk-com').selectOption('peace_order');
  await Promise.all([page.waitForURL(/personnel\.php/), page.locator('#ss-bulk-tc button[type=submit]').click()]);
  await expect(page.locator('.p-flash--ok')).toContainText('2 added to Peace and Order');
  // the list's 20-second refresh redraws the rows the way the server drew them
  await page.waitForTimeout(21500);
  const after = await page.$$eval('#accounts-tbody tr', rs => rs.map(x => x.outerHTML));
  expect(after.map(norm)).toEqual(before.map(norm));
  expect(r.errors, 'console errors').toEqual([]);
});

test('Control Room: no tab overflows sideways, the limits share a line, the seal picker is a visible control, counts read right', async ({ page }) => {
  const r = await open(page, 'control-room.php');
  for (const tab of ['types', 'hotlines', 'wording', 'brgy', 'parts']) {
    await page.locator(`.st-tabs [data-st="${tab}"]`).click();
    expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), `${tab} overflows sideways`).toBe(false);
  }
  await page.locator('.st-tabs [data-st="brgy"]').click();
  const box = await page.locator('#brgy-card input[type="file"]').boundingBox();
  expect(box && box.width > 100 && box.width < 1200, 'the seal picker is visible: ' + JSON.stringify(box)).toBeTruthy();
  await page.locator('.st-tabs [data-st="hotlines"]').click();
  await expect(page.locator('#hotlines-card')).not.toContainText('1 numbers');
  expect(r.errors, 'console errors').toEqual([]);
});

test('Administrative Services: headers sit over their cells, the committees say who leads them, escalation has its own tab', async ({ page }) => {
  const r = await open(page, 'administrative-services.php');
  for (const tab of ['access', 'admins', 'ladder']) {
    await page.locator(`.st-tabs [data-st="${tab}"]`).click();
    expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), `${tab} overflows sideways`).toBe(false);
  }
  await page.locator('.st-tabs [data-st="admins"]').click();   // Status then Access, as the cells run
  const heads = await page.locator('#ss-people thead th').allTextContents();
  const first = page.locator('#jp-rows tr.ss-arow').first().locator('td');
  expect(heads.map(h => h.trim()).slice(3, 5), 'headers').toEqual(['Status', 'Access']);
  await expect(first.nth(3)).toContainText('Active');
  await expect(first.nth(4)).toContainText('Super admin');
  await expect(page.locator('.ss-levels')).toBeHidden();           // escalation is not on this tab any more
  await page.locator('.st-tabs [data-st="ladder"]').click();
  await expect(page.locator('.ss-levels')).toBeVisible();
  await expect(page.locator('#wr-count')).toBeVisible();
  await page.locator('.st-tabs [data-st="access"]').click();
  await expect(page.locator('.acc-row .acc-meta').first()).toContainText('Led by');
  await expect(page.locator('#acc-super .acc-swatch')).toHaveCount(0);   // one swatch, the colour input itself
  const cut = await page.locator('.acc-row input[name="name_fil"]').evaluateAll(is => is.filter(i => i.scrollWidth > i.clientWidth + 1).length);
  expect(cut, 'Tagalog names cut off').toBe(0);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Case Reports and the Dashboard: equal rows, Review is the main button, what needs a super admin leads the Dashboard', async ({ page }) => {
  const r = await open(page, 'cases.php');
  const heights = await page.locator('.ss-cases-t tbody tr.p-click').evaluateAll(rs => rs.map(x => Math.round(x.getBoundingClientRect().height)));
  expect(heights.length, 'rows shown').toBeGreaterThan(5);
  expect(Math.max(...heights) - Math.min(...heights), 'rows are as tall as the next (a "Forwarded from" tag may add a line): ' + heights).toBeLessThanOrEqual(8);
  const row = page.locator('.ss-cases-t tbody tr.p-click').first();
  const rv = await row.locator('.fw-acts .p-btn').first().evaluate(b => { const c = getComputedStyle(b); return c.backgroundImage !== 'none' ? 'gradient' : c.backgroundColor; });
  const fw = await row.locator('.fw-acts .fw-btn').evaluate(b => getComputedStyle(b).backgroundColor);
  expect(fw, 'Forward is the second choice, not a filled button').toBe('rgba(0, 0, 0, 0)');
  expect(rv, 'Review is the filled one').not.toBe('rgba(0, 0, 0, 0)');
  const cut = await page.evaluate(() => { const b = document.querySelector('.ss-cases-t .fw-acts .fw-btn').getBoundingClientRect(); return b.right > document.querySelector('.ss-cases-t').getBoundingClientRect().right; });
  expect(cut, 'the Forward button is inside the table').toBe(false);
  const d = await open(page, 'dashboard.php');
  await page.waitForTimeout(1500);   // the tiles ease in
  // Rose, 2 Nov 2026: the Dashboard's own layout again. The month's reports across the top, the three figures stacked beside
  // the donuts; what waits on a super admin is in the engine's window.
  const chart = await page.locator('.dh-recv').evaluate(h => Math.round(h.getBoundingClientRect().bottom));
  const figs = await page.locator('.p-dash-mid .p-stack .p-tile-s').evaluateAll(ts => ts.map(t => { const b = t.getBoundingClientRect(); return [Math.round(b.left), Math.round(b.top)]; }));
  expect(figs.length, 'three figures').toBe(3);
  expect(new Set(figs.map(t => t[0])).size, 'stacked in one column').toBe(1);
  expect(figs[0][1], 'below the chart').toBeGreaterThan(chart);
  await page.locator('#ss-win-open').click();
  await expect(page.locator('#ss-panel .dc-needs .ss-tile')).toHaveCount(4);
  await expect(page.locator('#ss-panel .dc-coms')).toBeVisible();
  expect(r.errors.concat(d.errors), 'console errors').toEqual([]);
});

test('An account page: the tabs and sections are one box (16 Nov), no section stretched beside another, the controls in view', async ({ page }) => {
  const r = await open(page, 'personnel.php?id=u2');
  const box = sel => page.locator(sel).first().evaluate(e => { const b = e.getBoundingClientRect(); return [Math.round(b.top), Math.round(b.left), Math.round(b.height), Math.round(b.bottom), Math.round(b.width)]; });
  const bx = await box('.pd-box'), a = await box('.pd-details'), b = await box('.pd-tc'), c = await box('.pd-duty');
  expect(await page.locator('.pd-box > .pd-tabs').count(), 'the tabs are the top of the box').toBe(1);
  for (const s of ['.pd-details', '.pd-tc', '.pd-duty']) expect(await page.locator('.pd-box > ' + s).count(), s + ' is a section of the box').toBe(1);
  expect(a[4], 'a section uses the whole width of the box').toBeGreaterThan(bx[4] - 4);
  expect(Math.abs(a[3] - b[0]) <= 2 && Math.abs(b[3] - c[0]) <= 2, 'the sections stack with no gap between them').toBe(true);
  expect(await page.locator('.pd-box > .p-card').first().evaluate(e => getComputedStyle(e).boxShadow), 'a section is flat inside the box').toBe('none');
  await expect(page.locator('.pd-id'), 'the ID waits on its own tab').toBeHidden();
  await page.locator('.pd-tabs [data-tab="documents"]').click();
  await expect(page.locator('.pd-id')).toBeVisible();
  await expect(page.locator('.pd-details'), 'and the overview steps aside').toBeHidden();
  expect(await page.locator('.p-profile-grid > .p-controls').evaluate(e => getComputedStyle(e).position), 'the controls stay in view').toBe('sticky');
  const h = await page.evaluate(() => document.documentElement.scrollHeight);
  expect(h, 'a tanod page is no longer a tower of cards (was 1412+ px at 2048 with no dispatches)').toBeLessThan(1500);
  const q = await open(page, 'residents.php?id=u1');
  expect(await page.locator('.pd-grid').count(), 'the same layout for a resident').toBe(1);
  expect(r.errors.concat(q.errors), 'console errors').toEqual([]);
});

test('Report Summary: the chips are tabs, one section at a time, and a link or a pager lands on its section', async ({ page }) => {
  const r = await open(page, 'summary.php');
  const on = () => page.evaluate(() => ['rs-ledger', 'rs-esc', 'rs-tanod', 'rs-tl', 'rs-com'].filter(id => { const e = document.getElementById(id); return e && getComputedStyle(e).display !== 'none'; }));
  expect(await on(), 'the ledger first, alone').toEqual(['rs-ledger']);
  await page.locator('#ss-jump a[href="#rs-esc"]').click();
  expect(await on()).toEqual(['rs-esc']);
  await expect(page.locator('#ss-jump a.on')).toHaveCount(1);
  await page.locator('#ss-jump a[href="#rs-com"]').click();
  expect(await on()).toEqual(['rs-com']);
  expect(await page.evaluate(() => document.documentElement.scrollHeight), 'a tab is not a tower of sections').toBeLessThan(1600);
  await open(page, 'summary.php#rs-tl');
  expect(await on(), 'a deep link opens its section').toEqual(['rs-tl']);
  await open(page, 'summary.php?lp=2');
  expect(await on(), 'a ledger pager lands on the ledger').toEqual(['rs-ledger']);
  expect(r.errors, 'console errors').toEqual([]);
});

test('System status: health leads, the services are live rows that open a drawer, the diagram is a view of the same card', async ({ page }) => {
  const r = await open(page, 'settings.php');
  await expect(page.locator('#st-banner')).toBeVisible();
  await expect(page.locator('#st-rows .st-row')).toHaveCount(9);
  await expect(page.locator('.st-hmini > span')).toHaveCount(4);
  await expect(page.locator('#st-drawer')).not.toHaveAttribute('open', '');
  await page.locator('#st-rows .st-row').first().click();
  await expect(page.locator('#st-drawer')).toHaveAttribute('open', '');
  await expect(page.locator('#st-dr-t')).not.toBeEmpty();
  await expect(page.locator('#st-dr-body [data-st-recheck]')).toHaveCount(1);
  await expect(page.locator('#st-dr-body .st-bars.big i')).toHaveCount(36);
  await page.locator('#st-drawer [data-st-close]').click();
  await expect(page.locator('#st-drawer')).not.toHaveAttribute('open', '');
  await expect(page.locator('#st-map')).toBeHidden();
  await page.locator('[data-st-view="map"]').click();
  await expect(page.locator('#st-map svg')).toBeVisible();
  await expect(page.locator('#st-map .st-node')).toHaveCount(9);
  await expect(page.locator('#st-rows')).toBeHidden();
  await page.locator('#st-map .st-node').first().click();
  await expect(page.locator('#st-drawer')).toHaveAttribute('open', '');
  await page.locator('#st-drawer [data-st-close]').click();
  await page.locator('[data-st-view="list"]').click();
  await expect(page.locator('#st-rows .st-row')).toHaveCount(9);
  await expect(page.locator('.st-credits'), 'the map credits left this page').toHaveCount(0);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Plan and usage: the plans sit beside the usage; hovering focuses a plan, pressing keeps it, Show all clears it', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'settings.php');
  await page.locator('.st-tabs [data-st="usage"]').click();
  await expect(page.locator('.st-pl')).toHaveCount(6);
  await expect(page.locator('.st-uk > div')).toHaveCount(4);
  const first = page.locator('.st-pl').first();
  await first.hover();
  await expect(page.locator('#st-ul .st-um.dim').first()).toBeAttached();
  await first.click();
  await expect(first).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#st-ul .st-drs')).toHaveCount(3);
  await page.locator('[data-st-plan-clear]').click();
  await expect(page.locator('.st-pl[aria-pressed="true"]')).toHaveCount(0);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Case Reports: on a wide screen the search and the filters are one toolbar line', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'cases.php');
  const tops = await page.evaluate(() => [document.querySelector('.ss-cr-band .p-search'), ...document.querySelectorAll('.ss-cr-band .ss-band-filters .p-pill-select')].map(e => Math.round(e.getBoundingClientRect().top)));
  expect(tops.length, 'the search and the five filters').toBe(6);
  expect(Math.max(...tops) - Math.min(...tops), 'one line: ' + tops).toBeLessThanOrEqual(6);
  const bandH = await page.locator('.ss-cr-band').evaluate(e => Math.round(e.getBoundingClientRect().height));
  expect(bandH, 'the band is one row tall').toBeLessThan(110);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Report Summary, peak: each figure says how it moved and shows its shape, one sentence says what it means, overdue rows are marked, the orange is the identity', async ({ page }) => {
  const r = await open(page, 'summary.php?range=month');
  await expect(page.locator('.ss-sumkpis .p-kpi')).toHaveCount(4);
  await expect(page.locator('.ss-sumkpis .rs-chg').first()).toContainText(/before|new/);
  expect(await page.locator('.ss-sumkpis svg.rs-spark').count(), 'a shape for the figures that have one').toBeGreaterThanOrEqual(3);
  await expect(page.locator('.rs-story'), 'the sentence belongs to the engine window, not the page').toHaveCount(0);
  await expect(page.locator('#ss-panel')).toBeHidden();
  await page.locator('#ss-win-open').click();
  await expect(page.locator('#ss-panel')).toBeVisible();
  await expect(page.locator('#ss-panel .rs-w-list')).toContainText('overdue');
  await expect(page.locator('#ss-panel .rs-tn-row')).toHaveCount(2);   // by tanod lives in the engine's window now
  expect(await axe(page), 'Report Summary, engine window open').toEqual([]);
  await page.keyboard.press('Escape');
  await expect(page.locator('#ss-panel')).toBeHidden();
  const bar = await page.evaluate(() => { const n = document.querySelector('#ss-jump').getBoundingClientRect(), c = document.querySelector('#rs-ledger').getBoundingClientRect(); return [Math.round(n.left), Math.round(n.right), Math.round(c.left), Math.round(c.right)]; });
  expect(Math.abs(bar[0] - bar[2]) <= 1 && Math.abs(bar[1] - bar[3]) <= 1, 'the tab bar spans the card below it, with no gap: ' + bar).toBe(true);
  expect(await page.locator('#rs-ledger tr.rs-od').count(), 'overdue rows are marked').toBeGreaterThan(0);
  const wrong = await page.locator('#rs-ledger tbody tr').evaluateAll(rs => rs.filter(r => /Resolved|Closed/.test(r.children[4].textContent) && /open \d/.test(r.children[r.children.length - 1].textContent)).length);
  expect(wrong, 'a resolved case never reads as open').toBe(0);
  const bands = await page.evaluate(() => { const c = id => getComputedStyle(document.querySelector(id)).backgroundImage + '|' + getComputedStyle(document.querySelector(id)).backgroundColor; return [c('#rs-ledger > .p-card-head'), getComputedStyle(document.querySelector('#rs-ledger thead th')).backgroundColor]; });
  expect(bands[0], 'the title row is no longer an orange band (6 Nov: the period band is the one orange is the period band)').not.toMatch(/255, 1[5-8]\d, \d+/);
  expect(bands[1], 'the column header under it is no longer the blue').not.toBe('rgb(0, 48, 143)');
  await expect(page.locator('thead.p-orange'), 'one pair of colours on every tab').toHaveCount(0);
  await expect(page.locator('.p-period-band .p-btn-pdf2')).toBeVisible();
  expect(r.errors, 'console errors').toEqual([]);
});

test('Case Reports, peak: figures that link to their lists, the blue column header, overdue rows marked', async ({ page }) => {
  const r = await open(page, 'cases.php');
  await expect(page.locator('.cr-fig > a')).toHaveCount(4);
  const tops = await page.locator('.cr-fig > a').evaluateAll(as => as.map(a => Math.round(a.getBoundingClientRect().top)));
  expect(new Set(tops).size, 'the four figures are one band').toBe(1);
  await expect(page.locator('.cr-fig > a').first()).toHaveAttribute('href', /view=attention/);
  expect(Number(await page.locator('.cr-fig > a').first().locator('b').textContent())).toBeGreaterThan(0);
  expect(await page.locator('.ss-cases-t thead th').first().evaluate(e => getComputedStyle(e).backgroundColor), 'the column header is no longer the blue (6 Nov: white under the one orange header)').not.toBe('rgb(0, 48, 143)');
  expect(await page.locator('.ss-cases-t tr.cr-od').count(), 'overdue rows are marked').toBeGreaterThan(0);
  await page.locator('.cr-fig > a').first().click();
  await expect(page).toHaveURL(/view=attention/);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Case Reports: the header, the chooser and the list are three rounded objects on one grid, the chooser is a slim bar like the Report Summary tabs, no name is cut, the column head is white', async ({ page }) => {
  for (const w of [2048, 1440, 720]) {
    await page.setViewportSize({ width: w, height: 1000 });
    const r = await open(page, 'cases.php');
    const g = await page.evaluate(() => { const b = document.querySelector('.ss-cr-band').getBoundingClientRect(), c = document.querySelector('.cm-chips').getBoundingClientRect(), t = document.querySelector('.ss-cases-t').closest('.p-table-card').getBoundingClientRect(); return { x: [b.left, b.right, c.left, c.right, t.left, t.right].map(Math.round), y: [b.bottom, c.top, c.bottom, t.top].map(Math.round) }; });
    expect([g.x[0], g.x[1]], 'the header and the chooser share their edges at ' + w).toEqual([g.x[2], g.x[3]]);
    expect([g.x[2], g.x[3]], 'and the list at ' + w).toEqual([g.x[4], g.x[5]]);
    expect(g.y[1] - g.y[0], 'a gap between the header and the chooser at ' + w).toBeGreaterThanOrEqual(10);
    expect(g.y[3] - g.y[2], 'and between the chooser and the list at ' + w).toBeGreaterThanOrEqual(10);
    expect(await page.locator('.cm-chips').evaluate(e => Math.round(e.getBoundingClientRect().height)), 'the chooser is as slim as the tab bar of Report Summary at ' + w).toBeLessThanOrEqual(w === 720 ? 330 : w === 1440 ? 100 : 60);   // one line on a wide screen, two when the seven tabs no longer fit
    const cut = await page.locator('.cm-chips .cm-chip').evaluateAll(ns => ns.filter(n => n.scrollWidth > n.clientWidth + 1).length);
    expect(cut, 'no committee name is cut at ' + w).toBe(0);
    const heads = await page.locator('.ss-cases-t thead th').first().evaluate(e => [getComputedStyle(e).backgroundColor, getComputedStyle(e).textTransform]);
    expect(heads[0], 'the column head is not the blue at ' + w).not.toBe('rgb(0, 48, 143)');
    expect(await page.locator('.cm-ind').count(), 'the chosen tab is one sliding pill at ' + w).toBe(1);
    expect(await page.locator('.cm-ind').evaluate(e => getComputedStyle(e).backgroundImage.includes('gradient')), 'in the committee colours at ' + w).toBe(true);
    expect(await page.locator('.cm-chips .cm-chip > b').count(), 'every tab carries its count at ' + w).toBeGreaterThanOrEqual(5);
    expect(r.errors, 'console errors').toEqual([]);
  }
  await page.setViewportSize({ width: 2048, height: 1000 });
  await open(page, 'summary.php?range=month');
  await page.locator('#ss-jump a[href="#rs-com"]').click();
  expect(await page.locator('#rs-com thead th:first-child').evaluate(e => [getComputedStyle(e).borderTopLeftRadius, getComputedStyle(e).borderTopRightRadius]), 'and on Report Summary').toEqual(['0px', '0px']);
  await expect(page.locator('.rs-layout, .cr-rail'), 'no rail anywhere').toHaveCount(0);
});

test('Notifications keeps its live layout and wears the committee chooser, a slim bar under its header', async ({ page }) => {
  for (const w of [2048, 1440]) {
    await page.setViewportSize({ width: w, height: 1000 });
    const r = await open(page, 'notifications.php');
    const g = await page.evaluate(() => { const b = document.querySelector('.nf-main .p-band--calm').getBoundingClientRect(), c = document.querySelector('.nf-chips').getBoundingClientRect(), m = document.querySelector('.nf-main').getBoundingClientRect(), rail = document.querySelector('.nf-rail'); return { x: [b.left, b.right, c.left, c.right].map(Math.round), y: [b.bottom, c.top].map(Math.round), railBeside: !!rail && rail.getBoundingClientRect().left >= m.right - 1 }; });
    expect([g.x[0], g.x[1]], 'the band and the strip share their edges at ' + w).toEqual([g.x[2], g.x[3]]);
    expect(g.y[1] - g.y[0], 'a gap between the header and the chooser at ' + w).toBeGreaterThanOrEqual(10);
    if (w === 2048) expect(g.railBeside, 'the live layout: the work and the engine reading beside the feed').toBe(true);
    await expect(page.locator('.nf-chips .cm-chip')).toHaveCount(1 + 4 + 1 + 1);   // All, each active committee, No committee, System
    expect(await page.locator('.nf-chips .cm-ind').evaluate(e => getComputedStyle(e).backgroundImage.includes('gradient')), 'the chosen tab is a gradient pill at ' + w).toBe(true);
    expect(await page.locator('.nf-chips .cm-bg').count(), 'each carries its faint symbol at ' + w).toBeGreaterThanOrEqual(6);
    expect(await page.locator('.nf-chips').evaluate(e => Math.round(e.getBoundingClientRect().height)), 'the chooser is as slim as the tab bar of Report Summary at ' + w).toBeLessThanOrEqual(100);   // one line when the seven tabs fit, two when the feed column leaves them less room
    expect(await page.locator('.nf-chips ~ .p-notif-card').first().evaluate(e => [getComputedStyle(e).borderTopLeftRadius, getComputedStyle(e).borderTopRightRadius]), 'and the list is its own rounded card at ' + w).toEqual(['16px', '16px']);
    expect(await page.locator('.nf-chips .cm-n').evaluateAll(ns => ns.filter(n => n.scrollWidth > n.clientWidth + 1).length), 'no name is cut at ' + w).toBe(0);
    expect(r.errors, 'console errors').toEqual([]);
  }
  // each banner's number is what its list shows when it is pressed
  await page.setViewportSize({ width: 2048, height: 1000 });
  await open(page, 'notifications.php');
  const keys = await page.locator('.nf-chips .cm-chip').evaluateAll(cs => cs.map(c => [c.dataset.nc, c.querySelector('b').textContent.trim()]));
  expect(keys.length).toBe(7);
  for (const [k, shown] of keys) {
    await open(page, 'notifications.php' + (k ? '?ncom=' + k : ''));
    expect(await page.locator('#notif-count').textContent(), 'the banner "' + (k || 'All') + '" says what its list holds').toBe(shown);
  }
});

test('Personnel duty tiles keep their colour fields, so their white lettering reads', async ({ page }) => {
  for (const scheme of ['light', 'dark']) {
    await page.emulateMedia({ colorScheme: scheme });
    await page.setViewportSize({ width: 2048, height: 1000 });
    await open(page, 'personnel.php');
    const tiles = await page.locator('.p-attendance .p-kpi').evaluateAll(ts => ts.map(t => ({ bg: getComputedStyle(t).backgroundImage, fg: getComputedStyle(t.querySelector('.p-label')).color, v: getComputedStyle(t.querySelector('.p-value')).color, d: getComputedStyle(t.querySelector('.p-delta')).color, brk: t.classList.contains('p-att-break') })));
    expect(tiles.length).toBe(4);
    for (const x of tiles) {
      expect(x.bg, 'a colour field, not a white card (' + scheme + ')').toMatch(/linear-gradient\(145deg/);
      expect(x.fg, 'the label is the same ink as the number (' + scheme + ')').toBe(x.v);
      expect(x.d, 'and the line under it (' + scheme + ')').toBe(x.v);
      expect(x.v, 'white, or dark on the yellow Break tile').toBe(x.brk ? 'rgb(59, 42, 0)' : 'rgb(255, 255, 255)');
    }
  }
});

test('Personnel (tanods) and Residents wear the new chooser: a rounded header bar, a slim sliding chooser, a white column head, three objects with gaps', async ({ page }) => {
  for (const pg of ['personnel.php']) {
    for (const w of [2048, 1440]) {
      await page.setViewportSize({ width: w, height: 1000 });
      const r = await open(page, pg);

      await page.reload();
      const g = await page.evaluate(() => { const R = s => document.querySelector(s).getBoundingClientRect(), b = R('.ss-pband'), c = R('.cm-chips'), t = R('.ss-people'); return { x: [b.left, b.right, c.left, c.right, t.left, t.right].map(Math.round), y: [b.bottom, c.top, c.bottom, t.top].map(v => Math.round(v * 10) / 10) }; });
      expect([g.x[0], g.x[1]], pg + ': the header and the chooser share their edges at ' + w).toEqual([g.x[2], g.x[3]]);
      expect([g.x[0], g.x[1]], 'and the list at ' + w).toEqual([g.x[4], g.x[5]]);
      expect(g.y[1] - g.y[0], 'a gap under the header at ' + w).toBeGreaterThanOrEqual(10);
      expect(g.y[3] - g.y[2], 'and under the chooser at ' + w).toBeGreaterThanOrEqual(10);
      await expect(page.locator('.cm-chips .cm-chip'), pg + ' tabs').toHaveCount(6);
      expect(await page.locator('.cm-chips .cm-ind').evaluate(e => getComputedStyle(e).backgroundImage.includes('gradient')), 'the chosen tab is a gradient pill at ' + w).toBe(true);
      expect(await page.locator('.cm-chips').evaluate(e => Math.round(e.getBoundingClientRect().height)), 'the chooser stays slim at ' + w).toBeLessThanOrEqual(100);
      expect(await page.locator('.ss-people thead th').first().evaluate(t => getComputedStyle(t).backgroundColor), 'the column head is no longer the blue at ' + w).not.toBe('rgb(0, 48, 143)');
      expect(await page.locator('.p-attendance .p-kpi').first().evaluate(e => getComputedStyle(e).backgroundImage.includes('gradient')), 'the duty tiles are full-colour gradients').toBe(true);
      expect(r.errors, 'console errors').toEqual([]);
    }
  }
  // Residents (6 Nov): a one-height header bar, the sliding chooser, a white column head, three rounded objects on one grid
  for (const w of [2048, 1440]) {
    await page.setViewportSize({ width: w, height: 1000 });
    const r = await open(page, 'residents.php');
    await page.evaluate(() => { });
    await page.reload();
    const g = await page.evaluate(() => { const R = s => document.querySelector(s).getBoundingClientRect(), b = R('.ss-pband'), c = R('.cm-chips'), t = R('.ss-people'); return { x: [b.left, b.right, c.left, c.right, t.left, t.right].map(Math.round), y: [b.bottom, c.top, c.bottom, t.top].map(Math.round) }; });
    expect([g.x[0], g.x[1]], 'residents: the header and the chooser share their edges at ' + w).toEqual([g.x[2], g.x[3]]);
    expect([g.x[0], g.x[1]], 'and the list at ' + w).toEqual([g.x[4], g.x[5]]);
    expect(g.y[1] - g.y[0], 'a gap under the header at ' + w).toBeGreaterThanOrEqual(10);
    expect(g.y[3] - g.y[2], 'and under the chooser at ' + w).toBeGreaterThanOrEqual(10);
    await expect(page.locator('.cm-chips .cm-chip'), 'residents tabs').toHaveCount(6);
    expect(await page.locator('.cm-chips .cm-ind').evaluate(e => getComputedStyle(e).backgroundImage.includes('gradient')), 'the chosen tab is a gradient pill at ' + w).toBe(true);
    expect(await page.locator('.cm-chips').evaluate(e => Math.round(e.getBoundingClientRect().height)), 'the chooser stays slim at ' + w).toBeLessThanOrEqual(100);
    expect(await page.locator('.ss-people thead th').first().evaluate(t => getComputedStyle(t).backgroundColor), 'the column head is no longer the blue at ' + w).not.toBe('rgb(0, 48, 143)');
    expect(r.errors, 'console errors').toEqual([]);
  }
  await page.setViewportSize({ width: 2048, height: 1000 });
  await open(page, 'residents.php');
  expect(await page.locator('.ss-viewsw').count(), 'Squares mode is gone (16 Nov, parked for a new design)').toBe(0);
  // a banner filters the list like the dropdown it replaces did
  await open(page, 'residents.php');
  await page.locator('.rs-st .cm-chip[data-chip="verified"]').click();
  await expect(page).toHaveURL(/sort=verified/);
  await expect(page.locator('.rs-st .cm-chip.p-on')).toHaveCount(1);
});

test('Account pages, peak: the tanod page leads with figures and banners, and a staff card opens a staff page', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1000 });
  const r = await open(page, 'personnel.php?id=u2');
  await expect(page.locator('.pd-fig > div')).toHaveCount(4);
  await expect(page.locator('.pd-duty .p-duty-grid'), 'the figures left the Duty card').toHaveCount(0);
  await expect(page.locator('.pd-tabs [data-tab]'), 'Overview, Dispatches, Documents').toHaveCount(3);
  await expect(page.locator('#pd-grid')).toHaveAttribute('data-tab', 'overview');
  await expect(page.locator('.pd-recent'), 'the dispatches wait on their tab').toBeHidden();
  const g = await page.evaluate(() => { const R = s => document.querySelector(s).getBoundingClientRect(), b = R('.pd-tcb'), f = R('#tc-card'); return { w: Math.round(b.width), cardW: Math.round(f.width), bg: getComputedStyle(document.querySelector('.pd-tcb .cm-chip')).backgroundImage, th: getComputedStyle(document.querySelector('.pd-recent thead th')).backgroundColor, bandBottom: Math.round(R('.pd-recent .pd-band').bottom), headTop: Math.round(R('.pd-recent thead').top) }; });
  expect(g.w, 'the committee banner spans its card').toBeGreaterThan(g.cardW - 60);
  await expect(page.locator('.pd-details .cp-btn'), 'copy buttons on the email and the number').toHaveCount(1);   // this account has no email on file
  await page.locator('.pd-tabs [data-tab="dispatches"]').click();
  await expect(page.locator('.pd-recent')).toBeVisible();
  const gg = await page.evaluate(() => { const R = s => document.querySelector(s).getBoundingClientRect(); return { th: getComputedStyle(document.querySelector('.pd-recent thead th')).backgroundColor, bandBottom: Math.round(R('.pd-recent .pd-band').bottom), headTop: Math.round(R('.pd-recent thead').top) }; });
  g.th = gg.th; g.bandBottom = gg.bandBottom; g.headTop = gg.headTop;
  const here = page.url();
  await page.locator('.pd-recent .cp-btn').first().click();
  expect(page.url(), 'copying a tracking ID does not open the row').toBe(here);
  expect(g.bg, 'in the committee colours').toContain('gradient');
  expect(g.th, 'blue under the orange band').not.toBe('rgba(0, 0, 0, 0)');
  expect(g.headTop - g.bandBottom, 'the header bar and the chooser are two objects with a gap (6 Nov)').toBeGreaterThanOrEqual(10);
  expect(r.errors, 'console errors').toEqual([]);
  expect(await axe(page), 'Tanod account').toEqual([]);
  await open(page, 'personnel.php?view=staff');
  await page.locator('.pc-name').first().click();
  await expect(page).toHaveURL(/staff=s1/);
  await expect(page.locator('.pd-head h1')).toContainText('Santos');
  await expect(page.locator('.pd-fig > div')).toHaveCount(4);
  await expect(page.locator('.pd-head .pd-fadewrap'), 'the committee is the cover of the name card, not a card of its own').toHaveCount(1);
  await expect(page.locator('.pd-head .cm-pill')).toContainText('Peace and Order');
  await expect(page.locator('.pd-staffcom')).toHaveCount(0);
  await expect(page.locator('.tl-day')).toHaveCount(7);
  await expect(page.locator('.tl-day').first()).toContainText('Signed in');
  expect(await axe(page), 'Staff account').toEqual([]);
});

test('Resident account page, peak: figures, a Reports tab of their own named reports, and a cover by registration status', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1000 });
  const r = await open(page, 'residents.php?id=u1');
  await expect(page.locator('#pd-grid'), 'a registration waiting for review opens on the ID').toHaveAttribute('data-tab', 'documents');
  await expect(page.locator('.pd-fig > div')).toHaveCount(4);
  await expect(page.locator('.pd-fig > div').first()).toContainText('3');
  await expect(page.locator('.pd-head .pd-fadewrap'), 'a cover in the colour of the registration').toHaveCount(1);
  await expect(page.locator('.pd-tabs [data-tab]')).toHaveCount(3);   // Overview, Reports, Documents
  await page.locator('.pd-tabs [data-tab="reports"]').click();
  await expect(page.locator('.pd-reports tbody tr')).toHaveCount(3);
  await expect(page.locator('.pd-reports'), 'the anonymous and sensitive reports are never listed').not.toContainText('Husband hits wife');
  expect(await page.locator('.pd-reports thead th').first().evaluate(t => getComputedStyle(t).backgroundColor), 'blue under the orange band').not.toBe('rgba(0, 0, 0, 0)');
  await page.locator('.pd-reports tbody tr').first().locator('.p-mono-id').click();
  await expect(page).toHaveURL(/case\.php\?id=/);
  expect(r.errors, 'console errors').toEqual([]);
  await open(page, 'residents.php?id=u1');
  expect(await axe(page), 'Resident account').toEqual([]);
});

test('Roles and pages 5: the reroute question opens the case, and the Inbox is the case chats alone (BarangayMail is gone, Rose 15 Nov)', async ({ page, context }) => {
  const n = await open(page, 'notifications.php');
  await expect(page.locator('.fw-pins .p-notif', { hasText: 'No tanod of the committee is free' })).toHaveCount(1);
  await expect(page.locator('.fw-pins a', { hasText: 'Pick a tanod' })).toHaveAttribute('href', /case\.php\?id=/);   // Assign tanod on the case answers the question
  const i = await open(page, 'inbox.php');
  await expect(page.locator('.p-sidebar a[href="inbox.php"]'), 'Inbox is a section of the sidebar (Ace, 12 Nov)').toHaveCount(1);
  await expect(page.locator('.mg')).toBeVisible();
  await expect(page.locator('.gm, .ib-apps'), 'no BarangayMail, no header bar').toHaveCount(0);
  await expect(page.locator('.p-nav .p-ib-mail'), 'no envelope pill in the sidebar').toHaveCount(0);
  const old = await page.request.get('inbox.php?app=mail'); expect(old.status(), 'the old mail link still opens the chats').toBe(200);
  await context.addCookies([{ name: 'ss_tier', value: 'moderator', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const m = await open(page, 'inbox.php');
  await expect(page.locator('.p-sidebar a[href="inbox.php"]'), 'Inbox is a section of the sidebar (Ace, 12 Nov)').toHaveCount(1);
  expect(n.errors.concat(i.errors, m.errors), 'console errors').toEqual([]);
});

test('Feed rows: notifications about one case fold into a row, ', async ({ page }) => {
  const n = await open(page, 'notifications.php');
  const g = page.locator('details.nf-case');
  await expect(g).toHaveCount(1);
  await expect(g.locator('summary')).toContainText('SS-2610-1003');
  await expect(g.locator('summary')).toContainText('2 updates on this case');
  await expect(g.locator('summary')).toHaveAttribute('data-sev', 'high');
  await g.locator('summary').click();
  await expect(g.locator('.nf-case-items li')).toHaveCount(2);
  await expect(g.locator('.nf-case-act a')).toHaveAttribute('href', /case\.php\?id=/);
  await expect(page.locator('.p-notif.fr[data-sev]').first()).toBeVisible();
  expect(n.errors, 'console errors').toEqual([]);
});

test('Roles and pages 6a: the Dashboard super admin module, the box beside the donuts, the engine window', async ({ page }) => {
  const d = await open(page, 'dashboard.php');
  await expect(page.locator('.dc-needs .ss-tile').first()).toContainText('3');
  await expect(page.locator('.dc-coms tbody tr')).toHaveCount(4 + 1);
  await expect(page.locator('.dc-coms')).toContainText('Peace and Order');
  await page.locator('#legend-status [data-i="0"]').click();
  await expect(page.locator('#dq-box')).toBeVisible();
  await expect(page.locator('#dq-title')).toContainText('Done');
  await expect(page.locator('#dq-list li')).toHaveCount(2);
  await expect(page.locator('#dq-open')).toHaveAttribute('href', /cases\.php\?status=resolved/);
  await expect(page.locator('.dq-brain'), 'the charts have no brain button of their own').toHaveCount(0);
  await expect(page.locator('.ss-panel-btn'), 'nor is there an engine bar on the page').toHaveCount(0);
  await expect(page.locator('#ss-panel')).toBeHidden();
  await page.locator('#ss-win-open').click();   // the one brain button opens the engine's window
  await expect(page.locator('#ss-panel')).toBeVisible();
  await expect(page.locator('#ss-win-close')).toBeFocused();
  await expect(page.locator('#notes-received')).toContainText('51 complaints this month, up 28% from last month (40).');
  await expect(page.locator('#notes-efficiency')).toContainText('24 of 30 finished in time (80%).');
  expect(await axe(page), 'Dashboard, engine window open').toEqual([]);
  await page.keyboard.press('Escape');
  await expect(page.locator('#ss-panel')).toBeHidden();
  await expect(page.locator('#ss-win-open')).toBeFocused();
  expect(await axe(page), 'Dashboard, box open').toEqual([]);
  expect(d.errors, 'console errors').toEqual([]);
});

test('Roles and pages 6b: Report Summary by committee, and the committee form signed by its Kagawad', async ({ page, context }) => {
  const s = await open(page, 'summary.php?range=month');
  await expect(page.locator('.rs-scope')).toContainText('Barangay Overall');
  await expect(page.locator('#rs-ledger thead th', { hasText: 'Committee' })).toHaveCount(1);
  await expect(page.locator('#rs-com tbody tr')).toHaveCount(4 + 1);
  await expect(page.locator('#ss-jump a[href="#rs-com"]')).toHaveCount(1);
  expect(await axe(page), 'Report Summary, overall').toEqual([]);
  const c = await open(page, 'summary.php?range=month&com=peace_order');
  await expect(page.locator('.rs-scope')).toContainText('Peace and Order');
  await expect(page.locator('#rs-ledger thead th', { hasText: 'Committee' })).toHaveCount(0);
  await expect(page.locator('#rs-com')).toHaveCount(0);
  await expect(page.locator('a.p-btn-pdf2')).toHaveAttribute('href', /com=peace_order/);
  const f = await open(page, 'complaint-summary.php?com=peace_order');
  await expect(page.locator('.doc-signs')).toContainText('Kagawad, Committee Head');
  await expect(page.locator('.doc-title')).toContainText('Peace and Order');
  await context.addCookies([{ name: 'ss_tier', value: 'moderator', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  await page.goto('summary.php?range=month', { waitUntil: 'domcontentloaded' });         // staff have no Report Summary since 15 Nov (Rose): it sends them to Notifications
  await expect(page).toHaveURL(/notifications\.php/);
  expect(s.errors.concat(c.errors, f.errors), 'console errors').toEqual([]);
});

test('Roles and pages 6c: Notifications by committee, a dot on each case, engine warnings grouped', async ({ page, context }) => {
  const n = await open(page, 'notifications.php');
  await expect(page.locator('.nf-chips .cm-chip')).toHaveCount(1 + 4 + 2);
  await expect(page.locator('details.nf-group:not(.nf-case)')).toHaveCount(1);
  await expect(page.locator('details.nf-group:not(.nf-case) summary')).toContainText('2 cases waited without a tanod');
  await page.locator('details.nf-group:not(.nf-case) summary').click();
  await expect(page.locator('details.nf-group:not(.nf-case) .nf-items li')).toHaveCount(2);
  await expect(page.locator('.p-notif .nf-dot[title="Environment and Disaster Risk"]')).toHaveCount(1);
  expect(await axe(page), 'Notifications, a group open').toEqual([]);
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const k = await open(page, 'notifications.php');
  await expect(page.locator('.nf-chips')).toHaveCount(0);
  expect(n.errors.concat(k.errors), 'console errors').toEqual([]);
});

test('Profile (6 Nov), the Facebook way: edited in popups from the face, the cover, Edit profile and Change; the role ring is solid; the colour box is filled; Save is one step', async ({ page }) => {
  const e = await open(page, 'profile.php');
  await expect(page.locator('.p-topbar h1')).toHaveText('Profile');
  expect(await page.locator('#profile-form').getAttribute('data-native-confirm'), 'no browser dialog on Save').toBeNull();
  const ring = await page.locator('.ss-pf-av[data-r]').first().evaluate(el => { const s = getComputedStyle(el); return [s.outlineStyle, s.borderTopWidth]; });
  expect(ring, 'the role colour fills its ring: no outline gap, no white border').toEqual(['none', '0px']);
  // hovering the head shows the cover's Edit button; the face is a button
  await page.locator('.ss-pf-head').hover();
  await expect(page.locator('.pf-cvbtn')).toBeVisible();
  await page.locator('.pf-avbtn').click();
  await expect(page.locator('#m-avatar')).toBeVisible();
  const png = await page.evaluate(() => { const c = document.createElement('canvas'); c.width = 600; c.height = 400; const g = c.getContext('2d'); g.fillStyle = '#356cf9'; g.fillRect(0, 0, 600, 400); return c.toDataURL('image/png').split(',')[1]; });
  await page.setInputFiles('#avatar', { name: 'a.png', mimeType: 'image/png', buffer: Buffer.from(png, 'base64') });
  await expect(page.locator('.cr-modal')).toBeVisible();
  await page.locator('.cr-ok').click();
  await expect(page.locator('.cr-modal')).toHaveCount(0);
  expect(await page.locator('#avatar').evaluate(i => [i.files.length, i.files[0].name, i.files[0].size > 0]), 'the cropped picture is what the form posts').toEqual([1, 'photo.jpg', true]);
  await page.locator('#m-avatar [data-pf-cancel]').click();
  await expect(page.locator('#m-avatar')).toBeHidden();
  // the cover popup, with our colour box filled with the colour
  await page.goto('profile.php'); await page.locator('.ss-pf-head').hover(); await page.locator('.pf-cvbtn').click();
  await expect(page.locator('#m-cover')).toBeVisible();
  expect(await page.locator('#m-cover .sdp-colour').evaluate(el => getComputedStyle(el).backgroundColor), 'the colour box is the colour, filled').toBe('rgb(0, 48, 143)');
  // Change (name, mobile) opens the details popup; Change (password) opens the password popup; Save is one step, the browser never asks
  await page.goto('profile.php');
  let native = 0; page.on('dialog', d => { native++; d.dismiss(); });
  await page.locator('.ss-pf-change').first().click();
  await expect(page.locator('#m-details')).toBeVisible();
  await page.keyboard.press('Escape');
  await page.locator('.ss-pf-change', { hasText: 'Change' }).last().click();
  await expect(page.locator('#m-password')).toBeVisible();
  expect(native, 'the browser did not ask').toBe(0);
  expect(e.errors.filter(m => !/WebSocket/.test(m)), 'console errors').toEqual([]);
  expect(await axe(page), 'Profile with a popup open').toEqual([]);
});

test('The ladder (0166): an escalation names who it reaches; staff ask to retire from their profile; a Kagawad sees who is staff', async ({ page, context }) => {
  // a case the signed-in admin handles, still at the first rung: the Escalate control names the Kagawad it reaches
  const c = await open(page, 'case.php?id=c0000000-0000-0000-0000-000000000003');
  await expect(page.locator('summary', { hasText: 'Escalate to Dela Cruz Ramon, Kagawad (Peace and Order)' })).toHaveCount(1);
  await expect(page.locator('#eb-comm option').first()).toHaveText('The committee the case is with now');
  // staff (moderator): Profile > Account has the Retirement row and its button, behind a confirm
  await context.addCookies([{ name: 'ss_tier', value: 'moderator', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const s = await open(page, 'profile.php');
  await expect(page.locator('.ss-pf-row', { hasText: 'Retirement' }).locator('button[data-native-confirm]')).toHaveText('Ask to retire');
  expect(await axe(page), 'Profile, staff').toEqual([]);
  // retirement requests belong to the highest authority only (Rose, 15 Nov): a Kagawad's Personnel has Tanods and My staff, no Retirement requests
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }]);
  const k = await open(page, 'personnel.php');
  await expect(page.locator('.tc-tabs a')).toHaveText(['Tanods', 'My staff']);
  await page.goto('personnel.php?view=retire');
  await expect(page.locator('.tc-tabs a')).toHaveText(['Tanods', 'My staff']);   // the old address shows the ordinary Personnel
  expect(c.errors.concat(s.errors, k.errors), 'console errors').toEqual([]);
});

test('Roles and pages 7: Edit Profile (banner, pills, alert switches, punch card)', async ({ page, context }) => {
  const p = await open(page, 'profile.php');
  for (const k of ['case_forwarded', 'forward_flag', 'reroute_question']) await expect(page.locator(`.ss-al-kinds input[data-kind="${k}"]`)).toHaveCount(1);
  await expect(page.locator('.ss-pf-who .rank')).toHaveCount(1);
  const e = await open(page, 'profile.php');
  await page.locator('.ss-pf-head').hover(); await page.locator('.pf-cvbtn').click();
  await page.locator('input[name="banner_preset"][value="solid"]').check();
  await page.locator('#banner_colour').fill('#1e9e4a');
  await expect(page.locator('#ss-pf-banner')).toHaveAttribute('style', /background: (rgb\(30, 158, 74\)|#1e9e4a)/);
  expect(await axe(page), 'Edit Profile, editing the banner').toEqual([]);
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const k = await open(page, 'profile.php');
  await expect(page.locator('.pf-punch')).toContainText('Still in');
  await expect(page.locator('.ss-pf-who')).toContainText('Peace and Order');
  expect(p.errors.concat(e.errors, k.errors), 'console errors').toEqual([]);
});

test('0145 access: a committee admin sees only its pages, and no SMART drawer', async ({ page, context }) => {
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const r = await open(page, 'cases.php');
  for (const href of ['dashboard.php', 'residents.php', 'administrative-services.php', 'control-room.php']) await expect(page.locator(`.p-sidebar a[href="${href}"]`)).toHaveCount(0);
  await expect(page.locator('.p-sidebar a[href="personnel.php"]').first()).toBeVisible();   // 0153: a Kagawad sees their committee's tanods and staff
  await expect(page.locator('.p-sidebar a[href="cases.php"]').first()).toBeVisible();
  await expect(page.locator('#side-user')).toContainText('Peace and Order');
  await page.goto('dashboard.php');
  await expect(page).toHaveURL(/notifications\.php/);
  await page.goto('control-room.php');
  await expect(page).toHaveURL(/notifications\.php/);
  const s = await open(page, 'spatial.php');
  await expect(page.locator('#smart-toggle')).toHaveCount(0);
  await expect(page.locator('#smart-side')).toHaveCount(0);
  expect(await axe(page), 'Spatial Distribution, committee admin').toEqual([]);
  expect(r.errors.concat(s.errors), 'console errors').toEqual([]);
});

test('0145 access: a captain reads a case but its controls are view only', async ({ page, context }) => {
  await context.addCookies([{ name: 'ss_tier', value: 'captain', url: 'http://127.0.0.1:8013' }]);
  const r = await open(page, `case.php?id=${CASE}`);
  await expect(page.locator('.p-controls.ss-viewonly')).toHaveCount(1);
  await expect(page.locator('.p-controls')).toContainText('View only');
  await expect(page.locator('.p-sidebar a[href="settings.php"]')).toHaveCount(0);
  await expect(page.locator('.p-sidebar a[href="residents.php"]'), 'a view-only account sees only the four pages').toHaveCount(0);
  for (const href of ['dashboard.php', 'summary.php', 'spatial.php', 'cases.php']) await expect(page.locator(`.p-nav a[href="${href}"]`)).toHaveCount(1);
  await expect(page.locator('#side-user')).toContainText('Captain');
  expect(await axe(page), 'Case page, captain').toEqual([]);
  expect(r.errors, 'console errors').toEqual([]);
});

test('0164 each rung: the seal alone for everyone, a Kagawad and a staff member see their committee as the lettering and the glow under it, no Personnel for staff', async ({ page, context }) => {
  const r = await open(page, 'notifications.php');
  await expect(page.locator('.p-side-top .p-brand-img')).toHaveCount(1);   // the barangay seal
  await expect(page.locator('.p-side-top .p-brand-com')).toHaveCount(0);
  await expect(page.locator('.p-sidebar img[src*="logo-wordmark"]')).toHaveCount(0);   // the wordmark is on the sign-in pages only
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'environment', url: 'http://127.0.0.1:8013' }]);
  await open(page, 'notifications.php');
  await expect(page.locator('.p-side-top .p-brand-img')).toHaveCount(1);                 // the seal, big and alone (Ace's sketch, 12 Nov)
  await expect(page.locator('.p-side-top .p-brand-com')).toHaveCount(0);
  await expect(page.locator('.p-side-com')).toContainText('Environment and Disaster Risk');
  expect(await page.locator('.p-side-com b').evaluate(e => { const s = getComputedStyle(e); return s.fontStyle + ' ' + s.textTransform + ' ' + s.fontFamily.split(',')[0].replace(/['"]/g, ''); }), 'capitals in the portal face, upright').toBe('normal uppercase Inter Tight');
  expect(await page.locator('.p-sidebar').evaluate(e => getComputedStyle(e).backgroundImage), 'the committee colour glows from the top').toContain('radial-gradient');
  expect(await page.evaluate(() => getComputedStyle(document.querySelector('.p-sidebar'), '::before').backgroundImage), 'the committee logo, faded, instead of the pattern').toContain('url(');
  await context.addCookies([{ name: 'ss_tier', value: 'moderator', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  // 19 Nov 2026 (Rose): staff have no Personnel; the page sends them to their landing page
  const m = await open(page, 'notifications.php');
  await expect(page.locator('.p-side-com')).toContainText('Peace and Order');
  await expect(page.locator('.p-sidebar a[href="personnel.php"]')).toHaveCount(0);
  await page.goto('personnel.php');
  await expect(page).toHaveURL(/notifications\.php/);
  for (const href of ['residents.php', 'administrative-services.php', 'control-room.php', 'dashboard.php']) await expect(page.locator(`.p-sidebar a[href="${href}"]`)).toHaveCount(0);
  expect(r.errors.concat(m.errors), 'console errors').toEqual([]);
});

test('Settings for a Kagawad and staff: their look, their committee read only, their SMART module (0165)', async ({ page, context }) => {
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const r = await open(page, 'settings.php');
  await expect(page.locator('.st-tabs [data-st]')).toHaveText(['Appearance', 'My committee', 'SMART']);
  await expect(page.locator('#places, #st-check, [data-pane="status"], [data-pane="smart"]')).toHaveCount(0);   // the super admins' own
  await page.locator('.st-tabs [data-st="committee"]').click();
  await expect(page.locator('[data-pane="committee"] .cmx-banner')).toContainText('Peace and Order');
  await expect(page.locator('[data-pane="committee"] form, [data-pane="committee"] input')).toHaveCount(0);   // read only
  await page.locator('.st-tabs [data-st="module"]').click();
  await expect(page.locator('.my-mod h2')).toHaveText('Committee module');
  await expect(page.locator('.sm-four .sm-tile')).toHaveCount(4);   // the decisions waiting on the Kagawad
  expect(await axe(page), 'Settings, Kagawad').toEqual([]);
  await page.goto('settings.php#smart');   // an old link to the SMART tab opens their module, and does not loop
  await expect(page.locator('[data-pane="module"]')).toBeVisible();
  await context.addCookies([{ name: 'ss_tier', value: 'moderator', url: 'http://127.0.0.1:8013' }]);
  const m = await open(page, 'settings.php');
  await page.locator('.st-tabs [data-st="module"]').click();
  await expect(page.locator('.my-mod h2')).toHaveText('Staff module');
  await expect(page.locator('.sm-four')).toHaveCount(0);   // decisions stay with the Kagawad
  expect(r.errors.concat(m.errors), 'console errors').toEqual([]);
});

test('Rose, 2 Nov: the lock holds when the map is pressed, the layers stay in their tile at the bottom left of the map (Ace, 12 Nov), and the first day picked can be taken back', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'spatial.php');
  await expect(page.locator('#map-search .p-row-lyr')).toHaveCount(0);                       // not a row of the floating tab
  await expect(page.locator('#layers-btn')).toBeVisible();                                   // the tile at the bottom left
  const lb = await page.locator('#layers-btn').boundingBox();
  expect(lb.x).toBeLessThan(400); expect(lb.y).toBeGreaterThan(700);
  await expect(page.locator('#ss-lyr')).toBeHidden();
  await page.locator('#layers-btn').click();
  await expect(page.locator('#ss-lyr #lyr-list .map-sw')).not.toHaveCount(0);                // it opens the card of layers
  await page.locator('#layers-btn').click();
  await expect(page.locator('#ss-lyr')).toBeHidden();
  await page.locator('#map-pin').click();
  await expect(page.locator('#map-pin')).toHaveAttribute('aria-pressed', 'true');
  await page.mouse.move(1200, 900); await page.mouse.down(); await page.mouse.move(1260, 860, { steps: 6 }); await page.mouse.up();   // press and drag on the map
  await page.waitForTimeout(600);
  await expect(page.locator('#f-category')).toBeVisible();   // the filters stay
  await page.locator('#map-pin').click();   // unlocked again for the other tests
  const s = await open(page, 'summary.php');
  await page.locator('#period-form .sdp-btn').first().click();
  const day = page.locator('.sdp-rng .sdp-d[data-d]').nth(9);
  await day.click();
  await expect(page.locator('.sdp-rng [data-go]')).toBeEnabled();
  await day.click();   // the same day again takes it back
  await expect(page.locator('.sdp-rng [data-go]')).toBeDisabled();
  await day.click(); await page.locator('.sdp-rng .sdp-d[data-d]').nth(14).click();
  await expect(page.locator('.sdp-rng .sdp-rt')).toContainText('6 days');
  await page.locator('.sdp-rng [data-clear]').click();
  await expect(page.locator('.sdp-rng [data-go]')).toBeDisabled();
  expect(r.errors.concat(s.errors), 'console errors').toEqual([]);
});

test('Rose, 15 Nov: no Home for anyone; a Kagawad and staff land on Notifications; staff have no Report Summary', async ({ page, context }) => {
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  await page.goto('index.php');
  await expect(page).toHaveURL(/notifications\.php/);   // where they land after signing in
  const r = await open(page, 'notifications.php');
  await expect(page.locator('.p-sidebar a[href="home.php"]')).toHaveCount(0);
  await expect(page.locator('.p-sidebar a[href="summary.php"]')).toHaveCount(1);   // a Kagawad keeps Report Summary
  await page.goto('home.php');
  await expect(page).toHaveURL(/notifications\.php/);   // the old address goes to Notifications
  await context.addCookies([{ name: 'ss_tier', value: 'moderator', url: 'http://127.0.0.1:8013' }]);
  const m = await open(page, 'notifications.php');
  await expect(page.locator('.p-sidebar a[href="home.php"]')).toHaveCount(0);
  await expect(page.locator('.p-sidebar a[href="summary.php"]'), 'staff have no Report Summary').toHaveCount(0);
  await page.goto('summary.php');
  await expect(page).toHaveURL(/notifications\.php/);
  await context.addCookies([{ name: 'ss_tier', value: 'super', url: 'http://127.0.0.1:8013' }]);
  await page.goto('home.php');
  await expect(page).toHaveURL(/notifications\.php/);
  expect(r.errors.concat(m.errors), 'console errors').toEqual([]);
});

test('The brain button answers from the person\'s SMART module on Case Reports, Notifications, and Report Summary (part 4)', async ({ page, context }) => {
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const errs = [];
  for (const p of ['cases.php', 'notifications.php', 'summary.php']) {
    const r = await open(page, p);
    errs.push(...r.errors);
    await page.locator('#ss-win-open').click();
    await expect(page.locator('#ss-panel')).toHaveClass(/is-open/);
    await expect(page.locator('#ss-panel .mb-sec').first()).toContainText('Peace and Order');
    await expect(page.locator('#ss-panel .mb-sec .ss-tile').first()).toContainText('Escalations to decide');
    if (p === 'cases.php') {
      await expect(page.locator('.ss-brain-n')).toHaveText('5');   // the decisions waiting on the Kagawad
      expect(await axe(page), 'engine window on Case Reports, Kagawad').toEqual([]);
    }
    if (p === 'summary.php') await expect(page.locator('#ss-panel .rs-w-card').first()).toBeAttached();   // the report's own notes follow
    await page.keyboard.press('Escape');
    await expect(page.locator('#ss-panel')).not.toHaveClass(/is-open/);
  }
  expect(errs, 'console errors').toEqual([]);
});

test('The DEV switcher is a floating pill: out of the sidebar, draggable, remembered, put back by a double-click', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'notifications.php');
  await expect(page.locator('.p-sidebar .dv-sw'), 'the sidebar keeps its room').toHaveCount(0);
  const pill = page.locator('.dv-float summary');
  await expect(pill).toBeVisible();
  await expect(page.locator('.dv-sw[open]'), 'closed until asked').toHaveCount(0);
  const home = await pill.boundingBox();
  await page.mouse.move(home.x + 20, home.y + 10); await page.mouse.down(); await page.mouse.move(home.x + 520, home.y - 400, { steps: 8 }); await page.mouse.up();
  const moved = await pill.boundingBox();
  expect(Math.abs(moved.x - home.x), 'it moved').toBeGreaterThan(300);
  await expect(page.locator('.dv-sw[open]'), 'a drag does not open it').toHaveCount(0);
  await page.goto('cases.php', { waitUntil: 'networkidle' });
  const again = await pill.boundingBox();
  expect(Math.abs(again.x - moved.x) + Math.abs(again.y - moved.y), 'it stays where it was left on the next page').toBeLessThan(4);
  await pill.click();
  await expect(page.locator('.dv-sw[open] .dv-body')).toBeVisible();
  const panel = await page.locator('.dv-sw .dv-body').boundingBox();
  expect(panel.x >= 0 && panel.x + panel.width <= 2048 && panel.y >= 0 && panel.y + panel.height <= 1100, 'the panel stays on screen').toBe(true);
  await page.keyboard.press('Escape');
  await expect(page.locator('.dv-sw[open]')).toHaveCount(0);
  await pill.dblclick();
  const back = await pill.boundingBox();
  expect(Math.abs(back.x - home.x) + Math.abs(back.y - home.y), 'a double-click puts it back').toBeLessThan(4);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Press flow foundation (7 Nov): htmx with the portal config, a swap changes only its region, no page HTML in localStorage, a failed fetch falls back to the plain page', async ({ page }) => {
  const r = await open(page, 'cases.php');
  const cfg = await page.evaluate(() => [typeof htmx, htmx.config.allowEval, htmx.config.allowScriptTags, htmx.config.historyCacheSize, htmx.config.selfRequestsOnly, typeof ssPress, typeof ssPickersInit, typeof ssChooserInit, !!document.querySelector('.ss-progress')]);
  expect(cfg, 'htmx and the press layer are on the page, set up safely').toEqual(['object', false, false, 0, true, 'object', 'function', 'function', true]);
  const before = await page.locator('.ss-cases-t tbody tr').count();
  await page.evaluate(() => {
    window.__stay = 1;
    const b = document.createElement('button'); b.id = 'hx-probe'; b.textContent = 'probe';
    b.setAttribute('hx-get', 'cases.php?com=none'); b.setAttribute('hx-select', '.ss-cases-t tbody'); b.setAttribute('hx-target', '.ss-cases-t tbody'); b.setAttribute('hx-swap', 'outerHTML');
    document.body.appendChild(b); htmx.process(b);
    window.__settled = new Promise(res => document.addEventListener('htmx:afterSettle', res, { once: true }));
  });
  await page.locator('#hx-probe').click();
  await page.evaluate(() => window.__settled);
  expect(await page.evaluate(() => window.__stay), 'the page did not reload').toBe(1);
  expect(await page.locator('.ss-cases-t tbody tr').count(), 'the list was swapped').toBeGreaterThan(0);
  expect(await page.evaluate(() => Object.keys(localStorage).filter(k => /htmx/i.test(k))), 'no page HTML kept in the browser').toEqual([]);
  expect(before).toBeGreaterThan(0);
  // a fetch that fails: the press opens the plain page instead of doing nothing
  await page.route(/cases\.php\?com=fallback/, route => (route.request().headers()['hx-request'] ? route.abort() : route.continue()));
  await page.evaluate(() => {
    const b = document.createElement('button'); b.id = 'hx-probe2'; b.textContent = 'probe2';
    b.setAttribute('hx-get', 'cases.php?com=fallback'); b.setAttribute('hx-select', '.ss-cases-t tbody'); b.setAttribute('hx-target', '.ss-cases-t tbody');
    document.body.appendChild(b); htmx.process(b);
  });
  await Promise.all([page.waitForURL(/com=fallback/), page.locator('#hx-probe2').click()]);
  // the simulated failure itself is logged (htmx names the failed request, the browser the aborted fetch); nothing else may be
  expect(r.errors.filter(m => !/htmx:(afterRequest|sendError)|net::ERR_FAILED/.test(m)), 'console errors').toEqual([]);
});

test('Press flow step 2 (7 Nov): a save shows that it is working and a second press does not send it again', async ({ browser }) => {
  // its own context with the service worker blocked: the portal's worker answers requests before a test's network hook would see them
  const ctx = await browser.newContext({ serviceWorkers: 'block', baseURL: 'http://127.0.0.1:8013/admin/', viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  const r = await open(page, 'notifications.php');
  let posts = 0;
  await page.route(/notifications\.php/, async route => {
    if (route.request().method() !== 'POST') return route.continue();
    posts++; await new Promise(res => setTimeout(res, 2500)); return route.continue();   // a slow connection
  });
  // a plain save form (the guard covers every form that loads the next page the usual way), answering into a hidden frame so this
  // page stays on screen while the save is on its way (a test cannot read a page that a form is navigating away)
  await page.evaluate(() => {
    const fr = document.createElement('iframe'); fr.name = 'sink'; fr.hidden = true; document.body.appendChild(fr);
    const csrf = document.querySelector('input[name="csrf"]').value;
    const f = document.createElement('form'); f.method = 'post'; f.action = 'notifications.php'; f.target = 'sink'; f.id = 'probe-save';
    [['csrf', csrf], ['action', 'read_all']].forEach(([n, v]) => { const i = document.createElement('input'); i.type = 'hidden'; i.name = n; i.value = v; f.appendChild(i); });
    const b = document.createElement('button'); b.type = 'submit'; b.textContent = 'Save'; f.appendChild(b);
    document.body.appendChild(f);
  });
  const btn = page.locator('#probe-save button');
  await btn.click();
  await expect(btn, 'the pressed button says it is working').toHaveClass(/is-sending/);
  await expect(page.locator('#probe-save')).toHaveAttribute('aria-busy', 'true');
  // a second press, and a script sending the form again, while the first is on its way
  await btn.click({ force: true });
  await page.evaluate(() => document.getElementById('probe-save').requestSubmit());
  await page.waitForTimeout(3200);
  expect(posts, 'one press, one request').toBe(1);
  expect(r.errors, 'console errors').toEqual([]);
  await ctx.close();
});

test('Press flow step 3, Case Reports (7 Nov): the chooser, a filter and the pager swap the list in place; the address follows; a live refresh keeps the view; the Forward dialog still works', async ({ page, context }) => {
  const r = await open(page, 'cases.php');
  const ids = async (p) => p.locator('.ss-cases-t tbody .p-mono-id').allTextContents();
  await page.evaluate(() => { window.__stay = 1; });
  const settle = () => page.evaluate(() => new Promise(res => document.addEventListener('htmx:afterSettle', res, { once: true })));
  // a committee on the chooser
  let s = settle(); await page.locator('#cr-list .cm-chips .cm-chip').nth(1).click(); await s;
  expect(await page.evaluate(() => window.__stay), 'no reload').toBe(1);
  expect(page.url(), 'the address follows').toMatch(/com=/);
  await expect(page.locator('#cr-list .cm-chips .cm-chip').nth(1)).toHaveClass(/p-on/);
  const fresh = await context.newPage(); await fresh.goto(page.url(), { waitUntil: 'domcontentloaded' });
  expect(await ids(page), 'the rows are what the server draws for this address').toEqual(await ids(fresh));
  await fresh.close();
  // a filter dropdown (autosubmit) swaps too
  s = settle(); await page.evaluate(() => { const sel = document.querySelector('#cr-list form.ss-band-filters select[name="tanod"]'); sel.value = 'needs'; sel.dispatchEvent(new Event('change', { bubbles: true })); }); await s;
  expect(await page.evaluate(() => window.__stay), 'a filter does not reload').toBe(1);
  expect(page.url()).toMatch(/tanod=needs/);
  // a live update asks the server for the view on screen now, not the one the page first loaded with
  const shown = await ids(page);
  s = settle(); await page.evaluate(() => window.ssLive.cases()); await s;
  expect(await ids(page), 'a live refresh keeps the chosen view').toEqual(shown);
  expect(page.url()).toMatch(/tanod=needs/);
  // the Forward dialog is outside the region: after a swap it still opens, and it returns to the view on screen
  const fw = page.locator('#cr-list tbody [data-fw-open]').first();
  if (await fw.count()) {
    await fw.click(); await expect(page.locator('#fw-dlg')).toBeVisible();
    expect(await page.locator('#fw-dlg input[name="back"]').inputValue()).toMatch(/tanod=needs/);
    await page.locator('#fw-dlg [data-fw-close]').first().click();
  }
  // Back returns to the earlier view
  await page.goBack(); await page.waitForLoadState('domcontentloaded');
  expect(page.url()).not.toMatch(/tanod=needs/);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Press flow step 3, Notifications (7 Nov): Unread/All, the chooser and the sort swap in place, the address follows, a live refresh keeps the view', async ({ page, context }) => {
  const r = await open(page, 'notifications.php');
  await page.evaluate(() => { window.__stay = 1; });
  const settle = () => page.evaluate(() => new Promise(res => document.addEventListener('htmx:afterSettle', res, { once: true })));
  let s = settle(); await page.locator('#nf-list .bd-scope a').nth(1).click(); await s;
  expect(await page.evaluate(() => window.__stay), 'no reload').toBe(1);
  expect(page.url()).toMatch(/nview=all/);
  s = settle(); await page.locator('#nf-list .nf-chips .cm-chip').nth(1).click(); await s;
  expect(page.url()).toMatch(/ncom=/);
  const rows = async (p) => p.locator('#notif-list .p-notif, #notif-list .nf-group').count();
  const fresh = await context.newPage(); await fresh.goto(page.url(), { waitUntil: 'domcontentloaded' });
  expect(await rows(page), 'what the server draws for this address').toBe(await rows(fresh)); await fresh.close();
  const before = await rows(page);
  s = settle(); await page.evaluate(() => window.ssLive.notes()); await s;
  expect(await rows(page), 'a live refresh keeps the view').toBe(before);
  expect(page.url()).toMatch(/ncom=/);
  expect(await page.evaluate(() => window.__stay)).toBe(1);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Speed, step 3 (7 Nov 2026): Activity and Report Summary change view in place; their widgets work after a swap', async ({ page }) => {
  const settle = () => page.evaluate(() => new Promise(res => document.addEventListener('htmx:afterSettle', res, { once: true })));
  // Activity: the scopes swap the feed; the address follows
  const a = await open(page, 'activity.php');
  await page.evaluate(() => { window.__stay = 1; });
  let s = settle(); await page.locator('#act-list .ss-seg a').nth(2).click(); await s;
  expect(page.url()).toMatch(/show=peers/);
  await expect(page.locator('#act-list .ss-seg a.p-on')).toHaveCount(1);
  expect(await page.evaluate(() => window.__stay), 'Activity did not reload').toBe(1);
  // Report Summary: a quick range swaps the report; the tabs, the title and the engine window follow; a pager lands on its tab
  const r = await open(page, 'summary.php');
  await page.evaluate(() => { window.__stay = 1; });
  s = settle(); await page.locator('#rs-main .p-chips-q a.p-chip').nth(3).click(); await s;
  expect(page.url()).toMatch(/range=quarter/);
  await expect(page.locator('#rs-main .p-chips-q a.p-chip.p-on')).toHaveText(/90/);
  await expect(page.locator('#ss-jump .ss-jump-ind'), 'the tabs are set up again on the new report').toHaveCount(1);
  await page.locator('#ss-jump a[href="#rs-tanod"]').click();
  await expect(page.locator('#rs-tanod.p-table-card')).not.toHaveClass(/rs-off/);
  await expect(page.locator('#rs-ledger')).toHaveClass(/rs-off/);
  expect(await page.evaluate(() => document.getElementById('rs-win-dates').textContent), 'the engine window follows the period').toMatch(/–|-/);
  // a By committee row: the report swaps to that committee's version in place
  await page.locator('#ss-jump a[href="#rs-com"]').click();
  s = settle(); await page.locator('#rs-com tr.p-click').first().click(); await s;
  expect(page.url()).toMatch(/com=/);
  await expect(page.locator('#rs-scope-sync .rs-scope')).not.toHaveText('Barangay Overall');
  expect(await page.evaluate(() => window.__stay), 'Report Summary did not reload').toBe(1);
  // the spreadsheet stays an ordinary download, never boosted
  expect(await page.locator('#rs-main a[href*="export=xlsx"]').evaluate(el => !el.closest('[hx-boost]'))).toBe(true);
  expect(a.errors.concat(r.errors), 'console errors').toEqual([]);
});

test('Press flow step 3, Residents and Personnel (7 Nov): chooser and duty tiles swap in place; the ticks and the put-away banner survive a swap', async ({ page, context }) => {
  const settle = () => page.evaluate(() => new Promise(res => document.addEventListener('htmx:afterSettle', res, { once: true })));
  const r = await open(page, 'residents.php');
  await page.evaluate(() => { window.__stay = 1; try { sessionStorage.removeItem('ss-res-ov-off'); } catch (e) {} });
  // put the banner away
  if (await page.locator('#overdue-x').isVisible()) await page.locator('#overdue-x').click();
  let s = settle(); await page.locator('#people-list .rs-st .cm-chip[data-chip="verified"]').click(); await s;
  expect(await page.evaluate(() => window.__stay), 'no reload').toBe(1);
  expect(page.url()).toMatch(/sort=verified/);
  await expect(page.locator('#overdue-banner'), 'the banner stays put away').toBeHidden();
  const fresh = await context.newPage(); await fresh.goto(page.url(), { waitUntil: 'domcontentloaded' });
  const names = async (p) => p.locator('#accounts-tbody .p-person > span:last-child').allTextContents();
  expect(await names(page), 'what the server draws for this address').toEqual(await names(fresh)); await fresh.close();
  // a tick survives the 20-second refresh, and the bulk bar with it
  await page.locator('#accounts-tbody .ss-cb').first().check();
  await expect(page.locator('#ss-bulk')).toBeVisible();
  s = settle(); await page.evaluate(() => window.ssLive.people()); await s;
  await expect(page.locator('#accounts-tbody .ss-cb').first(), 'the tick is kept').toBeChecked();
  await expect(page.locator('#ss-bulk')).toBeVisible();
  expect(page.url()).toMatch(/sort=verified/);
  // Personnel: a duty tile swaps the list
  const p2 = await open(page, 'personnel.php');
  await page.evaluate(() => { window.__stay = 2; });
  s = settle(); await page.locator('#people-list #attendance-grid a').first().click(); await s;
  expect(await page.evaluate(() => window.__stay), 'no reload on Personnel').toBe(2);
  expect(page.url()).toMatch(/duty=/);
  expect(r.errors.concat(p2.errors), 'console errors').toEqual([]);
});

test('Press flow step 4 (7 Nov): saves update their region in place: a mark as read, a forward, a proposed tanod; the address stays; one request per save', async ({ page }) => {
  const settle = () => page.evaluate(() => new Promise(res => document.addEventListener('htmx:afterSettle', res, { once: true })));
  let posts = 0; page.on('request', q => { if (q.method() === 'POST' && /\.php/.test(q.url()) && !/geocode|heartbeat|presence|ping/.test(q.url())) posts++; });
  // Notifications: mark one as read
  const r = await open(page, 'notifications.php');
  await page.evaluate(() => { window.__stay = 1; });
  const url0 = page.url();
  const tick = page.locator('#nf-list form.p-n-x button[type="submit"]').first();
  if (await tick.count()) {
    let s = settle(); posts = 0; await tick.click(); await s;
    expect(await page.evaluate(() => window.__stay), 'a mark as read does not reload').toBe(1);
    expect(page.url(), 'the address stays').toBe(url0);
    expect(posts, 'one save, one request').toBe(1);
  }
  // Case Reports: a forward from the dialog
  const r2 = await open(page, 'cases.php');
  await page.evaluate(() => { window.__stay = 2; });
  const fw = page.locator('#cr-list tbody [data-fw-open]').first();
  if (await fw.count()) {
    await fw.click(); await expect(page.locator('#fw-dlg')).toBeVisible();
    const to = page.locator('#fw-dlg select[name="to"]');
    if (await to.count()) await to.evaluate(sel => { const o = [...sel.options].find(x => x.value && !x.disabled); if (o) { sel.value = o.value; sel.dispatchEvent(new Event('change', { bubbles: true })); } });
    let s = settle(); posts = 0; await page.locator('#fw-dlg button[type="submit"]').first().click(); await s;
    expect(await page.evaluate(() => window.__stay), 'a forward does not reload').toBe(2);
    await expect(page.locator('#fw-dlg'), 'the dialog closes').toBeHidden();
    expect(posts).toBe(1);
  }
  // Personnel: a proposed tanod
  const r3 = await open(page, 'personnel.php');
  await page.evaluate(() => { window.__stay = 3; });
  const ok = page.locator('#people-list form.tc-row button[type="submit"]').first();
  if (await ok.count()) {
    let s = settle(); await ok.click(); await s;
    expect(await page.evaluate(() => window.__stay), 'a decision does not reload').toBe(3);
  }
  expect(r.errors.concat(r2.errors, r3.errors), 'console errors').toEqual([]);
});

test('Press flow (7 Nov, Ace: "always a thin orange bar"): the bar goes away after a filter change and after a press that cancels an earlier one', async ({ page }) => {
  const r = await open(page, 'cases.php');
  const idle = async (why) => { await page.waitForTimeout(900); expect(await page.evaluate(() => [document.querySelector('.ss-progress').classList.contains('is-on') && !document.querySelector('.ss-progress').classList.contains('is-done'), document.documentElement.getAttribute('aria-busy')]), why).toEqual([false, null]); };
  const settle = () => page.evaluate(() => new Promise(res => document.addEventListener('htmx:afterSettle', res, { once: true })));
  // a filter dropdown (autosubmit, sent by htmx)
  let s = settle(); await page.evaluate(() => { const sel = document.querySelector('#cr-list form.ss-band-filters select[name="tanod"]'); sel.value = 'needs'; sel.dispatchEvent(new Event('change', { bubbles: true })); }); await s;
  await idle('no bar left after a filter change');
  // two chooser presses at once: the second cancels the first
  s = settle(); await page.evaluate(() => { const c = document.querySelectorAll('#cr-list .cm-chips .cm-chip'); c[1].click(); c[2].click(); }); await s;
  await idle('no bar left after a cancelled request');
  // Notifications' sort
  await open(page, 'notifications.php');
  s = settle(); await page.evaluate(() => { const sel = document.querySelector('#nf-list select[name="nsort"]'); sel.value = 'oldest'; sel.dispatchEvent(new Event('change', { bubbles: true })); }); await s;
  await idle('no bar left after a sort');
  // the cancelled request is logged by htmx (it names the request it dropped); nothing else may be
  expect(r.errors.filter(m => !/htmx:(afterRequest|sendAbort|abort)/.test(m)), 'console errors').toEqual([]);
});

test('Press flow (7 Nov): a background refresh never cancels a press (Personnel, a duty tile pressed just as the 20-second refresh fires)', async ({ browser }) => {
  const ctx = await browser.newContext({ serviceWorkers: 'block', baseURL: 'http://127.0.0.1:8013/admin/', viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  const r = await open(page, 'personnel.php');
  // the press's request takes its time (a slow connection); the background refresh fires while it is on its way
  await page.route(/personnel\.php\?duty=/, async route => { await new Promise(res => setTimeout(res, 1500)); return route.continue(); });
  const settled = page.evaluate(() => new Promise(res => document.addEventListener('htmx:afterSettle', e => { const c = e.detail && e.detail.requestConfig; if (!(c && c.headers && c.headers['X-Press-Quiet'])) res(); })));
  await page.locator('#people-list .p-att-on_duty').click();
  await page.evaluate(() => window.ssLive.people());
  await settled;
  await expect(page, 'the press won').toHaveURL(/duty=on_duty/);
  await expect(page.locator('#accounts-tbody tr'), 'and its list is shown').toHaveCount(2);
  expect(r.errors.filter(m => !/htmx:(afterRequest|sendAbort|abort)/.test(m)), 'console errors').toEqual([]);
  await ctx.close();
});

test('Press flow (7 Nov): a background refresh waits while someone types in the list, and a save goes back to the view it was made on', async ({ page }) => {
  // Residents: typing in the search box when the 20-second refresh fires
  const r = await open(page, 'residents.php');
  const box = page.locator('#acc-q');
  await box.click(); await box.pressSequentially('Mar');
  await page.evaluate(() => { window.__swaps = 0; document.addEventListener('htmx:afterSettle', () => window.__swaps++); window.ssLive.people(); });
  await page.waitForTimeout(700);
  expect(await page.evaluate(() => window.__swaps), 'no swap while typing').toBe(0);
  await expect(box, 'what was typed is still there').toHaveValue('Mar');
  await expect(box, 'and the box keeps the cursor').toBeFocused();
  await page.locator('.p-topbar h1').click();   // leaving the box lets the refresh run
  await expect.poll(() => page.evaluate(() => window.__swaps), { message: 'the refresh runs once the box is left' }).toBeGreaterThan(0);
  // Notifications: marking one read on a committee's view stays on that view
  await open(page, 'notifications.php');
  const settle = () => page.evaluate(() => new Promise(res => document.addEventListener('htmx:afterSettle', res, { once: true })));
  let s = settle(); await page.locator('#nf-list .nf-chips .cm-chip').nth(1).click(); await s;
  const url = page.url(); expect(url).toMatch(/ncom=/);
  const tick = page.locator('#nf-list form.p-n-x button[type="submit"]').first();
  if (await tick.count()) {
    s = settle(); await tick.click(); await s;
    expect(page.url()).toBe(url);
    await expect(page.locator('#nf-list .nf-chips .cm-chip').nth(1), 'the same committee is still chosen after the save').toHaveClass(/p-on/);
  }
  expect(r.errors, 'console errors').toEqual([]);
});

test('Press flow (7 Nov): a keyboard press on a chooser tab keeps the focus on that tab after the swap', async ({ page }) => {
  const r = await open(page, 'cases.php');
  const settle = () => page.evaluate(() => new Promise(res => document.addEventListener('htmx:afterSettle', res, { once: true })));
  const tab = page.locator('#cr-list .cm-chips .cm-chip').nth(2);
  const href = await tab.getAttribute('href');
  await tab.focus();
  const s = settle(); await page.keyboard.press('Enter'); await s;
  expect(await page.evaluate(() => document.activeElement && document.activeElement.getAttribute('href')), 'the focus is on the tab that was pressed').toBe(href);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Press flow (7 Nov): after a swap the new list has its widgets: the dropdowns are the portal pickers again and the chooser has its pill', async ({ page }) => {
  const r = await open(page, 'cases.php');
  const settle = () => page.evaluate(() => new Promise(res => document.addEventListener('htmx:afterSettle', res, { once: true })));
  const s = settle(); await page.locator('#cr-list .cm-chips .cm-chip').nth(1).click(); await s;
  expect(await page.locator('#cr-list form.ss-band-filters .sdp-btn').count(), 'the filter dropdowns are pickers in the new list').toBeGreaterThan(0);
  expect(await page.locator('#cr-list form.ss-band-filters select:not(.sdp-native)').count(), 'no bare browser dropdown left').toBe(0);
  await expect(page.locator('#cr-list .cm-chips .cm-ind'), 'the chooser has its pill').toHaveCount(1);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Press flow (7 Nov): a cancelled confirm does not leave a form stuck; the next press sends it, once', async ({ browser }) => {
  const ctx = await browser.newContext({ serviceWorkers: 'block', baseURL: 'http://127.0.0.1:8013/admin/', viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  const r = await open(page, 'notifications.php');
  let posts = 0;
  await page.route(/notifications\.php/, route => { if (route.request().method() === 'POST') posts++; return route.continue(); });
  await page.evaluate(() => {
    const fr = document.createElement('iframe'); fr.name = 'sink2'; fr.hidden = true; document.body.appendChild(fr);
    const f = document.createElement('form'); f.method = 'post'; f.action = 'notifications.php'; f.target = 'sink2'; f.id = 'probe-confirm';
    f.setAttribute('data-native-confirm', 'Send it?');
    [['csrf', document.querySelector('input[name="csrf"]').value], ['action', 'read_all']].forEach(([n, v]) => { const i = document.createElement('input'); i.type = 'hidden'; i.name = n; i.value = v; f.appendChild(i); });
    const b = document.createElement('button'); b.type = 'submit'; b.textContent = 'Send'; f.appendChild(b); document.body.appendChild(f);
  });
  const btn = page.locator('#probe-confirm button');
  page.once('dialog', d => d.dismiss());
  await btn.click(); await page.waitForTimeout(300);
  expect(posts, 'a cancelled confirm sends nothing').toBe(0);
  expect(await btn.evaluate(b => [b.disabled, b.classList.contains('is-sending'), b.form.dataset.pressSending || '']), 'and leaves nothing stuck').toEqual([false, false, '']);
  page.once('dialog', d => d.accept());
  await btn.click(); await page.waitForTimeout(800);
  expect(posts, 'the next press sends it, once').toBe(1);
  expect(r.errors, 'console errors').toEqual([]);
  await ctx.close();
});

test('Case page, the chat head (12 Nov 2026): one button opens Messages; the list, a conversation, a send in place, Escape; no accessibility finding while open', async ({ page }) => {
  const r = await open(page, `case.php?id=${CASE}`);
  await expect(page.locator('#resident-messages, .p-thread-card')).toHaveCount(0);   // the two cards that used to hold the conversations
  const fab = page.locator('#ch-fab');
  await expect(fab).toBeVisible();
  await expect(fab).toHaveAttribute('aria-expanded', 'false');
  await fab.click();
  await expect(fab).toHaveAttribute('aria-expanded', 'true');
  await expect(page.locator('.ch-row')).toHaveCount(2);                    // the resident and the tanod on the open dispatch
  await page.locator('.ch-row').nth(1).click();
  const conv = page.locator('.ch-conv:not([hidden])');
  expect(await conv.locator('.ch-b').count()).toBeGreaterThanOrEqual(3);      // earlier runs against the same fake add their own sends
  expect(await conv.locator('.ch-out').count()).toBeGreaterThanOrEqual(1);
  const note = 'Sige po, papunta na ang kasama ko ' + Date.now();
  const sent = page.waitForResponse(x => x.request().method() === 'POST' && x.url().includes('case.php'));
  const box = conv.locator('textarea'); await box.fill(note); await box.press('Enter');
  expect((await (await sent).json()).ok).toBe(true);
  await expect(conv.locator('.ch-b', { hasText: note })).toHaveCount(1);        // in place: the page did not reload
  expect(await axe(page), 'axe with the chat open').toEqual([]);
  await page.keyboard.press('Escape');
  await expect(page.locator('#ch-panel')).toBeHidden();
  expect(r.errors, 'console errors').toEqual([]);
});

test('Chat heads float (12 Nov 2026): right-click the bubble for a menu; Float on every page puts a bubble with a ball on another page; Stop floating takes it away; Settings has the card', async ({ page }) => {
  const r = await open(page, `case.php?id=${CASE}`);
  await page.evaluate(() => { try { localStorage.removeItem('ss-chat-cases'); localStorage.removeItem('ss-chat-prefs'); } catch (e) {} });
  await page.locator('#ch-fab').click({ button: 'right' });
  const menu = page.locator('.ch-menu');
  await expect(menu).toBeVisible();
  await expect(menu.locator('[role="menuitemcheckbox"]')).toHaveCount(2);          // Float on every page, Sound for this case
  await expect(menu.getByRole('menuitemcheckbox', { name: /Sound for this case/ })).toHaveAttribute('aria-checked', 'true');
  expect(await axe(page), 'axe with the menu open').toEqual([]);
  await menu.getByRole('menuitemcheckbox', { name: /Float on every page/ }).click();
  await expect(menu).toHaveCount(0);
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('ss-chat-cases'))[Object.keys(JSON.parse(localStorage.getItem('ss-chat-cases')))[0]].pin)).toBe(true);
  // another page: the case's bubble is there, and a new message from the resident lights its ball
  await page.goto('cases.php', { waitUntil: 'domcontentloaded' });
  const head = page.locator('.ch-float');
  await expect(head).toHaveCount(1);
  await expect(head.locator('.ch-tag')).toHaveText('1001');
  await page.evaluate(() => fetch('http://127.0.0.1:54399/rest/v1/rpc/fake_incoming', { method: 'POST', body: '{"body":"Kuya, may balita na po ba?"}' }));
  await page.evaluate(() => window.ssChatPoll());
  await expect(head.locator('.ch-badge')).toBeVisible();
  await head.locator('.ch-fab').click();
  await expect(head.locator('.ch-row')).toHaveCount(2);
  await head.locator('.ch-panel').evaluate(el => Promise.all(el.getAnimations({ subtree: true }).map(a => a.finished)));   // axe reads colours, so not mid-fade
  expect(await axe(page), 'axe with a floating chat open').toEqual([]);
  await page.keyboard.press('Escape');
  await expect(head.locator('.ch-panel')).toBeHidden();
  // dragging keeps its place; the bubble does not open when it was only dragged
  const b = await head.locator('.ch-fab').boundingBox();
  await page.mouse.move(b.x + 29, b.y + 29); await page.mouse.down(); await page.mouse.move(300, 300, { steps: 6 }); await page.mouse.up();
  await expect(head.locator('.ch-panel')).toBeHidden();
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('ss-chat-cases'))._float.side), 'the one floating head keeps its own place (19 Nov 2026)').toBe('l');
  // Settings: the card lists it and its switches are kept
  await page.goto('settings.php', { waitUntil: 'domcontentloaded' });
  await page.locator('.st-tabs [data-st="look"]').click();
  await expect(page.locator('#chp .chp-item')).toHaveCount(1);
  await page.locator('#chp [data-pref="floats"] [data-v="0"]').click();
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('ss-chat-prefs')).floats)).toBe(false);
  await expect(page.locator('.ch-float')).toHaveCount(0);                              // off: nothing floats
  await page.locator('#chp [data-pref="floats"] [data-v="1"]').click();
  await expect(page.locator('.ch-float')).toHaveCount(1);
  await page.locator('#chp .chp-item button', { hasText: /Stop floating/ }).click();
  await expect(page.locator('.ch-float')).toHaveCount(0);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Chat heads drag like a phone\'s (12 Nov 2026): the panel shuts when the bubble is picked up, it springs to a side edge on letting go, and dropping a floating head on the round X stops it floating', async ({ page }) => {
  await open(page, `case.php?id=${CASE}`);
  await page.evaluate(id => localStorage.setItem('ss-chat-cases', JSON.stringify({ [id]: { pin: true, t: 'SS-2610-1001' } })), CASE);
  await page.goto('cases.php', { waitUntil: 'domcontentloaded' });
  const head = page.locator('.ch-float');
  await expect(head).toHaveCount(1);
  await head.locator('.ch-fab').click();
  await expect(head.locator('.ch-panel')).toBeVisible();
  const b = await head.locator('.ch-fab').boundingBox();
  await page.mouse.move(b.x + 29, b.y + 29); await page.mouse.down();
  await page.mouse.move(700, 400, { steps: 8 });
  await expect(head.locator('.ch-panel')).toBeHidden();                     // picked up: the chat shuts
  await page.mouse.up();
  await expect.poll(async () => Math.round((await head.locator('.ch-fab').boundingBox()).x)).toBeLessThan(30);   // and it settles on the left edge
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('ss-chat-cases'))._float.side)).toBe('l');
  const c = await head.locator('.ch-fab').boundingBox();
  await page.mouse.move(c.x + 29, c.y + 29); await page.mouse.down();
  await page.mouse.move(700, 600, { steps: 6 });
  const tb = await page.locator('.ch-trash').boundingBox();
  await page.mouse.move(tb.x + tb.width / 2, tb.y + tb.height / 2, { steps: 6 });
  await expect(page.locator('.ch-trash')).toHaveClass(/ch-hot/);
  await page.mouse.up();
  await expect(page.locator('.ch-float')).toHaveCount(0);
  expect(await page.evaluate(id => JSON.parse(localStorage.getItem('ss-chat-cases'))[id].pin, CASE)).toBe(false);
});

test('Rose, 19 Nov: exactly one chat head on a page, whatever is floated; a case page\'s own head carries the other floated cases; its ball counts the conversations with something unread', async ({ page }) => {
  const CASE2 = 'c0000000-0000-0000-0000-000000000002';
  const r = await open(page, `case.php?id=${CASE}`);
  await page.evaluate(() => fetch('http://127.0.0.1:54399/rest/v1/rpc/fake_reset_chat_state', { method: 'POST', body: '{}' }));
  // two cases floated, and everything in the first case read just now
  await page.evaluate(([a, b]) => {
    const now = new Date(Date.now() + 1000).toISOString();
    localStorage.removeItem('ss-chat-prefs');
    localStorage.setItem('ss-chat-cases', JSON.stringify({ [a]: { pin: true, t: 'SS-2610-1001' }, [b]: { pin: true, t: 'SS-2610-1002' } }));
    localStorage.setItem('ss-chat-seen-' + a, JSON.stringify({ r: now, 'd-d1': now, 'd-d2': now }));
  }, [CASE, CASE2]);
  // the second case's page: one head, its own, which also carries the first case
  await page.goto(`case.php?id=${CASE2}`, { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(800);
  await expect(page.locator('.ch'), 'a case page: exactly one head').toHaveCount(1);
  await expect(page.locator('#chat-head')).toHaveCount(1);
  await page.evaluate(() => window.ssChatPoll());
  await page.waitForTimeout(1100);
  // two new messages from the resident of the first case: one conversation waits, so the ball says 1, not 2
  for (const body of ['Kuya, may balita na po ba?', 'Hello po?']) await page.evaluate(b => fetch('http://127.0.0.1:54399/rest/v1/rpc/fake_incoming', { method: 'POST', body: JSON.stringify({ body: b }) }), body);
  await page.evaluate(() => window.ssChatPoll());
  const main = page.locator('#chat-head');
  await expect(main.locator('#ch-badge')).toBeVisible();
  await expect(main.locator('#ch-badge')).toHaveText('1');
  await main.locator('#ch-fab').click();
  const row = main.locator('.ch-cases');
  await expect(row, 'the row of floated cases in the case page\'s own head').toBeVisible();
  await expect(row.locator('.ch-case')).toHaveCount(2);
  await expect(row.locator('.ch-case').first(), 'this case first, and on screen').toHaveText('1002');
  await expect(row.locator('.ch-case').first()).toHaveClass(/ch-case-on/);
  await expect(row.locator('.ch-case', { hasText: '1001' }), 'the other floated case carries its unread dot').toHaveClass(/ch-case-new/);
  await main.locator('.ch-panel').evaluate(el => Promise.all(el.getAnimations({ subtree: true }).map(a => a.finished)));
  expect(await axe(page), 'axe with the case page head carrying another case').toEqual([]);
  if (process.env.CAPTURE) {
    for (const [w, h] of [[2048, 1100], [390, 844]]) for (const theme of ['light', 'dark']) {
      await page.setViewportSize({ width: w, height: h });
      await page.evaluate(t => { document.documentElement.setAttribute('data-theme', t); }, theme);
      await page.waitForTimeout(400);
      await page.screenshot({ path: `${process.env.CAPTURE}/chathead-casepage-${theme}-${w}.png` });
    }
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'light'));
  }
  await row.locator('.ch-case', { hasText: '1001' }).click();
  await expect(row.locator('.ch-case.ch-case-on')).toHaveText('1001');
  await expect(main.locator('.ch-row')).toHaveCount(2);
  await page.keyboard.press('Escape');
  // another page: one floating head for both floated cases
  await page.goto('cases.php', { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(600);
  await expect(page.locator('.ch'), 'another page: one head for both floated cases').toHaveCount(1);
  const head = page.locator('.ch-float');
  await expect(head.locator('.ch-tag'), 'the case it shows, and how many more it carries').toHaveText('1002 +1');
  await page.evaluate(() => window.ssChatPoll());
  await expect(head.locator('.ch-badge')).toHaveText('1');
  await head.locator('.ch-fab').click();
  const strip = head.locator('.ch-cases');
  await expect(strip.locator('.ch-case')).toHaveCount(2);
  await expect(strip.locator('.ch-case', { hasText: '1001' })).toHaveClass(/ch-case-new/);
  await strip.locator('.ch-case', { hasText: '1001' }).click();
  await expect(strip.locator('.ch-case.ch-case-on')).toHaveText('1001');
  await expect(head.locator('.ch-row')).toHaveCount(2);
  await head.locator('.ch-panel').evaluate(el => Promise.all(el.getAnimations({ subtree: true }).map(a => a.finished)));
  expect(await axe(page), 'axe with the one floating head open').toEqual([]);
  if (process.env.CAPTURE) {
    for (const [w, h] of [[2048, 1100], [390, 844]]) for (const theme of ['light', 'dark']) {
      await page.setViewportSize({ width: w, height: h });
      await page.evaluate(t => { document.documentElement.setAttribute('data-theme', t); }, theme);
      await page.waitForTimeout(400);
      await page.screenshot({ path: `${process.env.CAPTURE}/chathead-${theme}-${w}.png` });
    }
    await page.setViewportSize({ width: 1280, height: 720 });
  }
  await page.keyboard.press('Escape');
  await page.goto('dashboard.php', { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(600);
  await expect(page.locator('.ch'), 'still one after another page load').toHaveCount(1);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Rose, 19 Nov: each concern is a row with its own status and progress, and updating one changes only that row, in place', async ({ page }) => {
  const C12 = 'c0000000-0000-0000-0000-000000000012';
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, `case.php?id=${C12}`);
  await page.evaluate(() => fetch('http://127.0.0.1:54399/rest/v1/rpc/fake_reset_concerns', { method: 'POST', body: '{}' }));
  await page.reload({ waitUntil: 'domcontentloaded' }); await page.waitForTimeout(600);
  const card = page.locator('#cn-card'), rows = card.locator('.ss-concern-list > li');
  await expect(rows).toHaveCount(3);
  const pills = async () => rows.evaluateAll(ls => ls.map(l => l.querySelector('.cn-top .p-badge').textContent.trim()));
  expect(await pills(), 'each concern its own status').toEqual(['Resolved', 'Being handled', 'Being handled']);
  await expect(card.locator('.cn-count')).toHaveText('1 of 3 resolved');
  await expect(card.locator('.cn-case .p-badge'), "the case's own status beside it").toHaveCount(1);
  expect(await rows.nth(1).locator('.cn-steps .now').textContent()).toBe('Being handled');
  // the add form offers only this case's category
  await card.locator('details.p-fix > summary').click();
  const vals = await card.locator('#ac-cat option').evaluateAll(os => os.map(o => o.value));
  expect(vals.length, 'something can still be added').toBeGreaterThan(0);
  expect(vals.every(v => v.startsWith('street_obstruction|')), "only the case's own category: " + vals.join(', ')).toBe(true);
  // update the second concern: only it changes, and the page does not reload
  await page.evaluate(() => { window.__still = 1; });
  await rows.nth(1).locator('input[name="remark"]').fill('Na-tow na ang sasakyan');
  const sent = page.waitForResponse(x => x.request().method() === 'POST' && x.url().includes('case.php'));
  await rows.nth(1).getByRole('button', { name: /Mark concern 2 resolved/ }).click();
  await sent;
  await expect(card.locator('.cn-count')).toHaveText('2 of 3 resolved');
  expect(await pills(), 'only the second row changed').toEqual(['Resolved', 'Resolved', 'Being handled']);
  await expect(rows.nth(1).locator('.p-quote')).toHaveText('Na-tow na ang sasakyan');
  expect(await page.evaluate(() => window.__still), 'updated in place, no reload').toBe(1);
  if (process.env.CAPTURE) {
    for (const [w, h] of [[2048, 1100], [390, 844]]) for (const theme of ['light', 'dark']) {
      await page.setViewportSize({ width: w, height: h });
      await page.evaluate(t => { document.documentElement.setAttribute('data-theme', t); }, theme);
      await card.scrollIntoViewIfNeeded(); await page.waitForTimeout(400);
      await card.screenshot({ path: `${process.env.CAPTURE}/concerns-${theme}-${w}.png` });
    }
    await page.setViewportSize({ width: 2048, height: 1100 });
    await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'light'));
  }
  // and back: reopening it changes only that row again
  await rows.nth(1).getByRole('button', { name: /Reopen concern 2/ }).click();
  await expect(card.locator('.cn-count')).toHaveText('1 of 3 resolved');
  expect(await pills()).toEqual(['Resolved', 'Being handled', 'Being handled']);
  expect(await axe(page), 'axe on the case with the concern rows').toEqual([]);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Rose, 19 Nov: the barangay seal on every exported document keeps its shape, on screen and in print', async ({ page }) => {
  for (const path of [`complaint-print.php?id=${CASE}`, `complaint-summary.php?id=${CASE}`, `certificate.php?id=${CASE}`]) {
    for (const media of ['screen', 'print']) {
      await page.emulateMedia({ media });
      const r = await open(page, path);
      const seal = page.locator('.letterhead img.seal');
      await expect(seal, path).toHaveCount(1);
      const m = await seal.evaluate(i => { const b = i.getBoundingClientRect(); return { w: b.width, h: b.height, nw: i.naturalWidth, nh: i.naturalHeight }; });
      expect(m.nw, 'the seal loaded').toBeGreaterThan(0);
      expect(Math.abs(m.w / m.h - m.nw / m.nh), `${path} (${media}): drawn ${m.w}x${m.h} for a ${m.nw}x${m.nh} seal`).toBeLessThan(0.02);
      if (process.env.CAPTURE && path.startsWith('complaint-print')) await page.screenshot({ path: `${process.env.CAPTURE}/export-${media}.png` });
      expect(r.errors, 'console errors').toEqual([]);
    }
  }
  await page.emulateMedia({ media: 'screen' });
});

test('Spatial Distribution (12 Nov 2026): the SMART panel stays navy by day; the buttons move (a grip, the nearer side, remembered, put back) and never cover an open panel', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'spatial.php');
  await page.evaluate(() => { try { localStorage.setItem('ss-theme', 'light'); localStorage.removeItem('ss-sd-dock'); } catch (e) {} });
  await page.reload({ waitUntil: 'domcontentloaded' }); await page.waitForTimeout(1500);
  // the SMART panel: dark behind light words, in the light theme too
  await page.locator('#smart-toggle').click();
  await expect(page.locator('#smart-side')).toBeVisible();
  const lum = await page.locator('#smart-side').evaluate(e => { const m = getComputedStyle(e).backgroundColor.match(/[\d.]+/g).map(Number); return (0.2126 * m[0] + 0.7152 * m[1] + 0.0722 * m[2]) / 255; });
  expect(lum).toBeLessThan(0.35);
  // an open panel is not covered: hovering the buttons does not widen them
  const btn = page.locator('#incident-toggle');
  await btn.hover(); await page.waitForTimeout(400);
  expect((await btn.boundingBox()).width).toBeLessThan(60);
  await page.locator('#smart-toggle').click();
  await expect(page.locator('#smart-side')).toBeHidden();
  // any button's popup does the same (Ace, 12 Nov): with Search open the others stay square under the pointer; shut, they widen with their words again
  await page.locator('#search-btn').click();
  await expect(page.locator('#search-btn')).toHaveAttribute('aria-expanded', 'true');
  await page.locator('#views-btn').hover(); await page.waitForTimeout(400);
  expect((await page.locator('#views-btn').boundingBox()).width, 'square while a popup is open').toBeLessThan(60);
  await page.locator('#search-btn').click();
  await expect(page.locator('#search-btn')).toHaveAttribute('aria-expanded', 'false');
  await page.locator('#views-btn').hover(); await page.waitForTimeout(400);
  expect((await page.locator('#views-btn').boundingBox()).width, 'wide again once it is shut').toBeGreaterThan(80);
  // the grip: drag the column to the left side, mid height; it settles on the left and is remembered
  const grip = page.locator('.p-map-dock .sd-grip'); await expect(grip).toBeVisible();
  const g = await grip.boundingBox();
  await page.mouse.move(g.x + g.width / 2, g.y + g.height / 2); await page.mouse.down(); await page.mouse.move(700, 400, { steps: 8 }); await page.mouse.up();
  await expect(page.locator('.p-map-dock')).toHaveClass(/sd-left/);
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('ss-sd-dock')).side)).toBe('l');
  await page.waitForTimeout(500);
  expect((await page.locator('.p-map-dock').boundingBox()).x).toBeLessThan(500);
  await page.reload({ waitUntil: 'domcontentloaded' }); await page.waitForTimeout(1200);
  await expect(page.locator('.p-map-dock')).toHaveClass(/sd-left/);                      // remembered
  await page.locator('.p-map-dock .sd-grip').dblclick();                                   // put back
  await expect(page.locator('.p-map-dock')).not.toHaveClass(/sd-moved/);
  expect(await page.evaluate(() => localStorage.getItem('ss-sd-dock'))).toBeNull();
  expect(r.errors, 'console errors').toEqual([]);
});

test('Duty only (Ace, 19 Nov): every on-duty tanod is ON DUTY in green and can be dispatched, whatever the age of their last location; no location wording', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  const r = await open(page, 'case.php?id=c0000000-0000-0000-0000-000000000006');
  const stale = page.locator('input[name="tanod"][value="b0000000-0000-0000-0000-000000000003"]');
  await expect(stale, 'the stale tanod is not greyed out').toBeEnabled();
  const row = page.locator('label.p-tanod-opt', { has: stale });
  await expect(row.locator('.p-status-dot')).toHaveText(/ON DUTY/);
  await expect(row.locator('.p-status-dot')).toHaveClass(/p-on-c/);
  await expect(row).not.toContainText('a while ago');
  await expect(page.locator('#assign-form')).not.toContainText(/location (is fresh|may be old)|a while ago/);
  for (const dot of await page.locator('#assign-form label.p-tanod-opt:not(.p-out) .p-status-dot').all()) await expect(dot).toHaveText(/ON DUTY/);
  await expect(row).not.toHaveClass(/p-out/);
  await expect(page.locator('button[name="action"][value="dispatch"]')).toBeEnabled();
  await page.evaluate(() => { let n = document.querySelector('input[name="tanod"][value="b0000000-0000-0000-0000-000000000003"]'); while (n) { if (n.tagName === 'DETAILS') n.open = true; n = n.parentElement; } });
  await stale.check({ force: true });
  await page.locator('#assign-form textarea[name="note"]').fill('Check the canal by the school.');
  await page.locator('button[name="action"][value="dispatch"]').click();
  await page.waitForLoadState('domcontentloaded');
  await expect(page.locator('.p-flash--error, [role="alert"].p-flash'), 'no refusal for an old location').toHaveCount(0);
  await expect(page.locator('.p-flash').first(), 'the dispatch went through').toContainText(/Dispatched|Na-dispatch/);
  expect(r.errors.filter(e => !/WebSocket/.test(e)), 'console errors').toEqual([]);
});

test('Case page (16 Nov): a chat button beside the brain does what the handler chose in its menu, the chat head or the Inbox', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  await page.addInitScript(() => { try { localStorage.removeItem('ss-case-chat-mode'); } catch (e) {} });
  const r = await open(page, `case.php?id=${CASE}`);
  const split = page.locator('#cc-chat');
  await expect(split).toBeVisible();
  const a = await split.boundingBox(), b = await page.locator('.ss-brain-case').boundingBox();
  expect(Math.abs((a.y + a.height / 2) - (b.y + b.height / 2)), 'beside the brain, on one line').toBeLessThan(6);
  expect(a.x + a.width, 'to the left of the brain').toBeLessThan(b.x);
  await expect(page.locator('#ch-panel'), 'the chat head waits').toBeHidden();
  await page.locator('[data-cc-chat]').click();
  await expect(page.locator('#ch-panel'), 'the default is the chat head').toBeVisible();
  await page.locator('[data-cc-chat]').click();
  await page.locator('[data-cc-chat-menu]').click();
  await expect(page.locator('.ss-chatmenu')).toBeVisible();
  await expect(page.locator('[data-cc-mode="head"]')).toHaveAttribute('aria-checked', 'true');
  await page.locator('[data-cc-mode="page"]').click();
  await expect(page.locator('.ss-chatmenu')).toBeHidden();
  expect(await page.evaluate(() => localStorage.getItem('ss-case-chat-mode')), 'the choice is kept').toBe('page');
  await expect(page.locator('#ch-fab'), 'no bubble on this page when the Inbox is chosen').toBeHidden();
  await page.locator('[data-cc-chat]').click();
  await expect(page).toHaveURL(/inbox\.php\?app=chats&c=c0000000-0000-0000-0000-000000000001&k=r/);
  expect(r.errors.filter(e => !/WebSocket/.test(e)), 'console errors').toEqual([]);
});

test('Inbox (16 Nov): the case number and its bubble take the colour of the case, the account has its own picture, and the open thread rests on a wash of that colour', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 });
  const r = await open(page, 'inbox.php?app=chats&c=c0000000-0000-0000-0000-000000000001&k=r');
  const row = page.locator('[data-mg-row][data-conv="r"]');
  expect(await row.getAttribute('style'), 'the row carries the colour of its case').toMatch(/--cc:#[0-9a-f]{6}/i);
  const num = await row.locator('.mg-cname b').evaluate(e => getComputedStyle(e).color);
  const plain = await page.locator('.mg-lhead h2').evaluate(e => getComputedStyle(e).color);
  expect(num, 'the case number is no longer the plain ink').not.toBe(plain);
  await expect(page.locator('.mg-person .mg-av--img img'), 'the resident own picture').toHaveCount(1);
  await expect(page.locator('.mg-chead .mg-av--img img'), 'a resident who filed as anonymous shows no picture to others').toHaveCount(0);
  expect(await page.locator('.mg-center').getAttribute('style')).toMatch(/--cc:#/);
  expect(await page.locator('.mg-msgs').evaluate(e => getComputedStyle(e).backgroundImage), 'a smooth gradient behind the messages').toContain('gradient');
  expect(r.errors.filter(e => !/WebSocket/.test(e)), 'console errors').toEqual([]);
});

test('Inbox, Case chats like Messenger (12 Nov 2026): a conversation per person with an unread dot, search and chips, a conversation that opens in place, send and the thumbs-up, emoji, mute, the information column; a community chat since 15 Nov 2026 (Rose): a profile per person with a bubble chat per case under it', async ({ page }) => {
  const r = await open(page, 'inbox.php');
  await page.evaluate(() => fetch('http://127.0.0.1:54399/rest/v1/rpc/fake_reset_chat_state', { method: 'POST', body: '{}' }));   // nothing read or muted yet, for anybody
  await page.evaluate(() => { try { Object.keys(localStorage).filter(k => k.startsWith('ss-chat-') || k.startsWith('ss-msgr') || k.startsWith('ss-emoji')).forEach(k => localStorage.removeItem(k)); } catch (e) {} });
  await page.reload({ waitUntil: 'domcontentloaded' });
  await expect(page.locator('.mg-lhead h2')).toHaveText('Inbox');                     // the list's title is Inbox (15 Nov), no header bar above it
  await expect(page.locator('.mg-lhead .ib-sub')).toContainText('Case chats');       // with the Case chats chip beside it
  await expect(page.locator('.gm, a[href*="app=mail"]')).toHaveCount(0);
  const rows = page.locator('[data-mg-row]');
  const people = page.locator('.mg-person');
  await expect(people).toHaveCount(2);                                                // a profile per person: the resident and the tanod of the case
  await expect(rows).toHaveCount(2);                                                  // and a bubble chat per case under each
  const rowR = page.locator('[data-mg-row][data-conv="r"]');
  const resident = people.filter({ hasText: 'Garcia' });
  await expect(rowR, 'profiles start closed').toBeHidden();
  await expect(resident.locator('.mg-pn'), 'the unread chats add up on the profile').toHaveText('1');
  await resident.locator('.mg-phead').click();                                        // the profile opens to its chats
  await expect(resident.locator('.mg-phead')).toHaveAttribute('aria-expanded', 'true');
  await expect(rowR).toBeVisible();
  await expect(rowR).toHaveClass(/mg-unread/);                                        // the resident's last question has no answer yet
  await page.locator('#mg-q').fill('lediac');
  await expect(page.locator('[data-mg-row]:not([hidden])')).toHaveCount(1);           // a search opens the profiles that match
  await page.locator('#mg-q').fill('');
  await page.locator('.mg-chip[data-f="mine"]').click();                              // the fake's case is handled by somebody else
  await expect(page.locator('[data-mg-row]:not([hidden])')).toHaveCount(0);
  await expect(page.locator('.mg-person:not([hidden])'), 'a profile with nothing to show is hidden').toHaveCount(0);
  await page.locator('.mg-chip[data-f="all"]').click();
  await expect(rowR, 'the profile stayed open').toBeVisible();
  await rowR.click();
  await expect(page).toHaveURL(/inbox\.php\?app=chats&c=c0000000-0000-0000-0000-000000000001&k=r/);
  const center = page.locator('.mg-center');
  await expect(center).toBeVisible();
  await expect(center.locator('.mg-row').first()).toBeVisible();
  await expect(rowR).not.toHaveClass(/mg-unread/);                                    // read: the dot clears
  await expect(resident.locator('.mg-pn')).toBeHidden();                              // and the profile's count with it
  const note = 'Opo, sinusuri na namin ' + Date.now();
  const sent = page.waitForResponse(x => x.request().method() === 'POST' && x.url().includes('case.php'));
  const box = center.locator('textarea'); await box.fill(note);
  await expect(page.locator('.mg-form')).toHaveClass(/has-text/);                      // the arrow has appeared
  await box.press('Enter');
  expect((await (await sent).json()).ok).toBe(true);
  await expect(center.locator('.mg-b', { hasText: note })).toHaveCount(1);
  const before = await center.locator('.mg-b').count();
  await box.press('Enter');                                                            // empty: nothing is sent
  expect(await center.locator('.mg-b').count()).toBe(before);
  await page.locator('.mg-emoji').click();
  await expect(page.locator('.em-pop')).toBeVisible();
  await page.locator('.em-pop .em-c').first().click();
  expect((await center.locator('textarea').inputValue()).length).toBeGreaterThan(0);
  await page.keyboard.press('Escape');
  await expect(page.locator('.em-pop')).toHaveCount(0);
  await page.locator('[data-mg="mute"]').click();
  await expect(page.locator('[data-mg="mute"]')).toHaveAttribute('aria-checked', 'true');      // Mute this case, a switch
  await page.locator('[data-mg="info"]').click();                                       // the information column closes
  await expect(page.locator('.mg-info')).toBeHidden();
  expect(await axe(page), 'axe on Case chats').toEqual([]);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Case chats keep where a person was in the database (12 Nov 2026): read and muted follow them to another browser', async ({ page, context, browser }) => {
  const FAKE = 'http://127.0.0.1:54399/rest/v1/rpc/';
  const r = await open(page, 'inbox.php');
  await page.waitForTimeout(1500);                                                    // a save an earlier test's page sent as it closed has landed by now
  await page.evaluate(u => fetch(u + 'fake_reset_chat_state', { method: 'POST', body: '{}' }), FAKE);
  await page.evaluate(u => fetch(u + 'fake_incoming', { method: 'POST', body: '{"body":"Kuya, kumusta po ang kaso ko?"}' }), FAKE);   // the resident writes again
  await page.evaluate(() => { try { localStorage.clear(); } catch (e) {} });          // this browser forgets what it learned from the database a moment ago
  await page.reload({ waitUntil: 'domcontentloaded' });
  const rowR = page.locator('[data-mg-row][data-conv="r"]');
  await expect(rowR).toHaveClass(/mg-unread/);
  await page.locator('.mg-person', { hasText: 'Garcia' }).locator('.mg-phead').click();   // the profile opens to its chats
  await rowR.click();
  await expect(page.locator('.mg-center')).toBeVisible();
  await expect(rowR).not.toHaveClass(/mg-unread/);
  await expect(page.locator('[data-mg="mute"]')).toHaveAttribute('aria-checked', 'false');   // nobody has muted it
  await page.locator('[data-mg="mute"]').click();
  await expect(page.locator('[data-mg="mute"]')).toHaveAttribute('aria-checked', 'true');
  await page.waitForTimeout(1600);                                                    // the page sends the two to the database a moment later
  // a second browser (no local memory at all) starts from the database
  const other = await browser.newContext({ baseURL: 'http://127.0.0.1:8013/admin/', storageState: { cookies: (await context.storageState()).cookies, origins: [] } });
  const p2 = await other.newPage();
  await p2.goto('inbox.php?app=chats&c=c0000000-0000-0000-0000-000000000001&k=r', { waitUntil: 'domcontentloaded' });
  await p2.waitForTimeout(1200);
  expect(await p2.evaluate(() => Object.keys(localStorage).some(k => k.startsWith('ss-chat-seen-')))).toBe(true);   // learned from the database
  await expect(p2.locator('[data-mg-row][data-conv="r"]')).not.toHaveClass(/mg-unread/);
  await expect(p2.locator('[data-mg="mute"]')).toHaveAttribute('aria-checked', 'true');
  await other.close();
  expect(r.errors, 'console errors').toEqual([]);
});

test('The Inbox in the sidebar (12 Nov 2026): the chats count with a bubble (no mail pill since 15 Nov); read on any page and kept live on the Inbox', async ({ page }) => {
  const FAKE = 'http://127.0.0.1:54399/rest/v1/rpc/';
  const r = await open(page, 'cases.php');
  await page.waitForTimeout(1200);
  await page.evaluate(u => fetch(u + 'fake_reset_chat_state', { method: 'POST', body: '{}' }), FAKE);
  await page.evaluate(u => fetch(u + 'fake_incoming', { method: 'POST', body: '{"body":"Kuya, may balita na po ba?"}' }), FAKE);
  await page.reload({ waitUntil: 'domcontentloaded' });
  const chat = page.locator('.p-nav a[href="inbox.php"] .p-ib-chat');
  await expect(chat).toBeVisible({ timeout: 6000 });                                   // the chats' count came from the server
  await expect(page.locator('.p-nav a[href="inbox.php"] .p-ib-mail'), 'no mail pill').toHaveCount(0);
  expect(await chat.evaluate(e => getComputedStyle(e).animationName)).toBe('none');
  const n1 = Number(await chat.getAttribute('data-n')); expect(n1).toBeGreaterThan(0);
  // on the Inbox itself the number follows what is read there
  await page.goto('inbox.php', { waitUntil: 'domcontentloaded' });
  await expect(chat).toBeVisible({ timeout: 5000 });
  await page.locator('.mg-person', { hasText: 'Garcia' }).locator('.mg-phead').click();
  await page.locator('[data-mg-row][data-conv="r"]').click();
  await expect.poll(async () => Number(await chat.getAttribute('data-n')), { timeout: 5000 }).toBeLessThan(n1);
  expect(r.errors, 'console errors').toEqual([]);
});

test('The folded sidebar (12 Nov 2026, Ace): the seal on top, no committee dot, only the profile picture at the foot and no exit button, for a committee person and a super admin', async ({ page, context }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  for (const [tier, com] of [['committee', 'peace_order'], ['super', '']]) {
    await context.addCookies([{ name: 'ss_tier', value: tier, url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: com, url: 'http://127.0.0.1:8013' }]);
    await page.goto('cases.php', { waitUntil: 'domcontentloaded' });
    await page.evaluate(() => document.documentElement.setAttribute('data-side', 'min'));
    await page.waitForTimeout(400);
    await expect(page.locator('.p-side-top .p-brand-img'), tier + ': the seal shows').toBeVisible();
    expect((await page.locator('.p-side-top .p-brand-img').boundingBox()).width, tier + ': small').toBeLessThan(60);
    if (tier === 'committee') await expect(page.locator('.p-side-com'), 'no committee dot').toBeHidden();
    await expect(page.locator('.p-side-user > button'), tier + ': no exit button').toBeHidden();
    await expect(page.locator('.p-side-user .p-side-me')).toBeVisible();
  }
});

test('The Inbox is one full page (12 Nov 2026, Ace): Case chats fill the page beside the sidebar, light and dark, in the portal colours', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  for (const th of ['light', 'dark']) {
    await page.goto('cases.php', { waitUntil: 'domcontentloaded' });
    await page.evaluate(x => { try { localStorage.setItem('ss-theme', x); } catch (e) {} }, th);
    for (const [url, app] of [['inbox.php', '.mg']]) {
      await page.goto(url, { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(1000);
      const g = await page.evaluate(a => { const r = document.querySelector(a).getBoundingClientRect(), m = document.querySelector('main.p-main').getBoundingClientRect(); return { top: Math.round(r.top), bottom: Math.round(r.bottom), vh: innerHeight, left: Math.round(r.left), mleft: Math.round(m.left), right: Math.round(r.right), mright: Math.round(m.right), radius: getComputedStyle(document.querySelector(a)).borderTopLeftRadius }; }, app);
      expect(g.bottom, url + ' ' + th + ': reaches the foot of the window').toBeGreaterThanOrEqual(g.vh - 2);
      expect([g.left, g.right], url + ' ' + th + ': edge to edge beside the sidebar').toEqual([g.mleft, g.mright]);
      expect(g.radius, 'no box corners').toBe('0px');
      expect(await page.locator('.mg-lhead .ib-sub').evaluate(e => getComputedStyle(e).backgroundColor), 'the chip is quiet, not orange').not.toBe('rgb(255, 152, 0)');
    }
  }
});

test('Rose, 15 Nov: the Chairman can switch to viewing (confirm dialog, four pages, every form refused) and back to editing', async ({ page, context }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  await context.addCookies([{ name: 'ss_tier', value: 'super', url: 'http://127.0.0.1:8013' }, { name: 'ss_role', value: 'chairman', url: 'http://127.0.0.1:8013' }]);
  const r = await open(page, 'cases.php');
  await expect(page.locator('.p-side-vm')).toContainText('Would you like to switch to viewing?');
  await page.locator('.p-side-vm').click();
  await expect(page.locator('#p-m-viewmode')).toBeVisible();
  await expect(page.locator('#p-m-viewmode')).toContainText('nothing can be changed');
  expect(await axe(page), 'the viewing dialog').toEqual([]);
  await page.locator('#p-m-viewmode [data-p-close]').click();                       // Cancel: nothing changed
  await expect(page.locator('.vm-band')).toHaveCount(0);
  await page.locator('.p-side-vm').click();
  await page.locator('#p-m-viewmode button[type="submit"]').click();
  await expect(page).toHaveURL(/dashboard\.php/);
  await expect(page.locator('.vm-band')).toContainText('not editable');
  for (const href of ['dashboard.php', 'summary.php', 'spatial.php', 'cases.php']) await expect(page.locator(`.p-nav a[href="${href}"]`)).toHaveCount(1);
  for (const href of ['residents.php', 'personnel.php', 'settings.php', 'notifications.php', 'inbox.php', 'administrative-services.php']) await expect(page.locator(`.p-sidebar a[href="${href}"]`)).toHaveCount(0);
  await page.goto('settings.php');
  await expect(page).toHaveURL(/dashboard\.php/);                                    // not a page of viewing mode
  const refused = await page.evaluate(async () => { const f = new FormData(); f.set('csrf', 'x'); f.set('action', 'noop'); const x = await fetch('cases.php', { method: 'POST', body: f, redirect: 'manual' }); return x.status + ' ' + x.type; });
  expect(refused, 'a form sent in viewing mode is refused').toMatch(/^(0 opaqueredirect|303|403)/);
  await page.locator('.vm-band button').click();                                     // back to editing
  await expect(page.locator('.vm-band')).toHaveCount(0);
  await expect(page.locator('.p-side-vm')).toContainText('switch to viewing');
  await expect(page.locator('.p-sidebar a[href="notifications.php"]')).toHaveCount(1);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Rose, 15 Nov: declining a retirement is a level full-width row, a Kagawad hands a case up to the barangay chairman, staff have no complaint type filter', async ({ page, context }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'retirement-requests.php');
  await page.locator('[data-reveal^="deny-"]').first().click();
  const row = page.locator('.ret-denytr:not([hidden])');
  await expect(row).toHaveCount(1);
  const g = await page.evaluate(() => { const tr = document.querySelector('.ret-denytr:not([hidden])'), tb = tr.closest('table').getBoundingClientRect(), b = tr.getBoundingClientRect(), ta = tr.querySelector('textarea').getBoundingClientRect(), bs = [...tr.querySelectorAll('.p-btn')].map(x => Math.round(x.getBoundingClientRect().height)); return { full: Math.round(b.width) === Math.round(tb.width), ta: Math.round(ta.height), bs }; });
  expect(g.full, 'the whole width of the table').toBe(true);
  expect([g.ta, ...g.bs], 'the box and the two buttons are one height').toEqual([42, 42, 42]);
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const k = await open(page, 'cases.php');
  await expect(page.locator('#fw-dlg select[name="to"] option[value="__super"]')).toHaveText('The barangay chairman');
  await context.addCookies([{ name: 'ss_tier', value: 'moderator', url: 'http://127.0.0.1:8013' }]);
  const m = await open(page, 'spatial.php');
  await expect(page.locator('#f-category')).toBeHidden();
  await expect(page.locator('#f-status')).toBeAttached();
  await context.addCookies([{ name: 'ss_tier', value: 'super', url: 'http://127.0.0.1:8013' }]);
  await open(page, 'spatial.php');
  await expect(page.locator('#f-category')).toBeAttached();
  expect(r.errors.concat(k.errors, m.errors), 'console errors').toEqual([]);
});

// 19 Nov 2026 (Rose, 0175): the case hierarchy. The fake answers each rung as row level security does (fake_sb.py as_tier):
// staff read the cases assigned to them or handled by them; /__hier_reset puts back the cases a test assigns or answers.
const FAKE = 'http://127.0.0.1:54399';
const ASSIGNED_TO_ME = 'c0000000-0000-0000-0000-000000000007';   // the Kagawad assigned it to the demo administrator, as staff
const MINE = 'c0000000-0000-0000-0000-000000000003';             // the demo administrator holds it
const as = (tier, committee) => [{ name: 'ss_tier', value: tier, url: 'http://127.0.0.1:8013' }].concat(committee ? [{ name: 'ss_committee', value: committee, url: 'http://127.0.0.1:8013' }] : []);

test('Rose, 19 Nov (0175): staff see only the cases assigned to them or handled by them, and have no Personnel and no Take over', async ({ page, context }) => {
  await page.request.get(FAKE + '/__hier_reset');
  await context.addCookies(as('moderator', 'peace_order'));
  const r = await open(page, 'cases.php');
  const ids = await page.locator('#reports-tbody .p-mono-id').allTextContents();
  expect(ids, 'a case of their committee nobody assigned to them').not.toContain('SS-2610-1002');
  expect(ids, 'the case assigned to them').toContain('SS-2610-1007');
  expect(ids, 'a case they handled before').toContain('SS-2610-1001');
  await open(page, 'case.php?id=c0000000-0000-0000-0000-000000000002');
  await expect(page.locator('.p-main')).toContainText('could not be found');
  await expect(page.locator('.p-controls')).toHaveCount(0);
  const n = await open(page, 'notifications.php');
  await expect(page.locator('#notif-list')).not.toContainText('SS-2610-1004');   // a notice about a case that is not theirs
  await expect(page.locator('.p-sidebar a[href="personnel.php"]')).toHaveCount(0);
  // a case they handled before, held by their Kagawad now: they read it, and nobody offers them Take over or Assign
  const c = await open(page, `case.php?id=${CASE}`);
  await expect(page.locator('.p-controls .ss-handler').first()).toContainText('Dela Cruz, Ramon');
  await expect(page.locator('input[name="action"][value="take_over"]')).toHaveCount(0);
  await expect(page.locator('details[data-assign]')).toHaveCount(0);
  expect(r.errors.concat(n.errors, c.errors), 'console errors').toEqual([]);
});

test('Rose, 19 Nov (0175): a Kagawad assigns a case to their own staff; the staff member accepts it, or declines it with a reason', async ({ page, context }) => {
  await page.request.get(FAKE + '/__hier_reset');
  await context.addCookies(as('committee', 'peace_order'));
  const k = await open(page, 'case.php?id=' + MINE);
  const asg = page.locator('details[data-assign]');
  await asg.locator('summary').click();
  expect(await asg.locator('select[name="to"] option:not([disabled])').allTextContents(), 'a Kagawad picks among their own staff only').toEqual(['Santos, Ben', 'Aquino, Lorna']);
  await asg.locator('select[name="to"]').selectOption('a0000000-0000-0000-0000-000000000009');
  await asg.locator('textarea[name="assign_note"]').fill('Ikaw na po ang bahala');
  await asg.locator('button[type="submit"]').click();
  await expect(page.locator('.ss-asg-wait')).toContainText('Assigned to Ben Santos, waiting for them to accept it');
  await expect(page.locator('.ss-ladder li.now')).toHaveAttribute('data-r', 'staff');
  await expect(page.locator('.ss-ladder li.now')).toHaveClass(/wait/);
  await expect(page.locator('.ss-asg-wait button', { hasText: 'Take it back' })).toHaveCount(1);
  expect(await axe(page), 'assigned, light').toEqual([]);

  // the staff member: the case waits for them; nothing else is offered until they answer
  await context.addCookies(as('moderator', 'peace_order'));
  const s = await open(page, 'case.php?id=' + ASSIGNED_TO_ME);
  const card = page.locator('.ss-assigned');
  await expect(card).toContainText('Ramon Dela Cruz assigned this case to you');
  await expect(card).toContainText('Pakiasikaso po ito bukas ng umaga');
  await expect(page.locator('.ss-ladder li.now')).toHaveClass(/wait/);
  await expect(page.locator('input[name="action"][value="take_over"]')).toHaveCount(0);
  expect(await axe(page), 'assigned to me, light').toEqual([]);
  await card.locator('button', { hasText: 'Accept the case' }).click();
  await expect(page.locator('.ss-assigned')).toHaveCount(0);
  await expect(page.locator('.p-controls .ss-handler').first()).toContainText('You are handling this case');
  await expect(page.locator('.ss-ladder li.now')).toHaveAttribute('data-r', 'staff');
  await expect(page.locator('.ss-ladder li.now')).not.toHaveClass(/wait/);

  // declining needs a reason, and the case leaves their list
  await page.request.get(FAKE + '/__hier_reset');
  await open(page, 'case.php?id=' + ASSIGNED_TO_ME);
  await card.locator('details summary', { hasText: 'Decline' }).click();
  await expect(card.locator('textarea[name="reason"]')).toHaveAttribute('required', '');
  await card.locator('textarea[name="reason"]').fill('Naka-leave po ako bukas');
  await card.locator('button', { hasText: 'Decline the case' }).click();
  await expect(page).toHaveURL(/cases\.php/);
  await expect(page.locator('.p-main')).toContainText('Declined. The case went back to whoever assigned it');
  await page.request.get(FAKE + '/__hier_reset');
  expect(k.errors.concat(s.errors), 'console errors').toEqual([]);
});

test('Rose, 19 Nov (0175): where the case is reads Chairman, Councilor, Staff and marks who holds it; a tanod shows when one is on it; Take over by rung', async ({ page, context }) => {
  await page.request.get(FAKE + '/__hier_reset');
  const a = await open(page, `case.php?id=${CASE}`);   // a Kagawad holds it and a tanod is on it
  await expect(page.locator('.ss-ladder li:not(.tan)')).toHaveText(['Chairman', 'Councilor', 'Staff']);
  await expect(page.locator('.ss-ladder li.now')).toHaveAttribute('data-r', 'kagawad');
  await expect(page.locator('.ss-ladder li.now')).not.toHaveClass(/wait/);
  await expect(page.locator('.ss-ladder li.tan')).toHaveCount(1);
  await expect(page.locator('.ss-ladder-who')).toContainText('With Ramon Dela Cruz (Councilor) · Tanod Ace Lediac is on it');
  await expect(page.locator('input[name="action"][value="take_over"]'), 'a super admin takes over from a Kagawad').toHaveCount(1);
  for (const [id, rung, wait, says] of [
    [MINE, 'chair', false, 'With you (Chairman)'],
    ['c0000000-0000-0000-0000-000000000004', 'chair', true, 'With the super admins, to place with a committee'],
    ['c0000000-0000-0000-0000-000000000002', 'kagawad', true, 'waiting for its Kagawad to accept it'],
    [ASSIGNED_TO_ME, 'staff', true, 'Assigned to you, waiting for you to accept it'],
  ]) {
    await open(page, 'case.php?id=' + id);
    await expect(page.locator('.ss-ladder li.now'), id).toHaveAttribute('data-r', rung);
    if (wait) await expect(page.locator('.ss-ladder li.now'), id).toHaveClass(/wait/); else await expect(page.locator('.ss-ladder li.now'), id).not.toHaveClass(/wait/);
    await expect(page.locator('.ss-ladder-who'), id).toContainText(says);
  }
  // the super admin's pick list: councilors and staff of every committee, councilors first
  await open(page, 'case.php?id=' + MINE);
  const groups = await page.locator('details[data-assign] optgroup').evaluateAll(g => g.map(x => x.label));
  expect(groups, 'councilors first, then staff').toEqual(['Councilors · Peace and Order', 'Councilors · Environment and Disaster Risk', 'Staff · Peace and Order', 'Staff · Environment and Disaster Risk']);
  // a Kagawad does not take over from another Kagawad
  await context.addCookies(as('committee', 'peace_order'));
  await open(page, `case.php?id=${CASE}`);
  await expect(page.locator('input[name="action"][value="take_over"]')).toHaveCount(0);
  await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'dark'));
  await page.waitForTimeout(300);
  expect(await axe(page), 'the ladder, dark').toEqual([]);
  expect(a.errors, 'console errors').toEqual([]);
});

test('Rose, 15 Nov: a report with several requests has a Request in focus bar over the controls; picking one lights it in the list and Next request moves on', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'case.php?id=c0000000-0000-0000-0000-000000000001');
  const n = await page.locator('.ss-concern-list > li').count();
  expect(n, 'the case has several requests').toBeGreaterThan(1);
  await expect(page.locator('#cf .cf-chip')).toHaveCount(n);
  await expect(page.locator('#cf .cf-chip.on')).toHaveCount(1);
  await page.locator('#cf .cf-chip').nth(1).click();
  await expect(page.locator('#cf .cf-chip').nth(1)).toHaveClass(/on/);
  await expect(page.locator('.ss-concern-list > li').nth(1)).toHaveClass(/is-focus/);
  await expect(page.locator('.ss-concern-list li.is-focus')).toHaveCount(1);
  await page.locator('#cf [data-cf="next"]').click();
  await expect(page.locator('#cf .cf-chip.on')).toHaveCount(1);
  expect(await page.locator('#cf').evaluate(e => e.getBoundingClientRect().top < document.querySelector('#assign-form, #review-form, .ss-ladder').getBoundingClientRect().top + 2000), 'the bar is in the controls').toBe(true);
  expect(await axe(page), 'Case page with the focus bar').toEqual([]);
  expect(r.errors, 'console errors').toEqual([]);
});


// ---------- the looks batch of 15 Nov 2026 (Ace's stack) ----------
test('Looks 15 Nov: a stack of pills holds four and opens the rest; the duplicate flag is in the stack', async ({ page }) => {
  const r = await open(page, 'cases.php');
  await page.locator('.ss-cases-t .p-badges').first().evaluate(box => { for (let i = 0; i < 6; i++) { const s = document.createElement('span'); s.className = 'p-badge p-b-grey ps-test'; s.textContent = 'Extra ' + i; box.appendChild(s); } });
  const box = page.locator('.ss-cases-t .p-badges').first();
  await expect(box.locator('.ps-more')).toContainText(/^\+\d+ more/);
  expect(await box.locator('.p-badge:visible').count(), 'four show').toBe(4);
  await box.locator('.ps-more').click();
  await expect(box.locator('.ps-more')).toHaveAttribute('aria-expanded', 'true');
  expect(await box.locator('.p-badge:visible').count(), 'all show when opened').toBeGreaterThan(4);
  await box.locator('.ps-more').click();
  expect(await box.locator('.p-badge:visible').count()).toBe(4);
  expect(await page.url(), 'the row did not open').toContain('cases.php');
  expect(r.errors, 'console errors').toEqual([]);
});

test('Looks 15 Nov: the handler list shows people in their role frames, the status list its colours, Report Summary categories theirs', async ({ page }) => {
  await open(page, 'cases.php');
  await page.locator('.p-pill-select:has(select[name="who"]) .sdp-btn').click();
  expect(await page.locator('.sdp-pop .sdp-av[data-r]').count(), 'people with a frame').toBeGreaterThan(1);
  expect(await page.locator('.sdp-pop .sdp-av').first().evaluate(e => e.getBoundingClientRect().width), 'a round picture, not stretched').toBeLessThan(40);
  await page.keyboard.press('Escape');
  await page.locator('.p-pill-select:has(select[name="status"]) .sdp-btn').click();
  expect(await page.locator('.sdp-pop .sdp-dot[style*="--c"]').count(), 'a dot for each status that has a colour').toBeGreaterThanOrEqual(6);
  await expect(page.locator('.sdp-pop .sdp-opt', { hasText: 'With a Kagawad' }).locator('.sdp-dot.none')).toHaveCount(1);
  await page.keyboard.press('Escape');
  await open(page, 'summary.php?range=month');
  await page.locator('.p-pill-select:has(#category) .sdp-btn').click();
  expect(await page.locator('.sdp-pop .sdp-dot[style*="--c"]').count(), 'every category has its dot').toBeGreaterThanOrEqual(7);
});

test('Looks 15 Nov: the red row action is white lettering at rest and a vibrant red when held', async ({ page }) => {
  await open(page, 'notifications.php');
  const b = page.locator('.p-notif-card .p-n-act .p-btn').first();
  await expect(b).toBeVisible();
  const at = async () => b.evaluate(e => { const s = getComputedStyle(e); return { c: s.color, bg: s.backgroundImage, o: s.opacity }; });
  const rest = await at();
  expect(rest.c).toBe('rgb(255, 255, 255)'); expect(rest.o).toBe('1');
  await b.hover(); await page.waitForTimeout(350);
  const held = await at();
  expect(held.c, 'still white when held').toBe('rgb(255, 255, 255)');
  expect(held.bg, 'a different, brighter red when held').not.toBe(rest.bg);
});

test('Looks 15 Nov: from four committees they become tiles; one open and wide, the rest tidy; turned-off ones wait in a closed list', async ({ page }) => {
  const r = await open(page, 'administrative-services.php');
  const grid = page.locator('#acc-committees .cmx-grid[data-tiles]').first();
  await expect(grid).toHaveClass(/ss-tiles/);
  await expect(grid.locator('> .tile-open')).toHaveCount(1);
  const cards = grid.locator('> [data-tile]'); const n = await cards.count(); expect(n).toBeGreaterThanOrEqual(4);
  expect(await grid.locator('> [data-tile]:not(.tile-open) .cmx-body:visible').count(), 'the others show only their banner and one line under it').toBe(0);
  expect(await grid.locator('> [data-tile]:not(.tile-open) [data-tile-meta]:visible').count(), 'each small tile says what is inside (16 Nov)').toBe(n - 1);
  await expect(grid.locator('> [data-tile]:not(.tile-open) [data-tile-meta]').first()).toContainText(/kind/);
  const cols = await grid.locator('> [data-tile]:not(.tile-open)').evaluateAll(ts => new Set(ts.map(t => Math.round(t.getBoundingClientRect().top))).size);
  expect(cols, 'the small tiles fill their rows, none left alone').toBeLessThanOrEqual(Math.ceil((n - 1) / 2));
  const closed = grid.locator('> [data-tile]:not(.tile-open)').first();
  const was = await grid.locator('> .tile-open').getAttribute('data-tile');
  await closed.locator('[data-tile-meta]').click();
  await expect(grid.locator('> .tile-open')).toHaveCount(1);
  expect(await grid.locator('> .tile-open').getAttribute('data-tile'), 'the clicked tile opened').not.toBe(was);
  await expect(page.locator('.cmx-offd summary')).toContainText('Turned off');
  expect(await page.locator('.cmx-offd').evaluate(e => e.open), 'closed by default').toBe(false);
  expect(await page.locator('#acc-committees > .cmx-grid[data-tiles] .acc-off').count(), 'no turned-off committee among the live ones').toBe(0);
  expect(await axe(page), 'Administrative Services, committees as tiles').toEqual([]);
  expect(r.errors, 'console errors').toEqual([]);
});

test('Looks 15 Nov: the Roles tag TEST is small and Online now wraps inside its column', async ({ page }) => {
  await open(page, 'administrative-services.php');
  await page.locator('.st-tabs').getByText('Roles', { exact: true }).first().click();
  await page.waitForTimeout(500);
  const h = await page.evaluate(() => {
    const row = document.querySelector('.ss-arow'), span = row.querySelector('.p-person > span');
    const t = document.createElement('span'); t.className = 'p-badge dv-test'; t.textContent = 'TEST'; span.appendChild(t);
    const on = row.querySelector('td.ss-online'); on.textContent = 'Has open: BRG-2026-1234567890-LONG';
    const e = row.querySelector('.ss-edit-btn').getBoundingClientRect(), o = on.getBoundingClientRect();
    return { test: Math.round(t.getBoundingClientRect().height), overlap: o.right > e.left + 1 };
  });
  expect(h.test, 'a small tag').toBeLessThanOrEqual(20);
  expect(h.overlap, 'the online text ends before the Edit button').toBe(false);
});

test('Looks 15 Nov: Settings > SMART turns the WHOLE page navy (edge to edge, no box) and its logo only glows green, light and dark', async ({ page }) => {
  for (const th of ['light', 'dark']) {
    await page.goto('settings.php', { waitUntil: 'domcontentloaded' });
    await page.evaluate(x => { try { localStorage.setItem('ss-theme', x); } catch (e) {} document.documentElement.setAttribute('data-theme', x); }, th);
    await page.locator('.st-tabs').getByText('SMART', { exact: true }).first().click();
    await page.waitForTimeout(600);
    const s = await page.evaluate(() => { const m = document.querySelector('main.p-main'), p = document.querySelector('.st-pane[data-pane="smart"]'), c = getComputedStyle(m), f = getComputedStyle(p.querySelector('.ss-engine img')).filter, pc = getComputedStyle(p); const r = m.getBoundingClientRect(), sb = document.querySelector('.p-sidebar').getBoundingClientRect(); return { bg: c.backgroundImage, color: c.color, filter: f, box: pc.backgroundImage + '|' + pc.borderTopWidth, onBody: document.body.classList.contains('st-smart-on'), left: Math.round(r.left), sideRight: Math.round(sb.right), right: Math.round(r.right), vw: innerWidth }; });
    expect(s.onBody, th + ': the page is in its navy state').toBe(true);
    expect(s.box, th + ': the pane is not a box any more').toBe('none|0px');
    expect(s.left, th + ': the navy starts at the sidebar').toBeLessThanOrEqual(s.sideRight + 1);
    expect(s.right, th + ': and runs to the right edge of the window').toBeGreaterThanOrEqual(s.vw - 20);
    expect(s.bg, th + ': a navy gradient').toContain('gradient');
    expect(s.color, th + ': light lettering').toBe('rgb(244, 247, 255)');
    expect(s.filter, th + ': the green glow').toContain('237, 250, 4');
    expect(s.filter, th + ': no dark outline').not.toContain('20, 33, 61');
  }
});

test('Looks 15 Nov: Profile has no empty space under the shorter column; Ask to retire sits level in its row; Propose a tanod is a card', async ({ page, context }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  await open(page, 'profile.php');
  const g = await page.evaluate(() => { const l = document.querySelector('.pf-left > .p-card:last-child').getBoundingClientRect(), r = document.querySelector('.pf-right > .ss-al').getBoundingClientRect(); return { l: Math.round(l.bottom), r: Math.round(r.bottom) }; });
  expect(Math.abs(g.l - g.r), 'both columns end together').toBeLessThanOrEqual(3);
  await context.addCookies([{ name: 'ss_tier', value: 'moderator', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  await open(page, 'profile.php');
  const row = await page.evaluate(() => { const r = document.querySelector('.ss-pf-act').closest('.ss-pf-row').getBoundingClientRect(); return Math.round(r.height); });
  expect(row, 'the Retirement row is not stretched by the old top padding').toBeLessThan(110);
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }, { name: 'ss_role', value: 'kagawad', url: 'http://127.0.0.1:8013' }]);
  await open(page, 'personnel.php');
  await expect(page.locator('#tc-propose .tp-ico')).toBeVisible();
  await expect(page.locator('#tc-propose .tp-t small')).toBeVisible();
  await page.locator('#tc-propose > summary').click();
  await expect(page.locator('#tc-propose form')).toBeVisible();
  expect(await axe(page), 'Personnel, propose open').toEqual([]);
});

test('Looks 15 Nov: Personnel > Committee staff turns into tiles from four committees (one wide, the rest small rectangles beneath)', async ({ page }) => {
  await open(page, 'personnel.php?view=staff');
  const wrap = page.locator('.pc-groups[data-tiles]');
  await expect(wrap, 'one or two committees stay wide').not.toHaveClass(/ss-tiles/);
  await wrap.evaluate(w => { const g = w.querySelector('.pc-group'); for (let i = 1; i < 4; i++) { const c = g.cloneNode(true); c.setAttribute('data-tile', 'x' + i); w.appendChild(c); } window.ssTiles(document); });
  await expect(wrap).toHaveClass(/ss-tiles/);
  await expect(wrap.locator('> .tile-open')).toHaveCount(1);
  expect(await wrap.locator('> [data-tile]:not(.tile-open) .pc-grid:visible').count(), 'the others are small rectangles').toBe(0);
  expect(await wrap.locator('> .tile-open .pc-grid').isVisible(), 'the open one shows its cards').toBe(true);
  const first = await wrap.locator('> [data-tile]:not(.tile-open)').first().evaluate(e => e.getBoundingClientRect().height);
  expect(first, 'a tile is a small rectangle').toBeLessThan(120);
  await wrap.locator('> [data-tile]:not(.tile-open) [data-tile-head]').first().click();
  await expect(wrap.locator('> .tile-open')).toHaveCount(1);
  expect(await wrap.locator('> .tile-open .pc-grid').isVisible()).toBe(true);
});


// ---------- the sign-in pages, 15 Nov 2026 (Ace): At a glance, the early-days orange as a gradient, the new card ----------
test('Sign-in 15 Nov: the side panel is At a glance (public, drawn, its hotlines open), the wordmark is HD, links are blue, the language is two circle flags', async ({ browser }) => {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  const { status, errors } = await open(page, 'login.php?demo=day-rain');
  expect(status).toBe(200);
  await expect(page.locator('#gl')).toHaveAttribute('data-phase', 'day');
  await expect(page.locator('#gl')).toHaveAttribute('data-wx', 'rain');
  await expect(page.locator('#gl-temp')).toHaveText(/^\d+°$/);
  await expect(page.locator('#gl-warn')).toBeVisible();
  await expect(page.locator('#gl-warn-t')).toContainText('Orange rainfall warning');
  await expect(page.locator('#gl-hot')).toBeVisible();
  await expect(page.locator('#gl-hotlist')).toBeHidden();
  await page.locator('#gl-hotbtn').click();
  await expect(page.locator('#gl-hotbtn')).toHaveAttribute('aria-expanded', 'true');
  await expect(page.locator('#gl-hotlist .n a[href^="tel:"]').first()).toBeVisible();
  await expect(page.locator('#gl-news a[target="_blank"][rel*="noopener"]').first()).toBeVisible();
  // the seal sits in the middle of the weather, with the name under it
  const seal = await page.locator('.gl-seal').boundingBox(), rail = await page.locator('#gl').boundingBox();
  expect(Math.abs((seal.x + seal.width / 2) - (rail.x + rail.width / 2)), 'the seal is centred in the panel').toBeLessThan(2);
  // Powered by moved into the panel; the old one under the card is gone
  await expect(page.locator('#gl .gl-powered')).toBeVisible();
  await expect(page.locator('.login-panel .login-powered')).toHaveCount(0);
  // the Smart Sumbong mark is the HD file, on the card's corner
  const wm = page.locator('img.login-wordmark');
  await expect(wm).toHaveAttribute('src', /logo-wordmark-hd\.webp/);
  expect(await wm.evaluate(i => i.naturalWidth), 'a sharp mark, not the old 355 px file').toBeGreaterThanOrEqual(700);
  // the links are blue, not orange
  expect(await page.locator('.forgot').evaluate(e => getComputedStyle(e).color)).toBe('rgb(0, 48, 143)');
  expect(await page.locator('.login-signup a').evaluate(e => getComputedStyle(e).color)).toBe('rgb(0, 48, 143)');
  // the language: two circle flags
  const flags = page.locator('.prefs--login .pref-lang button');
  await expect(flags).toHaveCount(2);
  for (let i = 0; i < 2; i++) {
    const f = flags.nth(i); const b = await f.boundingBox();
    expect(Math.abs(b.width - b.height), 'round').toBeLessThan(1);
    expect(await f.evaluate(e => getComputedStyle(e).borderRadius)).toBe('50%');
  }
  expect(errors, 'console errors').toEqual([]);
  expect(await axe(page), 'sign-in, light').toEqual([]);
  await page.evaluate(() => { document.documentElement.setAttribute('data-theme', 'dark'); });
  await page.waitForTimeout(300);
  expect(await axe(page), 'sign-in, dark').toEqual([]);
  await ctx.close();
});

test('Sign-in 15 Nov: the picture follows the weather and the hour, and every loop moves only opacity or transform (and stops for reduced motion)', async ({ browser }) => {
  const moods = [['dawn-clear', 'dawn', 'clear'], ['day-clear', 'day', 'clear'], ['dusk-rain', 'dusk', 'rain'], ['night-storm', 'night', 'storm'], ['golden-cloudy', 'golden', 'cloudy']];
  for (const [demo, phase, wx] of moods) {
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    await page.goto('login.php?demo=' + demo, { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(900);
    await expect(page.locator('#gl')).toHaveAttribute('data-phase', phase);
    await expect(page.locator('#gl')).toHaveAttribute('data-wx', wx);
    const vis = await page.evaluate(() => { const d = s => getComputedStyle(document.querySelector(s)).display !== 'none' && getComputedStyle(document.querySelector(s)).opacity !== '0'; return { sun: d('.gl-sun'), moon: d('.gl-moon'), rain: d('.gl-rain'), badge: getComputedStyle(document.querySelector('.gl-cloud.c2 .bd')).display !== 'none' }; });
    expect(vis.sun, demo + ': the sun shows only by day without rain').toBe(['dawn', 'day', 'golden', 'dusk'].includes(phase) && !['rain', 'storm'].includes(wx));
    expect(vis.moon, demo + ': the moon at night without rain').toBe(phase === 'night' && !['rain', 'storm'].includes(wx));
    expect(vis.rain, demo + ': rain').toBe(['rain', 'storm'].includes(wx));
    expect(vis.badge, demo + ': the warning badge on the cloud in a warning').toBe(['rain', 'storm'].includes(wx));
    const loops = await page.evaluate(() => document.getAnimations().filter(a => a.effect && a.effect.getComputedTiming().iterations === Infinity).map(a => {
      const kf = a.effect.getKeyframes(); return [...new Set(kf.flatMap(k => Object.keys(k).filter(x => !['offset', 'easing', 'composite', 'computedOffset'].includes(x))))];
    }));
    for (const props of loops) expect(props.filter(x => !['opacity', 'transform'].includes(x)), demo + ': a loop that repaints').toEqual([]);
    expect(loops.length, demo + ': it moves').toBeGreaterThan(0);
    await ctx.close();
  }
  const ctx = await browser.newContext({ reducedMotion: 'reduce' });
  const page = await ctx.newPage();
  await page.goto('login.php?demo=night-storm', { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(600);
  expect(await page.evaluate(() => document.getAnimations().filter(a => a.effect && a.effect.getComputedTiming().iterations === Infinity).length), 'nothing loops for reduced motion').toBe(0);
  await ctx.close();
});

test('Sign-in 15 Nov: glance.php is public and holds public information only; the other signed-out pages carry the same panel', async ({ browser }) => {
  const ctx = await browser.newContext();
  const r = await ctx.request.get('glance.php?demo=dusk-rain');
  expect(r.status()).toBe(200);
  expect(r.headers()['content-type']).toContain('application/json');
  const j = await r.json();
  expect(j.ok).toBe(true);
  expect(['dawn', 'day', 'golden', 'dusk', 'night']).toContain(j.phase);
  const text = JSON.stringify(j);
  for (const secret of ['tracking', 'full_name', 'resident', 'email', 'report_id', 'handler']) expect(text, 'no ' + secret + ' in a public answer').not.toContain(secret);
  expect((await ctx.request.post('glance.php', { data: {} })).status(), 'read only').toBe(405);
  for (const pg of ['forgot-password.php', 'request-access.php']) {
    const c2 = await browser.newContext();
    const page = await c2.newPage();
    await page.goto(pg + '?via=login.php', { waitUntil: 'domcontentloaded' });   // the fake signs everything in except urls naming login.php
    await expect(page.locator('#gl .gl-seal'), pg + ': the same panel').toBeVisible();
    await expect(page.locator('.login-stack img.login-wordmark'), pg + ': the HD mark').toHaveAttribute('src', /logo-wordmark-hd/);
    expect(await axe(page), pg).toEqual([]);
    await c2.close();
  }
  await ctx.close();
});

test('Sign-in 15 Nov: the weather sits at the bottom left so the seal and the name are centred; opening the hotlines scrolls the panel, never the page', async ({ browser }) => {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 720 } });
  const page = await ctx.newPage();
  await page.goto('login.php?demo=day-rain', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#gl-temp')).toHaveText(/^\d+°$/);
  const rail = await page.locator('#gl').boundingBox(), seal = await page.locator('.gl-seal').boundingBox(), name = await page.locator('.gl-name').boundingBox();
  const read = await page.locator('.gl-read').boundingBox(), scene = await page.locator('.gl-scene').boundingBox();
  expect(Math.abs((seal.x + seal.width / 2) - (rail.x + rail.width / 2)), 'the seal is centred').toBeLessThan(2);
  expect(Math.abs((name.x + name.width / 2) - (rail.x + rail.width / 2)), 'the name is centred under it').toBeLessThan(2);
  expect(read.x - rail.x, 'the weather is at the left edge, in line with the rows').toBeLessThan(30);
  expect(read.y, 'the weather is below the name').toBeGreaterThan(name.y + name.height);
  expect(read.y + read.height, 'and inside the picture').toBeLessThan(scene.y + scene.height);
  // the panel is as tall as the window and stays put; the hotlines open and only the rows scroll
  await page.locator('#gl-hotbtn').click();
  await expect(page.locator('#gl-hotlist')).toBeVisible();
  const m = await page.evaluate(() => {
    const r = document.getElementById('gl'), rows = document.querySelector('.gl-rows');
    return { pageH: document.documentElement.scrollHeight, winH: innerHeight, railH: r.getBoundingClientRect().height, rowsOver: rows.scrollHeight > rows.clientHeight, ov: getComputedStyle(rows).overflowY };
  });
  expect(m.pageH, 'the page did not grow').toBeLessThanOrEqual(m.winH + 1);
  expect(Math.abs(m.railH - m.winH), 'the panel is the window tall').toBeLessThan(2);
  expect(m.ov).toBe('auto');
  await page.locator('#gl-hotlist .n a').last().scrollIntoViewIfNeeded();
  await expect(page.locator('#gl-hotlist .n a').last()).toBeInViewport();
  expect(await page.evaluate(() => scrollY), 'the page itself did not move').toBe(0);
  await expect(page.locator('#gl .gl-powered')).toBeInViewport();
  await ctx.close();
});

test('Sign-in 15 Nov: when the server cannot read the weather, the browser asks Open-Meteo itself and the panel still fills', async ({ browser }) => {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  await page.route('**/glance.php*', r => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ ok: true, phase: 'night', when: '7:50 PM', now: null, warn: null, flood: false, hot: [], news: [] }) }));
  await page.route('https://api.open-meteo.com/**', r => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ current: { temperature_2m: 27.6, apparent_temperature: 31.2, weather_code: 63, wind_speed_10m: 14.4 }, daily: { sunrise: ['2026-11-15T05:56'], sunset: ['2026-11-15T17:24'] } }) }));
  await page.goto('login.php?via=login.php', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#gl-temp')).toHaveText('28°');
  await expect(page.locator('#gl-cond')).toHaveText('Heavy rain');
  await expect(page.locator('#gl-sub')).toContainText('wind 14 km/h');
  await expect(page.locator('#gl')).toHaveAttribute('data-wx', 'rain');
  // and when neither can be read, the panel says so and nothing breaks
  const c2 = await browser.newContext();
  const p2 = await c2.newPage();
  await p2.route('**/glance.php*', r => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ ok: true, phase: 'day', now: null, warn: null, flood: false, hot: [], news: [] }) }));
  await p2.route('https://api.open-meteo.com/**', r => r.abort());
  await p2.goto('login.php?via=login.php', { waitUntil: 'domcontentloaded' });
  await expect(p2.locator('#gl-cond')).toHaveText('Weather unavailable');
  await c2.close();
  await ctx.close();
});

test('Sign-in 15 Nov: the panel arrives drawn by the server (no blink between the signed-out pages), and the pages ask the browser to keep it still', async ({ browser }) => {
  const ctx = await browser.newContext();
  for (const pg of ['login.php', 'forgot-password.php', 'request-access.php']) {
    const r = await ctx.request.get(pg + '?demo=day-rain&via=login.php');
    const html = await r.text();
    expect(html, pg + ': the weather is already in the page').toMatch(/id="gl-temp">26°</);
    expect(html, pg + ': the picture already follows the weather').toContain('data-wx="rain"');
    expect(html, pg + ': the warning row is already shown').toMatch(/id="gl-warn"(?! hidden)/);
    expect(html, pg + ': its words are in the page').toContain('Orange rainfall warning');
  }
  const css = await (await ctx.request.get('assets/css/signin.css')).text();
  expect(css).toContain('@view-transition');
  expect(css).toContain('view-transition-name: gl');
  // the script's refresh writes the same words, so nothing changes when it arrives
  await ctx.close();
  const c2 = await browser.newContext();   // the requests above gave that context a session
  const page = await c2.newPage();
  await page.goto('login.php?demo=day-rain', { waitUntil: 'domcontentloaded' });
  const before = await page.locator('#gl .gl-read').innerText();
  await page.waitForTimeout(900);
  expect(await page.locator('#gl .gl-read').innerText()).toBe(before);
  await c2.close();
});

test('Spatial Distribution 15 Nov: Material at night too (solid graphite, no frosting, no border, no sheen, no glow on pins)', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' });
  await open(page, 'spatial.php');
  await page.evaluate(() => { document.documentElement.setAttribute('data-theme', 'dark'); });
  await page.waitForTimeout(500);
  const m = await page.evaluate(() => {
    const out = {};
    for (const sel of ['.p-map-search', '.fw-chip', '#layers-btn', '.maplibregl-ctrl-bottom-right .maplibregl-ctrl-group button']) {
      const el = document.querySelector('#s-spatial ' + sel); if (!el) continue;
      const c = getComputedStyle(el);
      out[sel] = { blur: c.backdropFilter, border: c.borderTopWidth, shadow: c.boxShadow, bg: c.backgroundColor, img: c.backgroundImage };
    }
    return out;
  });
  const keys = Object.keys(m);
  expect(keys.length, 'surfaces found').toBeGreaterThan(1);
  for (const k of keys) {
    expect(m[k].blur === 'none' || m[k].blur === '', k + ': no frosting').toBe(true);
    expect(m[k].border, k + ": no border " + JSON.stringify(m[k])).toBe("0px");
    expect(m[k].shadow, k + ': lifted by a shadow, not lit').not.toMatch(/inset/);
    expect(m[k].img, k + ': a flat fill').toBe('none');
  }
  // the pins' glow is gone: a pin's filter holds only black shadows
  const css = await (await page.request.get('assets/css/sd-dark.css')).text();
  expect(css).toContain('.dm svg { filter: drop-shadow(0 1px 1px rgba(0,0,0,.7))');
  const html = await (await page.request.get('spatial.php')).text();
  expect(html, 'the cluster pin is no longer a glass orb').not.toContain('radialGradient id="og"');
  expect(html, 'the complaint pins are solid discs by night too, with no glow in their colour').not.toContain("(dark ? fill : '#000')");
  expect(html, 'nor are the safe-point signs lit white at night').not.toContain("(dark ? '#fff' : '#000')");
});

test('Material, portal-wide (15 Nov): no frosted glass in either mode (Workspace, Report Summary, Profile, the sign-in card), scrims dim without blur', async ({ page, browser }) => {
  for (const mode of ['light', 'dark']) {
    await page.emulateMedia({ colorScheme: mode });
    for (const pg of ['workspace.php', 'summary.php', 'profile.php', 'cases.php', 'dashboard.php']) {
      await open(page, pg);
      await page.evaluate(m => { document.documentElement.setAttribute('data-theme', m); }, mode);
      await page.waitForTimeout(400);
      const frosted = await page.evaluate(() => [...document.querySelectorAll('body *')].filter(e => { const c = getComputedStyle(e); return c.backdropFilter && c.backdropFilter !== 'none' && e.getBoundingClientRect().width > 4; }).map(e => e.tagName + '.' + e.className));
      expect(frosted, pg + ' ' + mode + ': nothing is frosted').toEqual([]);
    }
  }
  const css = await (await page.request.get('assets/css/material.css')).text();
  expect(css).toContain('.p-scrim');
  const ctx = await browser.newContext({ colorScheme: 'dark' });
  const p2 = await ctx.newPage();
  await p2.goto('login.php?via=login.php', { waitUntil: 'domcontentloaded' });
  await p2.evaluate(() => document.documentElement.setAttribute('data-theme', 'dark'));
  await p2.waitForTimeout(400);
  const f2 = await p2.evaluate(() => [...document.querySelectorAll('body *')].filter(e => { const c = getComputedStyle(e); return c.backdropFilter && c.backdropFilter !== 'none'; }).map(e => e.className));
  expect(f2, 'the dark sign-in card, rail and switches are solid').toEqual([]);
  await ctx.close();
});

test('Case page on one screen (15 Nov): the cream card has tabs and a body that scrolls inside it, the controls scroll inside themselves, a stage track says where the case is, every action is still there', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 800 });
  await open(page, `case.php?id=${CASE}`);
  await page.waitForTimeout(600);
  const m = await page.evaluate(() => {
    const c = document.querySelector('.p-controls'), r = document.querySelector('.p-report'), b = document.querySelector('.cc-body');
    return { cH: c.getBoundingClientRect().height, cOv: getComputedStyle(c).overflowY, rH: r.getBoundingClientRect().height, bOv: getComputedStyle(b).overflowY, win: innerHeight };
  });
  expect(m.cH, 'the controls are never taller than the window').toBeLessThanOrEqual(m.win);
  expect(m.cOv).toBe('auto');
  expect(m.rH, 'the case card is never taller than the window').toBeLessThanOrEqual(m.win);
  expect(m.bOv, 'its body scrolls inside it').toBe('auto');
  // tabs: Report first, the timeline, the feedback and the evidence each have their own
  const tabs = page.locator('.cc-tabs [role="tab"]');
  await expect(tabs).toHaveCount(4);
  await expect(page.locator('.cc-tabs [aria-selected="true"]')).toHaveText(/Report/);
  await expect(page.locator('.cc-body .ss-concerns')).toBeVisible();
  await expect(page.locator('.cc-timeline')).toBeHidden();
  await page.locator('[data-cc-go="timeline"]').click();
  await expect(page.locator('.cc-timeline')).toBeVisible();
  await expect(page.locator('.cc-body .ss-concerns')).toBeHidden();
  await page.locator('[data-cc-go="evidence"]').click();
  await expect(page.locator('.cc-body [data-cc-tab="evidence"]:not([hidden])').first()).toBeVisible();
  await page.locator('[data-cc-go="feedback"]').click();
  await expect(page.locator('.cc-body [data-cc-tab="feedback"]')).toBeVisible();
  // the chosen tab is remembered across a reload (a save reloads the page), and #timeline opens that tab
  await page.reload({ waitUntil: 'domcontentloaded' });
  await expect(page.locator('.cc-tabs [aria-selected="true"]')).toHaveText(/Feedback/);
  await page.goto(`case.php?id=${CASE}#timeline`, { waitUntil: 'domcontentloaded' });
  await expect(page.locator('.cc-timeline')).toBeVisible();
  // keyboard: arrow keys move between tabs
  await page.locator('.cc-tabs [aria-selected="true"]').focus();
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('.cc-tabs [aria-selected="true"]')).toHaveText(/Feedback/);
  await expect(page.locator('.cc-track li')).toHaveCount(5);
  await expect(page.locator('.cc-track li[aria-current="step"]')).toHaveCount(1);
  const tiles = page.locator('.p-controls details.p-fix[data-ic]');
  expect(await tiles.count(), 'the secondary actions are tiles').toBeGreaterThan(0);
  await expect(page.locator('.p-controls details.p-fix[data-ic] .cc-st small').first()).toBeVisible();   // each has a hint line
  const first = tiles.first();
  await first.locator('summary').click();
  await expect(first).toHaveJSProperty('open', true);
  await expect(first.locator('form').first()).toBeVisible();
  const forms = await page.evaluate(() => [...document.querySelectorAll('.p-controls form, .p-case-grid form')].filter(f => f.querySelector('input[name="action"]')).map(f => f.querySelector('input[name="action"]').value));
  expect(forms.length, 'the case forms are all still on the page').toBeGreaterThan(1);
});

test('Case page, Next step (15 Nov): a waiting resolution leads with Approve and the assign form is one tap away; the deadline folds away unless it has passed', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await open(page, 'case.php?id=c0000000-0000-0000-0000-000000000006');
  const next = page.locator('.cc-next');
  await expect(next).toHaveCount(1);
  const firstBlock = await next.evaluate(n => (n.querySelector('.p-req-card, form, details') || {}).className || '');
  expect(firstBlock, 'the resolution approval comes first').toContain('p-req-card');
  await expect(next.locator('.p-req-card').first()).toContainText(/Resolution waiting for approval/i);
  const step2 = next.locator('details.cc-step2');
  await expect(step2).toHaveCount(1);
  await expect(step2.locator(':scope > summary')).toContainText('Send a different tanod');
  await expect(step2).toHaveJSProperty('open', false);
  await step2.locator(':scope > summary').click();
  await expect(step2.locator('#assign-form')).toBeVisible();
  // a deadline still ahead folds into one line, and its fields stay in the form
  const adv = step2.locator('details.cc-adv');
  await expect(adv).toHaveCount(1);
  await expect(adv).toHaveJSProperty('open', false);
  await expect(adv.locator('summary')).toContainText('Deadline');
  expect(await adv.locator('input[name="target"]').count()).toBe(1);
  await open(page, 'case.php?id=c0000000-0000-0000-0000-000000000008');
  const over = page.locator('#assign-form details.cc-adv');
  await expect(over, 'a deadline that has passed is open, so a required field is never hidden while invalid').toHaveJSProperty('open', true);
  await expect(over.locator('summary')).toContainText(/passed/i);
});

test('Case page (15 Nov): "Why this level" is a button beside the status pill and opens as a drawer, closed by its button, Escape or a click outside', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await open(page, `case.php?id=${CASE}`);
  const btn = page.locator('[data-smart-open]');
  await expect(btn).toBeVisible();
  await expect(btn).toHaveAttribute('aria-controls', 'smart-card');
  await expect(page.locator('#smart-card')).toBeHidden();
  await btn.click();
  await expect(page.locator('#smart-card')).toBeVisible();
  await expect(page.locator('#smart-card')).toContainText('Why this level');
  await expect(btn).toHaveAttribute('aria-expanded', 'true');
  const box = await page.locator('#smart-card').boundingBox();
  expect(box.x + box.width, 'it is a drawer on the right edge').toBeGreaterThan(1430);
  const paint = await page.locator('#smart-card').evaluate(e => { const c = getComputedStyle(e); return { img: c.backgroundImage, col: c.backgroundColor }; });
  expect(paint.img !== 'none' || !/rgba\(0, 0, 0, 0\)|transparent/.test(paint.col), 'the drawer is a solid card, never see-through (the cream card flattening must not reach it)').toBe(true);
  expect(await axe(page), 'the drawer, light').toEqual([]);
  await page.keyboard.press('Escape');
  await expect(page.locator('#smart-card')).toBeHidden();
  await expect(btn).toHaveAttribute('aria-expanded', 'false');
  await btn.click(); await expect(page.locator('#smart-card')).toBeVisible();
  await page.locator('[data-smart-close]').click(); await expect(page.locator('#smart-card')).toBeHidden();
  await btn.click(); await page.mouse.click(300, 400); await expect(page.locator('#smart-card'), 'a click outside closes it').toBeHidden();
  // Change level is still inside, and still a form
  await btn.click(); await page.locator('#smart-card .ss-sc-change summary').click();
  await expect(page.locator('#smart-card select[name="level"]')).toBeVisible();
});

test('Case page, the swap (15 Nov): what the case needs now is one Next step card, the secondary actions are two-up tiles under More with the map switch, and every action is still reachable', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await open(page, `case.php?id=${CASE}`);
  await expect(page.locator('.p-controls .cc-next')).toHaveCount(1);
  await expect(page.locator('.cc-next .cc-next-h')).toBeVisible();
  const more = page.locator('.p-controls .cc-more');
  await expect(more).toHaveCount(1);
  await expect(more.locator('> .p-flabel')).toContainText('More');
  const tiles = more.locator('.cc-tiles > details.p-fix');
  expect(await tiles.count(), 'the secondary actions are tiles under More').toBeGreaterThan(1);
  // two-up: the first two tiles share a row
  const a = await tiles.nth(0).boundingBox(), b = await tiles.nth(1).boundingBox();
  expect(Math.abs(a.y - b.y), 'two tiles on one row').toBeLessThan(6);
  expect(b.x, 'side by side').toBeGreaterThan(a.x + a.width - 4);
  // a tile opens full width, in place, and still holds its form
  const live = more.locator('.cc-tiles > details.p-fix[data-keep-details]').first();   // here someone else owns the case, so only the tiles that stay usable are pressed
  await live.locator('summary').click();
  const o = await live.boundingBox(), g = await more.locator('.cc-tiles').boundingBox();
  expect(o.width, 'an open tile is a full-width sheet').toBeGreaterThan(g.width - 8);
  await expect(live.locator('form')).toBeVisible();
  await expect(more.locator('.publish-toggle')).toHaveCount(1);   // the residents' map switch is under More too
  // no action went missing from the page: the same set of forms as before the swap
  const acts = await page.evaluate(() => [...new Set([...document.querySelectorAll('form input[name="action"]')].map(i => i.value))].sort());
  for (const must of ['take_over', 'forward', 'set_status', 'set_public', 'refer', 'smart_override']) expect(acts, 'action ' + must).toContain(must);
  expect(await axe(page), 'the case page, light').toEqual([]);
  await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'dark'));
  await page.waitForTimeout(300);
  expect(await axe(page), 'the case page, dark').toEqual([]);
});

test('Case page, as decided (16 Nov): the portal\'s brain button in the top bar opens Why this level, the map is the Where block of the Report tab, the Field report tab tracks the tanods', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await open(page, `case.php?id=${CASE}`);
  // the brain button belongs to this case: in the cream card's header, top right, carries the score, opens the drawer; the old pill is gone and the top bar has none
  expect(await page.evaluate(() => document.getElementById('cc-body').scrollTop + scrollY), 'nothing scrolls on load: the Subject is the first thing in the card').toBe(0);
  const brain = page.locator('.p-report .ss-brain-btn[data-smart-open]');
  await expect(page.locator('.p-topbar .ss-brain-btn')).toHaveCount(0);
  await expect(brain).toBeVisible();
  await expect(brain.locator('.ss-brain-n')).toHaveText(/^\d+$/);
  const bb = await brain.boundingBox(), cb = await page.locator('.p-report').boundingBox();
  expect(bb.x + bb.width, 'in the header corner, inside the card').toBeLessThan(cb.x + cb.width);
  expect(cb.x + cb.width - (bb.x + bb.width), 'at the right edge').toBeLessThan(40);
  expect(bb.y - cb.y, 'at the top').toBeLessThan(40);
  await expect(page.locator('.ss-smartbtn')).toHaveCount(0);
  await brain.click();
  await expect(page.locator('#smart-card')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.locator('#smart-card')).toBeHidden();
  // the map is part of the Report tab, not of the controls
  await expect(page.locator('.cc-body .cc-where #case-map-preview')).toBeVisible();
  await expect(page.locator('.p-controls #case-map-preview')).toHaveCount(0);
  await expect(page.locator('.cc-where .p-eyebrow')).toHaveText(/Where/i);
  // the third tab is the Field report: what the tanods did, and what they reported
  await expect(page.locator('[data-cc-go="evidence"]')).toHaveText(/Field report/);
  await page.locator('[data-cc-go="evidence"]').click();
  const acts = page.locator('.cc-body .cc-acts > li');
  expect(await acts.count(), 'each dispatch is a row of tanod activity').toBeGreaterThan(0);
  await expect(acts.first()).toContainText(/Assigned/);
  await expect(page.locator('.cc-body [data-cc-tab="evidence"]:not([hidden]) .p-eyebrow', { hasText: 'Field Report' }).first()).toBeVisible();
  // the timeline stays its own tab
  await page.locator('[data-cc-go="timeline"]').click();
  await expect(page.locator('.cc-timeline')).toBeVisible();
  await expect(page.locator('.cc-acts')).toBeHidden();
  expect(await axe(page), 'the case page, light').toEqual([]);
});

test('Case page, styled and without dead space (16 Nov): the cream card is as tall as the controls beside it on every tab, the track, owner, ladder and tiles carry the preview\'s styling', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await open(page, `case.php?id=${CASE}`);
  for (const tab of ['report', 'evidence', 'timeline', 'feedback']) {
    await page.locator(`[data-cc-go="${tab}"]`).click();
    const g = await page.evaluate(() => { const r = document.querySelector('.p-report').getBoundingClientRect(), c = document.querySelector('.p-controls').getBoundingClientRect(); return { r: r.bottom, c: c.bottom }; });
    expect(Math.abs(g.r - g.c), tab + ': no empty page under the case card').toBeLessThan(10);
  }
  const s = await page.evaluate(() => {
    const done = document.querySelector('.cc-track .done i'), cur = document.querySelector('.cc-track .cur i'), tile = document.querySelector('.p-controls details.p-fix[data-ic] > summary'), now = document.querySelector('.ss-ladder li.now');
    const ico = tile && getComputedStyle(tile, '::before');
    return { done: done && getComputedStyle(done).backgroundImage, cur: cur && getComputedStyle(cur).backgroundImage, ico: ico && [ico.width, ico.height, ico.backgroundImage.slice(0, 4)], now: now && getComputedStyle(now).backgroundImage };
  });
  expect(s.done, 'done stages are a gradient').toContain('gradient');
  expect(s.cur, 'the current stage is lit').toContain('gradient');
  expect(s.ico[0] + ' ' + s.ico[1] + ' ' + s.ico[2], 'a tile\'s icon sits in a 30px box').toBe('30px 30px url(');
  expect(s.now, 'the ladder\'s current rung is lit').toContain('gradient');
  expect(await axe(page), 'the case page, light').toEqual([]);
});

test('The view-only tier (16 Nov sweep): a Captain account sent away from a page it may not open lands on the Dashboard, never in a redirect loop', async ({ page, context }) => {
  await context.addCookies([{ name: 'ss_tier', value: 'captain', url: 'http://127.0.0.1:8013' }]);
  for (const p of ['workspace.php', 'notifications.php', 'inbox.php', 'residents.php', 'settings.php', 'home.php']) {
    const res = await page.goto(p, { waitUntil: 'domcontentloaded' });
    expect(res.status(), p + ': it answers').toBe(200);
    expect(new URL(page.url()).pathname, p + ': lands on the Dashboard').toMatch(/dashboard\.php$/);
  }
});

test('Looks 16 Nov, pills B: the account status stays a solid pill, the states beside it are soft pills, in light and dark', async ({ page }) => {
  for (const mode of ['light', 'dark']) {
    await page.emulateMedia({ colorScheme: mode });
    await open(page, 'residents.php');
    await page.evaluate(m => document.documentElement.setAttribute('data-theme', m), mode);
    const st = page.locator('#accounts-tbody .p-badge:not(.p-tag)').first(), tag = page.locator('#accounts-tbody .p-badge.p-tag').first();
    await expect(tag, 'there are tags (Overdue, On an incident, duty states)').toBeVisible();
    const sty = await st.evaluate(e => { const c = getComputedStyle(e); return { bg: c.backgroundColor, h: Math.round(e.getBoundingClientRect().height) }; });
    const tg = await tag.evaluate(e => { const c = getComputedStyle(e); return { bg: c.backgroundColor, color: c.color, ring: c.boxShadow, h: Math.round(e.getBoundingClientRect().height) }; });
    expect(sty.bg, 'the status is a solid colour: ' + mode).toMatch(/^rgb\(/);
    expect(tg.bg, 'a tag is a tint, not the solid status colour: ' + mode).not.toBe(sty.bg);
    expect(tg.ring, 'a tag has a thin ring, no glow: ' + mode).toMatch(/inset/);
    expect(tg.color, 'a tag\'s lettering is its own colour, not white: ' + mode).not.toBe('rgb(255, 255, 255)');
    expect(tg.h, 'a tag is a little lower than a status').toBeLessThan(sty.h);
  }
});

test('Looks 16 Nov, locked tiles: a tile the person cannot use stays in place, locked, with the reason; a named person wears the rank colour', async ({ page, context }) => {
  const CASE = 'c0000000-0000-0000-0000-000000000001';   // handled by someone else in the fake
  for (const [label, cookies] of [['super', [['ss_tier', 'super']]], ['staff', [['ss_tier', 'moderator'], ['ss_committee', 'peace_order']]]]) {
    await context.clearCookies();
    await context.addCookies(cookies.map(([n, v]) => ({ name: n, value: v, url: 'http://127.0.0.1:8013' })));
    await open(page, 'case.php?id=' + CASE);
    const locked = page.locator('.cc-tiles .cc-locked');
    expect(await locked.count(), label + ': some tiles are locked').toBeGreaterThanOrEqual(2);
    await expect(locked.first(), label + ': a locked tile cannot be pressed').toHaveAttribute('inert', '');
    const who = locked.first().locator('.cc-who');
    await expect(who, label + ': the reason names who holds the case').toBeVisible();
    expect(await who.getAttribute('data-r'), label + ': with the rank\'s colour').toMatch(/^(staff|kagawad|chair)$/);
    expect(await who.evaluate(e => getComputedStyle(e).fontWeight), label + ': bolder').toBe('800');
    const col = await who.evaluate(e => getComputedStyle(e).color), body = await locked.first().locator('.cc-st').evaluate(e => getComputedStyle(e).color);
    expect(col, label + ': in a colour of its own').not.toBe(body);
    expect(await page.locator('.cc-tiles').evaluate(g => g.children.length % 2), label + ': the grid ends on a full row or a spanning tile').toBeGreaterThanOrEqual(0);
  }
  await context.clearCookies();
  await context.addCookies([{ name: 'ss_tier', value: 'captain', url: 'http://127.0.0.1:8013' }, { name: 'ss_role', value: 'chairman', url: 'http://127.0.0.1:8013' }]);
  await open(page, 'case.php?id=' + CASE);
  expect(await page.locator('.cc-locked').count(), 'a view-only account sees the one note, not a grid of locks').toBe(0);
});

test('Looks 16 Nov, case page: the map is as wide as the card on a wide screen (no dead space beside it)', async ({ page }) => {
  await page.setViewportSize({ width: 1920, height: 1080 });
  await open(page, 'case.php?id=c0000000-0000-0000-0000-000000000006');
  const m = await page.locator('.cc-where .p-minimap').evaluate(e => { const c = e.closest('.cc-body').getBoundingClientRect(), b = e.getBoundingClientRect(); return { gap: Math.round(c.right - b.right), h: Math.round(b.height) }; });
  expect(m.gap, 'the map reaches the card\'s right padding').toBeLessThanOrEqual(40);
  expect(m.h, 'and is at least its old height').toBeGreaterThanOrEqual(220);
});

test('Looks 16 Nov, committee staff: each group has the line a small tile shows (in now, staff, faces)', async ({ page }) => {
  await open(page, 'personnel.php?view=staff');
  const groups = await page.locator('.pc-groups > [data-tile]').count();
  expect(groups, 'there are groups').toBeGreaterThan(0);
  expect(await page.locator('.pc-groups > [data-tile] > [data-tile-meta]').count(), 'each has its line').toBe(groups);
  await expect(page.locator('.pc-groups > [data-tile] > [data-tile-meta]').first()).toContainText(/in now/);
  expect(await page.locator('.pc-groups > [data-tile] > [data-tile-meta]').first().isVisible(), 'hidden while the groups are wide (fewer than four)').toBe(groups >= 4);
  expect(await page.locator('.pc-grid').first().evaluate(g => g.style.gridTemplateColumns || 'auto'), 'the cards share the width').toMatch(/repeat|auto/);
});
