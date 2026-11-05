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

test('Settings, peak: the SMART tab shows one group at a time and remembers it; the services are a band over a blue header', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'settings.php#status');
  const g = await page.evaluate(() => { const R = s => document.querySelector(s).getBoundingClientRect(); return { band: Math.round(R('.st-svcband').bottom), table: Math.round(R('.st-svc').top), th: getComputedStyle(document.querySelector('.st-svc thead th')).backgroundColor }; });
  expect(Math.abs(g.band - g.table), 'the band and the table touch').toBeLessThanOrEqual(1);
  expect(g.th, 'blue under the orange band').toBe('rgb(0, 48, 143)');
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
  await expect(page.locator('.st-tabs [data-st]')).toHaveText(['Complaint types', 'Rules', 'Emergency numbers', 'Wording', 'The barangay', 'Parts of the system', 'App updates'])   // the fake's own wording renames Hotlines;
  await page.locator('.st-tabs [data-st="parts"]').click();
  await expect(page.locator('#acc-switches li')).toHaveCount(3);   // Workspace, Command center, Live preview on a phone
  expect(await axe(page), 'Control Room > Parts of the system').toEqual([]);
  await page.goto('settings.php#types');
  await expect(page).toHaveURL(/control-room\.php#types$/);
  await expect(page.locator('section[data-pane="types"]')).toBeVisible();
  const q = await open(page, 'retirement-requests.php');
  await expect(page.locator('h1')).toHaveText('Administrative Services');
  await expect(page.locator('.st-tabs .st-link.p-on')).toHaveText('Retirement requests');
  expect(r.errors.concat(q.errors), 'console errors').toEqual([]);
});

test('Committees tab: a card each, a live banner, chips for the kinds of complaint, and Save only when something changed', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1000 });
  const r = await open(page, 'administrative-services.php');
  await page.locator('.st-tabs [data-st="access"]').click();
  await expect(page.locator('#acc-committees .cmx-card:not(.cmx-card-new)')).toHaveCount(5);
  await expect(page.locator('.cmx-note'), 'a note says which kinds of complaint nobody sees').toBeVisible();
  const card = page.locator('#acc-committees .cmx-card').first();
  await expect(card.locator('.cmx-save'), 'nothing changed, nothing to save').toBeDisabled();
  const before = await card.locator('.cmx-banner .cm-chip').evaluate(e => e.style.getPropertyValue('--g1') + '|' + e.querySelectorAll('.cm-sym svg').length);
  await card.locator('.cmx-t:not(:has(input:checked))').first().click();
  await expect(card.locator('.cmx-save'), 'a change lights Save up').toBeEnabled();
  await expect(card.locator('.cmx-dirty-note')).toBeVisible();
  const after = await card.locator('.cmx-banner .cm-chip').evaluate(e => e.style.getPropertyValue('--g1') + '|' + e.querySelectorAll('.cm-sym svg').length);
  expect(after, 'and the banner follows the kinds of complaint it has').not.toBe(before);
  await card.locator('.cmx-t:has(input:checked)').last().click();   // undo what was just added or a second change: still a change
  expect(await card.locator('.cmx-banner').evaluate(e => Math.round(e.getBoundingClientRect().height)), 'the banner is slim').toBeLessThanOrEqual(80);
  expect(await card.locator('.cmx-t').evaluateAll(ts => ts.filter(t => getComputedStyle(t).borderTopWidth === '0px').length), 'every kind is a bordered chip').toBe(0);
  await expect(page.locator('#acc-super'), 'the super admin colour is the last thing on the tab').toBeVisible();
  expect(r.errors.filter(e => !/WebSocket/.test(e)), 'console errors').toEqual([]);
});

test('Roles and Escalation, peak: the position chooser filters the table, the band, chooser and table are three objects, kinds of complaint wear their colour', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1000 });
  const r = await open(page, 'administrative-services.php');
  await page.locator('.st-tabs [data-st="admins"]').click();
  await expect(page.locator('.ad-roles .cm-chip')).toHaveCount(5);   // All, Chairman, Councilor, Secretary, Staff
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

