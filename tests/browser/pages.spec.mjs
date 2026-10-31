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
  const r = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']).analyze();
  return r.violations.filter(v => v.impact === 'serious' || v.impact === 'critical')
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
  await expect(page.locator('.login-rail img.rail-logo')).toHaveAttribute('alt', 'Barangay 183 seal');   // 0148: from the profile
  expect(errors, 'console errors').toEqual([]);
  expect(await axe(page), 'serious or critical accessibility problems').toEqual([]);
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

test('the barangay\'s places: listed in Settings, added from the map', async ({ page }) => {
  let r = await open(page, 'settings.php#places');
  await expect(page.locator('#places .st-plist li')).toHaveCount(2);
  expect(await axe(page), 'Settings > Appearance').toEqual([]);
  r = await open(page, 'spatial.php');
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
  await expect(page.locator('#ss-al [data-kind]')).toHaveCount(9);   // 0157 adds forwards, flags, reroute questions and Inbox messages
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
  await expect(page.locator('.p-meta-strip')).toContainText('Garcia');
  await expect(page.locator('.p-meta-strip')).toContainText('Anonymous to others');
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

test('SMART Iteration 3: rules need a reason, can be tested first, and have a history', async ({ page }) => {
  const r = await open(page, 'settings.php#smart');
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

test('SMART Iteration 3: planning (forecast, roster, work orders, sharing)', async ({ page }) => {
  const r = await open(page, 'administrative-services.php#plan');
  await expect(page.locator('#plan-forecast .st-uptime-tile')).toHaveCount(3);
  await expect(page.locator('#plan-forecast')).toContainText('does not guess');
  await expect(page.locator('#plan-roster li')).toHaveCount(2);
  await expect(page.locator('#plan-roster')).toContainText('needs +1');
  await expect(page.locator('#plan-hotspots .ss-vlist li').first()).toBeVisible();
  await expect(page.locator('#plan-fair')).toContainText('One tanod had most of the dispatches');
  await expect(page.locator('#plan-fair')).toContainText('One administrator holds most of the open cases');
  expect(await axe(page), 'Settings > Planning').toEqual([]);
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
  await expect(page.locator('#cc-side .cc-rings')).toContainText('Within 50 m');
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
  await expect(page.locator('#acc-committees form.acc-row:not(.acc-new)')).toHaveCount(5);
  await expect(page.locator('#acc-committees')).toContainText('Anti-Drug');
  await expect(page.locator('#acc-committees form.acc-off')).toHaveCount(1);
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

test('0147 rules and hotlines: a super admin edits the deadlines, limits and emergency numbers in Settings', async ({ page }) => {
  const r = await open(page, 'control-room.php#rules');
  await expect(page.locator('#rules-card .ru-t tbody tr')).toHaveCount(8);
  await expect(page.locator('#rules-card .ru-grid .ru-f')).toHaveCount(13);   // 0155 adds the two reroute waits, 0158 the five retention periods
  await expect(page.locator('#lim-max_deadline_extensions')).toHaveValue('2');
  expect(await axe(page), 'Settings > Rules').toEqual([]);
  await page.locator('#rules-card button[type="submit"]').click();
  await expect(page).toHaveURL(/control-room\.php#rules/);
  await expect(page.locator('section[data-pane="rules"] .p-flash--ok')).toContainText('Rules saved');
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
  await expect(page.locator('.st-tabs [data-st]')).toHaveText(['System status', 'Plan and usage', 'SMART', 'Appearance']);
  await expect(page.locator('.p-sidebar a[href="administrative-services.php"]')).toContainText('Administrative Services');
  await expect(page.locator('.p-sidebar a[href="control-room.php"]')).toContainText('Control Room');
  r = await open(page, 'administrative-services.php');
  await expect(page.locator('h1')).toHaveText('Administrative Services');
  await expect(page.locator('section[data-pane="access"]')).toBeVisible();
  await expect(page.locator('.st-tabs .st-link')).toHaveText('Retirement requests');
  r = await open(page, 'control-room.php');
  await expect(page.locator('.st-tabs [data-st]')).toHaveText(['Complaint types', 'Rules', 'Emergency numbers', 'Wording', 'The barangay', 'Parts of the system'])   // the fake's own wording renames Hotlines;
  await page.locator('.st-tabs [data-st="parts"]').click();
  await expect(page.locator('#acc-switches li')).toHaveCount(2);
  expect(await axe(page), 'Control Room > Parts of the system').toEqual([]);
  await page.goto('settings.php#types');
  await expect(page).toHaveURL(/control-room\.php#types$/);
  await expect(page.locator('section[data-pane="types"]')).toBeVisible();
  const q = await open(page, 'retirement-requests.php');
  await expect(page.locator('h1')).toHaveText('Administrative Services');
  await expect(page.locator('.st-tabs .st-link.p-on')).toHaveText('Retirement requests');
  expect(r.errors.concat(q.errors), 'console errors').toEqual([]);
});

test('Roles and pages 1b: committee colours, the super admin colour, and the sidebar each one wears', async ({ page, context }) => {
  let r = await open(page, 'administrative-services.php#access');
  await expect(page.locator('#acc-super input[type="color"]')).toHaveValue('#00308f');
  await expect(page.locator('#acc-committees form.acc-row input[type="color"]')).toHaveCount(6);
  await expect(page.locator('#acc-committees form.acc-row').first().locator('input[type="color"]')).toHaveValue('#d32f2f');
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
  for (const href of ['dashboard.php', 'administrative-services.php', 'control-room.php', 'settings.php', 'residents.php']) await expect(page.locator(`.p-sidebar a[href="${href}"]`)).toHaveCount(0);
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
  expect(await axe(page), 'Personnel, Committee staff').toEqual([]);
  const d = await open(page, 'personnel.php?id=u2');
  await expect(page.locator('#tc-card .tc-add button')).toContainText('Add to the committee');
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
  await Promise.all([page.waitForURL(/personnel\.php/), page.locator('#ss-bulk-tc button').click()]);
  await expect(page.locator('.p-flash--ok')).toContainText('2 added to Peace and Order');
  // the list's 20-second refresh redraws the rows the way the server drew them
  await page.waitForTimeout(21500);
  const after = await page.$$eval('#accounts-tbody tr', rs => rs.map(x => x.outerHTML));
  expect(after.map(norm)).toEqual(before.map(norm));
  expect(r.errors, 'console errors').toEqual([]);
});

test('Control Room: no tab overflows sideways, the limits share a line, the seal picker is a visible control, counts read right', async ({ page }) => {
  const r = await open(page, 'control-room.php');
  for (const tab of ['types', 'rules', 'hotlines', 'wording', 'brgy', 'parts']) {
    await page.locator(`.st-tabs [data-st="${tab}"]`).click();
    expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), `${tab} overflows sideways`).toBe(false);
  }
  await page.locator('.st-tabs [data-st="rules"]').click();
  for (const g of await page.locator('.ru-group').all()) {   // inputs of one group on one line, whatever their labels do
    const tops = await g.locator('.ru-f input').evaluateAll(is => is.map(i => Math.round(i.getBoundingClientRect().top)));
    expect(new Set(tops).size, 'limit inputs on one line: ' + tops).toBe(1);
  }
  expect(await page.locator('.ru-f input').count(), 'every limit is shown').toBe(13);
  await page.locator('.st-tabs [data-st="brgy"]').click();
  const box = await page.locator('#brgy-card input[type="file"]').boundingBox();
  expect(box && box.width > 100 && box.width < 1200, 'the seal picker is visible: ' + JSON.stringify(box)).toBeTruthy();
  await page.locator('.st-tabs [data-st="hotlines"]').click();
  await expect(page.locator('#hotlines-card')).not.toContainText('1 numbers');
  expect(r.errors, 'console errors').toEqual([]);
});

test('Roles and pages 5: the Inbox, writing along the ladder, and the reroute question', async ({ page, context }) => {
  const n = await open(page, 'notifications.php');
  await expect(page.locator('.fw-pins .p-notif', { hasText: 'No tanod of the committee is free' })).toHaveCount(1);
  await page.locator('.fw-pins a', { hasText: 'Pick a tanod' }).click();
  await expect(page).toHaveURL(/inbox\.php\?m=41/);
  await expect(page.locator('#ib-question')).toBeVisible();
  await expect(page.locator('#ib-question button[value="any"]')).toContainText('nearest from any committee');
  expect(await axe(page), 'Inbox, reroute question').toEqual([]);
  const i = await open(page, 'inbox.php');
  await expect(page.locator('.p-sidebar a[href="inbox.php"]').first()).toBeVisible();
  await expect(page.locator('.ib-row')).toHaveCount(2);
  await expect(page.locator('.ib-row.ib-unread')).toContainText('Needs your answer');
  const w = await open(page, 'inbox.php?new=1');
  await expect(page.locator('.ib-person')).toHaveCount(2);
  expect(await axe(page), 'Inbox, write').toEqual([]);
  const r = await open(page, 'inbox.php?m=42');
  await page.locator('.ib-act a', { hasText: 'Reply' }).click();
  await expect(page.locator('#ib-subject')).toHaveValue('Re: Pulong bukas');
  const c = await open(page, 'control-room.php#rules');
  await expect(page.locator('input[name="lim[reroute_ask_urgent_minutes]"]')).toHaveValue('5');
  await context.addCookies([{ name: 'ss_tier', value: 'moderator', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const m = await open(page, 'inbox.php');
  await expect(page.locator('.p-sidebar a[href="inbox.php"]').first()).toBeVisible();
  expect(n.errors.concat(i.errors, w.errors, r.errors, c.errors, m.errors), 'console errors').toEqual([]);
});

test('Feed rows: notifications about one case fold into a row, and the Inbox shows its countdown and its thread', async ({ page }) => {
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
  const i = await open(page, 'inbox.php');
  await expect(page.locator('.ib-row.ib-needs .ib-due')).toContainText(/\d+:\d\d left|time is up/);
  const t = await open(page, 'inbox.php?m=42');
  await expect(page.locator('.ib-thread .ib-msg')).toHaveCount(1);
  await expect(page.locator('.ib-thread .ib-msg')).toContainText('Sige po, darating ako.');
  expect(await axe(page), 'Inbox thread').toEqual([]);
  expect(n.errors.concat(i.errors, t.errors), 'console errors').toEqual([]);
});

test('Roles and pages 6a: the Dashboard super admin module, the box beside the donuts, the brain buttons', async ({ page }) => {
  const d = await open(page, 'dashboard.php');
  await page.locator('#ss-panel-btn').click();
  await expect(page.locator('.dc-needs .ss-tile').first()).toContainText('3');
  await expect(page.locator('.dc-coms tbody tr')).toHaveCount(4 + 1);
  await expect(page.locator('.dc-coms')).toContainText('Peace and Order');
  await page.locator('#legend-status [data-i="0"]').click();
  await expect(page.locator('#dq-box')).toBeVisible();
  await expect(page.locator('#dq-title')).toContainText('Done');
  await expect(page.locator('#dq-list li')).toHaveCount(2);
  await expect(page.locator('#dq-open')).toHaveAttribute('href', /cases\.php\?status=resolved/);
  await page.locator('.dq-brain[data-chart="received"]').click();
  await expect(page.locator('#notes-received')).toContainText('51 complaints this month, up 28% from last month (40).');
  await page.locator('.dq-brain[data-chart="efficiency"]').click();
  await expect(page.locator('#notes-efficiency')).toContainText('24 of 30 finished in time (80%).');
  expect(await axe(page), 'Dashboard, box and notes open').toEqual([]);
  expect(d.errors, 'console errors').toEqual([]);
});

test('Roles and pages 6b: Report Summary by committee, and the committee form signed by its Kagawad', async ({ page, context }) => {
  const s = await open(page, 'summary.php?range=month');
  await expect(page.locator('.rs-scope')).toContainText('Whole barangay');
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
  const m = await open(page, 'summary.php?range=month');
  await expect(page.locator('select#com')).toHaveCount(0);
  await expect(page.locator('.rs-scope')).toContainText('Peace and Order');
  expect(s.errors.concat(c.errors, f.errors, m.errors), 'console errors').toEqual([]);
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

test('Roles and pages 7: Edit Profile (banner, pills, alert switches, punch card) and a Kagawad endorsing a retirement', async ({ page, context }) => {
  const p = await open(page, 'profile.php');
  for (const k of ['case_forwarded', 'forward_flag', 'reroute_question', 'inbox_mail']) await expect(page.locator(`.ss-al-kinds input[data-kind="${k}"]`)).toHaveCount(1);
  await expect(page.locator('.ss-pf-who .rank')).toHaveCount(1);
  const e = await open(page, 'profile.php?edit=1');
  await page.locator('input[name="banner_preset"][value="solid"]').check();
  await page.locator('#banner_colour').fill('#1e9e4a');
  await expect(page.locator('#ss-pf-banner')).toHaveAttribute('style', /background: (rgb\(30, 158, 74\)|#1e9e4a)/);
  expect(await axe(page), 'Edit Profile, editing the banner').toEqual([]);
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const k = await open(page, 'profile.php');
  await expect(page.locator('.pf-punch')).toContainText('Still in');
  await expect(page.locator('.ss-pf-who')).toContainText('Peace and Order');
  const r = await open(page, 'personnel.php?view=retire');
  await expect(page.locator('#rt-k tbody tr')).toHaveCount(2);
  await expect(page.locator('.rt-endorse button')).toHaveCount(1);
  await expect(page.locator('#rt-k')).toContainText('Endorsed by Dela Cruz, Ramon');
  expect(await axe(page), 'Personnel, retirement requests (Kagawad)').toEqual([]);
  expect(p.errors.concat(e.errors, k.errors, r.errors), 'console errors').toEqual([]);
});

test('0145 access: a committee admin sees only its pages, and no SMART drawer', async ({ page, context }) => {
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const r = await open(page, 'cases.php');
  for (const href of ['dashboard.php', 'settings.php', 'residents.php']) await expect(page.locator(`.p-sidebar a[href="${href}"]`)).toHaveCount(0);
  await expect(page.locator('.p-sidebar a[href="personnel.php"]').first()).toBeVisible();   // 0153: a Kagawad sees their committee's tanods and staff
  await expect(page.locator('.p-sidebar a[href="cases.php"]').first()).toBeVisible();
  await expect(page.locator('#side-user')).toContainText('Peace and Order');
  await page.goto('dashboard.php');
  await expect(page).toHaveURL(/notifications\.php/);
  await page.goto('settings.php');
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
  await expect(page.locator('.p-sidebar a[href="residents.php"]')).toHaveCount(1);
  await expect(page.locator('#side-user')).toContainText('Captain');
  expect(await axe(page), 'Case page, captain').toEqual([]);
  expect(r.errors, 'console errors').toEqual([]);
});
