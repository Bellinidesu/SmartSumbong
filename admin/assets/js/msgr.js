/* The Inbox's Case chats, the way Messenger's web app behaves (12 Nov 2026). Markup: includes/case_msgr.php.
   - the left list filters as you type and by chip; an unread dot per conversation, read from what this browser last looked at;
   - a conversation opens without a page reload (the address follows), its thread keeps itself current every 15 seconds;
   - Enter sends (Shift+Enter is a new line), the thumbs-up becomes Send once there is text, the emoji button opens the picker;
   - the information panel opens and closes, Mute turns the sound of the case off, Search finds words in the conversation.
   Strict CSP: no inline handlers. The seen map is the chat head's (ss-chat-seen-<case>), so a bubble and this page agree. */
(function () {
  'use strict';
  var root = document.getElementById('mg');
  if (!root) { return; }
  var list = document.getElementById('mg-list'), detail = document.getElementById('mg-detail'), qIn = document.getElementById('mg-q'), none = document.getElementById('mg-nomatch');
  var tr = function (en, fil) { return typeof window.T === 'function' ? window.T(en, fil) : en; };
  var ts = function (s) { var n = Date.parse(s || ''); return isNaN(n) ? 0 : n; };
  var filter = 'all', sending = 0, polling = null;
  var kInfo = 'ss-msgr-info';

  function rd(k, d) { try { var v = JSON.parse(localStorage.getItem(k)); return v && typeof v === 'object' ? v : d; } catch (e) { return d; } }
  function wr(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* private window */ } }
  function seenOf(id) { return rd('ss-chat-seen-' + id, {}); }
  function setSeen(id, conv, t) { var c = window.ssChatCore; if (c) { c.store.setSeen(id, conv, t); return; } var m = seenOf(id); m[conv] = t; wr('ss-chat-seen-' + id, m); }
  function core() { return window.ssChatCore || null; }
  function soundOn(id) { var c = core(); return c ? c.soundFor(id) : true; }

  /* ---------- the list: unread, filters, search ---------- */
  function unreadN(row) {
    var d; try { d = JSON.parse(row.getAttribute('data-feed') || '{}'); } catch (e) { return 0; }
    var id = row.getAttribute('data-report'), conv = row.getAttribute('data-conv'), seen = seenOf(id), n = 0;
    var since = seen[conv] ? ts(seen[conv]) : (d.out && d.out[conv] ? ts(d.out[conv]) : 0);
    (d.in || []).forEach(function (m) { if (ts(m.ts) > since) { n++; } });
    return n;
  }
  function rows() { return [].slice.call(list.querySelectorAll('[data-mg-row]')); }
  function paint() {
    var total = 0, q = (qIn.value || '').trim().toLowerCase(), shown = 0;
    rows().forEach(function (r) {
      var n = r.classList.contains('mg-sel') ? 0 : unreadN(r); total += n;
      r.classList.toggle('mg-unread', n > 0); r.querySelector('.mg-udot').hidden = n === 0; r.querySelector('.mg-usr').hidden = n === 0;
      var ok = (!q || (r.getAttribute('data-search') || '').indexOf(q) >= 0) && (filter !== 'unread' || n > 0) && (filter !== 'mine' || r.getAttribute('data-mine') === '1');
      r.hidden = !ok; if (ok) { shown++; }
    });
    if (rows().length) { none.textContent = tr('No chats match.', 'Walang tumutugong chat.'); none.hidden = shown > 0; } else { none.hidden = false; }
    var b = document.getElementById('ib-chats-n'); if (b) { b.textContent = total > 9 ? '9+' : String(total); b.hidden = total === 0; }
  }
  qIn.addEventListener('input', paint);
  [].forEach.call(root.querySelectorAll('.mg-chip'), function (c) {
    c.addEventListener('click', function () {
      filter = c.getAttribute('data-f');
      [].forEach.call(root.querySelectorAll('.mg-chip'), function (x) { var on = x === c; x.classList.toggle('p-on', on); x.setAttribute('aria-pressed', on ? 'true' : 'false'); });
      paint();
    });
  });
  document.addEventListener('ss-chat-seen', paint);

  /* ---------- opening a conversation without reloading the page ---------- */
  function selected() { return list.querySelector('.mg-sel'); }
  function bindDetail() {
    var c = detail.querySelector('.mg-center'); if (!c) { return; }
    var msgs = c.querySelector('.mg-msgs'); if (msgs) { msgs.scrollTop = msgs.scrollHeight; }
    markSeen();
    applyInfo();
    paintMute();
  }
  function markSeen() {
    var c = detail.querySelector('.mg-center'); if (!c) { return; }
    var last = [].slice.call(c.querySelectorAll('.mg-row, .mg-sys')).pop();
    setSeen(c.getAttribute('data-report'), c.getAttribute('data-conv'), last ? last.getAttribute('data-ts') : new Date().toISOString());
    document.dispatchEvent(new Event('ss-chat-seen'));
  }
  function open(row, push) {
    var r = row.getAttribute('data-report'), k = row.getAttribute('data-conv');
    rows().forEach(function (x) { var on = x === row; x.classList.toggle('mg-sel', on); if (on) { x.setAttribute('aria-current', 'true'); } else { x.removeAttribute('aria-current'); } });
    var url = 'inbox.php?app=chats&c=' + encodeURIComponent(r) + '&k=' + encodeURIComponent(k);
    if (push) { history.pushState({ r: r, k: k }, '', url); }
    root.classList.add('mg-showing');
    detail.classList.add('mg-open');
    fetch(url + '&part=detail', { credentials: 'same-origin', headers: { 'Accept': 'text/html' } })
      .then(function (x) { return x.ok ? x.text() : Promise.reject(x.status); })
      .then(function (h) { detail.innerHTML = h; bindDetail(); paint(); var t = detail.querySelector('textarea'); if (t && window.innerWidth > 900) { t.focus(); } })
      .catch(function () { /* the link is a real link: a reload shows it */ location.href = url; });
  }
  list.addEventListener('click', function (e) {
    var row = e.target.closest('[data-mg-row]');
    if (!row || e.metaKey || e.ctrlKey || e.shiftKey || e.button) { return; }
    e.preventDefault(); open(row, true);
  });
  window.addEventListener('popstate', function () {
    var p = new URLSearchParams(location.search), r = p.get('c'), k = p.get('k');
    var row = rows().filter(function (x) { return x.getAttribute('data-report') === r && (!k || x.getAttribute('data-conv') === k); })[0];
    if (row) { open(row, false); } else { root.classList.remove('mg-showing'); detail.classList.remove('mg-open'); rows().forEach(function (x) { x.classList.remove('mg-sel'); }); paint(); }
  });

  /* ---------- the thread: grow, send, stay current ---------- */
  function grow(t) { t.style.height = 'auto'; t.style.height = Math.min(t.scrollHeight, 140) + 'px'; }
  function sendText(form, text) {
    var msgs = detail.querySelector('.mg-msgs'), first = msgs.querySelector('.mg-none'); if (first) { first.remove(); }
    var prev = msgs.lastElementChild;
    var row = document.createElement('div'), b = document.createElement('div'), p = document.createElement('p');
    row.className = 'mg-row mg-out mg-only mg-sending'; b.className = 'mg-b'; p.textContent = text; b.appendChild(p); row.appendChild(b);
    if (prev && prev.classList.contains('mg-out')) { prev.className = prev.className.replace(/mg-(only|last)/, function (m) { return m === 'mg-only' ? 'mg-first' : 'mg-mid'; }); row.className = 'mg-row mg-out mg-last mg-sending'; }
    msgs.appendChild(row); msgs.scrollTop = msgs.scrollHeight;
    var fd = new FormData(form); fd.set('body', text);
    sending++;
    fetch(form.getAttribute('action'), { method: 'POST', body: fd, credentials: 'same-origin', headers: { 'X-Chat': '1', 'Accept': 'application/json' } })   // getAttribute: the field named "action" shadows form.action
      .then(function (r) { return r.json(); })
      .then(function (j) { if (!j.ok) { throw new Error(j.text || ''); } row.classList.remove('mg-sending'); })
      .catch(function (err) {
        row.classList.remove('mg-sending'); row.classList.add('mg-failed');
        var f = document.createElement('button'); f.type = 'button'; f.className = 'mg-retry'; f.setAttribute('data-mg', 'retry'); f.setAttribute('data-text', text);
        f.textContent = tr('Not sent. Click to try again.', 'Hindi naipadala. I-click para subukan muli.') + (err && err.message ? ' ' + err.message : ''); row.appendChild(f);
      })
      .then(function () { sending--; if (!sending) { refreshThread(true); } });
  }
  function refreshThread(force) {
    var c = detail.querySelector('.mg-center'); if (!c || (sending && !force)) { return Promise.resolve(); }
    var msgs = c.querySelector('.mg-msgs'), near = msgs.scrollHeight - msgs.scrollTop - msgs.clientHeight < 90, top = msgs.scrollTop;
    var failed = [].slice.call(msgs.querySelectorAll('.mg-failed')).map(function (n) { return n.outerHTML; });
    var before = msgs.querySelectorAll('.mg-in').length;
    return fetch(c.getAttribute('data-thread-url'), { credentials: 'same-origin', headers: { 'Accept': 'text/html' } })
      .then(function (x) { return x.ok ? x.text() : Promise.reject(x.status); })
      .then(function (h) {
        if (detail.querySelector('.mg-center') !== c) { return; }          // another conversation was opened meanwhile
        msgs.innerHTML = h; failed.forEach(function (f) { msgs.insertAdjacentHTML('beforeend', f); });
        if (near) { msgs.scrollTop = msgs.scrollHeight; } else { msgs.scrollTop = top; }
        if (msgs.querySelectorAll('.mg-in').length > before && document.hasFocus() && soundOn(c.getAttribute('data-report')) && core()) { core().ding(); }
        markSeen();
      }).catch(function () { /* the next tick tries again */ });
  }
  function refreshList() {
    var sel = selected(), selKey = sel ? sel.getAttribute('data-key') : '';
    var old = {}; rows().forEach(function (r) { old[r.getAttribute('data-key')] = r.getAttribute('data-feed'); });
    return fetch(root.getAttribute('data-list-url') + (sel ? '&c=' + encodeURIComponent(sel.getAttribute('data-report')) + '&k=' + encodeURIComponent(sel.getAttribute('data-conv')) : ''), { credentials: 'same-origin', headers: { 'Accept': 'text/html' } })
      .then(function (x) { return x.ok ? x.text() : Promise.reject(x.status); })
      .then(function (h) {
        var top = list.scrollTop; list.innerHTML = h; list.scrollTop = top;
        rows().forEach(function (r) {   // a conversation other than the open one has something new: a ding if that case's sound is on
          var key = r.getAttribute('data-key'), was = old[key];
          if (key !== selKey && was !== undefined && was !== r.getAttribute('data-feed') && unreadN(r) > 0 && soundOn(r.getAttribute('data-report')) && core()) { core().ding(); }
        });
        paint();
      }).catch(function () { /* the next tick tries again */ });
  }
  polling = setInterval(function () { if (!document.hidden) { refreshList(); refreshThread(false); } }, 15000);
  document.addEventListener('visibilitychange', function () { if (!document.hidden) { refreshList(); refreshThread(false); } });

  detail.addEventListener('input', function (e) {
    var t = e.target; if (t.tagName !== 'TEXTAREA') { return; }
    grow(t); t.closest('form').classList.toggle('has-text', t.value.trim() !== '');
  });
  detail.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && e.target.tagName === 'TEXTAREA') { e.preventDefault(); e.target.closest('form').requestSubmit(); }
  });
  detail.addEventListener('submit', function (e) {
    var f = e.target.closest('[data-mg="form"]'); if (!f) { return; }
    e.preventDefault();
    var t = f.querySelector('textarea'), text = t.value.trim();
    if (!text) { return; }
    t.value = ''; grow(t); f.classList.remove('has-text');
    sendText(f, text); t.focus();
  });

  /* ---------- clicks inside the conversation: copy, retry, the information panel, mute, search, emoji, back ---------- */
  function toast(text) {
    var n = document.createElement('div'); n.className = 'mg-toast'; n.setAttribute('role', 'status'); n.textContent = text; document.body.appendChild(n);
    setTimeout(function () { n.remove(); }, 1600);
  }
  function applyInfo() {
    var on = rd(kInfo, null); on = on === null ? window.innerWidth >= 1380 : !!on.v;
    detail.classList.toggle('mg-noinfo', !on);
    var b = detail.querySelector('[data-mg="info"]'); if (b) { b.setAttribute('aria-pressed', on ? 'true' : 'false'); }
  }
  function paintMute() {
    var c = detail.querySelector('.mg-center'), b = detail.querySelector('[data-mg="mute"]'); if (!c || !b) { return; }
    var muted = !soundOn(c.getAttribute('data-report'));
    b.setAttribute('aria-checked', muted ? 'true' : 'false');                // Hide Alerts, a switch
  }
  function find(q) {
    var msgs = detail.querySelector('.mg-msgs'), n = 0, first = null; q = (q || '').trim().toLowerCase();
    [].forEach.call(msgs.querySelectorAll('.mg-row'), function (r) {
      var hit = q !== '' && (r.querySelector('.mg-b') || r).textContent.toLowerCase().indexOf(q) >= 0;
      r.classList.toggle('mg-hit', hit); r.classList.toggle('mg-dim', q !== '' && !hit); if (hit) { n++; first = first || r; }
    });
    if (first) { first.scrollIntoView({ block: 'center' }); }
  }
  detail.addEventListener('click', function (e) {
    var x = e.target.closest('[data-mg]'); if (!x) { return; }
    var a = x.getAttribute('data-mg'), c = detail.querySelector('.mg-center');
    if (a === 'info') { var on = x.getAttribute('aria-pressed') !== 'true'; wr(kInfo, { v: on }); applyInfo(); }
    else if (a === 'copy') { var b = x.closest('.mg-row').querySelector('.mg-b'); try { navigator.clipboard.writeText(b.innerText.trim()).then(function () { toast(tr('Copied', 'Nakopya')); }); } catch (err) { toast(tr('Could not copy', 'Hindi nakopya')); } }
    else if (a === 'retry') { var f = detail.querySelector('[data-mg="form"]'), t = f && f.querySelector('textarea'); if (t) { t.value = x.getAttribute('data-text') || ''; grow(t); f.classList.add('has-text'); t.focus(); } x.closest('.mg-row').remove(); }
    else if (a === 'mute') { var id = c.getAttribute('data-report'); if (core()) { core().store.patch(id, { sound: !soundOn(id), t: c.getAttribute('data-tracking') || '' }); } paintMute(); }
    else if (a === 'find') { var bar = detail.querySelector('.mg-find'); bar.hidden = false; var i = bar.querySelector('input'); i.focus(); }
    else if (a === 'findx') { var bar2 = detail.querySelector('.mg-find'); bar2.hidden = true; bar2.querySelector('input').value = ''; find(''); }
    else if (a === 'emoji') {
      var t2 = detail.querySelector('.mg-form textarea');
      if (window.ssEmoji && t2) { window.ssEmoji.open(x, function (em) { var s = t2.selectionStart || t2.value.length, en = t2.selectionEnd || s; t2.value = t2.value.slice(0, s) + em + t2.value.slice(en); t2.focus(); t2.selectionStart = t2.selectionEnd = s + em.length; t2.dispatchEvent(new Event('input', { bubbles: true })); }); }
    }
    else if (a === 'back') { e.preventDefault(); root.classList.remove('mg-showing'); detail.classList.remove('mg-open'); history.pushState({}, '', 'inbox.php?app=chats'); rows().forEach(function (r) { r.classList.remove('mg-sel'); }); paint(); }
  });
  detail.addEventListener('input', function (e) { if (e.target.classList && e.target.classList.contains('mg-findin')) { find(e.target.value); } });

  document.addEventListener('ss-chat-change', paintMute);
  /* where this person was, from the database (each row carries it as feed.st), joined to what this browser remembers */
  function joinState() {
    var c = core(); if (!c || !c.merge) { return; }
    var done = {};
    rows().forEach(function (r) { var id = r.getAttribute('data-report'); if (done[id]) { return; } done[id] = 1; try { c.merge(id, JSON.parse(r.getAttribute('data-feed') || '{}').st); } catch (e) { /* a row without it */ } });
    paint(); paintMute();
  }
  if (core()) { joinState(); } else { document.addEventListener('ss-chat-ready', joinState, { once: true }); }
  paint(); if (detail.querySelector('.mg-center')) { root.classList.add('mg-showing'); bindDetail(); }
})();