test('Control Room, peak: kinds of complaint are chips with who sees them, rules are sectioned with a save bar, hotlines are cards', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1000 });
  const r = await open(page, 'control-room.php');
  await expect(page.locator('#types-card details.ty-cat .ty-chip')).toHaveCount(8);
  await expect(page.locator('#types-card .ty-own-none').first(), 'a kind of complaint nobody sees is called out').toBeVisible();
  expect(await page.locator('#types-card .ty-chip').evaluateAll(cs => cs.filter(c => getComputedStyle(c).backgroundColor === 'rgba(0, 0, 0, 0)').length), 'each chip is in its colour').toBe(0);
  await page.locator('.st-tabs [data-st="rules"]').click();
  await expect(page.locator('#rules-card .ru-group'), 'a card per group of limits').toHaveCount(4);
  expect(await page.locator('#rules-card .ru-t thead th').first().evaluate(t => getComputedStyle(t).backgroundColor), 'blue under the heading').toBe('rgb(0, 48, 143)');
  await expect(page.locator('#rules-card .ru-bar .cmx-dirty-note'), 'nothing changed yet').toBeHidden();
  await page.locator('#rules-card .ru-f input').first().fill('7');
  await expect(page.locator('#rules-card .ru-bar .cmx-dirty-note')).toBeVisible();
  expect(await page.locator('#rules-card .ru-bar').evaluate(e => getComputedStyle(e).position), 'the save bar stays in view').toBe('sticky');
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
  await page.locator('.st-tabs [data-st="rules"]').click();
  await expect(page.locator('#ed-phone'), 'Rules has no screen').toBeHidden();
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
  await expect(sw.locator('.dv-l')).toHaveCount(4);   // Super admin, Captain, Kagawad, Staff
  await expect(sw.locator('.dv-l').nth(2)).toContainText('Kagawad');
  await expect(sw.locator('.dv-l').nth(2)).toContainText('Peace and Order');
  await sw.locator('.dv-setup button[type=submit]').click();
  await expect(page.locator('.dv-msg')).toContainText('test accounts are ready');
  await expect(page.locator('.dv-sw[open]'), 'the panel is open to show what the last action said').toHaveCount(1);
  await page.locator('.dv-sw .dv-l').nth(2).click();
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
  for (const href of ['dashboard.php', 'administrative-services.php', 'control-room.php', 'residents.php']) await expect(page.locator(`.p-sidebar a[href="${href}"]`)).toHaveCount(0);
  await expect(page.locator('.p-sidebar a[href="settings.php"]')).toHaveCount(1);   // their own Settings (4 Nov 2026)
  await page.goto('control-room.php');
  await expect(page).toHaveURL(/home\.php/);
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

