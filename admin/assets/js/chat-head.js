/* The chat head (12 Nov 2026), loaded on every portal page.
   - On a case page it runs the Messages-style panel the server rendered (includes/case_chat.php).
   - The cases whose chat is "floated" (right-click the bubble, or the ... button) share ONE draggable bubble on every other page; on a case page
     the case's own head carries them (the case first), so a page never has more than one head
     (19 Nov 2026, Rose: one bubble per case stacked up into several chat heads at once). Its panel has a row of the floated
     cases to switch between; its ball counts the conversations with something unread across all of them, fed by chat-feed.php
     every 15 seconds, and it plays the sound when wanted. A case page shows only that case's own head.
   - Choices live in this browser (localStorage): ss-chat-prefs (master switches), ss-chat-cases (per case: pin, sound, side, y),
     ss-chat-seen-<case> (what was last looked at). Since 0173 what was read and what is muted are also kept per person in the database
     (chat_state, through chat-feed.php): the browser stays the quick copy, the database is what another browser starts from.
   Strict CSP: no inline handlers; everything is delegated or bound here. */
(function () {
  'use strict';
  if (window.ssChatLoaded) { return; }
  window.ssChatLoaded = true;

  var tr = function (en, fil) { return typeof window.T === 'function' ? window.T(en, fil) : en; };
  var ts = function (s) { var n = Date.parse(s || ''); return isNaN(n) ? 0 : n; };
  var short = function (t) { var m = /([^-]+)$/.exec(t || ''); return m ? m[1] : (t || ''); };
  function el(tag, cls, text) { var n = document.createElement(tag); if (cls) { n.className = cls; } if (text != null) { n.textContent = text; } return n; }

  /* ---------- what this browser remembers ---------- */
  var PK = 'ss-chat-prefs', CK = 'ss-chat-cases';
  function rd(k, d) { try { var v = JSON.parse(localStorage.getItem(k)); return v && typeof v === 'object' ? v : d; } catch (e) { return d; } }
  function wr(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* a private window: choices last until the page closes */ } }
  /* ---------- the same two things, kept per person (read up to, muted) so they follow the person to another browser ---------- */
  var CSRF = (document.currentScript && document.currentScript.getAttribute('data-csrf')) || '', pend = {}, pendT = null;
  function flush() {
    var items = Object.keys(pend).map(function (k) { return pend[k]; }); pend = {};
    if (!items.length || !CSRF) { return; }
    fetch('chat-feed.php', { method: 'POST', credentials: 'same-origin', keepalive: true, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ csrf: CSRF, items: items }) }).catch(function () { /* the browser copy still holds it */ });
  }
  function save(it) { var k = it.c + '|' + (it.all ? '*' : it.k); pend[k] = Object.assign(pend[k] || {}, it); clearTimeout(pendT); pendT = setTimeout(flush, 800); }
  window.addEventListener('pagehide', flush);
  var listeners = [];
  function changed() { listeners.slice().forEach(function (f) { f(); }); }
  var store = {
    prefs: function () { var p = rd(PK, {}); return { floats: p.floats !== false, ball: p.ball !== false, sound: p.sound !== false }; },
    setPref: function (k, v) { var p = rd(PK, {}); p[k] = v; wr(PK, p); changed(); },
    cases: function () { return rd(CK, {}); },
    patch: function (id, o, quiet) { var c = rd(CK, {}); c[id] = Object.assign(c[id] || {}, o); wr(CK, c); if (!quiet && typeof o.sound === 'boolean') { save({ c: id, all: true, m: !o.sound }); } changed(); },
    seen: function (id) { return rd('ss-chat-seen-' + id, {}); },
    setSeen: function (id, conv, t) { var m = rd('ss-chat-seen-' + id, {}); if (m[conv] && ts(m[conv]) >= ts(t)) { return; } m[conv] = t; wr('ss-chat-seen-' + id, m); save({ c: id, k: conv, s: t }); }
  };
  /* what the database knows of a case (st: {conv: {s: read up to, m: muted}}) joins what this browser knows: reading only moves forward,
     the case's mute follows the database unless a change of ours is still on its way, and a mute only this browser has is sent up once */
  function merge(id, st) {
    if (!st || typeof st !== 'object') { return; }
    var key = 'ss-chat-seen-' + id, m = rd(key, {}), ch = false;
    Object.keys(st).forEach(function (k) { if (st[k] && st[k].s && ts(st[k].s) > ts(m[k])) { m[k] = st[k].s; ch = true; } });
    if (ch) { wr(key, m); }
    Object.keys(m).forEach(function (k) { if (!st[k] || !st[k].s || ts(m[k]) > ts(st[k].s)) { save({ c: id, k: k, s: m[k] }); } });   // what only this browser had read goes up once
    var local = store.cases()[id], mine = local && typeof local.sound === 'boolean' ? local.sound : null;
    if (!pend[id + '|*']) {
      if (st.r) { if (mine !== !st.r.m) { store.patch(id, { sound: !st.r.m }, true); ch = true; } }
      else if (mine === false) { save({ c: id, all: true, m: true }); }
    }
    if (ch) { document.dispatchEvent(new Event('ss-chat-seen')); }
  }
  function pull(ids) {
    return fetch('chat-feed.php?ids=' + ids.slice(0, 8).map(encodeURIComponent).join(','), { credentials: 'same-origin', headers: { 'Accept': 'application/json' } })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (j) { if (j && j.ok) { ids.forEach(function (id) { if (j.cases[id]) { merge(id, j.cases[id].st); } }); } })
      .catch(function () { /* offline: the browser copy stands */ });
  }
  window.addEventListener('storage', function (e) { if (e.key === PK || e.key === CK) { changed(); } });
  function soundFor(id) { var c = store.cases()[id]; return c && typeof c.sound === 'boolean' ? c.sound : store.prefs().sound; }

  /* ---------- a short two-note ding, made in the browser (no file); it can only play after the person has touched the page once ---------- */
  var ac = null;
  function unlock() { try { ac = ac || new (window.AudioContext || window.webkitAudioContext)(); if (ac.state === 'suspended') { ac.resume(); } } catch (e) { ac = null; } }
  ['pointerdown', 'keydown'].forEach(function (ev) { document.addEventListener(ev, unlock, { once: true, passive: true }); });
  function ding() {
    if (!ac) { return; }
    try {
      var t = ac.currentTime;
      [[880, 0], [1175, 0.13]].forEach(function (n) {
        var o = ac.createOscillator(), g = ac.createGain(); o.type = 'sine'; o.frequency.value = n[0];
        g.gain.setValueAtTime(0.0001, t + n[1]); g.gain.exponentialRampToValueAtTime(0.08, t + n[1] + 0.02); g.gain.exponentialRampToValueAtTime(0.0001, t + n[1] + 0.24);
        o.connect(g); g.connect(ac.destination); o.start(t + n[1]); o.stop(t + n[1] + 0.26);
      });
    } catch (e) { /* silent is fine */ }
  }

  /* the Inbox's chats pill in the sidebar (the Inbox page tells it live, other pages ask once a minute); the mail pill comes with the page */
  var ibPill = document.querySelector('.p-nav .p-ib-chat');
  function setNavChats(n) {
    if (!ibPill) { return; }
    ibPill.setAttribute('data-n', String(Math.min(n, 99))); ibPill.querySelector('b').textContent = n > 99 ? '99+' : String(n); ibPill.hidden = n <= 0;
    ibPill.setAttribute('title', n + tr(' unread case chats', ' hindi pa nababasang chat sa kaso'));
  }
  function pullNavChats() {
    if (!ibPill || document.hidden || document.getElementById('mg')) { return; }
    fetch('chat-feed.php?unread=1', { credentials: 'same-origin', headers: { 'Accept': 'application/json' } })
      .then(function (r) { return r.ok ? r.json() : null; }).then(function (j) { if (j && j.ok) { setNavChats(j.n); } }).catch(function () { /* the next minute */ });
  }
  document.addEventListener('ss-chat-total', function (e) { setNavChats(e.detail || 0); });
  if (ibPill) { pullNavChats(); setInterval(pullNavChats, 60000); document.addEventListener('visibilitychange', function () { if (!document.hidden) { pullNavChats(); } }); }
  window.ssChatCore = { store: store, ding: ding, soundFor: soundFor, merge: merge, pull: pull };
  document.dispatchEvent(new Event('ss-chat-ready'));   // for the Inbox's Case chats (msgr.js), which shares the seen map, the sound and the mute

  /* ---------- the right-click menu ---------- */
  var menu = null, menuBack = null, sharedTrash = null, holding = false;
  // a bubble held over a link or an image must not start the browser's own drag of it: that would cancel ours
  document.addEventListener('dragstart', function (e) { if (holding) { e.preventDefault(); } }, true);
  function outside(e) { if (menu && !menu.contains(e.target)) { closeMenu(false); } }
  function menuKey(e) {
    if (!menu) { return; }
    var items = [].slice.call(menu.querySelectorAll('.ch-mi')), i = items.indexOf(document.activeElement);
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeMenu(true); }
    else if (e.key === 'ArrowDown') { e.preventDefault(); items[(i + 1) % items.length].focus(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); items[(i - 1 + items.length) % items.length].focus(); }
    else if (e.key === 'Tab') { closeMenu(false); }
  }
  function closeMenu(back) {
    if (!menu) { return; }
    menu.remove(); menu = null;
    document.removeEventListener('pointerdown', outside, true); document.removeEventListener('keydown', menuKey, true);
    window.removeEventListener('resize', closeOnly); window.removeEventListener('blur', closeOnly);
    if (back && menuBack) { menuBack.focus(); }
  }
  function closeOnly() { closeMenu(false); }
  function showMenu(x, y, items, back) {
    closeMenu(false); menuBack = back;
    var m = el('div', 'ch-menu'), list = el('div', 'ch-mlist');   // a labelled region around the menu, so the page keeps every part inside a landmark
    m.setAttribute('role', 'region'); m.setAttribute('aria-label', tr('Chat options', 'Mga opsyon ng chat')); list.setAttribute('role', 'menu'); list.setAttribute('aria-label', tr('Chat options', 'Mga opsyon ng chat')); m.appendChild(list);
    items.forEach(function (it) {
      if (it.sep) { var s = el('div', 'ch-msep'); s.setAttribute('role', 'separator'); list.appendChild(s); return; }
      var b = it.href ? el('a', 'ch-mi') : el('button', 'ch-mi');
      if (it.href) { b.href = it.href; } else { b.type = 'button'; }
      b.setAttribute('role', it.check === undefined ? 'menuitem' : 'menuitemcheckbox');
      if (it.check !== undefined) { b.setAttribute('aria-checked', it.check ? 'true' : 'false'); }
      b.appendChild(el('span', 'ch-tick', it.check ? '✓' : '')); b.appendChild(el('span', 'ch-ml', it.label));
      b.addEventListener('click', function (ev) { closeMenu(false); if (it.act) { ev.preventDefault(); it.act(); } });
      list.appendChild(b);
    });
    document.body.appendChild(m);
    var w = m.offsetWidth, h = m.offsetHeight;
    if (y + h > window.innerHeight - 8) { y = y - h; }
    m.style.left = Math.max(8, Math.min(x, window.innerWidth - w - 8)) + 'px'; m.style.top = Math.max(8, Math.min(y, window.innerHeight - h - 8)) + 'px';
    menu = m;
    document.addEventListener('pointerdown', outside, true); document.addEventListener('keydown', menuKey, true);
    window.addEventListener('resize', closeOnly); window.addEventListener('blur', closeOnly);
    var f = m.querySelector('.ch-mi'); if (f) { f.focus(); }
  }

  /* ---------- one chat head: the button, the panel, the conversations ---------- */
  function mount(root) {
    var report = root.getAttribute('data-report'), url = root.getAttribute('data-url');
    var main = root.getAttribute('data-main') === '1';
    var inline = root.getAttribute('data-inline') === '1';   // the Inbox's reader: no button, the panel is part of the page
    var fab = root.querySelector('.ch-fab') || el('button', 'ch-fab'), panel = root.querySelector('.ch-panel'), body = root.querySelector('.ch-body'), badge = root.querySelector('.ch-badge') || el('span', 'ch-badge');
    var cur = null, drafts = {}, sending = 0, loaded = main || inline;
    var api = { root: root, report: report, home: report, tracking: root.getAttribute('data-tracking') || '', defY: null };
    var feedBadge = !main && !inline;       // a floating head's ball comes from the feed; the case page's from its own conversations
    // 19 Nov 2026 (Rose): the one floating head keeps its own place ('_float'), whichever floated case it shows; a case page's head keeps the case's
    var posKey = feedBadge ? '_float' : report;

    function convs() { return [].slice.call(body.querySelectorAll('.ch-conv')); }
    function lastOf(sel, c) { var n = c.querySelectorAll(sel); return n.length ? n[n.length - 1] : null; }
    function unreadIn(c, seen) {
      var id = c.getAttribute('data-conv'), since = seen[id] ? ts(seen[id]) : 0;
      if (!since) { var o = lastOf('.ch-out', c); since = o ? ts(o.getAttribute('data-ts')) : 0; }
      var n = 0; [].forEach.call(c.querySelectorAll('.ch-b[data-in]'), function (b) { if (ts(b.getAttribute('data-ts')) > since) { n++; } }); return n;
    }
    // the ball counts conversations with something unread (19 Nov 2026, Rose), the way a phone counts chats, not single messages
    // 19 Nov 2026 (Ace): a case page's head that also carries other floated cases takes its ball from the feed, like the floating head
    api.setFeedBadge = function (v) { feedBadge = v; paintUnread(); };
    api.setBadge = function (n) { badge.textContent = n > 9 ? '9+' : String(n); badge.hidden = !(n > 0 && store.prefs().ball); fab.classList.toggle('ch-has', n > 0); };
    function paintUnread() {
      var seen = store.seen(report), total = 0;   // the floating head lights its rows too; only its ball comes from the feed
      convs().forEach(function (c) {
        var n = (cur === c.getAttribute('data-conv') && !panel.hidden) ? 0 : unreadIn(c, seen); total += n > 0 ? 1 : 0;
        var row = body.querySelector('.ch-row[data-conv="' + c.getAttribute('data-conv') + '"]'); if (row) { row.classList.toggle('ch-unread', n > 0); }
      });
      if (!feedBadge) { api.setBadge(total); }
    }
    function markSeen(id) {
      var c = body.querySelector('.ch-conv[data-conv="' + id + '"]'); if (!c) { return; }
      var l = lastOf('.ch-b, .ch-sys', c); store.setSeen(report, id, l ? l.getAttribute('data-ts') : new Date().toISOString());
      if (api.onSeen) { api.onSeen(); }
      document.dispatchEvent(new Event('ss-chat-seen'));
    }
    function toBottom(c) { var m = c && c.querySelector('.ch-msgs'); if (m) { m.scrollTop = m.scrollHeight; } }
    function grow(t) { t.style.height = 'auto'; t.style.height = Math.min(t.scrollHeight, 120) + 'px'; }

    function show(id) {
      cur = id;
      [].forEach.call(body.querySelectorAll('.ch-view'), function (v) { v.hidden = true; });
      var v = id ? body.querySelector('.ch-conv[data-conv="' + id + '"]') : body.querySelector('.ch-listview');
      if (!v) { cur = null; v = body.querySelector('.ch-listview'); }
      if (v) { v.hidden = false; }
      if (cur) {
        markSeen(cur); toBottom(v);
        var t = v.querySelector('textarea');
        if (t) { if (drafts[cur]) { t.value = drafts[cur]; grow(t); v.querySelector('.ch-input').classList.add('has-text'); } if (!inline) { t.focus(); } }
      }
      paintUnread();
    }

    /* where the panel opens: towards the roomier side of the screen, never off it */
    function orient() {
      if (inline) { return; }
      var r = root.getBoundingClientRect(), vw = window.innerWidth, vh = window.innerHeight;
      var left = r.left + r.width / 2 < vw / 2, up = r.top + r.height / 2 > vh / 2;
      root.classList.toggle('ch-l', left); root.classList.toggle('ch-r', !left); root.classList.toggle('ch-up', up); root.classList.toggle('ch-down', !up);
      var space = (up ? r.top : vh - r.bottom) - 14 - 12;
      panel.style.height = vw <= 640 ? '' : Math.max(280, Math.min(640, space)) + 'px';
    }
    api.orient = orient;
    function open(id) {
      closeMenu(false); panel.hidden = false; fab.setAttribute('aria-expanded', 'true'); root.classList.add('ch-open'); orient();
      var peek = root.querySelector('.ch-peek'); if (peek) { peek.hidden = true; }
      var go = function () { var all = convs(); show(id || (all.length === 1 ? all[0].getAttribute('data-conv') : null)); if (!cur && !inline) { var r = body.querySelector('.ch-row'); if (r) { r.focus(); } } };
      if (!loaded) { body.textContent = ''; body.appendChild(el('p', 'ch-empty', tr('Loading…', 'Naglo-load…'))); refresh().then(function () { loaded = true; go(); }); } else { go(); }
    }
    function close() {
      if (cur) { var t = body.querySelector('.ch-conv[data-conv="' + cur + '"] textarea'); if (t) { drafts[cur] = t.value; } markSeen(cur); }
      panel.hidden = true; fab.setAttribute('aria-expanded', 'false'); root.classList.remove('ch-open'); paintUnread();
    }
    api.open = open; api.close = close; api.isOpen = function () { return !panel.hidden; };
    /* the one floating head shows another floated case: its conversations are fetched afresh, its place on screen stays */
    api.setCase = function (id, tracking) {
      if (tracking) { api.tracking = tracking; root.setAttribute('data-tracking', tracking); }
      if (id === report) { return; }
      if (cur && !panel.hidden) { markSeen(cur); }
      report = id; api.report = id; url = 'case.php?id=' + encodeURIComponent(id) + '&chat=1';
      root.setAttribute('data-report', id); root.setAttribute('data-url', url);
      cur = null; drafts = {}; loaded = false; body.textContent = '';
      if (!panel.hidden) {
        body.appendChild(el('p', 'ch-empty', tr('Loading…', 'Naglo-load…')));
        refresh().then(function () { loaded = true; var all = convs(); show(all.length === 1 ? all[0].getAttribute('data-conv') : null); });
      }
    };
    api.current = function () { return panel.hidden ? null : cur; };

    /* the live refresh: the conversations again, keeping the open one, the draft, the scroll and any unsent bubble */
    function refresh() {
      if (sending) { return Promise.resolve(); }
      var was = cur, c0 = was && body.querySelector('.ch-conv[data-conv="' + was + '"] .ch-msgs');
      var stick = !c0 || (c0.scrollHeight - c0.scrollTop - c0.clientHeight < 80), top = c0 ? c0.scrollTop : 0;
      if (was) { var t0 = body.querySelector('.ch-conv[data-conv="' + was + '"] textarea'); if (t0) { drafts[was] = t0.value; } }
      var failed = {}, before = body.querySelectorAll('.ch-b[data-in]').length;
      convs().forEach(function (c) { var f = [].slice.call(c.querySelectorAll('.ch-failed')).map(function (n) { return n.outerHTML; }); if (f.length) { failed[c.getAttribute('data-conv')] = f; } });
      return fetch(url, { credentials: 'same-origin', headers: { 'Accept': 'text/html' } }).then(function (r) { return r.ok ? r.text() : Promise.reject(r.status); }).then(function (h) {
        body.innerHTML = h;
        Object.keys(failed).forEach(function (id) { var m = body.querySelector('.ch-conv[data-conv="' + id + '"] .ch-msgs'); if (m) { failed[id].forEach(function (f) { m.insertAdjacentHTML('beforeend', f); }); } });
        // a new message while the case page is open: a ding, unless you are reading that very chat
        if (main && body.querySelectorAll('.ch-b[data-in]').length > before && soundFor(report) && (panel.hidden || !document.hasFocus() || !cur)) { ding(); }
        if (!panel.hidden) { show(was); var c1 = was && body.querySelector('.ch-conv[data-conv="' + was + '"] .ch-msgs'); if (c1 && !stick) { c1.scrollTop = top; } }
        else { cur = was; paintUnread(); }
        if (api.onRefreshed) { api.onRefreshed(); }
      }).catch(function () { /* the next event or the next poll tries again */ });
    }
    api.refresh = refresh;

    function send(form) {
      var t = form.querySelector('textarea'), text = t.value.trim();
      if (!text) { return; }
      var c = form.closest('.ch-conv'), id = c.getAttribute('data-conv'), list = c.querySelector('.ch-msgs');
      var none = list.querySelector('.ch-none'); if (none) { none.remove(); }
      var prev = list.lastElementChild, b = el('div', 'ch-b ch-out ch-last ch-first ch-sending'), p = el('p', '', text); b.appendChild(p);
      if (prev && prev.classList.contains('ch-out')) { prev.classList.remove('ch-last'); b.classList.remove('ch-first'); }
      list.appendChild(b); toBottom(c);
      t.value = ''; grow(t); form.querySelector('.ch-input').classList.remove('has-text'); delete drafts[id]; t.focus();
      var fd = new FormData(form); fd.set('body', text);
      sending++;
      fetch(form.getAttribute('action'), { method: 'POST', body: fd, credentials: 'same-origin', headers: { 'X-Chat': '1', 'Accept': 'application/json' } })   // getAttribute: the field named "action" shadows form.action
        .then(function (r) { return r.json(); })
        .then(function (j) { if (!j.ok) { throw new Error(j.text || ''); } b.classList.remove('ch-sending'); })
        .catch(function (err) {
          b.classList.remove('ch-sending'); b.classList.add('ch-failed');
          var f = el('button', 'ch-retry', tr('Not delivered. Tap to try again.', 'Hindi naipadala. Pindutin para subukan muli.') + (err && err.message ? ' ' + err.message : ''));
          f.type = 'button'; f.setAttribute('data-ch', 'retry'); f.setAttribute('data-text', text); b.appendChild(f);
        })
        .then(function () { sending--; if (!sending) { refresh(); } });
    }

    /* the options, from the right-click or the ... button */
    function menuItems() {
      var cs = store.cases()[report] || {}, isOpen = !panel.hidden;
      var items = inline ? [] : [
        { label: isOpen ? tr('Close chat', 'Isara ang chat') : tr('Open chat', 'Buksan ang chat'), act: function () { if (isOpen) { close(); } else { open(); } } },
        { sep: true }
      ];
      items.push(
        { label: tr('Float on every page', 'Ilutang sa lahat ng pahina'), check: !!cs.pin, act: function () { store.patch(report, { pin: !cs.pin, t: api.tracking || cs.t || '' }); } },
        { label: tr('Sound for this case', 'Tunog para sa kasong ito'), check: soundFor(report), act: function () { store.patch(report, { sound: !soundFor(report), t: api.tracking || cs.t || '' }); } }
      );
      if (!main || report !== api.home) { items.push({ label: tr('Go to the case', 'Pumunta sa kaso'), href: 'case.php?id=' + encodeURIComponent(report) }); }
      items.push({ sep: true }, { label: tr('Chat head settings', 'Mga setting ng chat head'), href: 'settings.php#look' });
      return items;
    }
    fab.addEventListener('contextmenu', function (e) {
      e.preventDefault();
      var r = fab.getBoundingClientRect(), x = e.clientX || r.left, y = e.clientY || r.top;
      showMenu(x, y, menuItems(), fab);
    });

    /* dragging, the way a phone's chat heads work: the panel shuts when you pick the bubble up, it follows your finger or mouse,
       a quick flick sends it to that side, and on letting go it springs to the left or right edge at the height you left it.
       A floating head also shows a round X at the bottom while it is held: drop it there and it stops floating. */
    var EDGE = 12, SZ = 58, drag = null, moved = false, suppress = false;
    var trash = null;
    function getTrash() {          // one round X for the whole page, shared by every head
      if (!sharedTrash) {
        sharedTrash = el('div', 'ch-trash'); sharedTrash.setAttribute('aria-hidden', 'true');
        sharedTrash.innerHTML = '<svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>';
        document.body.appendChild(sharedTrash);
      }
      trash = sharedTrash;
      return sharedTrash;
    }
    function xFor(side) { return side === 'l' ? EDGE : window.innerWidth - SZ - EDGE; }
    function clampY(y) { return Math.max(EDGE, Math.min(window.innerHeight - SZ - EDGE, y)); }
    function place(x, y) {
      root.classList.add('ch-placed'); root.style.left = Math.max(0, Math.min(window.innerWidth - SZ, x)) + 'px'; root.style.top = Math.max(0, Math.min(window.innerHeight - SZ, y)) + 'px';
      root.style.right = 'auto'; root.style.bottom = 'auto';
    }
    function applyPos() {
      var c = store.cases()[posKey] || {}, y = c.y != null ? Number(c.y) : api.defY;
      if (y != null && isFinite(y)) { place(xFor(c.side === 'l' ? 'l' : 'r'), clampY(y)); }
      else if (main) { root.classList.remove('ch-placed'); root.style.top = root.style.left = root.style.right = root.style.bottom = ''; }
      orient();
    }
    api.applyPos = applyPos;
    fab.addEventListener('pointerdown', function (e) {
      if (e.button !== 0) { return; }
      drag = { x: e.clientX, y: e.clientY, r: root.getBoundingClientRect(), vx: 0, lx: e.clientX, lt: e.timeStamp, near: false };
      moved = false; holding = true;
      try { fab.setPointerCapture(e.pointerId); } catch (x) { /* the drag still works while the pointer stays over the bubble */ }   // captured at once, so a quick flick cannot leave the bubble behind
    });
    fab.addEventListener('pointermove', function (e) {
      if (!drag) { return; }
      var dx = e.clientX - drag.x, dy = e.clientY - drag.y;
      if (!moved && Math.hypot(dx, dy) < 6) { return; }
      if (!moved) {
        moved = true; closeMenu(false); if (!panel.hidden) { close(); }
        root.classList.remove('ch-snap'); root.classList.add('ch-drag'); if (!main) { getTrash().classList.add('ch-on'); }
      }
      place(drag.r.left + dx, drag.r.top + dy);
      var dt = Math.max(1, e.timeStamp - drag.lt); drag.vx = 0.6 * drag.vx + 0.4 * ((e.clientX - drag.lx) / dt); drag.lx = e.clientX; drag.lt = e.timeStamp;
      if (!main) {
        var tb = getTrash().getBoundingClientRect();
        drag.near = Math.hypot(e.clientX - (tb.left + tb.width / 2), e.clientY - (tb.top + tb.height / 2)) < 84;
        trash.classList.toggle('ch-hot', drag.near); root.classList.toggle('ch-bin', drag.near);
      }
    });
    function endDrag() {
      if (!drag) { return; }
      var was = moved, near = drag.near, vx = drag.vx; drag = null; moved = false; holding = false;
      if (trash) { trash.classList.remove('ch-on', 'ch-hot'); }
      if (!was) { return; }
      root.classList.remove('ch-drag', 'ch-bin'); suppress = true; setTimeout(function () { suppress = false; }, 80);
      if (near && !main) {                                   // dropped on the X: it shrinks into it and stops floating
        var tb = trash.getBoundingClientRect();
        root.classList.add('ch-snap', 'ch-gone'); root.style.left = (tb.left + tb.width / 2 - SZ / 2) + 'px'; root.style.top = (tb.top + tb.height / 2 - SZ / 2) + 'px';
        setTimeout(function () { if (api.onTrash) { api.onTrash(); } else { store.patch(report, { pin: false }); } }, 200);
        return;
      }
      var r = root.getBoundingClientRect(), mid = r.left + r.width / 2;
      var side = Math.abs(vx) > 0.5 ? (vx > 0 ? 'r' : 'l') : (mid < window.innerWidth / 2 ? 'l' : 'r');
      var y = Math.round(clampY(r.top));
      root.classList.add('ch-snap'); root.style.left = xFor(side) + 'px'; root.style.top = y + 'px';
      setTimeout(function () { root.classList.remove('ch-snap'); }, 400);
      store.patch(posKey, posKey === report ? { side: side, y: y, t: api.tracking || (store.cases()[report] || {}).t || '' } : { side: side, y: y });
    }
    fab.addEventListener('pointerup', endDrag); fab.addEventListener('pointercancel', endDrag); fab.addEventListener('lostpointercapture', endDrag);
    fab.addEventListener('click', function () { if (suppress) { return; } if (panel.hidden) { open(); } else { close(); } });
    window.addEventListener('resize', applyPos);

    /* a new message while the panel is shut: the bubble shakes and a small preview sits next to it for a few seconds */
    api.pulse = function (who, text, caseId) {
      fab.classList.remove('ch-pulse'); void fab.offsetWidth; fab.classList.add('ch-pulse');
      var pk = root.querySelector('.ch-peek');
      if (!pk) { pk = el('button', 'ch-peek'); pk.type = 'button'; pk.setAttribute('role', 'status'); pk.addEventListener('click', function () { if (pk._case && api.onCase) { api.onCase(pk._case); } open(); }); root.appendChild(pk); }
      pk._case = caseId || null;
      pk.textContent = ''; pk.appendChild(el('b', '', who)); pk.appendChild(document.createTextNode(' ' + text)); pk.hidden = false;
      clearTimeout(pk._t); pk._t = setTimeout(function () { pk.hidden = true; }, 7000);
    };

    root.addEventListener('click', function (e) {
      var x = e.target.closest('[data-ch]'); if (!x) { return; }
      var a = x.getAttribute('data-ch');
      if (a === 'close') { close(); fab.focus(); }
      else if (a === 'open') { show(x.getAttribute('data-conv')); }
      else if (a === 'back') { show(null); var r = body.querySelector('.ch-row'); if (r) { r.focus(); } }
      else if (a === 'menu') { var br = x.getBoundingClientRect(); showMenu(br.left, br.bottom + 4, menuItems(), x); }
      else if (a === 'case' && api.onCase) { api.onCase(x.getAttribute('data-case')); }
      else if (a === 'retry') {
        var bb = x.closest('.ch-b'), c = x.closest('.ch-conv'), t = c.querySelector('textarea');
        if (t) { t.value = x.getAttribute('data-text') || ''; grow(t); c.querySelector('.ch-input').classList.add('has-text'); t.focus(); }
        bb.remove();
      }
    });
    root.addEventListener('submit', function (e) { var f = e.target.closest('[data-ch="form"]'); if (f) { e.preventDefault(); send(f); } });
    root.addEventListener('input', function (e) { var t = e.target; if (t.tagName !== 'TEXTAREA') { return; } grow(t); t.closest('.ch-input').classList.toggle('has-text', t.value.trim() !== ''); });
    root.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && e.target.tagName === 'TEXTAREA') { e.preventDefault(); var f = e.target.closest('form'); if (f) { send(f); } }
      else if (e.key === 'Escape' && !panel.hidden && !menu) { e.stopPropagation(); close(); fab.focus(); }
    });

    listeners.push(applyPos);
    api.destroy = function () { listeners = listeners.filter(function (f) { return f !== applyPos; }); window.removeEventListener('resize', applyPos); root.remove(); };
    applyPos(); paintUnread();
    if (inline) {                         // the reader: open at once, and kept current while the tab is in view
      open();
      var iv = setInterval(function () { if (!root.isConnected) { clearInterval(iv); return; } if (!document.hidden) { refresh(); } }, 15000);
    }
    if (main) {
      pull([report]).then(paintUnread);       // where this person was, from the database
      if (location.hash === '#chat') { open(); } else if (location.hash === '#resident-messages') { open('r'); }
    }
    return api;
  }

  /* ---------- ONE floating head for the cases whose chat is floated, on the pages that are not a case page ----------
     19 Nov 2026 (Rose): each floated case used to get its own bubble, so a handler who floated a few cases had several chat heads
     on every page. Now there is exactly one: it shows one floated case at a time (a row of the cases in its panel switches between
     them), and its ball counts the conversations with something unread across every floated case. A case page has its own head
     and no floating one. */
  var stack = null, stackIds = [], stackCur = null, lastIn = {}, lastFeed = {}, pollT = null;
  var lastAct = Date.now();
  ['pointerdown', 'keydown', 'wheel', 'touchstart'].forEach(function (ev) { window.addEventListener(ev, function () { lastAct = Date.now(); }, { passive: true }); });
  var mainEl = document.getElementById('chat-head');

  /* how many conversations of a floated case have something unread: what came in since this person last looked, or since the barangay last wrote */
  function unreadConvs(id, d) {
    if (!d) { return 0; }
    var seen = store.seen(id), on = {};
    (d.in || []).forEach(function (m) {
      var since = seen[m.c] ? ts(seen[m.c]) : (d.out && d.out[m.c] ? ts(d.out[m.c]) : 0);
      if (ts(m.ts) > since) { on[m.c] = true; }
    });
    if (stack && id === stackCur) { var reading = stack.current(); if (reading) { delete on[reading]; } }   // the conversation open on screen is not waiting
    return Object.keys(on).length;
  }
  function trackOf(id) { var c = store.cases()[id] || {}; return (lastFeed[id] && lastFeed[id].t) || c.t || (mainApi && id === mainApi.home ? mainApi.root.getAttribute('data-home-tracking') || '' : ''); }
  function paintStack() {
    if (!stack) { return; }
    var total = 0, n = stackIds.length, t = trackOf(stackCur);
    stackIds.forEach(function (id) { total += unreadConvs(id, lastFeed[id]); });
    stack.setBadge(total);
    var tag = stack.root.querySelector('.ch-tag'); if (tag) { tag.textContent = short(t) + (n > 1 ? ' +' + (n - 1) : ''); }
    stack.fab.setAttribute('aria-label', (n > 1 ? tr('Messages for ', 'Mga mensahe para sa ') + n + tr(' floating cases', ' lumulutang na kaso') : tr('Messages for case ', 'Mga mensahe para sa kaso ') + t)
      + (total > 0 ? ', ' + total + tr(' unread', ' hindi pa nababasa') : '') + tr('. Right-click for options.', '. I-right-click para sa mga opsyon.'));
    var strip = stack.strip, key = stackIds.join(',');
    strip.hidden = n < 2;
    if (strip.getAttribute('data-ids') !== key) {
      strip.setAttribute('data-ids', key); strip.textContent = '';
      stackIds.forEach(function (id) {
        var b = el('button', 'ch-case'); b.type = 'button'; b.setAttribute('data-ch', 'case'); b.setAttribute('data-case', id);
        var dot = el('i', 'ch-case-dot'); dot.setAttribute('aria-hidden', 'true'); b.appendChild(dot); b.appendChild(el('span', 'ch-case-t', ''));
        strip.appendChild(b);
      });
    }
    [].forEach.call(strip.querySelectorAll('.ch-case'), function (b) {
      var id = b.getAttribute('data-case'), on = id === stackCur, u = unreadConvs(id, lastFeed[id]) > 0, tk = trackOf(id);
      b.classList.toggle('ch-case-on', on); b.setAttribute('aria-pressed', on ? 'true' : 'false'); b.classList.toggle('ch-case-new', u);
      b.querySelector('.ch-case-t').textContent = short(tk) || id.slice(0, 4);
      b.setAttribute('aria-label', tr('Case ', 'Kaso ') + (tk || id.slice(0, 8)) + (u ? tr(', unread messages', ', may hindi pa nababasa') : ''));
    });
  }
  function applyFeed(id, d) {
    lastFeed[id] = d;
    var newest = null;
    (d.in || []).forEach(function (m) { if (!newest || ts(m.ts) > ts(newest.ts)) { newest = m; } });
    var t = newest ? ts(newest.ts) : 0;
    if (lastIn[id] === undefined) { lastIn[id] = t; return; }          // the first look only learns what is already there
    if (t > lastIn[id] && stack) {
      lastIn[id] = t;
      if (stack.isOpen() && id === stackCur) { stack.refresh(); }
      else if (mainApi && id === mainApi.home && mainApi.report === mainApi.home) { /* this page's own case on screen: its live refresh already rings and repaints it */ }
      else if (unreadConvs(id, d) > 0) {
        stack.pulse((stackIds.length > 1 ? short(d.t || trackOf(id)) + ' · ' : '') + (newest.c === 'r' ? tr('Resident:', 'Residente:') : tr('Tanod:', 'Tanod:')), newest.x || '', id);
        if (soundFor(id)) { ding(); }
      }
    }
  }
  function poll() {
    var ids = stackIds.slice(); if (!ids.length) { return Promise.resolve(); }
    return fetch('chat-feed.php?ids=' + ids.map(encodeURIComponent).join(','), { credentials: 'same-origin', headers: { 'Accept': 'application/json' } })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (j) { if (!j || !j.ok) { return; } ids.forEach(function (id) { if (j.cases[id]) { merge(id, j.cases[id].st); applyFeed(id, j.cases[id]); } }); paintStack(); })
      .catch(function () { /* offline or signed out: the next poll tries again */ });
  }
  window.ssChatPoll = poll;
  function makeStack() {
    var root = el('div', 'ch ch-float');
    var panel = el('section', 'ch-panel'); panel.setAttribute('role', 'dialog'); panel.setAttribute('aria-label', tr('Messages', 'Mga Mensahe')); panel.hidden = true;
    var strip = el('div', 'ch-cases'); strip.setAttribute('role', 'group'); strip.setAttribute('aria-label', tr('Floating cases', 'Mga lumulutang na kaso')); strip.hidden = true;
    panel.appendChild(strip); panel.appendChild(el('div', 'ch-body'));
    var fab = el('button', 'ch-fab'); fab.type = 'button'; fab.setAttribute('aria-haspopup', 'menu'); fab.setAttribute('aria-expanded', 'false');
    fab.innerHTML = '<svg viewBox="0 0 24 24" width="26" height="26" fill="currentColor" aria-hidden="true"><path d="M12 3C6.5 3 2 6.8 2 11.5c0 2.5 1.3 4.7 3.4 6.2-.2 1.3-.8 2.6-1.7 3.6a.5.5 0 0 0 .5.8c2-.3 3.7-1.1 4.9-2A11.7 11.7 0 0 0 12 20c5.5 0 10-3.8 10-8.5S17.5 3 12 3z"/></svg>';
    var badge = el('span', 'ch-badge', '0'); badge.hidden = true; fab.appendChild(badge);
    root.setAttribute('data-report', stackCur || ''); root.setAttribute('data-tracking', trackOf(stackCur));
    root.setAttribute('data-url', 'case.php?id=' + encodeURIComponent(stackCur || '') + '&chat=1');
    root.appendChild(panel); root.appendChild(fab); root.appendChild(el('span', 'ch-tag', ''));
    document.body.appendChild(root);
    var api = mount(root); api.fab = fab; api.strip = strip; api.defY = window.innerHeight - 90; api.applyPos();
    api.onSeen = paintStack;
    api.onCase = function (id) { if (stackIds.indexOf(id) < 0) { return; } stackCur = id; api.setCase(id, trackOf(id)); paintStack(); };
    // dropped on the round X: none of the floated cases floats any more
    api.onTrash = function () { var c = rd(CK, {}); stackIds.forEach(function (id) { if (c[id]) { c[id].pin = false; } }); wr(CK, c); changed(); };
    return api;
  }
  /* 19 Nov 2026 (Ace): on a case page the case's own head is the one head; when other cases float it carries them too, with the same row
     (this case first), their unread dots and the preview of a new message, and its ball counts every one of them */
  var mainApi = null;
  function carryOnMain(api) {
    var panel = api.root.querySelector('.ch-panel'), body = api.root.querySelector('.ch-body');
    var strip = el('div', 'ch-cases'); strip.setAttribute('role', 'group'); strip.setAttribute('aria-label', tr('Floating cases', 'Mga lumulutang na kaso')); strip.hidden = true;
    panel.insertBefore(strip, body);
    api.strip = strip; api.fab = api.root.querySelector('.ch-fab');
    api.root.setAttribute('data-home-tracking', api.tracking);
    api.onSeen = paintStack;
    api.onCase = function (id) { if (stackIds.indexOf(id) < 0) { return; } stackCur = id; api.setCase(id, trackOf(id)); paintStack(); };
    api.onRefreshed = function () { if (stack === api) { poll(); } };
    return api;
  }
  function sync() {
    var pr = store.prefs(), cs = store.cases();
    var pinned = pr.floats ? Object.keys(cs).filter(function (id) { return id !== '_float' && cs[id] && cs[id].pin && !(mainApi && id === mainApi.home); }) : [];
    var want = mainApi ? (pinned.length ? [mainApi.home].concat(pinned.slice(-7)) : []) : pinned.slice(-8);
    Object.keys(lastFeed).forEach(function (id) { if (want.indexOf(id) < 0) { delete lastIn[id]; delete lastFeed[id]; } });
    stackIds = want;
    if (mainApi) {
      if (!want.length) {
        if (stack) { if (mainApi.report !== mainApi.home) { mainApi.setCase(mainApi.home, mainApi.root.getAttribute('data-home-tracking')); } mainApi.strip.hidden = true; mainApi.setFeedBadge(false); stack = null; }
        stackCur = null;
      } else {
        if (want.indexOf(stackCur) < 0) { stackCur = mainApi.home; }   // the case of this page, until another is picked
        if (!stack) { stack = mainApi; mainApi.setFeedBadge(true); }
        if (mainApi.report !== stackCur) { mainApi.setCase(stackCur, trackOf(stackCur)); }
        paintStack();
      }
    } else if (!want.length) { if (stack) { stack.destroy(); stack = null; } stackCur = null; }
    else {
      if (want.indexOf(stackCur) < 0) { stackCur = want[want.length - 1]; }   // the case floated last, until another is picked
      if (!stack) { stack = makeStack(); }
      stack.setCase(stackCur, trackOf(stackCur));
      paintStack();
    }
    // every 15 s while someone is at the page; once nobody has touched it for two minutes, every minute (speed sweep, 16 Nov 2026)
    if (want.length && !pollT) { var tickN = 0; poll(); pollT = setInterval(function () { tickN++; if (document.hidden) { return; } if (Date.now() - lastAct > 120000 && tickN % 4) { return; } poll(); }, 15000); }
    else if (want.length && pollT && Object.keys(lastFeed).length < want.length) { poll(); }   // a case just floated: learn its state now
    if (!want.length && pollT) { clearInterval(pollT); pollT = null; }
  }
  document.addEventListener('visibilitychange', function () { if (!document.hidden && pollT) { poll(); } });
  document.addEventListener('ss-chat-seen', paintStack);

  /* ---------- Settings: the "Chat heads" card (settings.php, Appearance) ---------- */
  function wireSettings() {
    var card = document.getElementById('chp'); if (!card) { return; }
    function btn(label, fn) { var b = el('button', 'p-btn p-btn-ghost p-btn-sm', label); b.type = 'button'; b.addEventListener('click', fn); return b; }
    function paint() {
      var pr = store.prefs();
      [].forEach.call(card.querySelectorAll('[data-pref]'), function (g) {
        var on = pr[g.getAttribute('data-pref')];
        [].forEach.call(g.querySelectorAll('button'), function (b) { var v = b.getAttribute('data-v') === '1'; b.classList.toggle('p-on', v === on); b.setAttribute('aria-pressed', v === on ? 'true' : 'false'); });
      });
      var ul = card.querySelector('#chp-list'); ul.textContent = '';
      var cs = store.cases(), ids = Object.keys(cs).filter(function (id) { return id !== '_float' && cs[id].pin; });
      card.querySelector('#chp-count').textContent = String(ids.length); card.querySelector('#chp-none').hidden = ids.length > 0;
      ids.forEach(function (id) {
        var li = el('li', 'chp-item'), a = el('a', '', cs[id].t || id.slice(0, 8)); a.href = 'case.php?id=' + encodeURIComponent(id);
        var snd = btn(soundFor(id) ? tr('Sound on', 'May tunog') : tr('Sound off', 'Walang tunog'), function () { store.patch(id, { sound: !soundFor(id) }); });
        snd.setAttribute('aria-pressed', soundFor(id) ? 'true' : 'false');
        li.appendChild(a); li.appendChild(snd); li.appendChild(btn(tr('Stop floating', 'Itigil ang paglutang'), function () { store.patch(id, { pin: false }); })); ul.appendChild(li);
      });
    }
    card.addEventListener('click', function (e) {
      var b = e.target.closest('[data-pref] button');
      if (b) { store.setPref(b.parentNode.getAttribute('data-pref'), b.getAttribute('data-v') === '1'); }
      if (e.target.closest('#chp-reset')) { var c = store.cases(); Object.keys(c).forEach(function (id) { delete c[id].y; delete c[id].side; }); wr(CK, c); changed(); }
    });
    listeners.push(paint); paint();
  }

  // 19 Nov 2026: the case page's head moves out of <main> to the body like the floating one; inside <main>'s own stacking it sat under the
  // phone's top bar, so the full-screen chat lost its header there
  if (mainEl && mainEl.parentElement !== document.body) { document.body.appendChild(mainEl); }
  if (mainEl) { window.ssChat = mainApi = carryOnMain(mount(mainEl)); }
  wireSettings();
  listeners.push(sync); sync();
})();
