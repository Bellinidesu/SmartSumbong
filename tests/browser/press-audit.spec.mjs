// Local audit tool: PA=1 npx playwright test press-audit.spec.mjs
// What every press on every page does, for each rung: the listeners actually attached in the browser are recorded (addEventListener is
// watched from the first line of the page), delegated handlers are read for the selectors they answer, and every pressable element is
// classified: navigates elsewhere, reloads this same page (a filter, a tab, a sort, a pager), posts a form and reloads, autosubmits and
// reloads, opens a popup, acts in place, opens a new tab, or has nothing listening (a dead press). Output: one JSON per rung and a summary.
import { test } from '@playwright/test';
import fs from 'node:fs';
test.skip(!process.env.PA, 'audit tool');
test.setTimeout(600000);
const OUT = (process.env.OUT || 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/press') + '/';
fs.mkdirSync(OUT, { recursive: true });
const CASE = 'c0000000-0000-0000-0000-000000000001';
const ALL = ['dashboard.php', 'home.php', 'cases.php', `case.php?id=${CASE}`, 'summary.php', 'spatial.php', 'workspace.php', 'notifications.php', 'inbox.php',
  'residents.php', 'residents.php?id=u1', 'personnel.php', 'personnel.php?tab=staff', 'settings.php', 'profile.php', 'activity.php', 'retirement-requests.php',
  'administrative-services.php', 'control-room.php'];
const RUNGS = [['super', '', ALL], ['committee', 'peace_order', ALL], ['moderator', 'peace_order', ALL]];

const WATCH = () => {
  const seen = new WeakMap(); window.__paSrc = [];
  const orig = EventTarget.prototype.addEventListener;
  EventTarget.prototype.addEventListener = function (type, fn, opts) {
    try {
      let m = seen.get(this); if (!m) { m = new Set(); seen.set(this, m); } m.add(type);
      if ((this === document || this === window || this === document.body || this === document.documentElement) && fn) window.__paSrc.push([type, String(fn.handleEvent || fn)]);
    } catch (e) {}
    return orig.call(this, type, fn, opts);
  };
  window.__paHas = function (el, types) { const m = seen.get(el); return !!m && types.some(t => m.has(t)); };
};

const CLASSIFY = () => {
  const PRESS = ['click', 'pointerdown', 'pointerup', 'mousedown', 'mouseup', 'keydown', 'touchstart'];
  // selectors the page-wide (delegated) press handlers answer to, read from their source
  const del = new Set();
  (window.__paSrc || []).forEach(([type, src]) => {
    if (!PRESS.concat(['change', 'input', 'submit']).includes(type)) return;
    const re = /(?:closest|matches|querySelector(?:All)?)\(\s*(['"])((?:(?!\1).)+)\1\s*\)/g; let m;
    while ((m = re.exec(src))) del.add(type + '|' + m[2]);
    const re2 = /classList\.contains\(\s*['"]([\w-]+)['"]\s*\)/g; while ((m = re2.exec(src))) del.add(type + '|.' + m[1]);
  });
  const delegated = (el, types) => { for (const d of del) { const [t, sel] = d.split(/\|(.+)/); if (!types.includes(t)) continue; try { if (el.matches(sel) || el.closest(sel)) return sel; } catch (e) {} } return null; };
  const own = (el, types) => { for (let n = el; n && n !== document.body && n !== document.documentElement; n = n.parentElement) if (window.__paHas(n, types)) return n === el ? 'self' : 'ancestor'; return null; };
  const here = location.pathname.split('/').pop();
  const vis = el => { const r = el.getBoundingClientRect(), s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'; };
  const txt = el => (el.getAttribute('aria-label') || el.innerText || el.value || el.title || el.getAttribute('placeholder') || el.name || el.id || '').replace(/\s+/g, ' ').trim().slice(0, 70);
  const where = el => { const sec = el.closest('[id], section, nav, form, aside'); return sec ? (sec.id ? '#' + sec.id : sec.tagName.toLowerCase() + (sec.className && typeof sec.className === 'string' ? '.' + sec.className.split(' ')[0] : '')) : ''; };
  const out = [];
  const els = document.querySelectorAll('a[href], button, input:not([type=hidden]), select, textarea, summary, [role=tab], [role=button], tr[data-href], .p-click, [data-href], label[for]');
  els.forEach(el => {
    if (el.closest('.p-side, .p-nav, nav.p-sidebar, .dv-float, .dv-sw')) return;   // the sidebar and the DEV pill: once, not per page
    const tag = el.tagName.toLowerCase(), type = (el.getAttribute('type') || '').toLowerCase();
    let kind = '', does = '', how = '';
    const d1 = delegated(el, PRESS), o1 = own(el, PRESS);
    if (tag === 'label') {
      const t = document.getElementById(el.htmlFor); if (!t || t.type !== 'file') return; kind = 'file picker'; does = 'opens the file picker'; how = 'native';
    } else if (tag === 'a') {
      kind = 'link'; const raw = el.getAttribute('href');
      if (el.matches('[data-open],[data-p-open]')) { does = 'opens a popup'; how = 'data-open'; }
      else if (raw === '#' || raw.startsWith('javascript:')) { does = o1 || d1 ? 'acts in place' : 'DEAD: a # link with nothing listening'; how = o1 || d1 || ''; }
      else if (raw.startsWith('#')) { does = o1 || d1 ? 'acts in place (in-page link)' : 'jumps within the page'; how = o1 || d1 || 'hash'; }
      else if (el.target === '_blank') { does = 'opens a new tab'; }
      else {
        let u; try { u = new URL(el.href); } catch (e) { return; }
        const page = u.pathname.split('/').pop();
        if (u.origin !== location.origin) does = 'leaves the portal';
        else if (page === here && (u.search !== location.search || u.hash)) does = 'RELOADS this page (' + (u.search || u.hash).slice(0, 40) + ')';
        else if (page === here) does = 'RELOADS this page (same address)';
        else does = 'goes to ' + page;
        how = o1 || d1 ? 'with a script on it (' + (o1 || d1) + ')' : 'plain link';
      }
    } else if (tag === 'select' || (tag === 'input' && ['checkbox', 'radio', 'text', 'search', 'month', 'date', 'number', 'email', 'tel', 'password', 'color', 'range', 'file', ''].includes(type)) || tag === 'textarea') {
      kind = tag === 'select' ? 'dropdown' : tag === 'textarea' ? 'text box' : (type || 'text') + ' box';
      const f = el.form;
      if (el.hasAttribute('data-autosubmit')) does = 'RELOADS on change (autosubmit, ' + ((f && f.method) || 'get').toUpperCase() + ')';
      else if (own(el, ['change', 'input']) || delegated(el, ['change', 'input'])) does = 'acts in place on change';
      else if (f) does = 'part of a form (sent by its button)';
      else does = 'DEAD: no form and nothing listening';
      how = own(el, ['change', 'input']) || delegated(el, ['change', 'input']) || '';
    } else if (tag === 'button' || (tag === 'input' && ['submit', 'button', 'image', 'reset'].includes(type))) {
      kind = 'button'; const f = el.form, isSubmit = f && (type === 'submit' || (tag === 'button' && (!type || type === 'submit')));
      if (el.matches('[data-open],[data-p-open]')) { does = 'opens a popup'; how = 'data-open'; }
      else if (isSubmit) {
        const intercepted = window.__paHas(f, ['submit']) || delegated(f, ['submit']);
        const m = (f.getAttribute('method') || 'get').toUpperCase();
        does = m === 'POST' ? 'POSTS and RELOADS' : 'RELOADS (' + m + ' form)'; how = intercepted ? 'a script sees the submit first (' + (window.__paHas(f, ['submit']) ? 'form' : intercepted) + ')' : 'plain form';
      } else if (o1 || d1) { does = 'acts in place'; how = o1 ? 'listener on ' + o1 : 'delegated: ' + d1; }
      else does = 'DEAD: a button with nothing listening';
    } else if (tag === 'summary') { kind = 'fold'; does = 'opens or closes in place'; how = 'native details'; }
    else { kind = el.getAttribute('role') || 'clickable row'; if (el.dataset.href) { const p = el.dataset.href.split('?')[0]; does = (p === here ? 'RELOADS this page' : 'goes to ' + p) + ' (row click)'; how = o1 || d1 || 'NO LISTENER'; if (!o1 && !d1) does = 'DEAD: a row with data-href and nothing listening'; } else { does = o1 || d1 ? 'acts in place' : 'DEAD: a clickable with nothing listening'; how = o1 || d1 || ''; } }
    if (el.disabled) does += ' [disabled]';
    out.push({ kind, text: txt(el), where: where(el), does, how, visible: vis(el) });
  });
  return out;
};

for (const [tier, com, pages] of RUNGS) test('press audit ' + tier, async ({ page, context }) => {
  await context.addCookies([{ name: 'ss_tier', value: tier, url: 'http://127.0.0.1:8013' }, ...(com ? [{ name: 'ss_committee', value: com, url: 'http://127.0.0.1:8013' }] : [])]);
  await page.addInitScript(WATCH);
  await page.setViewportSize({ width: 2048, height: 1100 });
  const all = {};
  for (const p of pages) {
    const res = await page.goto(p, { waitUntil: 'domcontentloaded' }).catch(() => null);
    if (!res || res.status() !== 200 || !page.url().includes(p.split('?')[0])) { all[p] = { skipped: res ? 'status ' + res.status() + ' → ' + page.url().split('/').pop() : 'no response' }; continue; }
    await page.waitForLoadState('networkidle', { timeout: 6000 }).catch(() => {});
    await page.waitForTimeout(700);
    all[p] = await page.evaluate(CLASSIFY);
  }
  fs.writeFileSync(OUT + tier + '.json', JSON.stringify(all, null, 1));
  const lines = [];
  for (const [p, rows] of Object.entries(all)) {
    if (!Array.isArray(rows)) { lines.push(p + ': ' + rows.skipped); continue; }
    const c = {}; rows.forEach(r => { const k = r.does.replace(/\(.*$/, '').replace(/ \[disabled\]/, '').trim(); c[k] = (c[k] || 0) + 1; });
    lines.push(p + ': ' + Object.entries(c).sort((a, b) => b[1] - a[1]).map(([k, n]) => n + '× ' + k).join(' · '));
  }
  fs.writeFileSync(OUT + tier + '-summary.txt', lines.join('\n'));
  console.log('PA ' + tier + '\n' + lines.join('\n'));
});
