/* The case page's chat head (12 Nov 2026): one button, a Messages-style panel, a list of conversations, then one at a time.
   The markup comes from includes/case_chat.php; this only opens and closes it, sends in place and keeps it current.
   Sending posts the same form as before (dispatch_reply / resident_reply) and asks for JSON; the live refresh re-reads the
   conversations from case.php?id=...&chat=1. Strict CSP: no inline handlers, everything is delegated from #chat-head. */
(function () {
  'use strict';
  var root = document.getElementById('chat-head');
  if (!root) { return; }
  // Out of the page's own stacking level, so on a phone the full-screen chat sits above the sidebar and top bar.
  if (root.parentNode !== document.body) { document.body.appendChild(root); }
  var fab = document.getElementById('ch-fab'), panel = document.getElementById('ch-panel'), body = document.getElementById('ch-body');
  var badge = document.getElementById('ch-badge');
  var report = root.getAttribute('data-report') || '';
  var url = root.getAttribute('data-url') || '';
  var KEY = 'ss-chat-seen-' + report;
  var cur = null;               // the open conversation's id, or null for the list
  var drafts = {};              // conversation id -> unsent text, kept across a refresh
  var sending = 0, wantRefresh = false;
  var tr = function (en, fil) { return typeof window.T === 'function' ? window.T(en, fil) : en; };

  function seenMap() { try { return JSON.parse(localStorage.getItem(KEY) || '{}') || {}; } catch (e) { return {}; } }
  function saveSeen(m) { try { localStorage.setItem(KEY, JSON.stringify(m)); } catch (e) { /* private window: the badge just resets */ } }
  function convs() { return [].slice.call(body.querySelectorAll('.ch-conv')); }
  function lastOf(sel, el) { var n = el.querySelectorAll(sel); return n.length ? n[n.length - 1] : null; }

  // Unread = what they wrote after you last looked, or after your last reply when you have not opened it yet.
  function unreadIn(c, seen) {
    var id = c.getAttribute('data-conv'), since = seen[id];
    if (!since) { var o = lastOf('.ch-out', c); since = o ? o.getAttribute('data-ts') : ''; }
    var n = 0;
    [].forEach.call(c.querySelectorAll('.ch-b[data-in]'), function (b) { if (!since || b.getAttribute('data-ts') > since) { n++; } });
    return n;
  }
  function paintUnread() {
    var seen = seenMap(), total = 0;
    convs().forEach(function (c) {
      var n = (cur === c.getAttribute('data-conv') && !panel.hidden) ? 0 : unreadIn(c, seen);
      total += n;
      var row = body.querySelector('.ch-row[data-conv="' + c.getAttribute('data-conv') + '"]');
      if (row) { row.classList.toggle('ch-unread', n > 0); }
    });
    badge.textContent = total > 9 ? '9+' : String(total);
    badge.hidden = total === 0;
    fab.classList.toggle('ch-has', total > 0);
  }
  function markSeen(id) {
    var c = body.querySelector('.ch-conv[data-conv="' + id + '"]'); if (!c) { return; }
    var l = lastOf('.ch-b, .ch-sys', c), m = seenMap();
    m[id] = l ? l.getAttribute('data-ts') : new Date().toISOString(); saveSeen(m);
  }

  function toBottom(c) { var m = c && c.querySelector('.ch-msgs'); if (m) { m.scrollTop = m.scrollHeight; } }
  function grow(t) { t.style.height = 'auto'; t.style.height = Math.min(t.scrollHeight, 120) + 'px'; }

  function show(id) {
    cur = id;
    [].forEach.call(body.querySelectorAll('.ch-view'), function (v) { v.hidden = true; });
    var v = id ? body.querySelector('.ch-conv[data-conv="' + id + '"]') : body.querySelector('.ch-listview');
    if (!v) { cur = null; v = body.querySelector('.ch-listview'); }
    if (v) { v.hidden = false; }
    root.classList.toggle('ch-in-conv', !!cur);
    if (cur) {
      markSeen(cur); toBottom(v);
      var t = v.querySelector('textarea');
      if (t) { if (drafts[cur]) { t.value = drafts[cur]; grow(t); v.querySelector('.ch-input').classList.add('has-text'); } t.focus(); }
    }
    paintUnread();
  }
  function open(id) {
    panel.hidden = false; fab.setAttribute('aria-expanded', 'true'); root.classList.add('ch-open');
    var all = convs();
    show(id || (all.length === 1 ? all[0].getAttribute('data-conv') : null));
    if (!cur) { var r = body.querySelector('.ch-row'); if (r) { r.focus(); } }
  }
  function close() {
    if (cur) { var t = body.querySelector('.ch-conv[data-conv="' + cur + '"] textarea'); if (t) { drafts[cur] = t.value; } markSeen(cur); }
    panel.hidden = true; fab.setAttribute('aria-expanded', 'false'); root.classList.remove('ch-open'); paintUnread();
  }

  // The live refresh: take the conversations again, keep the open one, the draft and the scroll position.
  function refresh() {
    if (sending) { wantRefresh = true; return Promise.resolve(); }
    var was = cur, c0 = was && body.querySelector('.ch-conv[data-conv="' + was + '"] .ch-msgs');
    var stick = !c0 || (c0.scrollHeight - c0.scrollTop - c0.clientHeight < 80), top = c0 ? c0.scrollTop : 0;
    if (was) { var t0 = body.querySelector('.ch-conv[data-conv="' + was + '"] textarea'); if (t0) { drafts[was] = t0.value; } }
    var failed = {};
    convs().forEach(function (c) { var f = [].slice.call(c.querySelectorAll('.ch-failed')).map(function (n) { return n.outerHTML; }); if (f.length) { failed[c.getAttribute('data-conv')] = f; } });
    return fetch(url, { credentials: 'same-origin', headers: { 'Accept': 'text/html' } }).then(function (r) { return r.ok ? r.text() : Promise.reject(r.status); }).then(function (h) {
      body.innerHTML = h;
      Object.keys(failed).forEach(function (id) { var m = body.querySelector('.ch-conv[data-conv="' + id + '"] .ch-msgs'); if (m) { failed[id].forEach(function (f) { m.insertAdjacentHTML('beforeend', f); }); } });
      if (!panel.hidden) { show(was); var c1 = was && body.querySelector('.ch-conv[data-conv="' + was + '"] .ch-msgs'); if (c1 && !stick) { c1.scrollTop = top; } }
      else { cur = was; paintUnread(); }
    }).catch(function () { /* the next event or the next press tries again */ });
  }

  function send(form) {
    var t = form.querySelector('textarea'), text = t.value.trim();
    if (!text) { return; }
    var c = form.closest('.ch-conv'), id = c.getAttribute('data-conv'), list = c.querySelector('.ch-msgs');
    var none = list.querySelector('.ch-none'); if (none) { none.remove(); }
    var prev = list.lastElementChild, b = document.createElement('div'), p = document.createElement('p');
    b.className = 'ch-b ch-out ch-last ch-first ch-sending'; p.textContent = text; b.appendChild(p);
    if (prev && prev.classList.contains('ch-out')) { prev.classList.remove('ch-last'); b.classList.remove('ch-first'); }
    list.appendChild(b); toBottom(c);
    t.value = ''; grow(t); form.querySelector('.ch-input').classList.remove('has-text'); delete drafts[id]; t.focus();
    var fd = new FormData(form); fd.set('body', text);
    sending++;
    fetch(form.getAttribute('action'), {   // not form.action: the field named "action" shadows it
      method: 'POST', body: fd, credentials: 'same-origin', headers: { 'X-Chat': '1', 'Accept': 'application/json' } })
      .then(function (r) { return r.json(); })
      .then(function (j) { if (!j.ok) { throw new Error(j.text || ''); } b.classList.remove('ch-sending'); })
      .catch(function (err) {
        b.classList.remove('ch-sending'); b.classList.add('ch-failed');
        var f = document.createElement('button'); f.type = 'button'; f.className = 'ch-retry'; f.setAttribute('data-ch', 'retry'); f.setAttribute('data-text', text);
        f.textContent = tr('Not delivered. Tap to try again.', 'Hindi naipadala. Pindutin para subukan muli.') + (err && err.message ? ' ' + err.message : '');
        b.appendChild(f);
      })
      .then(function () { sending--; if (!sending) { refresh(); wantRefresh = false; } });
  }

  root.addEventListener('click', function (e) {
    var el = e.target.closest('[data-ch]'); if (!el) { return; }
    var a = el.getAttribute('data-ch');
    if (a === 'close') { close(); fab.focus(); }
    else if (a === 'open') { show(el.getAttribute('data-conv')); }
    else if (a === 'back') { show(null); var r = body.querySelector('.ch-row'); if (r) { r.focus(); } }
    else if (a === 'retry') {
      var b = el.closest('.ch-b'), c = el.closest('.ch-conv'), t = c.querySelector('textarea');
      if (t) { t.value = el.getAttribute('data-text') || ''; grow(t); c.querySelector('.ch-input').classList.add('has-text'); t.focus(); }
      b.remove();
    }
  });
  fab.addEventListener('click', function () { if (panel.hidden) { open(); } else { close(); } });
  root.addEventListener('submit', function (e) { var f = e.target.closest('[data-ch="form"]'); if (f) { e.preventDefault(); send(f); } });
  root.addEventListener('input', function (e) {
    var t = e.target; if (t.tagName !== 'TEXTAREA') { return; }
    grow(t); t.closest('.ch-input').classList.toggle('has-text', t.value.trim() !== '');
  });
  root.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && e.target.tagName === 'TEXTAREA') { e.preventDefault(); var f = e.target.closest('form'); if (f) { send(f); } }
    else if (e.key === 'Escape' && !panel.hidden) { e.stopPropagation(); close(); fab.focus(); }
  });

  window.ssChat = { refresh: refresh, open: open };
  paintUnread();
  if (location.hash === '#chat') { open(); }
  else if (location.hash === '#resident-messages') { open('r'); }
})();
