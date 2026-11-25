/* Live updates (25 Nov 2026, Ace; looks approved by Rose): every page that opts in updates itself, never over what someone is doing.
 *
 * The page names its live parts with data-live="name" (stable wrappers; docs/LIVE_UPDATES.md) and the server writes the tables that
 * concern it into #ss-live-cfg (includes/live.php). This layer:
 *   - listens on Supabase Realtime for those tables on the page's one shared connection (window.ssSupabase), or, while Realtime is
 *     down, checks every cfg.poll seconds; while it is up, every cfg.safety seconds for the parts no table pushes. Never while the
 *     tab is hidden; the channel is removed when the page goes away;
 *   - on a change, waits a moment (bursts become one), then fetches this same address (GET, same origin, X-Live: 1) and morphs only
 *     the named parts whose HTML changed: elements are kept (their listeners, focus, scroll, open <details>), only what differs moves;
 *   - never over what someone is doing: a part with a field being typed in or changed, an open dialog or menu, a <details> they opened,
 *     a text selection, or a press on its way waits until they are done; if it waits more than 10 s a small chip offers the update;
 *   - tints what changed for a moment (motion rule: 200 ms each way, none with reduced motion), and says Live, Polling or Offline;
 *   - when the page is no longer shown to this person (a redirect, 401/403/404, or the parts are gone), a calm notice, not an error.
 * Off for everyone with the server's switch (the page then has no #ss-live-cfg); off in one browser with localStorage ss-live=off or
 * window.SS_LIVE_OFF. Off, window.ssLiveLayer.active is false and each page keeps its old behaviour. No inline handlers (strict CSP). */
