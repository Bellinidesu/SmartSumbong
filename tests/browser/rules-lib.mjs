// The rules pass, as code: Ace's standing rule ("aesthetic, symmetrically aesthetic, aligned properly") turned into measurements.
// auditScope(page, rootSelector) runs in the page and returns findings: { rule, where, detail }. Used by rules-audit.spec.mjs (RA=1).
//
//  overflow      the page scrolls sideways
//  cut           text is cut off (ellipsis, clip or line clamp) and nothing says the whole of it (no title)
//  oneword       a line of text with three or more words has every word on its own line
//  padding       a button, pill or chip whose content is not centred (unequal space left and right)
//  cardheight    cards that start on one line (one row of a grid) are not one height
//  straggler     a wrapped row whose last line holds one lone item after rows of three or more
//  rowheight     the rows of a table are not one height (more than 8 px apart)
//  headerline    a column header does not start where its cells start (more than 3 px apart)
//  unlabelled    a checkbox or an icon button with no label, or a row whose label is empty
//  plural        "1 numbers", "1 tanods": a one that is followed by a plural
export async function auditScope(page, root) {
  return page.evaluate((rootSel) => {
    const out = [];
    const add = (rule, el, detail) => out.push({ rule, where: sel(el), detail: String(detail).slice(0, 160) });
    function sel(e) {
      if (!e || !e.tagName) return '?';
      let s = e.tagName.toLowerCase();
      if (typeof e.id === 'string' && e.id) return s + '#' + e.id;
      if (typeof e.className === 'string' && e.className.trim()) s += '.' + e.className.trim().split(/\s+/).slice(0, 3).join('.');
      const p = e.parentElement; if (p && p !== document.body && typeof p.className === 'string' && p.className.trim()) s = p.tagName.toLowerCase() + '.' + p.className.trim().split(/\s+/)[0] + ' > ' + s;
      return s;
    }
    const shown = e => { if (e.closest('details:not([open])') && !e.closest('summary')) return false; const r = e.getBoundingClientRect(), cs = getComputedStyle(e); return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none' && cs.opacity !== '0'; };
    const scope = (rootSel ? document.querySelector(rootSel) : document.querySelector('main.p-main')) || document.body;
    const all = sub => [...scope.querySelectorAll(sub)].filter(shown);
    const r1 = n => Math.round(n * 10) / 10;

    if (!rootSel && document.documentElement.scrollWidth > innerWidth + 1) add('overflow', document.documentElement, document.documentElement.scrollWidth + ' > ' + innerWidth);

    // cut
    for (const e of all('button, .p-btn, .p-badge, .cm-pill, .cm-chip, .p-chip, th, td, label, h1, h2, h3, .p-person > span, .ss-case, input:not([type=checkbox]):not([type=radio]):not([type=hidden]):not([type=color]):not([type=file]):not([type=range]), select, textarea')) {
      const cs = getComputedStyle(e);
      if (e.matches('.p-sr, .p-sr *') || (e.matches('textarea') && cs.overflowY !== 'hidden')) continue;
      const w = e.scrollWidth > e.clientWidth + 1 && (cs.overflowX !== 'visible' || e.matches('input, select'));
      const h = cs.webkitLineClamp !== 'none' && e.scrollHeight > e.clientHeight + 1;
      if ((w || h) && !e.title && !e.closest('[title]') && !e.querySelector('[title]')) add('cut', e, (e.value || e.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 60) + ' (' + e.scrollWidth + ' > ' + e.clientWidth + ')');
    }

    // one word per line
    for (const e of all('p, span, div, td, th, label, small, b, a, h1, h2, h3, h4, li')) {
      const tn = [...e.childNodes].filter(n => n.nodeType === 3 && n.textContent.trim());
      if (tn.length !== e.childNodes.length || !tn.length) continue;
      const text = e.textContent.trim().replace(/\s+/g, ' ');
      const words = text.split(' ');
      if (words.length < 3 || words.some(w => w.length > 22)) continue;
      const range = document.createRange(); range.selectNodeContents(e);
      const tops = new Set([...range.getClientRects()].map(r => Math.round(r.top)));
      if (tops.size >= words.length) add('oneword', e, text.slice(0, 60));
    }

    // padding: content centred in its box
    for (const e of all('.p-btn, .p-badge, .cm-pill, .cm-chip, .p-chip, .p-seg button, .st-tabs button, .st-tabs a, .ss-viewsw button, .p-pill-select, .p-badge-n')) {
      if (e.matches('select, input, .p-pill-select') || e.children.length === 0 && !e.textContent.trim()) continue;
      if (e.matches('.cm-chip, .p-chip') && e.querySelector('b')) continue;   // a count slot on the right is part of the design
      const box = e.getBoundingClientRect(), cs = getComputedStyle(e);
      if (cs.display === 'block' || cs.display === 'grid') continue;
      const range = document.createRange(); range.selectNodeContents(e);
      const rects = [...range.getClientRects()].filter(r => r.width > 0);
      if (!rects.length) continue;
      if (e.scrollWidth > e.clientWidth + 1 || new Set([...range.getClientRects()].filter(r => r.width > 0 && r.height < box.height - 2).map(r => Math.round(r.top / 4))).size > 1) continue;   // cut or wrapped content is judged by the cut and one-word rules
      const pb = getComputedStyle(e, '::before'), pa = getComputedStyle(e, '::after');
      const pw = ps => (ps.content !== 'none' && ps.display !== 'none' && ps.position !== 'absolute') ? (parseFloat(ps.width) || 0) + (parseFloat(ps.marginLeft) || 0) + (parseFloat(ps.marginRight) || 0) + (parseFloat(cs.columnGap) || 0) : 0;
      const left = Math.min(...rects.map(r => r.left)) - (box.left + parseFloat(cs.borderLeftWidth)) - pw(pb);
      const right = (box.right - parseFloat(cs.borderRightWidth)) - Math.max(...rects.map(r => r.right)) - pw(pa);
      if (Math.abs(left - right) > 2.5 && left < 60 && right < 60 && left > -2 && right > -2) add('padding', e, 'left ' + r1(left) + ' right ' + r1(right) + ' "' + e.textContent.trim().replace(/\s+/g, ' ').slice(0, 30) + '"');
    }

    // cards of one row, one height
    for (const p of new Set(all('.p-card').map(c => c.parentElement))) {
      const kids = [...p.children].filter(c => c.classList.contains('p-card') && shown(c));
      const rows = []; for (const k of kids) { const t = Math.round(k.getBoundingClientRect().top); const g = rows.find(r => Math.abs(r.t - t) <= 2); g ? g.items.push(k) : rows.push({ t, items: [k] }); }
      for (const g of rows) if (g.items.length > 1) { const hs = g.items.map(i => Math.round(i.getBoundingClientRect().height)); if (Math.max(...hs) - Math.min(...hs) > 2) add('cardheight', p, hs.join(' vs ')); }
    }

    // stragglers on a wrapped row
    for (const e of all('*')) {
      const cs = getComputedStyle(e);
      const wrap = (cs.display.includes('flex') && cs.flexWrap === 'wrap') || (cs.display === 'grid' && cs.gridTemplateColumns.split(' ').length >= 3 && !e.matches('table, tbody, tr'));
      if (!wrap) continue;
      const kids = [...e.children].filter(shown); if (kids.length < 4) continue;
      if (e.matches('.ss-pager, .doc-page *')) continue;
      const rows = []; for (const k of kids) { const b = k.getBoundingClientRect(); const g = rows.find(r => Math.min(r.bottom, b.bottom) - Math.max(r.top, b.top) > 0.4 * Math.min(r.bottom - r.top, b.height)); g ? (g.n++, g.top = Math.min(g.top, b.top), g.bottom = Math.max(g.bottom, b.bottom)) : rows.push({ top: b.top, bottom: b.bottom, n: 1 }); }
      if (rows.length < 2) continue;
      const cnt = rows.map(r => r.n);
      const lone = kids.filter(k => Math.min(rows[rows.length - 1].bottom, k.getBoundingClientRect().bottom) - Math.max(rows[rows.length - 1].top, k.getBoundingClientRect().top) > 0).pop();
      if (lone && lone.getBoundingClientRect().width > 0.8 * e.getBoundingClientRect().width) continue;   // a full-width last row (a search box) is a row, not a straggler
      if (cnt[cnt.length - 1] === 1 && cnt[0] >= 3 && cnt.slice(0, -1).every(c => c === cnt[0])) add('straggler', e, cnt.join('+'));
    }

    // tables
    for (const t of all('table:not(.form-table)')) {
      const rows = [...t.querySelectorAll('tbody > tr')].filter(r => shown(r) && !r.hidden && !r.querySelector('td.p-empty') && !r.classList.contains('ss-erow'));
      if (rows.length >= 4) { const hs = rows.map(r => Math.round(r.getBoundingClientRect().height)); if (Math.max(...hs) - Math.min(...hs) > 8) add('rowheight', t, hs.join(',')); }
      const ths = [...t.querySelectorAll('thead th')].filter(shown), first = rows[0];
      if (first) {
        const tds = [...first.children].filter(shown);
        if (ths.length === tds.length) ths.forEach((th, i) => {
          const al = x => ['left', 'start'].includes(getComputedStyle(x).textAlign);
          if (!th.textContent.trim() || th.matches('.p-right, .ss-c') || tds[i].matches('.p-right, .ss-c') || !al(th) || !al(tds[i])) return;
          const a = document.createRange(); a.selectNodeContents(th); const b = document.createRange(); b.selectNodeContents(tds[i]);
          const l1 = a.getBoundingClientRect().left, l2 = b.getBoundingClientRect().left;
          if (Math.abs(l1 - l2) > 3) add('headerline', th, th.textContent.trim().slice(0, 24) + ' header ' + r1(l1) + ' cell ' + r1(l2));
        });
      }
    }

    // unlabelled controls
    for (const c of all('input[type=checkbox]')) if (!c.labels.length && !c.getAttribute('aria-label') && !c.title) add('unlabelled', c, 'checkbox with no label');
    for (const b of all('button, a.p-btn')) if (!b.textContent.trim() && !b.getAttribute('aria-label') && !b.title && !b.querySelector('img[alt], .p-sr')) add('unlabelled', b, 'button with no name');
    for (const li of all('.ss-vlist li')) if (!li.querySelector('b') || !li.querySelector('b').textContent.trim()) add('unlabelled', li, 'a row with an empty label');

    // "1 numbers"
    const walker = document.createTreeWalker(scope, NodeFilter.SHOW_TEXT);
    for (let n; (n = walker.nextNode());) { const el = n.parentElement; if (!el || !shown(el) || el.closest('script, style, option, textarea')) continue; const m = n.textContent.match(/(^|[\s(])1 (?!am\b|pm\b)[a-z]{3,}s\b/i); if (m) add('plural', el, m[0].trim()); }
    return out;
  }, root || null);
}

export function summarise(rows) {
  const by = {};
  for (const r of rows) { const k = r.rule + ' | ' + r.where; (by[k] ||= { rule: r.rule, where: r.where, detail: r.detail, n: 0, on: new Set() }).n++; by[k].on.add(r.page); }
  return Object.values(by).sort((a, b) => b.on.size - a.on.size || b.n - a.n);
}