test('Administrative Services: headers sit over their cells, the committees say who leads them, escalation has its own tab', async ({ page }) => {
  const r = await open(page, 'administrative-services.php');
  for (const tab of ['access', 'admins', 'ladder', 'plan']) {
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

test('An account\'s page: two columns of cards, one height per row, the controls in view', async ({ page }) => {
  const r = await open(page, 'personnel.php?id=u2');
  const box = sel => page.locator(sel).first().evaluate(e => { const b = e.getBoundingClientRect(); return [Math.round(b.top), Math.round(b.left), Math.round(b.height), Math.round(b.bottom)]; });
  const a = await box('.pd-details'), b = await box('.pd-tc'), c = await box('.pd-duty'), d = await box('.pd-id');
  expect(a[0], 'details and committees start on one line').toBe(b[0]);
  expect(Math.abs(c[3] - b[3]), 'details and the shift stack down the left as tall as the committees card').toBeLessThanOrEqual(2);
  expect(Math.abs(a[3] + 20 - c[0]), 'with the grid gap between them').toBeLessThanOrEqual(2);
  expect(b[1], 'two columns').toBeGreaterThan(a[1] + 100);
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

test('System status: the table is the page, the diagram of the same services opens on request', async ({ page }) => {
  const r = await open(page, 'settings.php');
  await expect(page.locator('#st-rows tr')).toHaveCount(9);
  await expect(page.locator('details.st-mapd')).not.toHaveAttribute('open', '');
  const closed = await page.evaluate(() => document.documentElement.scrollHeight);
  await page.locator('details.st-mapd summary').click();
  await expect(page.locator('#st-map svg')).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollHeight), 'opening it adds the diagram').toBeGreaterThan(closed + 250);
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
      await page.evaluate(() => { try { localStorage.setItem('ss-people-view', 'list'); } catch (e) {} });
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
    await page.evaluate(() => { try { localStorage.setItem('ss-people-view', 'list'); } catch (e) {} });
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
  // Squares: wide cards, no lone straggler beside a gap, the strip closes off under the band
  await page.setViewportSize({ width: 2048, height: 1000 });
  await open(page, 'residents.php');
  await page.evaluate(() => { try { localStorage.setItem('ss-people-view', 'sq'); } catch (e) {} });
  await page.reload();
  const cols = await page.locator('.ss-people.ss-sq tbody tr').evaluateAll(rs => new Set(rs.map(r => Math.round(r.getBoundingClientRect().top))).size);
  expect(cols, 'six residents fall in two rows at most').toBeLessThanOrEqual(2);
  expect(await page.locator('.ss-people.ss-sq tbody tr').first().evaluate(r => r.getBoundingClientRect().width), 'each card is at least 300 wide').toBeGreaterThanOrEqual(300);
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
  await expect(page.locator('.pd-head h2')).toContainText('Santos');
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

test('Roles and pages 7: Edit Profile (banner, pills, alert switches, punch card) and a Kagawad endorsing a retirement', async ({ page, context }) => {
  const p = await open(page, 'profile.php');
  for (const k of ['case_forwarded', 'forward_flag', 'reroute_question', 'inbox_mail']) await expect(page.locator(`.ss-al-kinds input[data-kind="${k}"]`)).toHaveCount(1);
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
  for (const href of ['dashboard.php', 'residents.php', 'administrative-services.php', 'control-room.php']) await expect(page.locator(`.p-sidebar a[href="${href}"]`)).toHaveCount(0);
  await expect(page.locator('.p-sidebar a[href="personnel.php"]').first()).toBeVisible();   // 0153: a Kagawad sees their committee's tanods and staff
  await expect(page.locator('.p-sidebar a[href="cases.php"]').first()).toBeVisible();
  await expect(page.locator('#side-user')).toContainText('Peace and Order');
  await page.goto('dashboard.php');
  await expect(page).toHaveURL(/home\.php/);
  await page.goto('control-room.php');
  await expect(page).toHaveURL(/home\.php/);
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

test('0164 each rung: the seal alone for a super admin, the committee logo beside it for a Kagawad, Personnel view only for staff', async ({ page, context }) => {
  const r = await open(page, 'notifications.php');
  await expect(page.locator('.p-side-top .p-brand-img')).toHaveCount(1);   // the barangay seal
  await expect(page.locator('.p-side-top .p-brand-com')).toHaveCount(0);
  await expect(page.locator('.p-sidebar img[src*="logo-wordmark"]')).toHaveCount(0);   // the wordmark is on the sign-in pages only
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'environment', url: 'http://127.0.0.1:8013' }]);
  await open(page, 'notifications.php');
  await expect(page.locator('.p-side-top img.p-brand-com')).toHaveAttribute('alt', /Environment and Disaster Risk/);   // an uploaded logo
  await context.addCookies([{ name: 'ss_tier', value: 'moderator', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const m = await open(page, 'personnel.php');
  await expect(page.locator('.p-side-top .p-brand-com.p-brand-sym svg path').first()).toBeAttached();   // no logo yet: the committee's symbol
  await expect(page.locator('.p-sidebar a[href="personnel.php"]').first()).toBeVisible();
  await expect(page.locator('.tc-tabs a')).toHaveText(['Tanods', 'Committee staff']);
  await expect(page.locator('#tc-propose, #ss-bulk-tc, .quick-verify-form, .ss-requests')).toHaveCount(0);
  await expect(page.locator('#overdue-banner')).toBeHidden();
  await expect(page.locator('#ss-people a.p-btn-primary')).toHaveCount(0);   // nothing to review: only a super admin verifies
  await open(page, 'personnel.php?view=staff');
  await expect(page.locator('.p-main form')).toHaveCount(0);
  await open(page, 'personnel.php?id=u2');
  await expect(page.locator('.p-main form')).toHaveCount(0);
  expect(await axe(page), 'tanod page, staff').toEqual([]);
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

test('Rose, 2 Nov: the lock holds when the map is pressed, the layers are a row of the floating tab, and the first day picked can be taken back', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1100 });
  const r = await open(page, 'spatial.php');
  await expect(page.locator('#map-search .p-row-lyr #lyr-list .map-sw')).not.toHaveCount(0);   // the layers, in the tab
  await expect(page.locator('#layers-btn')).toBeHidden();
  await page.locator('#map-pin').click();
  await expect(page.locator('#map-pin')).toHaveAttribute('aria-pressed', 'true');
  await page.mouse.move(1200, 900); await page.mouse.down(); await page.mouse.move(1260, 860, { steps: 6 }); await page.mouse.up();   // press and drag on the map
  await page.waitForTimeout(600);
  await expect(page.locator('#f-category')).toBeVisible();   // the filters stay
  expect(await page.locator('.p-row-lyr').evaluate(e => e.getBoundingClientRect().height)).toBeGreaterThan(30);
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

test('Home for a Kagawad and staff: they land there, it reads their SMART module, and the Dashboard stays with the super admins (part 3)', async ({ page, context }) => {
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  await page.goto('index.php');
  await expect(page).toHaveURL(/home\.php/);   // where they land after signing in
  const r = await open(page, 'home.php');
  await expect(page.locator('.p-sidebar .p-nav a').first()).toHaveAttribute('href', 'home.php');
  await expect(page.locator('.hm-banner')).toContainText('Peace and Order');
  await expect(page.locator('.hm-lead .hm-tile')).toHaveCount(4);
  await expect(page.locator('.hm-lead .hm-tile').first()).toContainText('Escalations to approve');
  await expect(page.locator('.hm-row-6 .hm-tile')).toHaveCount(6);
  await expect(page.locator('.hm-list tr[data-href^="case.php?id="]').first()).toBeAttached();
  expect(await axe(page), 'Home, Kagawad').toEqual([]);
  await context.addCookies([{ name: 'ss_tier', value: 'moderator', url: 'http://127.0.0.1:8013' }]);
  const m = await open(page, 'home.php');
  await expect(page.locator('.hm-lead .hm-tile').first()).toContainText('Yours');   // staff: their work, not decisions
  await expect(page.locator('.hm-lead')).not.toContainText('Escalations to approve');
  await context.addCookies([{ name: 'ss_tier', value: 'super', url: 'http://127.0.0.1:8013' }]);
  await page.goto('home.php');
  await expect(page).toHaveURL(/notifications\.php/);   // a super admin has the Dashboard
  await expect(page.locator('.p-sidebar a[href="home.php"]')).toHaveCount(0);
  expect(r.errors.concat(m.errors), 'console errors').toEqual([]);
});

test('The brain button answers from the person\'s SMART module on Case Reports, Notifications, Report Summary and Home (part 4)', async ({ page, context }) => {
  await context.addCookies([{ name: 'ss_tier', value: 'committee', url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
  const errs = [];
  for (const p of ['cases.php', 'notifications.php', 'summary.php', 'home.php']) {
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
    if (p === 'home.php') await expect(page.locator('#ss-panel .mb-home')).toHaveCount(0);   // already home
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
  const btn = page.locator('form:has(input[name="action"][value="read_all"]) button[type="submit"]');
  await expect(btn).toHaveCount(1);
  // the form answers into a hidden frame, so this page stays on screen while the save is on its way (a test cannot read a page that
  // a form is navigating away); the send itself is the normal one
  await page.evaluate(() => { const fr = document.createElement('iframe'); fr.name = 'sink'; fr.hidden = true; document.body.appendChild(fr);
    document.querySelector('form:has(input[name="action"][value="read_all"])').setAttribute('target', 'sink'); });
  await btn.click();
  await expect(btn, 'the pressed button says it is working').toHaveClass(/is-sending/);
  await expect(page.locator('form:has(input[name="action"][value="read_all"])')).toHaveAttribute('aria-busy', 'true');
  // a second press, and a script sending the form again, while the first is on its way
  await btn.click({ force: true });
  await page.evaluate(() => document.querySelector('form:has(input[name="action"][value="read_all"])').requestSubmit());
  await page.waitForTimeout(3200);
  expect(posts, 'one press, one request').toBe(1);
  expect(r.errors, 'console errors').toEqual([]);
  await ctx.close();
});
