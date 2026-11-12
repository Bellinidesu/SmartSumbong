// Motion (12 Nov 2026, Ace): every page but Control Room, Settings and Profile opens with a short rise and answers hover and press; nothing that loops
// repaints; loops stop when they cannot be seen; reduced motion turns it all off. Run: bash serve.sh, then npx playwright test motion.spec.mjs.
import { test, expect } from '@playwright/test';

const CASE = 'c0000000-0000-0000-0000-000000000001';
const WITH = ['dashboard.php', 'home.php', 'cases.php', `case.php?id=${CASE}`, 'summary.php', 'spatial.php', 'workspace.php', 'notifications.php', 'inbox.php', 'inbox.php?app=mail',
  'residents.php', 'personnel.php', 'activity.php', 'administrative-services.php', 'retirement-requests.php'];
const WITHOUT = ['control-room.php', 'settings.php', 'profile.php'];

test('no loop repaints: every endless animation on every page moves only opacity and transform (or steps a gradient slowly)', async ({ page }) => {
  test.setTimeout(150000);
  const cheap = new Set(['opacity', 'transform', 'translate', 'scale', 'rotate', 'offset']);
  const bad = [];
  for (const p of [...WITH, ...WITHOUT]) {
    await page.goto(p, { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(1600);
    const found = await page.evaluate(() => document.getAnimations().filter(a => a.effect && a.effect.getComputedTiming().iterations === Infinity).map(a => {
      const kf = a.effect.getKeyframes ? a.effect.getKeyframes() : [];
      const props = [...new Set(kf.flatMap(k => Object.keys(k).filter(x => !['offset', 'easing', 'composite', 'computedOffset'].includes(x))))];
      const t = a.effect.target;
      return { name: a.animationName || a.transitionProperty, props, steps: /steps/.test(a.effect.getTiming().easing || '') || kf.some(k => /steps/.test(k.easing || '')), target: t ? t.tagName.toLowerCase() + (t.id ? '#' + t.id : '') : '?' };
    }));
    for (const f of found) {
      const heavy = f.props.filter(x => !cheap.has(x) && !(x.startsWith('backgroundPosition') && f.steps) && !(x === 'strokeDashoffset' && f.steps));
      if (heavy.length) bad.push(`${p}: ${f.name} (${heavy.join(', ')}) on ${f.target}`);
    }
  }
  expect(bad, 'endless animations that repaint').toEqual([]);
});

test('first open: the pages rise in once and then the class that lets them is taken off; Control Room, Settings and Profile have none', async ({ page }) => {
  test.setTimeout(120000);
  // a block must never start moving again once the first open is over (the class coming off must not hand it to another rule that animates it)
  await page.addInitScript(() => {
    window.__ev = []; window.__rm = 0;
    document.addEventListener('animationstart', e => { const p = e.target.parentElement; window.__ev.push({ n: e.animationName, t: performance.now(), main: !!(p && p.matches && p.matches('main.p-main')) }); }, true);
    new MutationObserver(() => { if (document.body && !document.body.classList.contains('mo-in') && !window.__rm) window.__rm = performance.now(); }).observe(document.documentElement, { subtree: true, attributes: true, attributeFilter: ['class'] });
  });
  for (const p of ['cases.php', 'workspace.php', 'inbox.php', 'dashboard.php', 'summary.php', 'residents.php', 'spatial.php', `case.php?id=${CASE}`]) {
    await page.goto(p, { waitUntil: 'commit' });
    await page.waitForSelector('main.p-main', { state: 'attached' });
    await expect(page.locator('body')).toHaveClass(/mo-on/);
    const rising = await page.evaluate(() => document.getAnimations().filter(a => a.animationName === 'moRise').length);
    if (p === 'spatial.php') { expect(rising, 'the map keeps its own entrances').toBe(0); continue; }
    expect(rising, p + ': blocks rising in').toBeGreaterThan(0);
    await expect(page.locator('body')).not.toHaveClass(/mo-in/, { timeout: 4000 });                // it plays once; later swaps never replay it
    await page.waitForTimeout(1500);
    expect(await page.evaluate(() => document.getAnimations().filter(a => a.animationName === 'moRise').length), p + ': nothing left rising').toBe(0);
    const late = await page.evaluate(() => window.__ev.filter(e => e.main && window.__rm && e.t > window.__rm - 50 && e.n !== 'moRise').map(e => e.n));
    expect(late, p + ': a block started another animation when the first open ended').toEqual([]);
  }
  for (const p of WITHOUT) {
    await page.goto(p, { waitUntil: 'commit' });
    await page.waitForSelector('main.p-main', { state: 'attached' });
    const cls = await page.locator('body').getAttribute('class');
    expect(cls, p + ' has no motion classes').not.toMatch(/mo-on|mo-in/);
    expect(await page.evaluate(() => document.getAnimations().filter(a => a.animationName === 'moRise').length), p + ': nothing rises').toBe(0);
  }
});

test('reduced motion: nothing rises, nothing lifts', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('cases.php', { waitUntil: 'commit' });
  await page.waitForSelector('main.p-main', { state: 'attached' });
  expect(await page.evaluate(() => document.getAnimations().filter(a => a.animationName === 'moRise').length)).toBe(0);
  await page.waitForLoadState('networkidle').catch(() => {});
  const btn = page.locator('.p-main a.p-btn.p-btn-ghost.p-btn-sm').first();
  await expect(btn).toBeVisible();
  await btn.hover(); await page.waitForTimeout(300);
  expect(await btn.evaluate(e => new DOMMatrix(getComputedStyle(e).transform).m42), 'no lift under reduced motion').toBe(0);
});

test('hover and press: a button lifts and presses; the sidebar answers on every page, the excepted ones too', async ({ page }) => {
  await page.goto('cases.php', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle').catch(() => {}); await page.waitForTimeout(1500);        // the first open has finished
  const chip = page.locator('.p-main a.p-btn.p-btn-ghost.p-btn-sm').first();
  expect(await chip.count(), 'Case Reports has buttons to point at').toBeGreaterThan(0);
  {
    expect(await chip.evaluate(e => getComputedStyle(e).transitionProperty), 'a button fades and moves, it does not snap').toMatch(/transform/);
    await chip.hover(); await page.waitForTimeout(350);
    expect(await chip.evaluate(e => new DOMMatrix(getComputedStyle(e).transform).m42), 'a button lifts a pixel on hover').toBeLessThan(0);
    await page.mouse.down(); await page.waitForTimeout(150);
    expect(await chip.evaluate(e => new DOMMatrix(getComputedStyle(e).transform).a), 'presses in').toBeLessThan(1);
    await page.mouse.move(0, 0); await page.mouse.up();
  }
  for (const p of ['cases.php', 'settings.php']) {
    await page.goto(p, { waitUntil: 'domcontentloaded' });
    const link = page.locator('.p-nav a').nth(1);
    expect(await link.evaluate(e => getComputedStyle(e).transitionProperty), p + ': the sidebar fades its colours').toMatch(/background-color/);
    expect(await link.locator('> svg').evaluate(e => getComputedStyle(e).transitionProperty), p + ': the icon leans in').toMatch(/transform/);
  }
});

test('a loop that cannot be seen stops: out of view it is paused, in view it runs', async ({ page }) => {
  await page.goto('cases.php', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle').catch(() => {});
  await page.evaluate(() => {
    const s = document.createElement('style'); s.textContent = '@keyframes moTestBlink { 50% { opacity: .5; } } #mo-test { position: absolute; left: 20px; top: 6000px; width: 20px; height: 20px; background: red; animation: moTestBlink 1s infinite; }';
    document.head.appendChild(s); const d = document.createElement('div'); d.id = 'mo-test'; document.body.appendChild(d);
  });
  const state = () => page.evaluate(() => { const a = document.getAnimations().find(x => x.animationName === 'moTestBlink'); return a ? a.playState : 'none'; });
  await expect.poll(state, { timeout: 5000 }).toBe('paused');                                  // far below the screen
  await page.evaluate(() => { document.getElementById('mo-test').style.top = '120px'; });       // brought into view
  await expect.poll(state, { timeout: 5000 }).toBe('running');
});

test('Spatial Distribution: the filter box opens over nothing; the SMART suggestion rides down with it', async ({ page }) => {
  await page.setViewportSize({ width: 2048, height: 1000 });
  await page.goto('spatial.php', { waitUntil: 'domcontentloaded' });
  const sug = page.locator('#cc-suggest');
  await expect(sug).toBeVisible({ timeout: 8000 });
  await page.mouse.move(700, 40);                                                       // point at the filter box: it opens downward
  await page.waitForTimeout(900);
  const box = await page.locator('#map-search').boundingBox(), s = await sug.boundingBox();
  expect(s.y, 'the suggestion starts below the open filter box').toBeGreaterThanOrEqual(box.y + box.height - 1);
  await page.mouse.move(1200, 700); await page.waitForTimeout(900);
  const s2 = await sug.boundingBox(); expect(s2.y, 'and comes back up when the box closes').toBeLessThan(s.y);
});

