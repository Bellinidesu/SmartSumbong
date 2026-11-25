/* A report with several requests (Rose, 15 Nov 2026): the Request in focus bar in the Admin Controls. Pick the request being handled; it is lit in the list of
   concerns, its note and remark are read out here, "Next request" moves to the next one still open, and "Mark this request resolved" presses that request's own
   Mark resolved button. Strict CSP: no inline handlers.
   19 Nov 2026 (Rose): a concern is now updated in place (only the concerns card is swapped, and this bar follows it through data-press-sync), so every press is
   delegated from the document and the request in focus is lit again after each swap, instead of being bound to chips that are replaced. */
(function () {
  'use strict';
  if (!document.getElementById('cf')) { return; }
  var tr = function (en, fil) { return typeof window.T === 'function' ? window.T(en, fil) : en; };
  var cur = -1;
  function bar() { return document.getElementById('cf'); }
  function chips() { var b = bar(); return b ? [].slice.call(b.querySelectorAll('.cf-chip')) : []; }
  function li(i) { return document.querySelector('.ss-concern-list li[data-cf-i="' + i + '"]'); }
  function show(i, quiet) {   // quiet: the first, automatic pick on load must not scroll the case card's body (it hid the Subject)
    var cs = chips(), b = bar();
    if (!b || i < 0 || i >= cs.length) { return; }
    cur = i;
    cs.forEach(function (c, k) { var on = k === i; c.classList.toggle('on', on); c.setAttribute('aria-pressed', on ? 'true' : 'false'); });
    [].forEach.call(document.querySelectorAll('.ss-concern-list li'), function (x) { x.classList.toggle('is-focus', x === li(i)); });
    var l = li(i), isDone = cs[i].getAttribute('data-done') === '1', now = b.querySelector('.cf-now'), done = b.querySelector('[data-cf="done"]');
    now.textContent = '';
    var st = document.createElement('p'); st.className = 'cf-st'; st.textContent = isDone ? tr('Resolved', 'Nalutas') : tr('Open', 'Bukás'); now.appendChild(st);
    var note = l && l.querySelector('.p-sub'), rem = l && l.querySelector('.p-quote');
    [note, rem].forEach(function (n) { if (n && n.textContent.trim()) { var p = document.createElement('p'); p.className = 'cf-note'; p.textContent = n.textContent.trim(); now.appendChild(p); } });
    done.hidden = isDone || !(l && l.querySelector('form.ss-concern-act'));
    if (!quiet && l && l.scrollIntoView) { l.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); }
  }
  document.addEventListener('click', function (e) {
    var b = bar(); if (!b || !e.target.closest || !b.contains(e.target)) { return; }
    var chip = e.target.closest('.cf-chip');
    if (chip) { show(chips().indexOf(chip)); return; }
    var act = e.target.closest('[data-cf]'); if (!act) { return; }
    var cs = chips();
    if (act.getAttribute('data-cf') === 'next') {
      for (var s = 1; s <= cs.length; s++) { var k = (cur + s) % cs.length; if (cs[k].getAttribute('data-done') !== '1' || s === cs.length) { show(k); return; } }
    } else if (act.getAttribute('data-cf') === 'done') {
      var f = li(cur) && li(cur).querySelector('form.ss-concern-act');
      if (f) { if (f.requestSubmit) { f.requestSubmit(); } else { f.submit(); } }
    }
  });
  function first() { var cs = chips(), i = cs.findIndex(function (c) { return c.getAttribute('data-done') !== '1'; }); return i < 0 ? 0 : i; }
  // after a concern was updated in place: the same request stays in focus while it is open, otherwise the next open one
  document.addEventListener('htmx:afterSettle', function () {
    var cs = chips(); if (!cs.length) { return; }
    show(cur >= 0 && cur < cs.length && cs[cur].getAttribute('data-done') !== '1' ? cur : first(), true);
  });
  // and after a live update (live.js, 25 Nov 2026) redrew the concerns or this bar in place
  document.addEventListener('ss:live', function () {
    var cs = chips(); if (!cs.length) { return; }
    show(cur >= 0 && cur < cs.length && cs[cur].getAttribute('data-done') !== '1' ? cur : first(), true);
  });
  show(first(), true);
})();
