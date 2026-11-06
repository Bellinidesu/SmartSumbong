// Local audit tool, the rules pass: RA=1 [SIZES=2048:light,2048:dark,1440:light,1024:light] [OUT=dir] npx playwright test rules-audit.spec.mjs
// Opens every page, every tab and every popup of the super admin, applies the rules in rules-lib.mjs, and writes rules-findings.json
// (all findings) and prints the findings grouped by rule and element, most widespread first.
import { test } from '@playwright/test';
import { writeFileSync, mkdirSync } from 'node:fs';
import { auditScope, summarise } from './rules-lib.mjs';
test.skip(!process.env.RA, 'audit tool');
test.describe.configure({ mode: 'serial' });
test.setTimeout(900000);
const OUT = (process.env.OUT || 'C:/Users/acele/AppData/Local/Temp/claude/c--Users-acele-SmartSumbong/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/ra') + '/';
mkdirSync(OUT, { recursive: true });
const CASE = 'c0000000-0000-0000-0000-000000000001';
const SIZES = (process.env.SIZES || '2048:light,2048:dark,1440:light,1024:light').split(',').map(x => x.split(':'));
const PAGES = [
  'dashboard.php', 'summary.php', 'spatial.php', 'cases.php', `case.php?id=${CASE}`, 'workspace.php', 'notifications.php', 'inbox.php',
  'residents.php', 'residents.php?id=u1', 'personnel.php', 'personnel.php?id=u2', 'personnel.php?view=staff', 'retirement-requests.php', 'activity.php',
  'administrative-services.php', 'control-room.php', 'settings.php', 'profile.php', `complaint-summary.php?id=${CASE}`, 'widgets.php',
];
const findings = []; const covered = new Set();

async function tabs(page, p) {
  const names = await page.$$eval('.st-tabs [data-st]', bs => bs.map(b => b.dataset.st));
  return names;
}

