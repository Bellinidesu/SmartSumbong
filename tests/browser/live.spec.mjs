// Live updates (25 Nov 2026, Ace; docs/LIVE_UPDATES.md): pages update themselves, never over what someone is doing.
// The fake Supabase answers a Realtime socket only for a browser that carries the cookie ss_rt=<token> (fake/fake_sb.py), so each
// test has its own socket and pushes its own changes; the other specs see no socket, as before. Each test changes one case the
// other specs do not use (case 10, waiting for review) and puts it back.
//   bash serve.sh, then: npx playwright test live.spec.mjs --workers=1
//   (another port pair: LIVE_BASE=http://127.0.0.1:8023/admin/ FAKE_URL=http://127.0.0.1:54409)
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const FAKE = process.env.FAKE_URL || 'http://127.0.0.1:54399';
if (process.env.LIVE_BASE) test.use({ baseURL: process.env.LIVE_BASE });
test.describe.configure({ mode: 'serial' });
test.setTimeout(120000);

const C10 = 'c0000000-0000-0000-0000-000000000010';   // pending review, nobody handles it, no concerns
const CASE = `case.php?id=${C10}`;
const NOISE = [/tiles\.openfreemap\.org|mapillary|wikimedia|nominatim|open-meteo|overpass/i, /Failed to load resource: net::ERR_(NAME_NOT_RESOLVED|INTERNET_DISCONNECTED|CONNECTION_REFUSED|BLOCKED_BY_CLIENT)/,
  /Failed to load resource: the server responded with a status of 404/];
// without a socket (the polling tests) the browser logs the refused handshake: that is the condition under test
const NO_SOCKET = /realtime|websocket|ws:\/\/127\.0\.0\.1/i;

async function setup(page, context, { socket = true, liveOff = false } = {}) {
  const token = 't' + Math.random().toString(36).slice(2, 10);
  if (socket) await context.addCookies([{ name: 'ss_rt', value: token, domain: '127.0.0.1', path: '/' }]);
  if (liveOff) await context.addInitScript(() => { try { localStorage.setItem('ss-live', 'off'); } catch (e) {} });
  const errors = [];
  page.on('pageerror', e => errors.push('page: ' + e.message));
  page.on('console', m => { const t = m.text() + ' ' + (m.location().url || ''); if (m.type() === 'error' && !NOISE.some(r => r.test(t)) && (socket || !NO_SOCKET.test(t))) errors.push('console: ' + m.text()); });
  return { token, errors };
}
const patch = (page, body) => page.request.post(`${FAKE}/__patch`, { data: body });
const push = (page, token, table = 'reports', type = 'UPDATE') => page.request.get(`${FAKE}/__rt/push?token=${token}&table=${table}&type=${type}`).then(r => r.json());
const setStatus = (page, status) => patch(page, { table: 'reports', id: C10, set: { status } });
async function open(page, path) {
  await page.goto(path, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => window.ssLiveLayer && window.ssLiveLayer.mode !== 'starting', null, { timeout: 15000 }).catch(() => {});
}
const flags = page => page.locator('[data-live="case-flags"]');
const accept = page => page.locator('[data-live="case-controls"] button[value="accept"]');

test.afterEach(async ({ page }) => { await setStatus(page, 'pending_review'); });

test('a change pushed by Realtime updates the case in place: status pill, controls and tabs, the same elements kept', async ({ page, context }) => {
  const { token, errors } = await setup(page, context);
  await open(page, CASE);
  await expect(page.locator('#live-badge-text')).toHaveText('Live');
  await expect(accept(page)).toBeVisible();
  await page.evaluate(() => { document.querySelector('[data-live="case-flags"]').__kept = 1; document.querySelector('[data-live="case-controls"]').__kept = 1; });
  const before = await flags(page).innerText();
  await setStatus(page, 'validated');
  expect((await push(page, token)).sent, 'the page listens on its channel').toBeGreaterThan(0);
  await expect(flags(page)).not.toHaveText(before, { timeout: 10000 });
  await expect(accept(page), 'the review buttons go once the case is accepted').toHaveCount(0);
  expect(await page.evaluate(() => document.querySelector('[data-live="case-flags"]').__kept === 1 && document.querySelector('[data-live="case-controls"]').__kept === 1), 'morphed, not replaced').toBe(true);
  await expect(page.locator('#update-banner')).not.toHaveClass(/p-on/);   // the old "Refresh to see it" banner is not needed
  expect(await page.evaluate(() => document.querySelector('input[name="v"][data-case-v]') !== null), 'forms still carry the case version').toBe(true);
  expect(errors).toEqual([]);
  const axe = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']).analyze();
  expect(axe.violations.filter(v => ['serious', 'critical'].includes(v.impact)).map(v => v.id)).toEqual([]);
});

