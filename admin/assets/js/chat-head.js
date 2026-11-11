/* The chat head (12 Nov 2026), loaded on every portal page.
   - On a case page it runs the Messages-style panel the server rendered (includes/case_chat.php).
   - A case whose chat is "floated" (right-click the bubble, or the ... button) gets its own draggable bubble on every other page,
     with a notification ball and, if wanted, a sound, fed by chat-feed.php every 15 seconds.
   - Choices live in this browser (localStorage): ss-chat-prefs (master switches), ss-chat-cases (per case: pin, sound, side, y),
     ss-chat-seen-<case> (what was last looked at). The backend is not involved.
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
  var listeners = [];
  function changed() { listeners.slice().forEach(function (f) { f(); }); }
  var store = {
    prefs: function () { var p = rd(PK, {}); return { floats: p.floats !== false, ball: p.ball !== false, sound: p.sound !== false }; },
    setPref: function (k, v) { var p = rd(PK, {}); p[k] = v; wr(PK, p); changed(); },
    cases: function () { return rd(CK, {}); },
    patch: function (id, o) { var c = rd(CK, {}); c[id] = Object.assign(c[id] || {}, o); wr(CK, c); changed(); },
    seen: function (id) { return rd('ss-chat-seen-' + id, {}); },
    setSeen: function (id, conv, t) { var m = rd('ss-chat-seen-' + id, {}); m[conv] = t; wr('ss-chat-seen-' + id, m); }
  };
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

  /* ---------- the right-click menu ---------- */
  var menu = null, menuBack = null;
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
    var fab = root.querySelector('.ch-fab'), panel = root.querySelector('.ch-panel'), body = root.querySelector('.ch-body'), badge = root.querySelector('.ch-badge');
    var cur = null, drafts = {}, sending = 0, loaded = main;
    var api = { root: root, report: report, tracking: root.getAttribute('data-tracking') || '', defY: null };
    var feedBadge = !main;       // a floating head's ball comes from the feed; the case page's from its own conversations

    function convs() { return [].slice.call(body.querySelectorAll('.ch-conv')); }
    function lastOf(sel, c) { var n = c.querySelectorAll(sel); return n.length ? n[n.length - 1] : null; }
    function unreadIn(c, seen) {
      var id = c.getAttribute('data-conv'), since = seen[id] ? ts(seen[id]) : 0;
      if (!since) { var o = lastOf('.ch-out', c); since = o ? ts(o.getAttribute('data-ts')) : 0; }
      var n = 0; [].forEach.call(c.querySelectorAll('.ch-b[data-in]'), function (b) { if (ts(b.getAttribute('data-ts')) > since) { n++; } }); return n;
    }
    api.setBadge = function (n) { badge.textContent = n > 9 ? '9+' : String(n); badge.hidden = !(n > 0 && store.prefs().ball); fab.classList.toggle('ch-has', n > 0); };
    function paintUnread() {
      if (feedBadge) { return; }
      var seen = store.seen(report), total = 0;
      convs().forEach(function (c) {
        var n = (cur === c.getAttribute('data-conv') && !panel.hidden) ? 0 : unreadIn(c, seen); total += n;
        var row = body.querySelector('.ch-row[data-conv="' + c.getAttribute('data-conv') + '"]'); if (row) { row.classList.toggle('ch-unread', n > 0); }
      });
      api.setBadge(total);
    }
    function markSeen(id) {
      var c = body.querySelector('.ch-conv[data-conv="' + id + '"]'); if (!c) { return; }
      var l = lastOf('.ch-b, .ch-sys', c); store.setSeen(report, id, l ? l.getAttribute('data-ts') : new Date().toISOString());
      if (api.onSeen) { api.onSeen(); }
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
        if (t) { if (drafts[cur]) { t.value = drafts[cur]; grow(t); v.querySelector('.ch-input').classList.add('has-text'); } t.focus(); }
      }
      paintUnread();
    }

    /* where the panel opens: towards the roomier side of the screen, never off it */
    function orient() {
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
      var go = function () { var all = convs(); show(id || (all.length === 1 ? all[0].getAttribute('data-conv') : null)); if (!cur) { var r = body.querySelector('.ch-row'); if (r) { r.focus(); } } };
      if (!loaded) { body.textContent = ''; body.appendChild(el('p', 'ch-empty', tr('Loading…', 'Naglo-load…'))); refresh().then(function () { loaded = true; go(); }); } else { go(); }
    }
    function close() {
      if (cur) { var t = body.querySelector('.ch-conv[data-conv="' + cur + '"] textarea'); if (t) { drafts[cur] = t.value; } markSeen(cur); }
      panel.hidden = true; fab.setAttribute('aria-expanded', 'false'); root.classList.remove('ch-open'); paintUnread();
    }
    api.open = open; api.close = close; api.isOpen = function () { return !panel.hidden; };

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
      var items = [
        { label: isOpen ? tr('Close chat', 'Isara ang chat') : tr('Open chat', 'Buksan ang chat'), act: function () { if (isOpen) { close(); } else { open(); } } },
        { sep: true },
        { label: tr('Float on every page', 'Ilutang sa lahat ng pahina'), check: !!cs.pin, act: function () { store.patch(report, { pin: !cs.pin, t: api.tracking || cs.t || '' }); } },
        { label: tr('Sound for this case', 'Tunog para sa kasong ito'), check: soundFor(report), act: function () { store.patch(report, { sound: !soundFor(report), t: api.tracking || cs.t || '' }); } }
      ];
      if (!main) { items.push({ label: tr('Go to the case', 'Pumunta sa kaso'), href: 'case.php?id=' + encodeURIComponent(report) }); }
      items.push({ sep: true }, { label: tr('Chat head settings', 'Mga setting ng chat head'), href: 'settings.php#look' });
      return items;
    }
    fab.addEventListener('contextmenu', function (e) {
      e.preventDefault();
      var r = fab.getBoundingClientRect(), x = e.clientX || r.left, y = e.clientY || r.top;
      showMenu(x, y, menuItems(), fab);
    });

    /* dragging: press and move the bubble anywhere; it settles on the nearer side and remembers where */
    var drag = null, moved = false, suppress = false;
    function place(x, y) {
      var vw = window.innerWidth, vh = window.innerHeight;
      root.classList.add('ch-placed'); root.style.left = Math.max(0, Math.min(vw - 58, x)) + 'px'; root.style.top = Math.max(0, Math.min(vh - 58, y)) + 'px'; root.style.right = 'auto'; root.style.bottom = 'auto';
    }
    function applyPos() {
      var c = store.cases()[report] || {}, y = c.y != null ? c.y : api.defY;
      if (y != null) {
        var vh = window.innerHeight, ty = Math.max(10, Math.min(vh - 68, y)), lft = c.side === 'l';
        root.classList.add('ch-placed'); root.style.top = ty + 'px'; root.style.bottom = 'auto'; root.style.left = lft ? '16px' : 'auto'; root.style.right = lft ? 'auto' : '16px';
      } else if (main) { root.classList.remove('ch-placed'); root.style.top = root.style.left = root.style.right = root.style.bottom = ''; }
      orient();
    }
    api.applyPos = applyPos;
    fab.addEventListener('pointerdown', function (e) {
      if (e.button !== 0) { return; }
      drag = { x: e.clientX, y: e.clientY, r: root.getBoundingClientRect(), id: e.pointerId }; moved = false;
      try { fab.setPointerCapture(e.pointerId); } catch (x) { /* the drag still works while the pointer stays over the bubble */ }   // captured at once, so a quick flick cannot leave the bubble behind
    });
    fab.addEventListener('pointermove', function (e) {
      if (!drag) { return; }
      var dx = e.clientX - drag.x, dy = e.clientY - drag.y;
      if (!moved && Math.hypot(dx, dy) < 6) { return; }
      if (!moved) { moved = true; root.classList.add('ch-drag'); }
      place(drag.r.left + dx, drag.r.top + dy);
    });
    function endDrag() {
      if (!drag) { return; }
      var was = moved; drag = null; moved = false;
      if (was) {
        root.classList.remove('ch-drag'); suppress = true; setTimeout(function () { suppress = false; }, 60);
        var r = root.getBoundingClientRect();
        store.patch(report, { side: r.left + r.width / 2 < window.innerWidth / 2 ? 'l' : 'r', y: Math.round(r.top), t: api.tracking || (store.cases()[report] || {}).t || '' });
      }
    }
    fab.addEventListener('pointerup', endDrag); fab.addEventListener('pointercancel', endDrag);
    fab.addEventListener('click', function () { if (suppress) { return; } if (panel.hidden) { open(); } else { close(); } });
    window.addEventListener('resize', applyPos);

    /* a new message while the panel is shut: the bubble shakes and a small preview sits next to it for a few seconds */
    api.pulse = function (who, text) {
      fab.classList.remove('ch-pulse'); void fab.offsetWidth; fab.classList.add('ch-pulse');
      var pk = root.querySelector('.ch-peek');
      if (!pk) { pk = el('button', 'ch-peek'); pk.type = 'button'; pk.setAttribute('role', 'status'); pk.addEventListener('click', function () { open(); }); root.appendChild(pk); }
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
    if (main) {
      if (location.hash === '#chat') { open(); } else if (location.hash === '#resident-messages') { open('r'); }
    }
    return api;
  }

  /* ---------- floating heads for the cases whose chat is floated, on the pages that are not that case ---------- */
  var floaters = {}, lastIn = {}, lastFeed = {}, pollT = null;
  var mainEl = document.getElementById('chat-head'), here = mainEl ? mainEl.getAttribute('data-report') : '';

  function unreadOf(id, d) {
    var seen = store.seen(id), n = 0;
    (d.in || []).forEach(function (m) {
      var since = seen[m.c] ? ts(seen[m.c]) : (d.out && d.out[m.c] ? ts(d.out[m.c]) : 0);
      if (ts(m.ts) > since) { n++; }
    });
    return n;
  }
  function applyFeed(id, d) {
    var f = floaters[id]; if (!f) { return; }
    if (d.t && f.tracking !== d.t) { f.tracking = d.t; f.root.querySelector('.ch-tag').textContent = short(d.t); f.root.setAttribute('data-tracking', d.t); }
    var n = unreadOf(id, d); f.setBadge(n);
    var newest = null;
    (d.in || []).forEach(function (m) { if (!newest || ts(m.ts) > ts(newest.ts)) { newest = m; } });
    var t = newest ? ts(newest.ts) : 0;
    if (lastIn[id] === undefined) { lastIn[id] = t; return; }          // the first look only learns what is already there
    if (t > lastIn[id]) {
      lastIn[id] = t;
      if (f.isOpen()) { f.refresh(); }
      else if (n > 0) { f.pulse(newest.c === 'r' ? tr('Resident:', 'Residente:') : tr('Tanod:', 'Tanod:'), newest.x || ''); if (soundFor(id)) { ding(); } }
    }
  }
  function poll() {
    var ids = Object.keys(floaters); if (!ids.length) { return; }
    fetch('chat-feed.php?ids=' + ids.map(encodeURIComponent).join(','), { credentials: 'same-origin', headers: { 'Accept': 'application/json' } })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (j) { if (!j || !j.ok) { return; } ids.forEach(function (id) { if (j.cases[id]) { lastFeed[id] = j.cases[id]; applyFeed(id, j.cases[id]); } }); })
      .catch(function () { /* offline or signed out: the next poll tries again */ });
  }
  window.ssChatPoll = poll;
  function makeFloater(id, c, i) {
    var root = el('div', 'ch ch-float'); root.setAttribute('data-report', id); root.setAttribute('data-tracking', c.t || '');
    root.setAttribute('data-url', 'case.php?id=' + encodeURIComponent(id) + '&chat=1');
    var panel = el('section', 'ch-panel'); panel.setAttribute('role', 'dialog'); panel.setAttribute('aria-label', tr('Messages', 'Mga Mensahe')); panel.hidden = true; panel.appendChild(el('div', 'ch-body'));
    var fab = el('button', 'ch-fab'); fab.type = 'button'; fab.setAttribute('aria-haspopup', 'menu'); fab.setAttribute('aria-expanded', 'false');
    fab.setAttribute('aria-label', tr('Messages for case ', 'Mga mensahe para sa kaso ') + (c.t || '') + tr('. Right-click for options.', '. I-right-click para sa mga opsyon.'));
    fab.innerHTML = '<svg viewBox="0 0 24 24" width="26" height="26" fill="currentColor" aria-hidden="true"><path d="M12 3C6.5 3 2 6.8 2 11.5c0 2.5 1.3 4.7 3.4 6.2-.2 1.3-.8 2.6-1.7 3.6a.5.5 0 0 0 .5.8c2-.3 3.7-1.1 4.9-2A11.7 11.7 0 0 0 12 20c5.5 0 10-3.8 10-8.5S17.5 3 12 3z"/></svg>';
    var badge = el('span', 'ch-badge', '0'); badge.hidden = true; fab.appendChild(badge);
    root.appendChild(panel); root.appendChild(fab); root.appendChild(el('span', 'ch-tag', short(c.t || '')));
    document.body.appendChild(root);
    var api = mount(root); api.defY = window.innerHeight - 90 - i * 78; api.applyPos();
    api.onSeen = function () { if (lastFeed[id]) { applyFeed(id, lastFeed[id]); } };
    return api;
  }
  function sync() {
    var pr = store.prefs(), cs = store.cases();
    var want = pr.floats ? Object.keys(cs).filter(function (id) { return cs[id].pin && id !== here; }).slice(0, 8) : [];
    Object.keys(floaters).forEach(function (id) { if (want.indexOf(id) < 0) { floaters[id].destroy(); delete floaters[id]; delete lastIn[id]; delete lastFeed[id]; } });
    want.forEach(function (id, i) { if (!floaters[id]) { floaters[id] = makeFloater(id, cs[id], i); } });
    Object.keys(floaters).forEach(function (id) { var f = floaters[id]; if (lastFeed[id]) { f.setBadge(unreadOf(id, lastFeed[id])); } });
    var any = Object.keys(floaters).length > 0;
    if (any && !pollT) { poll(); pollT = setInterval(function () { if (!document.hidden) { poll(); } }, 15000); }
    if (!any && pollT) { clearInterval(pollT); pollT = null; }
  }
  document.addEventListener('visibilitychange', function () { if (!document.hidden && pollT) { poll(); } });

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
      var cs = store.cases(), ids = Object.keys(cs).filter(function (id) { return cs[id].pin; });
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

  if (mainEl) { window.ssChat = mount(mainEl); }
  wireSettings();
  listeners.push(sync); sync();
})();