for (const [W, mode] of SIZES) {
  test(`rules ${W} ${mode}`, async ({ page }) => {
    await page.setViewportSize({ width: +W, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
    await page.goto('dashboard.php'); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); localStorage.removeItem('ss-people-view'); } catch (e) {} }, mode);
    const push = (page_, rows) => { covered.add(page_); rows.forEach(r => findings.push({ ...r, page: page_, size: W, mode })); };
    for (const p of PAGES) {
      try {
        await page.goto(p, { waitUntil: 'domcontentloaded' }); await page.waitForLoadState('networkidle', { timeout: 6000 }).catch(() => {}); await page.waitForTimeout(1300);
        const t = await tabs(page, p);
        if (t.length) {
          for (const k of t) { await page.locator(`.st-tabs [data-st="${k}"]`).click(); await page.waitForTimeout(500); push(`${p}#${k}`, await auditScope(page)); }
        } else push(p, await auditScope(page));
        // every modal on the page
        for (const id of (await page.$$eval('.p-scrim[id]', s => s.map(x => x.id))).filter(x => x !== 'p-m-confirm')) {
          await page.evaluate(i => window.pOpen && window.pOpen(i), id); await page.waitForTimeout(350);
          push(`${p} [modal ${id}]`, await auditScope(page, `#${id} .p-modal`));
          await page.keyboard.press('Escape'); await page.evaluate(i => { const s = document.getElementById(i); s && s.classList.remove('p-on', 'on', 'open'); }, id);
        }
      } catch (e) { findings.push({ rule: 'error', where: p, detail: String(e.message).slice(0, 120), page: p, size: W, mode }); }
    }
    // overlays that are not .p-scrim: the Forward / Flag dialog, the engine panel, the donut's quick view
    try {
      await page.goto('cases.php', { waitUntil: 'networkidle' }); await page.waitForTimeout(800);
      await page.locator('.fw-btn').first().click(); await page.waitForTimeout(500);
      push('cases.php [Forward dialog]', await auditScope(page, '#fw-dlg')); await page.keyboard.press('Escape');
      await page.goto('dashboard.php', { waitUntil: 'networkidle' }); await page.waitForTimeout(1200);
      await page.locator('#ss-win-open').click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(700);
      push('dashboard.php [engine window open]', await auditScope(page, '#ss-panel')); await page.keyboard.press('Escape'); await page.waitForTimeout(400);
      await page.locator('#legend-status > div').first().click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(600);
      push('dashboard.php [quick view]', await auditScope(page, '#dq-box'));
      // 5 Nov sweep: the brain windows, the pickers, the map's overlays
      for (const p of ['cases.php', 'notifications.php', 'summary.php']) {
        await page.goto(p, { waitUntil: 'networkidle' }); await page.waitForTimeout(800);
        await page.locator('#ss-win-open').click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(700);
        push(`${p} [engine window open]`, await auditScope(page, '#ss-panel')); await page.keyboard.press('Escape'); await page.waitForTimeout(300);
      }
      await page.locator('#period-form .sdp-btn').first().click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(500);
      await page.locator('.sdp-rng .sdp-d[data-d]').nth(9).click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(300);
      push('summary.php [range picker]', await auditScope(page, '.sdp-pop')); await page.keyboard.press('Escape');
      await page.locator('.sdp-btn:not(.sdp-month)').first().click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(400);
      push('summary.php [select picker]', await auditScope(page, '.sdp-pop')); await page.keyboard.press('Escape');
      await page.goto('spatial.php', { waitUntil: 'domcontentloaded' }); await page.waitForTimeout(3500);
      push('spatial.php [floating tab]', await auditScope(page, '#map-search'));
      await page.locator('#cc-toggle').click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(700);
      push('spatial.php [command center]', await auditScope(page, '#cc-side')); await page.locator('#cc-toggle').click({ timeout: 2000 }).catch(() => {});
      await page.locator('#incident-toggle').click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(500);
      await page.locator('#pin-list button, #pin-list li').first().click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(900);
      push('spatial.php [case sheet]', await auditScope(page, '#case-sheet'));
    } catch (e) { findings.push({ rule: 'error', where: 'overlays', detail: String(e.message).slice(0, 120), page: 'overlays', size: W, mode }); }
  });
}
// 5 Nov sweep: the portal as a Kagawad and as staff (their Home, their Settings, Personnel and the case pages)
const RUNG_PAGES = ['home.php', 'cases.php', 'notifications.php', 'summary.php', 'inbox.php', 'personnel.php', 'personnel.php?view=staff', 'personnel.php?id=u2', 'settings.php', 'profile.php'];
for (const [tier, label] of [['committee', 'Kagawad'], ['moderator', 'staff']]) for (const [W, mode] of SIZES.slice(0, 2)) {
  test(`rules ${label} ${W} ${mode}`, async ({ page, context }) => {
    await context.addCookies([{ name: 'ss_tier', value: tier, url: 'http://127.0.0.1:8013' }, { name: 'ss_committee', value: 'peace_order', url: 'http://127.0.0.1:8013' }]);
    await page.setViewportSize({ width: +W, height: 1100 }); await page.emulateMedia({ colorScheme: mode });
    await page.goto('home.php'); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
    for (const p of RUNG_PAGES) {
      try {
        await page.goto(p, { waitUntil: 'domcontentloaded' }); await page.waitForLoadState('networkidle', { timeout: 6000 }).catch(() => {}); await page.waitForTimeout(1200);
        const t = await tabs(page, p);
        const tag = `[${label}] ${p}`;
        if (t.length) { for (const k of t) { await page.locator(`.st-tabs [data-st="${k}"]`).click(); await page.waitForTimeout(500); findings.push(...(await auditScope(page)).map(r => ({ ...r, page: `${tag}#${k}`, size: W, mode }))); covered.add(`${tag}#${k}`); } }
        else { findings.push(...(await auditScope(page)).map(r => ({ ...r, page: tag, size: W, mode }))); covered.add(tag); }
        if (await page.locator('#ss-win-open').count()) { await page.locator('#ss-win-open').click(); await page.waitForTimeout(600); findings.push(...(await auditScope(page, '#ss-panel')).map(r => ({ ...r, page: `${tag} [engine window]`, size: W, mode }))); await page.keyboard.press('Escape'); }
      } catch (e) { findings.push({ rule: 'error', where: p, detail: String(e.message).slice(0, 120), page: `[${label}] ${p}`, size: W, mode }); }
    }
  });
}
test.afterAll(() => {
  writeFileSync(OUT + 'rules-findings.json', JSON.stringify(findings, null, 1));
  const g = summarise(findings);
  console.log('RULES covered', covered.size, 'screens:', [...covered].map(x => x.replace(/c0000000[-0-9a-f]+/, 'CASE')).join(' ; '));
  console.log('RULES total', findings.length, 'distinct', g.length);
  for (const x of g.slice(0, 120)) console.log('R', x.rule.padEnd(11), String(x.on.size).padStart(3) + ' pages', String(x.n).padStart(4) + 'x', x.where, '::', x.detail);
});
