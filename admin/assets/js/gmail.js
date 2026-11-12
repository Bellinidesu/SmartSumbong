/* BarangayMail, the way Gmail's web app works (12 Nov 2026). The page is a shell (inbox.php?app=mail); this draws and drives it, asking
   mail.php for the rows, the conversations and the people, and sending every change through it (the 0173 functions: a person's own marks,
   labels and drafts). Folders and labels in a rail, a search box with Gmail's operators, a toolbar that changes with the selection,
   conversations with stars and hover actions, an Undo bar after archive / delete / snooze, snooze times, labels, a reading view with
   older messages folded, replies inline or in floating compose windows that keep drafts as you type (Cc, Bcc, formatting marks, the case
   to attach, Undo send), and Gmail's keys (c / j k o u x s e # r a f z, g then i s t d a). Strict CSP: no inline handlers. */
(function () {
  'use strict';
  var root = document.getElementById('gm');
  if (!root || !window.GMC) { return; }
  var CSRF = root.getAttribute('data-csrf'), DOOR = 'mail.php', ME = root.getAttribute('data-me'), MYNAME = root.getAttribute('data-name') || '';
  var tr = function (en, fil) { return typeof window.T === 'function' ? window.T(en, fil) : en; };
  var $ = function (s, r) { return (r || root).querySelector(s); };
  var $$ = function (s, r) { return [].slice.call((r || root).querySelectorAll(s)); };
  function el(tag, cls, text) { var n = document.createElement(tag); if (cls) { n.className = cls; } if (text != null) { n.textContent = text; } return n; }
  function csv(s) { return s ? String(s).split(',').filter(Boolean) : []; }
  function uniq(a) { return a.filter(function (x, i) { return a.indexOf(x) === i; }); }
  var IC = {
    archive: '<rect x="3" y="4" width="18" height="4" rx="1"/><path d="M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8M10 12h4"/>',
    trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6"/>',
    mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/>',
    open: '<rect x="3" y="7" width="18" height="12" rx="2"/><path d="M3 9l9-6 9 6M3 9l9 6 9-6"/>',
    clock: '<circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2M5 4 3 6M19 4l2 2"/>',
    label: '<path d="M3 12V5a2 2 0 0 1 2-2h7l9 9-9 9z"/><circle cx="8" cy="8" r="1.2"/>',
    back: '<path d="M15 5l-7 7 7 7"/>', refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7"/>',
    more: '<circle cx="12" cy="5" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="12" cy="19" r="1.4"/>',
    prev: '<path d="M15 5l-7 7 7 7"/>', next: '<path d="M9 5l7 7-7 7"/>', inbox: '<path d="M3 13l3-8h12l3 8v6H3zM3 13h5l1 3h6l1-3h5"/>',
    star: '<path d="M12 3.2l2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 17l-5.4 2.9 1.1-6.1L3.2 9.6l6.1-.8z"/>', send: '<path d="M3 20l18-8L3 4v6l11 2-11 2z"/>',
    pencil: '<path d="M4 20h4L19 9l-4-4L4 16z"/>', x: '<path d="M6 6l12 12M18 6L6 18"/>', min: '<path d="M6 18h12"/>', max: '<path d="M4 4h6M4 4v6M20 4h-6M20 4v6M4 20h6M4 20v-6M20 20h-6M20 20v-6"/>',
    bold: '<path d="M7 5h6a3.5 3.5 0 0 1 0 7H7zM7 12h7a3.5 3.5 0 0 1 0 7H7z"/>', italic: '<path d="M10 5h8M6 19h8M14 5l-4 14"/>',
    ul: '<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r="1"/><circle cx="4.5" cy="12" r="1"/><circle cx="4.5" cy="18" r="1"/>',
    ol: '<path d="M10 6h10M10 12h10M10 18h10M4 5l1.5-1v4M4 11h2.5L4 14h2.5M4 17h2.5l-1 1.5 1 1.5H4"/>',
    quote: '<path d="M4 6h5v5H6a2 2 0 0 0 2 3M13 6h5v5h-3a2 2 0 0 0 2 3"/>', link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
    case: '<path d="M7 3h7l5 5v13H7zM14 3v5h5"/>', face: '<circle cx="12" cy="12" r="9"/><path d="M8.5 14.2c.9 1.1 2 1.7 3.5 1.7s2.6-.6 3.5-1.7"/>', fmt: '<path d="M5 19 12 5l7 14M8 14h8"/>',
    check: '<path d="M5 12l5 5 9-10"/>', pop: '<path d="M14 4h6v6M20 4l-8 8M10 6H5a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-5"/>', caret: '<path d="M7 10l5 5 5-5"/>'
  };
  function ic(name, size) { var s = size || 18; return '<svg viewBox="0 0 24 24" width="' + s + '" height="' + s + '" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + IC[name] + '</svg>'; }

  /* ---------- the door ---------- */
  function get(p) {
    return fetch(DOOR + '?' + new URLSearchParams(p).toString(), { credentials: 'same-origin', headers: { 'Accept': 'application/json' } })
      .then(function (r) { return r.json().catch(function () { return { ok: false, text: tr('Something went wrong.', 'Nagkaproblema.') }; }); })
      .catch(function () { return { ok: false, text: tr('Could not reach the server.', 'Hindi maabot ang server.') }; });
  }
  function post(act, data) {
    return fetch(DOOR, { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' }, body: JSON.stringify(Object.assign({ act: act, csrf: CSRF }, data || {})) })
      .then(function (r) { return r.json().catch(function () { return { ok: false, text: tr('Something went wrong.', 'Nagkaproblema.') }; }); })
      .catch(function () { return { ok: false, text: tr('Could not reach the server.', 'Hindi maabot ang server.') }; });
  }

  /* ---------- the little bar at the bottom left: "Conversation archived. Undo" ---------- */
  var snackEl = $('#gm-snack'), snackT = null, lastUndo = null;
  function snack(text, undo, link) {
    snackEl.style.left = Math.max(24, Math.round(root.getBoundingClientRect().left) + 16) + 'px';   // clear of the portal sidebar, on the mail's own edge
    snackEl.textContent = ''; snackEl.appendChild(el('span', '', text)); lastUndo = undo || null;
    if (undo) { var u = el('button', 'gm-snk-b', tr('Undo', 'I-undo')); u.type = 'button'; u.addEventListener('click', function () { var f = lastUndo; hideSnack(); if (f) { f(); } }); snackEl.appendChild(u); }
    if (link) { var a = el('button', 'gm-snk-b', link.label); a.type = 'button'; a.addEventListener('click', function () { hideSnack(); link.fn(); }); snackEl.appendChild(a); }
    var x = el('button', 'gm-snk-x', '✕'); x.type = 'button'; x.setAttribute('aria-label', tr('Close', 'Isara')); x.addEventListener('click', hideSnack); snackEl.appendChild(x);
    snackEl.hidden = false; clearTimeout(snackT); snackT = setTimeout(hideSnack, 8000);
  }
  function hideSnack() { snackEl.hidden = true; clearTimeout(snackT); lastUndo = null; }

  /* ---------- menus ---------- */
  var menu = null, menuBack = null;
  function closeMenu(back) {
    if (!menu) { return; }
    menu.remove(); menu = null; document.removeEventListener('pointerdown', menuOut, true); document.removeEventListener('keydown', menuKey, true);
    if (back && menuBack) { menuBack.focus(); }
  }
  function menuOut(e) { if (menu && !menu.contains(e.target)) { closeMenu(false); } }
  function menuKey(e) {
    if (!menu) { return; }
    var items = $$('.gm-mi', menu), i = items.indexOf(document.activeElement);
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeMenu(true); }
    else if (e.key === 'ArrowDown') { e.preventDefault(); items[(i + 1) % items.length].focus(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); items[(i - 1 + items.length) % items.length].focus(); }
  }
  function openMenu(anchor, build) {
    closeMenu(false); menuBack = anchor;
    var m = el('div', 'gm-menu'); m.setAttribute('role', 'menu'); build(m);
    document.body.appendChild(m);
    var r = anchor.getBoundingClientRect(), w = m.offsetWidth, h = m.offsetHeight;
    m.style.left = Math.max(8, Math.min(r.left, window.innerWidth - w - 8)) + 'px';
    m.style.top = (r.bottom + h + 12 > window.innerHeight ? Math.max(8, r.top - h - 4) : r.bottom + 4) + 'px';
    menu = m; document.addEventListener('pointerdown', menuOut, true); document.addEventListener('keydown', menuKey, true);
    var f = $('.gm-mi', m); if (f) { f.focus(); }
    return m;
  }
  function mitem(m, label, fn, opts) {
    var b = el('button', 'gm-mi'); b.type = 'button'; b.setAttribute('role', opts && opts.check !== undefined ? 'menuitemcheckbox' : 'menuitem');
    if (opts && opts.check !== undefined) { b.setAttribute('aria-checked', opts.check ? 'true' : 'false'); b.appendChild(el('span', 'gm-tick', opts.check ? '✓' : '')); }
    b.appendChild(el('span', 'gm-ml', label)); if (opts && opts.hint) { b.appendChild(el('small', '', opts.hint)); }
    b.addEventListener('click', function () { if (!opts || !opts.stay) { closeMenu(false); } fn(b); }); m.appendChild(b); return b;
  }
  function msep(m) { m.appendChild(el('div', 'gm-msep')); }

  /* ---------- a small question: a name for a label, a time to snooze to ---------- */
  function ask(title, fields, okLabel, cb) {
    var back = el('div', 'gm-dlg-back'), d = el('div', 'gm-dlg'); d.setAttribute('role', 'dialog'); d.setAttribute('aria-modal', 'true'); d.setAttribute('aria-label', title);
    d.appendChild(el('h3', '', title));
    var inputs = fields.map(function (f) { var l = el('label', 'gm-dlg-l', f.label), i = el('input'); i.type = f.type || 'text'; i.value = f.value || ''; if (f.max) { i.maxLength = f.max; } if (f.min) { i.min = f.min; } l.appendChild(i); d.appendChild(l); return i; });
    var row = el('div', 'gm-dlg-r'), no = el('button', 'gm-btn', tr('Cancel', 'Kanselahin')), ok = el('button', 'gm-btn gm-btn--blue', okLabel);
    no.type = 'button'; ok.type = 'button'; row.appendChild(no); row.appendChild(ok); d.appendChild(row); back.appendChild(d); document.body.appendChild(back);
    function close() { back.remove(); document.removeEventListener('keydown', key, true); }
    function go() { var v = inputs.map(function (i) { return i.value; }); if (v[0] === '' ) { inputs[0].focus(); return; } close(); cb(v); }
    function key(e) { if (e.key === 'Escape') { e.stopPropagation(); close(); } else if (e.key === 'Enter') { e.preventDefault(); go(); } }
    no.addEventListener('click', close); ok.addEventListener('click', go); back.addEventListener('pointerdown', function (e) { if (e.target === back) { close(); } });
    document.addEventListener('keydown', key, true); inputs[0].focus(); inputs[0].select();
  }

  /* ---------- the state ---------- */
  var S = { folder: 'inbox', q: '', tab: 'people', page: 1, view: 'list', counts: { inbox: 0, updates: 0, drafts: 0, labels: {} }, labels: [], total: 0, from: 0, to: 0, cur: -1, thread: null, order: [], busy: false };
  var listEl = $('#gm-list'), readerEl = $('#gm-reader'), tbEl = $('#gm-tb'), tabsEl = $('#gm-tabs'), qIn = $('#gm-q');
  var FOLDERS = { inbox: tr('Inbox', 'Inbox'), starred: tr('Starred', 'May bituin'), snoozed: tr('Snoozed', 'Naka-snooze'), sent: tr('Sent', 'Naipadala'), drafts: tr('Drafts', 'Mga draft'), all: tr('All Mail', 'Lahat ng mail'), trash: tr('Trash', 'Basurahan') };
  function rows() { return $$('.gm-row', listEl); }
  function selRows() { return rows().filter(function (r) { return r.querySelector('.gm-ck input').checked; }); }

  /* ---------- the rail ---------- */
  function paintRail() {
    $$('.gm-nav a').forEach(function (a) {
      var f = a.getAttribute('data-f'), on = S.view === 'list' && !S.q && f === S.folder;
      a.classList.toggle('on', on); if (on) { a.setAttribute('aria-current', 'page'); } else { a.removeAttribute('aria-current'); }
      var n = a.querySelector('.gm-n'); if (!n) { return; }
      var v = f === 'inbox' ? S.counts.inbox + S.counts.updates : (f === 'drafts' ? S.counts.drafts : 0);
      n.textContent = v ? String(v) : ''; n.hidden = !v;
    });
    var box = $('#gm-labels'); box.textContent = '';
    S.labels.forEach(function (l) {
      var a = el('a', 'gm-lab' + (S.folder === 'label:' + l.id && !S.q && S.view === 'list' ? ' on' : '')); a.href = '#label/' + l.id;
      var dot = el('i', 'gm-ld'); dot.style.background = l.colour; a.appendChild(dot); a.appendChild(el('span', 'gm-lname', l.name));
      var n = el('span', 'gm-n', l.n ? String(l.n) : ''); n.hidden = !l.n; a.appendChild(n);
      var mb = el('button', 'gm-lmore'); mb.type = 'button'; mb.innerHTML = ic('more', 16); mb.setAttribute('aria-label', tr('Label options for ', 'Mga opsyon ng label na ') + l.name);
      mb.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); labelMenu(mb, l); }); a.appendChild(mb); box.appendChild(a);
    });
    if (!S.labels.length) { box.appendChild(el('p', 'gm-lnone', tr('No labels yet.', 'Wala pang label.'))); }
    tabsEl.hidden = !(S.view === 'list' && S.folder === 'inbox' && !S.q);
    $$('button', tabsEl).forEach(function (b) { var u = b.getAttribute('data-tab') === 'updates', on = (S.tab === 'updates') === u; b.classList.toggle('on', on); b.setAttribute('aria-selected', on ? 'true' : 'false');
      var c = b.querySelector('.gm-n'); var v = u ? S.counts.updates : S.counts.inbox; c.textContent = v ? v + ' ' + tr('new', 'bago') : ''; c.hidden = !v; });
    var t = FOLDERS[S.folder] || (S.folder.indexOf('label:') === 0 ? (S.labels.filter(function (l) { return 'label:' + l.id === S.folder; })[0] || { name: '' }).name : '');
    document.title = (S.q ? tr('Search', 'Paghahanap') : t) + ' – BarangayMail';
  }
  function labelMenu(anchor, l) {
    openMenu(anchor, function (m) {
      mitem(m, tr('Edit', 'I-edit'), function () { ask(tr('Rename label', 'Palitan ang pangalan ng label'), [{ label: tr('Name', 'Pangalan'), value: l.name, max: 40 }, { label: tr('Colour', 'Kulay'), type: 'color', value: l.colour }], tr('Save', 'I-save'),
        function (v) { post('label_save', { id: l.id, name: v[0], colour: v[1] }).then(function (j) { if (!j.ok) { snack(j.text); } loadList(true); }); }); });
      mitem(m, tr('Remove label', 'Alisin ang label'), function () { post('label_delete', { id: l.id }).then(function () { if (S.folder === 'label:' + l.id) { go('#inbox'); } else { loadList(true); } snack(tr('The label was removed.', 'Inalis ang label.')); }); });
    });
  }

  /* ---------- the toolbar ---------- */
  function tbtn(icon, label, fn, extra) {
    var b = el('button', 'gm-tbtn' + (extra ? ' ' + extra : '')); b.type = 'button'; b.innerHTML = ic(icon); b.title = label; b.setAttribute('aria-label', label); b.addEventListener('click', function () { fn(b); }); return b;
  }
  function selectAllBtn() {
    var w = el('span', 'gm-sa'), cb = el('input'); cb.type = 'checkbox'; cb.setAttribute('aria-label', tr('Select all', 'Piliin lahat'));
    var n = selRows().length, all = rows().length; cb.checked = n > 0 && n === all; cb.indeterminate = n > 0 && n < all;
    cb.addEventListener('change', function () { rows().forEach(function (r) { setSel(r, cb.checked); }); paintToolbar(); });
    var c = el('button', 'gm-tbtn gm-tbtn--caret'); c.type = 'button'; c.innerHTML = ic('caret', 16); c.setAttribute('aria-label', tr('Select options', 'Mga opsyon sa pagpili')); c.setAttribute('aria-haspopup', 'menu');
    c.addEventListener('click', function () {
      openMenu(c, function (m) {
        [[tr('All', 'Lahat'), function () { return true; }], [tr('None', 'Wala'), function () { return false; }], [tr('Read', 'Nabasa na'), function (r) { return !r.classList.contains('gm-unread'); }], [tr('Unread', 'Hindi pa nabasa'), function (r) { return r.classList.contains('gm-unread'); }],
         [tr('Starred', 'May bituin'), function (r) { return r.getAttribute('data-star') === '1'; }], [tr('Unstarred', 'Walang bituin'), function (r) { return r.getAttribute('data-star') !== '1'; }]].forEach(function (x) {
          mitem(m, x[0], function () { rows().forEach(function (r) { setSel(r, x[1](r)); }); paintToolbar(); }); });
      });
    });
    w.appendChild(cb); w.appendChild(c); return w;
  }
  function setSel(r, on) { r.querySelector('.gm-ck input').checked = on; r.classList.toggle('sel', on); }
  function pager() {
    var p = el('div', 'gm-pg');
    var txt = S.total ? S.from + '–' + S.to + ' ' + tr('of', 'sa') + ' ' + S.total : '0';
    p.appendChild(el('span', 'gm-pgt', txt));
    var a = tbtn('prev', tr('Newer', 'Mas bago'), function () { S.page--; loadList(); }); a.disabled = S.page <= 1;
    var b = tbtn('next', tr('Older', 'Mas luma'), function () { S.page++; loadList(); }); b.disabled = S.to >= S.total;
    p.appendChild(a); p.appendChild(b); return p;
  }
  function paintToolbar() {
    tbEl.textContent = ''; tbEl.hidden = false;
    var l = el('div', 'gm-tb-l');
    if (S.view === 'thread') {
      l.appendChild(tbtn('back', tr('Back to ', 'Bumalik sa ') + (FOLDERS[S.folder] || tr('list', 'listahan')), function () { go(backHash()); }));
      var inTrash = S.folder === 'trash';
      if (!inTrash) { l.appendChild(tbtn('archive', tr('Archive', 'I-archive'), function () { threadAct('archive'); })); }
      l.appendChild(tbtn('trash', inTrash ? tr('Move to Inbox', 'Ibalik sa Inbox') : tr('Delete', 'Burahin'), function () { threadAct(inTrash ? 'untrash' : 'trash'); }));
      l.appendChild(el('span', 'gm-tbsep'));
      l.appendChild(tbtn('mail', tr('Mark as unread', 'Markahang hindi pa nababasa'), function () { threadAct('unread'); }));
      l.appendChild(tbtn('clock', tr('Snooze', 'I-snooze'), function (b) { snoozeMenu(b, null); }));
      l.appendChild(tbtn('label', tr('Labels', 'Mga label'), function (b) { labelsPicker(b, null); }));
      tbEl.appendChild(l);
      var p = el('div', 'gm-pg'), i = S.order.indexOf(S.thread ? S.thread.id : '');
      if (i >= 0) { p.appendChild(el('span', 'gm-pgt', (i + 1) + ' ' + tr('of', 'sa') + ' ' + S.order.length)); }
      var nw = tbtn('prev', tr('Newer', 'Mas bago'), function () { go('#t/' + S.order[i - 1]); }); nw.disabled = i <= 0;
      var od = tbtn('next', tr('Older', 'Mas luma'), function () { go('#t/' + S.order[i + 1]); }); od.disabled = i < 0 || i >= S.order.length - 1;
      p.appendChild(nw); p.appendChild(od); tbEl.appendChild(p); return;
    }
    l.appendChild(selectAllBtn());
    var n = selRows().length;
    if (n === 0) {
      l.appendChild(tbtn('refresh', tr('Refresh', 'I-refresh'), function () { loadList(); }));
      l.appendChild(tbtn('more', tr('More', 'Higit pa'), function (b) { openMenu(b, function (m) {
        mitem(m, tr('Mark all as read', 'Markahang nabasa ang lahat'), function () { var ids = []; rows().forEach(function (r) { ids = ids.concat(csv(r.getAttribute('data-u'))); }); if (ids.length) { post('read', { ids: ids, read: true }).then(function () { loadList(true); }); } });
        mitem(m, tr('Select all', 'Piliin lahat'), function () { rows().forEach(function (r) { setSel(r, true); }); paintToolbar(); });
      }); }));
    } else if (S.folder === 'drafts' && !S.q) {
      l.appendChild(tbtn('trash', tr('Discard drafts', 'Itapon ang mga draft'), function () { Promise.all(selRows().map(function (r) { return post('draft_delete', { id: r.getAttribute('data-draft') }); })).then(function () { loadList(true); snack(tr('Drafts discarded.', 'Naitapon ang mga draft.')); }); }));
    } else {
      var inTr = S.folder === 'trash';
      if (!inTr && S.folder !== 'sent') { l.appendChild(tbtn('archive', tr('Archive', 'I-archive'), function () { bulk('archive'); })); }
      if (inTr) { l.appendChild(tbtn('trash', tr('Delete forever', 'Burahin nang tuluyan'), function () { bulk('purge'); })); l.appendChild(tbtn('inbox', tr('Move to Inbox', 'Ibalik sa Inbox'), function () { bulk('untrash'); })); }
      else { l.appendChild(tbtn('trash', tr('Delete', 'Burahin'), function () { bulk('trash'); })); }
      l.appendChild(el('span', 'gm-tbsep'));
      var anyUnread = selRows().some(function (r) { return r.classList.contains('gm-unread'); });
      l.appendChild(tbtn(anyUnread ? 'open' : 'mail', anyUnread ? tr('Mark as read', 'Markahang nabasa') : tr('Mark as unread', 'Markahang hindi pa nababasa'), function () { bulk(anyUnread ? 'read' : 'unread'); }));
      l.appendChild(tbtn('clock', tr('Snooze', 'I-snooze'), function (b) { snoozeMenu(b, null); }));
      l.appendChild(tbtn('label', tr('Labels', 'Mga label'), function (b) { labelsPicker(b, null); }));
      l.appendChild(el('span', 'gm-selcount', n + ' ' + tr('selected', 'napili')));
    }
    tbEl.appendChild(l); tbEl.appendChild(pager());
  }

  /* ---------- the list ---------- */
  function loadList(quiet) {
    var keep = {}; rows().forEach(function (r) { if (r.querySelector('.gm-ck input').checked) { keep[r.getAttribute('data-t') || r.getAttribute('data-draft')] = true; } });
    if (!quiet) { listEl.setAttribute('aria-busy', 'true'); }
    return get({ v: 'list', f: S.folder, q: S.q, tab: S.tab, p: String(S.page) }).then(function (j) {
      listEl.removeAttribute('aria-busy');
      if (!j.ok) { listEl.textContent = ''; var em = el('p', 'gm-empty', j.text || tr('Could not load your mail.', 'Hindi ma-load ang mail mo.')); em.setAttribute('role', 'listitem'); listEl.appendChild(em); return; }
      S.total = j.total; S.page = j.page; S.from = j.from; S.to = j.to; S.counts = j.counts; S.labels = j.labels;
      listEl.innerHTML = j.html;
      S.order = rows().map(function (r) { return r.getAttribute('data-t'); }).filter(Boolean);
      rows().forEach(function (r) { var k = r.getAttribute('data-t') || r.getAttribute('data-draft'); if (keep[k]) { setSel(r, true); } });
      if (S.cur >= 0 && rows()[S.cur]) { rows()[S.cur].classList.add('cur'); }
      paintRail(); paintToolbar(); paintTimes();
    });
  }
  function paintTimes() { /* the countdown on a question that waits for an answer */
    $$('.gm-q-due[data-due]').forEach(function (p) {
      var left = Math.floor((new Date(p.getAttribute('data-due')).getTime() - Date.now()) / 1000), b = p.querySelector('b');
      b.textContent = left <= 0 ? tr('time is up', 'tapos na ang oras') : Math.floor(left / 60) + ':' + ('0' + (left % 60)).slice(-2) + ' ' + tr('left', 'natitira');
    });
  }
  setInterval(paintTimes, 1000);

  /* actions on conversations: archive, delete, snooze, read, unread, star, label; the ones that take a conversation out of the list say so with Undo */
  var DO = {
    archive: { f: { archived: true }, back: { archived: false }, msg: ['Conversation archived.', '%d conversations archived.'], gone: true },
    trash: { f: { trashed: true }, back: { trashed: false }, msg: ['Conversation moved to Trash.', '%d conversations moved to Trash.'], gone: true },
    untrash: { f: { trashed: false, archived: false }, back: { trashed: true }, msg: ['Conversation moved to Inbox.', '%d conversations moved to Inbox.'], gone: true },
    purge: { f: { purged: true }, msg: ['Conversation deleted forever.', '%d conversations deleted forever.'], gone: true },
    inbox: { f: { archived: false, trashed: false }, back: { archived: true }, msg: ['Conversation moved to Inbox.', '%d conversations moved to Inbox.'], gone: true }
  };
  function plural(m, n) { return n === 1 ? m[0] : m[1].replace('%d', String(n)); }
  function bulk(kind, list) {
    var rs = list || selRows(); if (!rs.length) { return; }
    var b = uniq(rs.reduce(function (a, r) { return a.concat(csv(r.getAttribute('data-b'))); }, [])), n = rs.length;
    if (kind === 'read' || kind === 'unread') {
      var ids = uniq(rs.reduce(function (a, r) { return a.concat(csv(r.getAttribute(kind === 'read' ? 'data-u' : 'data-r'))); }, []));
      post('read', { ids: ids, read: kind === 'read' }).then(function () { snack(kind === 'read' ? tr('Marked as read.', 'Namarkahang nabasa.') : tr('Marked as unread.', 'Namarkahang hindi pa nababasa.'), function () { post('read', { ids: ids, read: kind !== 'read' }).then(function () { loadList(true); }); }); loadList(true); });
      return;
    }
    var d = DO[kind]; if (!d) { return; }
    if (kind === 'purge' && !window.confirm(tr('Delete these conversations forever? This cannot be undone.', 'Burahin nang tuluyan ang mga usapang ito? Hindi na ito maibabalik.'))) { return; }
    if (d.gone) { rs.forEach(function (r) { r.remove(); }); }
    post('flag', Object.assign({ batches: b }, d.f)).then(function (j) {
      if (!j.ok) { snack(j.text); loadList(true); return; }
      snack(tr(plural(d.msg, n), plural(d.msg, n)), d.back ? function () { post('flag', Object.assign({ batches: b }, d.back)).then(function () { loadList(true); }); } : null);
      loadList(true);
    });
  }
  function starRow(r) {
    var on = r.getAttribute('data-star') !== '1', btn = r.querySelector('.gm-star');
    r.setAttribute('data-star', on ? '1' : '0'); btn.classList.toggle('on', on); btn.setAttribute('aria-pressed', on ? 'true' : 'false');
    post('flag', { batches: csv(r.getAttribute('data-b')), starred: on }).then(function (j) { if (!j.ok) { snack(j.text); loadList(true); } else if (S.folder === 'starred' && !on) { loadList(true); } });
  }
  function snoozeMenu(anchor, rowsArg) {
    var d = new Date(), at = function (days, h, m) { var x = new Date(d.getFullYear(), d.getMonth(), d.getDate() + days, h, m || 0, 0); return x; };
    var opts = [];
    if (d.getHours() < 17) { opts.push([tr('Later today', 'Mamaya ngayon'), at(0, 18), '6:00 PM']); }
    opts.push([tr('Tomorrow', 'Bukas'), at(1, 8), '8:00 AM']);
    var dow = d.getDay(); if (dow !== 0 && dow !== 6) { opts.push([tr('This weekend', 'Ngayong weekend'), at(6 - dow, 8), tr('Sat 8:00 AM', 'Sab 8:00 AM')]); }
    opts.push([tr('Next week', 'Susunod na linggo'), at(((8 - dow) % 7) || 7, 8), tr('Mon 8:00 AM', 'Lun 8:00 AM')]);
    openMenu(anchor, function (m) {
      m.insertBefore(el('div', 'gm-mh', tr('Snooze until…', 'I-snooze hanggang…')), m.firstChild);
      opts.forEach(function (o) { mitem(m, o[0], function () { doSnooze(o[1], rowsArg); }, { hint: o[2] }); });
      mitem(m, tr('Pick date & time', 'Pumili ng petsa at oras'), function () {
        var def = new Date(Date.now() + 3600 * 1000); var pad = function (n) { return ('0' + n).slice(-2); };
        ask(tr('Snooze until', 'I-snooze hanggang'), [{ label: tr('Date and time', 'Petsa at oras'), type: 'datetime-local', value: def.getFullYear() + '-' + pad(def.getMonth() + 1) + '-' + pad(def.getDate()) + 'T' + pad(def.getHours()) + ':' + pad(def.getMinutes()) }], tr('Save', 'I-save'),
          function (v) { var x = new Date(v[0]); if (!isNaN(x.getTime())) { doSnooze(x, rowsArg); } });
      });
    });
  }
  function doSnooze(date, rowsArg) {
    var batches, rs = null;
    if (S.view === 'thread' && S.thread) { batches = S.thread.batches; } else { rs = rowsArg || selRows(); batches = uniq(rs.reduce(function (a, r) { return a.concat(csv(r.getAttribute('data-b'))); }, [])); }
    if (rs) { rs.forEach(function (r) { r.remove(); }); }
    post('flag', { batches: batches, snooze: date.toISOString() }).then(function (j) {
      if (!j.ok) { snack(j.text); loadList(true); return; }
      snack(tr('Conversation snoozed.', 'Na-snooze ang usapan.'), function () { post('flag', { batches: batches, unsnooze: true }).then(function () { if (S.view === 'thread') { openThread(S.thread.id); } else { loadList(true); } }); });
      if (S.view === 'thread') { go(backHash()); } else { loadList(true); }
    });
  }
  function labelsPicker(anchor, rowsArg) {
    var rs = S.view === 'thread' ? null : (rowsArg || selRows());
    var batches = S.view === 'thread' && S.thread ? S.thread.batches : uniq(rs.reduce(function (a, r) { return a.concat(csv(r.getAttribute('data-b'))); }, []));
    var have = function (lid) { if (S.view === 'thread') { return S.thread.labels.indexOf(lid) >= 0; } return rs.length > 0 && rs.every(function (r) { return csv(r.getAttribute('data-l')).indexOf(String(lid)) >= 0; }); };
    openMenu(anchor, function (m) {
      m.insertBefore(el('div', 'gm-mh', tr('Label as:', 'I-label bilang:')), m.firstChild);
      S.labels.forEach(function (l) {
        var on = have(l.id), b = mitem(m, l.name, function () {
          post('label_apply', { batches: batches, label: l.id, on: !on }).then(function (j) { if (!j.ok) { snack(j.text); return; } if (S.view === 'thread') { openThread(S.thread.id, true); } else { loadList(true); } snack(on ? tr('Label removed.', 'Inalis ang label.') : tr('Label applied.', 'Nailagay ang label.')); });
        }, { check: on });
        var dot = el('i', 'gm-ld'); dot.style.background = l.colour; b.insertBefore(dot, b.querySelector('.gm-ml'));
      });
      if (S.labels.length) { msep(m); }
      mitem(m, tr('Create new', 'Gumawa ng bago'), function () {
        ask(tr('New label', 'Bagong label'), [{ label: tr('Name', 'Pangalan'), max: 40 }, { label: tr('Colour', 'Kulay'), type: 'color', value: '#1A73E8' }], tr('Create', 'Gumawa'), function (v) {
          post('label_save', { name: v[0], colour: v[1] }).then(function (j) {
            if (!j.ok) { snack(j.text); return; }
            post('label_apply', { batches: batches, label: j.id, on: true }).then(function () { if (S.view === 'thread') { openThread(S.thread.id, true); } else { loadList(true); } });
          });
        });
      });
    });
  }

  /* ---------- the list's own clicks ---------- */
  var lastClick = null;
  listEl.addEventListener('click', function (e) {
    var row = e.target.closest('.gm-row'); if (!row) { return; }
    var g = e.target.closest('[data-gm]'), g2 = g && g.getAttribute('data-gm');
    if (e.target.closest('.gm-ck')) {
      var cb = row.querySelector('.gm-ck input');
      if (e.target === cb) {
        if (e.shiftKey && lastClick && lastClick !== row) { var rs = rows(), a = rs.indexOf(lastClick), b = rs.indexOf(row); rs.slice(Math.min(a, b), Math.max(a, b) + 1).forEach(function (r) { setSel(r, cb.checked); }); }
        else { row.classList.toggle('sel', cb.checked); }
        lastClick = row; paintToolbar();
      }
      return;
    }
    if (g2 === 'star') { e.preventDefault(); starRow(row); return; }
    if (g2 === 'archive' || g2 === 'trash') { bulk(g2, [row]); return; }
    if (g2 === 'toggleread') { bulk(row.classList.contains('gm-unread') ? 'read' : 'unread', [row]); return; }
    if (g2 === 'snooze') { snoozeMenu(g, [row]); return; }
    if (g2 === 'deldraft') { post('draft_delete', { id: row.getAttribute('data-draft') }).then(function () { loadList(true); snack(tr('Draft discarded.', 'Naitapon ang draft.')); }); return; }
    if (row.hasAttribute('data-draft')) { e.preventDefault(); C.openDraft(row.getAttribute('data-draft')); return; }
    var a = e.target.closest('a.gm-subj');
    if (a || e.target.closest('.gm-from, .gm-when, .gm-snip')) { e.preventDefault(); go('#t/' + row.getAttribute('data-t')); }
  });
  listEl.addEventListener('keydown', function (e) {
    var row = e.target.closest('.gm-row');
    if (row && (e.key === 'Enter') && e.target === row) { e.preventDefault(); if (row.hasAttribute('data-draft')) { C.openDraft(row.getAttribute('data-draft')); } else { go('#t/' + row.getAttribute('data-t')); } }
  });

  /* ---------- the reading view ---------- */
  function backHash() { return S.q ? '#search/' + encodeURIComponent(S.q) : (S.folder === 'inbox' ? '#inbox' : (S.folder.indexOf('label:') === 0 ? '#label/' + S.folder.slice(6) : '#' + S.folder)); }
  function openThread(id, quiet) {
    S.view = 'thread'; listEl.hidden = true; readerEl.hidden = false; tabsEl.hidden = true; $('#gm-main').classList.add('gm-reading');
    if (!quiet) { readerEl.textContent = ''; readerEl.appendChild(el('p', 'gm-empty', tr('Loading…', 'Naglo-load…'))); }
    return get({ v: 'thread', t: id }).then(function (j) {
      if (!j.ok) { readerEl.textContent = ''; readerEl.appendChild(el('p', 'gm-empty', j.text || tr('That conversation is not here.', 'Wala ang usapang iyan.'))); paintToolbar(); return; }
      S.thread = { id: id, batches: j.batches, ids: j.ids, labels: j.labels, star: j.star, reply: j.reply, subject: j.subject };
      S.counts = j.counts; S.labels = j.labelsList;
      readerEl.innerHTML = j.html; readerEl.scrollTop = 0;
      var last = $$('.gm-msg', readerEl).pop(); if (last) { last.scrollIntoView({ block: 'nearest' }); }
      paintRail(); paintToolbar(); paintTimes();
    });
  }
  function closeThread() { S.view = 'list'; S.thread = null; readerEl.hidden = true; readerEl.textContent = ''; listEl.hidden = false; $('#gm-main').classList.remove('gm-reading'); }
  function threadAct(kind) {
    if (!S.thread) { return; }
    var t = S.thread, b = t.batches;
    if (kind === 'unread') { post('read', { ids: t.ids, read: false }).then(function () { go(backHash()); snack(tr('Marked as unread.', 'Namarkahang hindi pa nababasa.')); }); return; }
    var d = DO[kind]; if (!d) { return; }
    post('flag', Object.assign({ batches: b }, d.f)).then(function (j) {
      if (!j.ok) { snack(j.text); return; }
      go(backHash()); snack(plural(d.msg, 1), d.back ? function () { post('flag', Object.assign({ batches: b }, d.back)).then(function () { loadList(true); }); } : null);
    });
  }
  readerEl.addEventListener('click', function (e) {
    var h = e.target.closest('.gm-m-head'); var g = e.target.closest('[data-gm]'), a = g && g.getAttribute('data-gm');
    if (a === 'mstar') { e.stopPropagation(); var art = g.closest('.gm-msg'), on = g.getAttribute('aria-pressed') !== 'true'; g.classList.toggle('on', on); g.setAttribute('aria-pressed', on ? 'true' : 'false'); post('flag', { batches: [art.getAttribute('data-b')], starred: on }); return; }
    if (a === 'reply' || a === 'replyall' || a === 'forward') { C.composeFrom(a); return; }
    if (a === 'answer-go') {
      var f = g.closest('.gm-q'), sel = f.querySelector('select'); g.disabled = true;
      post('answer', { question: f.getAttribute('data-question'), tanod: sel ? sel.value : '', pick: g.getAttribute('data-pick') }).then(function (j) { snack(j.text || (j.ok ? tr('Sent.', 'Naipadala.') : tr('Could not send.', 'Hindi naipadala.'))); if (S.thread) { openThread(S.thread.id, true); } });
      return;
    }
    if (h && !e.target.closest('.gm-star')) { var art2 = h.closest('.gm-msg'), tg = $('.gm-m-toggle', h); art2.classList.toggle('open'); tg.setAttribute('aria-expanded', art2.classList.contains('open') ? 'true' : 'false'); }
  });

  /* ---------- search ---------- */
  qIn.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); var v = qIn.value.trim(); closeOpts(); go(v ? '#search/' + encodeURIComponent(v) : '#inbox'); } else if (e.key === 'Escape') { qIn.blur(); } });
  $('#gm-qx').addEventListener('click', function () { qIn.value = ''; go('#inbox'); });
  var optsEl = $('#gm-opts');
  function closeOpts() { optsEl.hidden = true; $('#gm-optsbtn').setAttribute('aria-expanded', 'false'); }
  $('#gm-optsbtn').addEventListener('click', function () {
    var open = optsEl.hidden; optsEl.hidden = !open; this.setAttribute('aria-expanded', open ? 'true' : 'false');
    if (open) {
      var sel = $('[name="label"]', optsEl); sel.textContent = ''; sel.appendChild(el('option', '', tr('Any label', 'Kahit anong label'))).value = '';
      S.labels.forEach(function (l) { var o = el('option', '', l.name); o.value = l.name; sel.appendChild(o); }); $('[name="from"]', optsEl).focus();
    }
  });
  optsEl.addEventListener('submit', function (e) {
    e.preventDefault(); var f = function (n) { return ($('[name="' + n + '"]', optsEl).value || '').trim(); }, q = [];
    if (f('from')) { q.push('from:' + f('from')); } if (f('to')) { q.push('to:' + f('to')); } if (f('subject')) { q.push('subject:' + f('subject')); }
    if (f('words')) { q.push(f('words')); } if (f('label')) { q.push('label:"' + f('label') + '"'); }
    if ($('[name="unread"]', optsEl).checked) { q.push('is:unread'); } if ($('[name="starred"]', optsEl).checked) { q.push('is:starred'); }
    if (f('after')) { q.push('after:' + f('after')); } if (f('before')) { q.push('before:' + f('before')); }
    closeOpts(); qIn.value = q.join(' '); go(q.length ? '#search/' + encodeURIComponent(q.join(' ')) : '#inbox');
  });
  $('[data-gm="optsclear"]', optsEl).addEventListener('click', function () { optsEl.reset(); });

  /* ---------- compose lives in gmail-compose.js (the windows, drafts, people) ---------- */
  var C = window.GMC({ ME: ME, S: S, el: el, get: get, go: go, hideSnack: hideSnack, ic: ic, loadList: loadList, openThread: openThread, post: post, readerEl: readerEl,
    snack: snack, tr: tr, $: $, $$: $$, menu: function () { return menu; } });

  /* ---------- the keyboard (Gmail's keys); nothing fires while typing, or while a menu or window has the keys ---------- */
  var gPending = false, gTimer = null;
  function typing(t) { return t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable); }
  function curRow() { return rows()[S.cur] || null; }
  function moveCur(d) { var rs = rows(); if (!rs.length) { return; } if (rs[S.cur]) { rs[S.cur].classList.remove('cur'); } S.cur = Math.max(0, Math.min(rs.length - 1, (S.cur < 0 ? (d > 0 ? 0 : 0) : S.cur + d))); rs[S.cur].classList.add('cur'); rs[S.cur].scrollIntoView({ block: 'nearest' }); rs[S.cur].focus({ preventScroll: true }); }
  var HELP = [['c', tr('Compose', 'Sumulat')], ['/', tr('Search mail', 'Maghanap sa mail')], ['j / k', tr('Older / newer conversation', 'Mas luma / mas bagong usapan')], ['o or Enter', tr('Open conversation', 'Buksan ang usapan')], ['u', tr('Back to the list', 'Bumalik sa listahan')],
    ['x', tr('Select conversation', 'Piliin ang usapan')], ['s', tr('Star', 'Bituin')], ['e', tr('Archive', 'I-archive')], ['#', tr('Delete', 'Burahin')], ['r / a / f', tr('Reply / reply all / forward', 'Sagot / sagot sa lahat / i-forward')],
    ['Shift + I / U', tr('Mark as read / unread', 'Markahang nabasa / hindi pa nabasa')], ['z', tr('Undo', 'I-undo')], ['g then i / s / t / d / a', tr('Go to Inbox / Starred / Sent / Drafts / All Mail', 'Pumunta sa Inbox / May bituin / Naipadala / Mga draft / Lahat')], ['Ctrl + Enter', tr('Send (in a message)', 'Ipadala (sa mensahe)')], ['?', tr('This list', 'Ang listahang ito')]];
  function helpDialog() {
    var back = el('div', 'gm-dlg-back'), d = el('div', 'gm-dlg gm-help'); d.setAttribute('role', 'dialog'); d.setAttribute('aria-modal', 'true'); d.setAttribute('aria-label', tr('Keyboard shortcuts', 'Mga shortcut sa keyboard')); d.appendChild(el('h3', '', tr('Keyboard shortcuts', 'Mga shortcut sa keyboard')));
    var dl = el('dl'); HELP.forEach(function (h) { dl.appendChild(el('dt', '', h[0])); dl.appendChild(el('dd', '', h[1])); }); d.appendChild(dl);
    var ok = el('button', 'gm-btn gm-btn--blue', tr('Close', 'Isara')); ok.type = 'button'; d.appendChild(ok); back.appendChild(d); document.body.appendChild(back);
    function close() { back.remove(); document.removeEventListener('keydown', key, true); } function key(e) { if (e.key === 'Escape') { e.stopPropagation(); close(); } }
    ok.addEventListener('click', close); back.addEventListener('pointerdown', function (e) { if (e.target === back) { close(); } }); document.addEventListener('keydown', key, true); ok.focus();
  }
  document.addEventListener('keydown', function (e) {
    if (e.metaKey || e.ctrlKey || e.altKey || typing(e.target) || menu || document.querySelector('.gm-dlg-back')) { return; }
    var k = e.key;
    if (gPending) { gPending = false; clearTimeout(gTimer); var m = { i: '#inbox', s: '#starred', t: '#trash', d: '#drafts', a: '#all', n: '#snoozed' }[k]; if (m) { e.preventDefault(); go(m); } return; }
    if (k === 'g') { gPending = true; gTimer = setTimeout(function () { gPending = false; }, 1500); return; }
    if (k === 'c') { e.preventDefault(); C.newCompose({}, {}); return; }
    if (k === '/') { e.preventDefault(); qIn.focus(); return; }
    if (k === '?') { e.preventDefault(); helpDialog(); return; }
    if (k === 'z' && lastUndo) { e.preventDefault(); var f = lastUndo; hideSnack(); f(); return; }
    if (S.view === 'thread') {
      if (k === 'u') { e.preventDefault(); go(backHash()); } else if (k === 'e') { threadAct('archive'); } else if (k === '#') { threadAct('trash'); }
      else if (k === 'r') { e.preventDefault(); C.composeFrom('reply'); } else if (k === 'a') { e.preventDefault(); C.composeFrom('replyall'); } else if (k === 'f') { e.preventDefault(); C.composeFrom('forward'); }
      else if (k === 'j' || k === 'k') { var i = S.order.indexOf(S.thread.id), n = i + (k === 'j' ? 1 : -1); if (S.order[n]) { go('#t/' + S.order[n]); } }
      else if (k === 'I' || k === 'U') { threadAct('unread'); }
      return;
    }
    var row = curRow();
    if (k === 'j') { e.preventDefault(); moveCur(1); } else if (k === 'k') { e.preventDefault(); moveCur(-1); }
    else if ((k === 'o' || k === 'Enter') && row) { e.preventDefault(); if (row.hasAttribute('data-draft')) { C.openDraft(row.getAttribute('data-draft')); } else { go('#t/' + row.getAttribute('data-t')); } }
    else if (k === 'x' && row) { setSel(row, !row.querySelector('.gm-ck input').checked); paintToolbar(); }
    else if (k === 's' && row && row.hasAttribute('data-t')) { starRow(row); }
    else if ((k === 'e' || k === '#') && (row || selRows().length)) { bulk(k === 'e' ? 'archive' : 'trash', selRows().length ? null : [row]); }
    else if ((k === 'I' || k === 'U') && (row || selRows().length)) { bulk(k === 'I' ? 'read' : 'unread', selRows().length ? null : [row]); }
  });

  /* ---------- the address is the place: #inbox, #starred, #label/3, #search/words, #t/<conversation>, #compose, #draft/4 ---------- */
  function go(h) { if (location.hash === h) { route(); } else { location.hash = h; } }
  function route() {
    var h = decodeURIComponent((location.hash || '#inbox').slice(1)), m;
    closeMenu(false);
    if ((m = /^t\/([0-9a-f-]{36})$/i.exec(h))) { openThread(m[1].toLowerCase()); return; }
    if (S.view === 'thread') { closeThread(); }
    S.page = 1; S.cur = -1;
    if (h === 'compose') { history.replaceState(null, '', location.pathname + location.search + '#inbox'); C.newCompose({}, {}); h = 'inbox'; }
    else if ((m = /^draft\/(\d+)$/.exec(h))) { history.replaceState(null, '', location.pathname + location.search + '#drafts'); C.openDraft(m[1]); h = 'drafts'; }
    if ((m = /^search\/(.*)$/.exec(h))) { S.q = m[1]; S.folder = 'all'; qIn.value = S.q; }
    else { S.q = ''; qIn.value = ''; if ((m = /^label\/(\d+)$/.exec(h))) { S.folder = 'label:' + m[1]; } else { S.folder = FOLDERS[h] ? h : 'inbox'; } }
    $('#gm-main').classList.toggle('gm-searching', !!S.q);
    loadList();
  }
  window.addEventListener('hashchange', route);
  tabsEl.addEventListener('click', function (e) { var b = e.target.closest('[data-tab]'); if (b) { S.tab = b.getAttribute('data-tab'); S.page = 1; loadList(); } });
  root.addEventListener('click', function (e) {
    var g = e.target.closest('[data-gm]'); if (!g) { return; }
    var a = g.getAttribute('data-gm');
    if (a === 'compose') { C.newCompose({}, {}); }
    else if (a === 'newlabel') { ask(tr('New label', 'Bagong label'), [{ label: tr('Name', 'Pangalan'), max: 40 }, { label: tr('Colour', 'Kulay'), type: 'color', value: '#1A73E8' }], tr('Create', 'Gumawa'), function (v) { post('label_save', { name: v[0], colour: v[1] }).then(function (j) { if (!j.ok) { snack(j.text); } loadList(true); }); }); }
    else if (a === 'help') { helpDialog(); }
  });
  document.addEventListener('pointerdown', function (e) { if (!optsEl.hidden && !e.target.closest('#gm-opts, #gm-optsbtn')) { closeOpts(); } });
  setInterval(function () { if (!document.hidden && S.view === 'list' && !selRows().length && !C.count()) { loadList(true); } }, 45000);

  // old links to a letter (?m=ID), and to writing one (?new=1), still work
  var m0 = root.getAttribute('data-m');
  if (m0 && !location.hash) { get({ v: 'find', m: m0 }).then(function (j) { if (j.ok && j.thread) { go('#t/' + j.thread); } else { route(); } }); }
  else { route(); }
  if (root.getAttribute('data-new') === '1') { C.newCompose({}, {}); }
})();