test('what is being typed is never clobbered: the other parts update, the typed part waits, the chip applies it', async ({ page, context }) => {
  const { token, errors } = await setup(page, context);
  await open(page, CASE);
  await page.locator('#deny-toggle').click();
  await page.locator('#reason').fill('Labas sa sakop ng barangay');
  const before = await flags(page).innerText();
  await setStatus(page, 'validated'); await push(page, token);
  await expect(flags(page), 'a part nobody is in updates at once').not.toHaveText(before, { timeout: 10000 });
  await expect(page.locator('#reason')).toHaveValue('Labas sa sakop ng barangay');
  await expect(page.locator('#reason')).toBeFocused();
  await expect(accept(page), 'the controls wait while the reason is typed').toBeVisible();
  await page.locator('.p-topbar .p-crumb').click();   // focus leaves the field; what was typed is still there, so it still waits
  await page.waitForTimeout(1500);
  await expect(page.locator('#reason')).toHaveValue('Labas sa sakop ng barangay');
  await expect(accept(page)).toBeVisible();
  const chip = page.locator('.ss-live-chip');
  await expect(chip, 'after 10 s a chip offers the update').toBeVisible({ timeout: 15000 });
  const box = await chip.locator('button').boundingBox();
  expect(box.height, 'the chip button is a 44 px target').toBeGreaterThanOrEqual(44);
  await chip.locator('button').click();
  await expect(accept(page), 'pressed: the controls follow the case').toHaveCount(0);
  await expect(chip).toBeHidden();
  expect(errors).toEqual([]);
});

test('a focused field waits only while it has the focus; an open dialog and an opened <details> hold their part until closed', async ({ page, context }) => {
  const { token, errors } = await setup(page, context);
  await open(page, CASE);
  // focus without typing: applies once the focus leaves
  await page.locator('#deny-toggle').click();
  await expect(page.locator('#reason')).toBeFocused();
  await setStatus(page, 'validated'); await push(page, token);
  await page.waitForTimeout(1500);
  await expect(accept(page)).toBeVisible();
  await page.locator('.p-topbar .p-crumb').click();
  await expect(accept(page)).toHaveCount(0, { timeout: 5000 });
  // the engine's "Why this level" dialog in the case body: the status pill beside the map waits behind it
  const pill = page.locator('[data-live="case-body"] .ss-ms-pills .p-badge').last();
  const pillBefore = await pill.innerText();
  await page.locator('[data-smart-open]').first().click();
  await expect(page.locator('#smart-card')).toBeVisible();
  await setStatus(page, 'in_progress'); await push(page, token);
  await page.waitForTimeout(2000);
  await expect(pill).toHaveText(pillBefore);
  await page.keyboard.press('Escape');
  await expect(page.locator('#smart-card')).toBeHidden();
  await expect(pill).not.toHaveText(pillBefore, { timeout: 5000 });
  // a <details> opened by hand in the controls holds them; closing it lets the update in
  const tile = page.locator('[data-live="case-controls"] details.p-fix:not(.cc-locked) > summary').first();
  await tile.click();
  const ctlBefore = await page.locator('[data-live="case-controls"]').innerHTML();
  await setStatus(page, 'validated'); await push(page, token);
  await page.waitForTimeout(2000);
  expect(await page.locator('[data-live="case-controls"]').innerHTML(), 'held while the details is open').toBe(ctlBefore);
  await tile.click();
  await expect.poll(() => page.locator('[data-live="case-controls"]').innerHTML(), { timeout: 6000 }).not.toBe(ctlBefore);
  expect(errors).toEqual([]);
});

test('the tab, the scroll inside the case and the chat head stay as they were', async ({ page, context }) => {
  const { token, errors } = await setup(page, context);
  await page.setViewportSize({ width: 1440, height: 640 });
  await open(page, CASE);
  await page.locator('#cc-tab-timeline').click();
  await expect(page.locator('.cc-timeline')).toBeVisible();
  await page.locator('#cc-body').evaluate(b => { b.scrollTop = 40; });
  const top = await page.locator('#cc-body').evaluate(b => b.scrollTop);
  const tabsBefore = await page.locator('[data-live="case-tabs"]').innerText();
  await setStatus(page, 'validated'); await push(page, token);
  await expect(accept(page)).toHaveCount(0, { timeout: 10000 });
  await expect(page.locator('#cc-tab-timeline')).toHaveAttribute('aria-selected', 'true');
  await expect(page.locator('.cc-timeline')).toBeVisible();
  await expect(page.locator('[data-live="case-body"] [data-cc-tab="report"]').first()).toBeHidden();
  expect(await page.locator('#cc-body').evaluate(b => b.scrollTop)).toBe(top);
  expect(await page.locator('[data-live="case-tabs"]').innerText()).toBe(tabsBefore);
  expect(errors).toEqual([]);
});