(function () {
  'use strict';
  var cfgEl = document.getElementById('ss-live-cfg'); if (!cfgEl) { return; }
  var C; try { C = JSON.parse(cfgEl.textContent); } catch (e) { return; }
  var off = !!window.SS_LIVE_OFF; try { off = off || localStorage.getItem('ss-live') === 'off'; } catch (e) { /* storage blocked: on */ }
  var X = C.txt || {};
  var api = window.ssLiveLayer = { active: !off, mode: off ? 'disabled' : 'starting', kick: function () {}, applyNow: function () {}, stats: { fetches: 0, applied: 0, deferred: 0 } };
  if (off) { document.documentElement.setAttribute('data-live-mode', 'disabled'); return; }

  var GAP = (C.gap || 3) * 1000, POLL = (C.poll || 25) * 1000, SAFETY = (C.safety || 120) * 1000, CHIP_AFTER = 10000;
  var last = {}, pending = {}, touched = new WeakSet(), userOpened = new WeakSet();
  var mode = 'starting', stopped = false, timer = null, inflight = false, again = false, lastFetch = Date.now(), hiddenDirty = false;
  var gen = 0, fails = 0, sb = null, ch = null, wasDown = false;
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)');

  function regionEl(n) { return document.querySelector('[data-live="' + (window.CSS && CSS.escape ? CSS.escape(n) : n) + '"]'); }
  function regionNames() { var out = []; [].forEach.call(document.querySelectorAll('[data-live]'), function (el) { var n = el.getAttribute('data-live'); if (n && out.indexOf(n) < 0) { out.push(n); } }); return out; }

  // ---- the badge: Live, Polling or Offline
  function setMode(m) {
    mode = m; api.mode = m;
    document.documentElement.setAttribute('data-live-mode', m);
    var b = document.getElementById('live-badge'), t = document.getElementById('live-badge-text');
    if (!b || !t || m === 'starting') { return; }
    b.classList.toggle('p-down', m === 'off'); b.classList.toggle('p-poll', m === 'poll');
    t.textContent = m === 'live' ? X.live : m === 'poll' ? X.poll : X.off;
    b.title = m === 'live' ? X.liveTip : m === 'poll' ? X.pollTip : X.offTip;
  }

  // ---- what someone is doing: a part that holds any of it waits
  document.addEventListener('input', function (e) { if (e.target && e.target.nodeType === 1) { touched.add(e.target); } }, true);
  document.addEventListener('change', function (e) { if (e.target && e.target.nodeType === 1) { touched.add(e.target); } }, true);
  document.addEventListener('click', function (e) { var s = e.target.closest && e.target.closest('summary'); if (s && s.parentNode && s.parentNode.tagName === 'DETAILS') { userOpened.add(s.parentNode); } }, true);
  // a field being typed in or chosen from (a tick box, a radio or a button with the focus is not: its state is checked as "changed" below)
  function isField(el) {
    if (!el) { return false; }
    if (el.isContentEditable || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT') { return true; }
    return el.tagName === 'INPUT' && /^(text|search|email|tel|url|number|password|date|month|week|time|datetime-local|)$/i.test(el.getAttribute('type') || '');
  }
  function selDirty(s) {
    var o = s.options, def = -1, i;
    if (s.multiple) { for (i = 0; i < o.length; i++) { if (o[i].selected !== o[i].defaultSelected) { return true; } } return false; }
    for (i = 0; i < o.length; i++) { if (o[i].defaultSelected) { def = i; } }
    if (def < 0) { for (i = 0; i < o.length; i++) { if (!o[i].disabled) { def = i; break; } } }
    return o.length > 0 && s.selectedIndex !== Math.max(0, def);
  }
  function dirty(x) {
    if (!touched.has(x) || x.disabled) { return false; }
    if (x.tagName === 'SELECT') { return selDirty(x); }
    if (x.tagName === 'TEXTAREA') { return x.value !== x.defaultValue; }
    if (x.isContentEditable) { return true; }
    var t = (x.type || '').toLowerCase();
    if (/^(hidden|submit|button|reset|image)$/.test(t)) { return false; }
    if (t === 'checkbox' || t === 'radio') { return x.checked !== x.defaultChecked; }
    if (t === 'file') { return !!x.value; }
    return x.value !== x.defaultValue;
  }
  function busy(el) {
    var de = document.documentElement;
    if (de.classList.contains('sdp-live') || document.querySelector('.p-scrim.p-on, .cr-scrim')) { return 'menu'; }   // a portal dropdown, calendar or modal is open
    if (document.querySelector('.htmx-request') || el.querySelector('form[data-press-sending]')) { return 'press'; }
    var a = document.activeElement;
    if (a && a !== document.body && el.contains(a) && isField(a)) { return 'focus'; }
    var fs = el.querySelectorAll('input, textarea, select, [contenteditable="true"]');
    for (var i = 0; i < fs.length; i++) { if (dirty(fs[i])) { return 'dirty'; } }
    if (el.querySelector('dialog[open]') || (el.closest && el.closest('dialog[open], [role="dialog"][aria-hidden="false"]'))) { return 'dialog'; }
    if (el.querySelector('[aria-haspopup][aria-expanded="true"], .ss-chatmenu:not([hidden])')) { return 'menu'; }
    try { if (el.querySelector(':popover-open')) { return 'menu'; } } catch (e) { /* no popovers in this browser */ }
    var ds = el.querySelectorAll('details[open]');
    for (i = 0; i < ds.length; i++) { if (userOpened.has(ds[i])) { return 'details'; } }
    var s = window.getSelection && window.getSelection();
    if (s && !s.isCollapsed && s.rangeCount && el.contains(s.anchorNode)) { return 'selection'; }
    try { if (typeof window.ssLiveBusy === 'function' && window.ssLiveBusy(el)) { return 'page'; } } catch (e) { /* the page's own rule failed: not held */ }
    return '';
  }

  // ---- the morph: the live element keeps its identity; only attributes, text and children that differ change
  var KEEP = { open: 1, 'aria-expanded': 1, 'aria-selected': 1, tabindex: 1, nonce: 1 };
  function key(n) { return n.nodeType !== 1 ? null : (n.id ? '#' + n.id : (n.getAttribute('data-live-key') ? 'k:' + n.getAttribute('data-live-key') : null)); }
  function same(x, y) {
    if (x.nodeType !== y.nodeType) { return false; }
    if (x.nodeType !== 1) { return true; }
    if (x.tagName !== y.tagName || key(x) !== key(y)) { return false; }
    if (x.tagName === 'INPUT' && ((x.getAttribute('type') || '') !== (y.getAttribute('type') || '') || (x.getAttribute('name') || '') !== (y.getAttribute('name') || ''))) { return false; }
    return true;
  }
  function attrs(a, b, out) {
    var keep = (a.getAttribute('data-live-keep') || '').split(/\s+/), selDirtyParent = a.tagName === 'OPTION' && a.parentNode && a.parentNode.tagName === 'SELECT' && dirty(a.parentNode);
    // (a portal dropdown's own marks, data-sdp and sdp-native, are not kept: its button goes with the morph and the press flow's set-up
    // draws it again over the same <select>, which keeps its value)
    var skip = function (n) { return KEEP[n] || keep.indexOf(n) > -1 || n === 'data-tile-hidden' || (n === 'selected' && selDirtyParent); };
    var ch = false, i, n;
    for (i = a.attributes.length - 1; i >= 0; i--) { n = a.attributes[i].name; if (!b.hasAttribute(n) && !skip(n)) { a.removeAttribute(n); ch = true; } }
    for (i = 0; i < b.attributes.length; i++) { n = b.attributes[i].name; if (!skip(n) && a.getAttribute(n) !== b.attributes[i].value) { a.setAttribute(n, b.attributes[i].value); ch = true; } }
    if (ch) { out.attr.push(a); }
  }
  // the text an element showed before this pass changed it: what is tinted is only what reads differently once the page's own scripts
  // have redrawn their parts (a countdown, the request in focus), so a part a script fills in is not mistaken for news
  function note(out, el) { if (!out.before.has(el)) { out.before.set(el, el.textContent); out.text.push(el); } }
  function morph(a, b, out) {
    if (a.hasAttribute('data-live-skip') || a.tagName === 'SCRIPT' || a.tagName === 'STYLE') { return; }
    attrs(a, b, out);
    if (a.tagName === 'TEXTAREA') { if (a.defaultValue !== b.defaultValue) { a.defaultValue = b.defaultValue; } return; }   // the text typed stays; only its default follows
    kids(a, b, out);
  }
  function kids(a, b, out) {
    var fresh = [].slice.call(b.childNodes), keyed = {}, cur = a.firstChild, i, f, k, m;
    for (m = a.firstChild; m; m = m.nextSibling) { k = key(m); if (k) { keyed[k] = m; } }
    for (i = 0; i < fresh.length; i++) {
      f = fresh[i]; k = key(f); m = null;
      if (f.nodeType === 1 && f.tagName === 'SCRIPT') { continue; }   // a script from a refetch never runs (and its nonce is not this page's)
      if (f.nodeType === 8) { continue; }                                  // comments are left out
      while (cur && (cur.nodeType === 8 || owned(cur))) { cur = cur.nextSibling; }   // comments and nodes a script owns are stepped over
      if (k) { m = keyed[k] && same(keyed[k], f) ? keyed[k] : null; }
      else if (cur && !key(cur) && same(cur, f)) { m = cur; }
      else if (cur && !key(cur) && cur.nextSibling && !key(cur.nextSibling) && same(cur.nextSibling, f) && !(fresh[i + 1] && same(cur, fresh[i + 1])) && !owned(cur)) {
        note(out, a); var dead = cur; cur = cur.nextSibling; a.removeChild(dead); m = cur;   // one old node is gone: step over it
      }
      if (m) {
        if (m !== cur) { a.insertBefore(m, cur); }
        if (f.nodeType === 1) { morph(m, f, out); }
        else if (m.nodeValue !== f.nodeValue) { if (f.nodeValue.trim() || m.nodeValue.trim()) { note(out, a); } m.nodeValue = f.nodeValue; }
        cur = m.nextSibling;
      } else {
        var n = document.importNode(f, true);
        a.insertBefore(n, cur);
        if (n.nodeType === 1) { out.added.push(n); } else if ((n.nodeValue || '').trim()) { note(out, a); }
      }
    }
    while (cur) {
      var nx = cur.nextSibling;
      if (owned(cur) || cur.nodeType === 8) { cur = nx; continue; }   // kept: a script, a comment, or a node a widget owns
      if (cur.nodeType === 1 || (cur.nodeValue || '').trim()) { note(out, a); }
      a.removeChild(cur); cur = nx;
    }
  }
  function owned(n) { return n.nodeType === 1 && (n.tagName === 'SCRIPT' || n.hasAttribute('data-live-own')); }
  function apply(cur, fresh) {
    var out = { attr: [], text: [], added: [], before: new Map() }, act = document.activeElement, actId = act && act.id, scrolls = [];
    [cur].concat([].slice.call(cur.querySelectorAll('*'))).forEach(function (el) { if (el.scrollTop || el.scrollLeft) { scrolls.push([el, el.scrollTop, el.scrollLeft]); } });
    try {
      if (cur.tagName !== fresh.tagName) { var n = document.importNode(fresh, true); cur.parentNode.replaceChild(n, cur); out.added.push(n); cur = n; }
      else { morph(cur, fresh, out); }
    } catch (e) {
      if (window.console) { console.warn('live: morph failed, replacing', e); }
      var r = document.importNode(fresh, true); cur.parentNode.replaceChild(r, cur); cur = r; out.added.push(r);
    }
    scrolls.forEach(function (s) { if (s[0].isConnected) { s[0].scrollTop = s[1]; s[0].scrollLeft = s[2]; } });
    if (act && act !== document.body && !act.isConnected) {   // the focused control is gone: the same one by id, or the part itself
      var same2 = actId && document.getElementById(actId);
      if (same2 && same2.focus) { same2.focus({ preventScroll: true }); }
      else if (cur.isConnected) { if (!cur.hasAttribute('tabindex')) { cur.setAttribute('tabindex', '-1'); } cur.focus({ preventScroll: true }); }
    }
    return { el: cur, out: out };
  }

  // ---- what changed: a short tint (200 ms in, 200 ms out; a still highlight with reduced motion)
  function tint(out, root) {
    var list = out.text.filter(function (el) { return el.isConnected && el.textContent !== out.before.get(el); })
      .concat(out.added.filter(function (el) { return el.isConnected && (el.textContent || '').trim(); }));
    var seen = [], el, i;
    for (i = 0; i < list.length && seen.length < 12; i++) {
      el = list[i]; if (!el || el.nodeType !== 1 || (el.closest && el.closest('[data-live-skip], [data-live-quiet]'))) { continue; }
      el = (el.closest && el.closest('[data-live-key], li, tr, .p-badge, .p-pill, .p-card')) || el;
      if (!root.contains(el) && el !== root) { el = list[i]; }
      if (seen.indexOf(el) < 0) { seen.push(el); }
    }
    seen.forEach(function (x) {
      x.classList.remove('ss-live-tint', 'ss-live-still'); void x.offsetWidth;
      x.classList.add(reduce && reduce.matches ? 'ss-live-still' : 'ss-live-tint');
      setTimeout(function () { x.classList.remove('ss-live-tint', 'ss-live-still'); }, 1000);
    });
  }

  // ---- applying what came: every part that is free now; the rest waits (and a chip offers it after 10 s)
  var chipEl = null;
  function chip(show) {
    if (!show) { if (chipEl) { chipEl.hidden = true; } return; }
    if (!chipEl) {
      chipEl = document.createElement('div'); chipEl.className = 'ss-live-chip'; chipEl.setAttribute('role', 'status'); chipEl.hidden = true;
      var s = document.createElement('span'); s.textContent = X.chip; chipEl.appendChild(s);
      var b = document.createElement('button'); b.type = 'button'; b.className = 'p-btn p-btn-primary p-btn-sm'; b.textContent = X.apply;
      b.addEventListener('click', function () { flush(true); if (window.ssPress && window.ssPress.announce) { window.ssPress.announce(X.applied); } });
      chipEl.appendChild(b); document.body.appendChild(chipEl);
    }
    chipEl.hidden = false;
  }
  function flush(force) {
    var done = [], changed = [], oldest = 0;
    Object.keys(pending).forEach(function (n) {
      var cur = regionEl(n); if (!cur) { delete pending[n]; return; }
      if (!force && busy(cur)) { oldest = oldest ? Math.min(oldest, pending[n].since) : pending[n].since; return; }
      var p = pending[n]; delete pending[n];
      var r = apply(cur, p.f); last[n] = p.h; done.push(r.el); changed.push([r.out, r.el]);
    });
    if (done.length) {
      api.stats.applied += done.length;
      done.forEach(function (el) {
        try { if (window.htmx && htmx.process) { htmx.process(el); } } catch (e) { /* htmx re-reads it on the next press */ }
        try { if (window.ssPress && window.ssPress.init) { window.ssPress.init(el); } } catch (e) { /* the widgets stay as they are */ }
      });
      try { document.dispatchEvent(new CustomEvent('ss:live', { detail: { regions: done.map(function (el) { return el.getAttribute('data-live'); }), els: done } })); } catch (e) { /* old browser */ }
      changed.forEach(function (c) { tint(c[0], c[1]); });
    }
    api.stats.deferred = Object.keys(pending).length;
    chip(oldest > 0 && Date.now() - oldest > CHIP_AFTER);
  }
  api.applyNow = function () { flush(true); };
  // for a person looking into it (docs/LIVE_UPDATES.md): what holds each waiting part
  api.waiting = function () { var o = {}; Object.keys(pending).forEach(function (n) { var el = regionEl(n); o[n] = el ? (busy(el) || 'free') : 'gone'; }); return o; };
  var retryT = null;
  function retry() { clearTimeout(retryT); retryT = setTimeout(function () { if (Object.keys(pending).length) { flush(false); } }, 80); }
  ['focusout', 'change', 'click', 'keyup', 'close', 'toggle', 'htmx:afterSettle', 'selectionchange'].forEach(function (n) { document.addEventListener(n, retry, true); });

  // ---- the refetch
  function gone() {
    stopped = true; teardown();
    var b = document.getElementById('live-badge'); if (b) { b.hidden = true; }
    if (document.querySelector('.ss-live-gone')) { return; }
    var box = document.createElement('div'); box.className = 'p-flash p-flash--info ss-live-gone'; box.setAttribute('role', 'status');
    var s = document.createElement('span'); s.textContent = X.gone + ' '; box.appendChild(s);
    var a = document.createElement('a'); a.href = location.href; a.textContent = X.goneBack; box.appendChild(a);
    var main = document.querySelector('.p-main') || document.body; main.insertBefore(box, main.firstChild);
  }
  function handle(r, url, g) {
    if (r.type === 'opaqueredirect' || r.status === 401 || r.status === 403 || r.status === 404 || r.status === 410) { gone(); return null; }
    if (!r.ok) { throw new Error('HTTP ' + r.status); }
    return r.text().then(function (html) {
      if (g !== gen || url !== location.href) { again = true; return; }   // a press, or a new view, came in between: ask again
      var doc = new DOMParser().parseFromString(html, 'text/html'), names = regionNames(), found = 0;
      names.forEach(function (n) { if (n !== 'side-nav' && doc.querySelector('[data-live="' + (window.CSS && CSS.escape ? CSS.escape(n) : n) + '"]')) { found++; } });
      if (!found && names.some(function (n) { return n !== 'side-nav'; })) { gone(); return; }
      if (!doc.getElementById('ss-live-cfg')) { stopped = true; teardown(); return; }   // switched off on the server: the page stays as it is
      fails = 0;
      names.forEach(function (n) {
        var f = doc.querySelector('[data-live="' + (window.CSS && CSS.escape ? CSS.escape(n) : n) + '"]'); if (!f) { return; }
        var h = f.outerHTML;
        if (last[n] === h) { delete pending[n]; return; }
        pending[n] = { f: f, h: h, since: pending[n] ? pending[n].since : Date.now() };
      });
      flush(false);
    });
  }
  function refetch() {
    if (stopped) { return; }
    if (document.hidden) { hiddenDirty = true; return; }
    if (inflight) { again = true; return; }
    inflight = true; lastFetch = Date.now(); api.stats.fetches++;
    var url = location.href, g = gen;
    fetch(url, { credentials: 'same-origin', cache: 'no-store', redirect: 'manual', headers: { 'X-Live': '1', Accept: 'text/html' } })
      .then(function (r) { return handle(r, url, g); })
      .catch(function () { fails++; if (!navigator.onLine) { setMode('off'); } })
      .then(function () { inflight = false; if (again && !stopped) { again = false; kick('again'); } });
  }
  function kick() {
    if (stopped) { return; }
    if (document.hidden) { hiddenDirty = true; return; }
    if (timer) { return; }
    var wait = Math.max(500, lastFetch + GAP - Date.now());
    timer = setTimeout(function () { timer = null; refetch(); }, wait);
  }
  api.kick = kick;

  // a press in place (htmx) is newer than anything already on its way: that answer is dropped, and the rest of the page is asked for after it
  document.addEventListener('htmx:beforeRequest', function (e) { var c = e.detail && e.detail.requestConfig; if (!(c && c.headers && c.headers['X-Press-Quiet'])) { gen++; pending = {}; } });
  document.addEventListener('htmx:afterSettle', function (e) { var c = e.detail && e.detail.requestConfig; if (!(c && c.headers && c.headers['X-Press-Quiet'])) { kick(); } });

  // ---- the schedule: polling while Realtime is down, a slow safety check while it is up; nothing while hidden
  setInterval(function () {
    if (stopped || document.hidden) { return; }
    var since = Date.now() - lastFetch;
    if ((mode === 'poll' || mode === 'off') ? since >= POLL : since >= SAFETY) { kick(); }
    if (Object.keys(pending).length) { flush(false); }
  }, 2000);
  document.addEventListener('visibilitychange', function () {
    if (document.hidden || stopped) { return; }
    var since = Date.now() - lastFetch;
    if (hiddenDirty || since >= (mode === 'live' ? SAFETY : POLL)) { hiddenDirty = false; kick(); }
  });
  window.addEventListener('online', function () { setMode(ch && !wasDown ? 'live' : 'poll'); kick(); });
  window.addEventListener('offline', function () { setMode('off'); });

  // ---- Realtime: one channel on the page's one connection
  function teardown() { if (sb && ch) { try { sb.removeChannel(ch); } catch (e) { /* already gone */ } } ch = null; }
  function connect() {
    if (stopped) { return; }
    if (!C.tables || !C.tables.length || !window.supabase || !window.ssSupabase) { setMode('poll'); return; }
    sb = window.ssSupabase(C.url, C.key, C.token); if (!sb) { setMode('poll'); return; }
    ch = sb.channel('live-' + C.page);
    C.tables.forEach(function (t) {
      var o = { event: '*', schema: 'public', table: t.t }; if (t.f) { o.filter = t.f; }
      ch.on('postgres_changes', o, function (p) {
        try { document.dispatchEvent(new CustomEvent('ss:live-event', { detail: { table: t.t, type: p && p.eventType } })); } catch (e) { /* old browser */ }
        kick();
      });
    });
    var upT = setTimeout(function () { if (mode === 'starting') { wasDown = true; setMode(navigator.onLine ? 'poll' : 'off'); } }, 10000);
    ch.subscribe(function (s) {
      if (s === 'SUBSCRIBED') { clearTimeout(upT); setMode('live'); if (wasDown) { wasDown = false; kick(); } }
      else if (s === 'CHANNEL_ERROR' || s === 'TIMED_OUT' || s === 'CLOSED') { clearTimeout(upT); if (!stopped) { wasDown = true; setMode(navigator.onLine ? 'poll' : 'off'); } }
    });
  }
  window.addEventListener('pagehide', teardown);
  window.addEventListener('pageshow', function (e) { if (e.persisted && !stopped) { connect(); kick(); } });

  function start() {
    regionNames().forEach(function (n) { last[n] = null; });
    if (document.prerendering) { document.addEventListener('prerenderingchange', start, { once: true }); return; }
    connect();
  }
  // a deferred script runs before DOMContentLoaded but may come before supabase.js (deferred too, later in the page): wait for it
  var started = false;
  function go() { if (!started) { started = true; start(); } }
  if (document.readyState === 'complete') { go(); } else { document.addEventListener('DOMContentLoaded', go); window.addEventListener('load', go); }
})();