test('Realtime down: the badge says Polling and the page still updates itself', async ({ page, context }) => {
  const { errors } = await setup(page, context, { socket: false });
  await open(page, CASE);
  await expect(page.locator('#live-badge-text')).toHaveText('Polling', { timeout: 15000 });
  await expect(page.locator('#live-badge')).toHaveClass(/p-poll/);
  const axe = await new AxeBuilder({ page }).include('#live-badge').withTags(['wcag2a', 'wcag2aa']).analyze();
  expect(axe.violations.map(v => v.id), 'the Polling badge reads at AA').toEqual([]);
  await setStatus(page, 'validated');
  await expect(accept(page), 'the next check (every 25 s) brings it').toHaveCount(0, { timeout: 40000 });
  expect(errors).toEqual([]);
});

test('a rung that may not listen (the join is refused) falls back to polling', async ({ page, context }) => {
  const { token, errors } = await setup(page, context);
  await page.request.get(`${FAKE}/__rt/fail?token=${token}&table=reports`);
  await open(page, CASE);
  await expect(page.locator('#live-badge-text')).toHaveText('Polling', { timeout: 15000 });
  expect(errors.filter(e => !NO_SOCKET.test(e))).toEqual([]);
});

test('kill switch in this browser (ss-live=off): the old banner, nothing rewritten', async ({ page, context }) => {
  const { token, errors } = await setup(page, context, { liveOff: true });
  await open(page, CASE);
  expect(await page.evaluate(() => window.ssLiveLayer && window.ssLiveLayer.active)).toBe(false);
  const before = await flags(page).innerText();
  await setStatus(page, 'validated');
  await expect.poll(async () => (await push(page, token)).sent, { timeout: 10000 }).toBeGreaterThan(0);   // the page's own old channel
  await expect(page.locator('#update-banner')).toHaveClass(/p-on/, { timeout: 10000 });
  expect(await flags(page).innerText()).toBe(before);
  await expect(accept(page)).toBeVisible();
  expect(errors).toEqual([]);
});

test('kill switch on the server (feature switch live_updates off): no layer at all, the old behaviour', async ({ page, context }) => {
  const { token, errors } = await setup(page, context);
  await page.request.get(`${FAKE}/__feat?ws=1&cc=1&live=0`);
  try {
    await page.goto(CASE, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1500);
    expect(await page.locator('#ss-live-cfg').count()).toBe(0);
    expect(await page.evaluate(() => typeof window.ssLiveLayer)).toBe('undefined');
    await setStatus(page, 'validated');
    await expect.poll(async () => (await push(page, token)).sent, { timeout: 10000 }).toBeGreaterThan(0);
    await expect(page.locator('#update-banner')).toHaveClass(/p-on/, { timeout: 10000 });
    await expect(accept(page)).toBeVisible();
  } finally {
    await page.request.get(`${FAKE}/__feat?ws=1&cc=1&live=x`);
  }
  expect(errors).toEqual([]);
});

test('switched off on the server while a page is open: that page stops quietly', async ({ page, context }) => {
  const { token, errors } = await setup(page, context);
  await open(page, CASE);
  await expect(page.locator('#live-badge-text')).toHaveText('Live');
  await page.request.get(`${FAKE}/__feat?ws=1&cc=1&live=0`);
  try {
    await setStatus(page, 'validated'); await push(page, token);
    await expect.poll(() => page.evaluate(() => window.ssLiveLayer.stats.fetches), { timeout: 10000 }).toBeGreaterThan(0);
    await page.waitForTimeout(1000);
    await expect(accept(page), 'nothing is rewritten once the server says off').toBeVisible();
  } finally {
    await page.request.get(`${FAKE}/__feat?ws=1&cc=1&live=x`);
  }
  expect(errors).toEqual([]);
});

test('the case is no longer this person\'s (staff cannot read it): a calm notice, not an error', async ({ page, context }) => {
  const { token, errors } = await setup(page, context);
  await open(page, CASE);
  await expect(page.locator('#live-badge-text')).toHaveText('Live');
  await context.addCookies([{ name: 'ss_tier', value: 'moderator', domain: '127.0.0.1', path: '/' }]);   // the next request is a staff member's
  await push(page, token);
  const note = page.locator('.ss-live-gone');
  await expect(note).toBeVisible({ timeout: 10000 });
  await expect(note).toHaveAttribute('role', 'status');
  await expect(note.locator('a')).toHaveAttribute('href', /case\.php\?id=/);
  await expect(page.locator('.p-flash--error')).toHaveCount(0);
  expect(errors).toEqual([]);
});

test('Case Reports: a row changes in place, the view and ticked rows are kept', async ({ page, context }) => {
  const { token, errors } = await setup(page, context);
  await open(page, 'cases.php?by=created_at&dir=desc');
  await expect(page.locator('#live-badge-text')).toHaveText('Live');
  const row = page.locator(`[data-live="cases-list"] tr[data-live-key="${C10}"]`);
  await expect(row).toHaveCount(1);
  const url = page.url();
  const cell = row.locator('.p-badges');
  const before = await cell.innerText();
  // a ticked row (a super admin's bulk forward) holds the list
  const tick = page.locator('[data-live="cases-list"] input.fw-sel').first();
  await tick.check();
  await setStatus(page, 'validated'); await push(page, token);
  await page.waitForTimeout(2000);
  expect(await cell.innerText()).toBe(before);
  await tick.uncheck();
  await expect(cell).not.toHaveText(before, { timeout: 6000 });
  expect(page.url(), 'the view on screen is the one refetched').toBe(url);
  expect(errors).toEqual([]);
});

test('Notifications: a new one appears, the sidebar count follows', async ({ page, context }) => {
  const { token, errors } = await setup(page, context);
  const id = 'nlive' + Date.now();
  await open(page, 'notifications.php');
  await expect(page.locator('#live-badge-text')).toHaveText('Live');
  const pill = page.locator('#side-nav a[href="notifications.php"] .p-pill');
  const n0 = +(await pill.innerText().catch(() => '0')) || 0;
  await page.waitForTimeout(5500);   // the sidebar's counts are kept 5 s for a live refetch
  try {
    await patch(page, { table: 'notifications', append: { id, kind: 'status_change', message: 'Live test: SS-2610-1010 has a new update', created_at: new Date().toISOString(), is_read: false, report_id: C10, notification_committee: null } });
    await push(page, token, 'notifications', 'INSERT');
    await expect(page.locator(`[data-live="notes"] [data-live-key="n${id}"]`)).toBeVisible({ timeout: 10000 });
    await expect.poll(async () => +(await pill.innerText()), { timeout: 10000 }).toBe(n0 + 1);
  } finally {
    await patch(page, { table: 'notifications', remove: id });
  }
  expect(errors).toEqual([]);
});

test('Dashboard: one channel, a change refetches the engine window and the sidebar', async ({ page, context }) => {
  const { token, errors } = await setup(page, context);
  await open(page, 'dashboard.php');
  await expect(page.locator('#live-badge-text')).toHaveText('Live');
  const st = await (await page.request.get(`${FAKE}/__rt/state?token=${token}`)).json();
  expect(st.sockets, 'one connection for the page').toBe(1);
  await push(page, token);
  await expect.poll(() => page.evaluate(() => window.ssLiveLayer.stats.fetches), { timeout: 20000 }).toBeGreaterThan(0);
  expect(errors).toEqual([]);
});

test('hidden tab: no checks while hidden, one when it comes back', async ({ page, context }) => {
  const { errors } = await setup(page, context, { socket: false });
  await open(page, CASE);
  await expect(page.locator('#live-badge-text')).toHaveText('Polling', { timeout: 15000 });
  await page.evaluate(() => { Object.defineProperty(document, 'hidden', { configurable: true, get: () => true }); document.dispatchEvent(new Event('visibilitychange')); });
  const f0 = await page.evaluate(() => window.ssLiveLayer.stats.fetches);
  await page.evaluate(() => window.ssLiveLayer.kick());
  await page.waitForTimeout(4000);
  expect(await page.evaluate(() => window.ssLiveLayer.stats.fetches), 'nothing while hidden').toBe(f0);
  await page.evaluate(() => { Object.defineProperty(document, 'hidden', { configurable: true, get: () => false }); document.dispatchEvent(new Event('visibilitychange')); });
  await expect.poll(() => page.evaluate(() => window.ssLiveLayer.stats.fetches), { timeout: 5000 }).toBe(f0 + 1);
  expect(errors).toEqual([]);
});
