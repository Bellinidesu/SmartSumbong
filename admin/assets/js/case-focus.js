/* A report with several requests (Rose, 15 Nov 2026): the Request in focus bar in the Admin Controls. Pick the request being handled; it is lit in the list of
   concerns, its note and remark are read out here, "Next request" moves to the next one still open, and "Mark this request resolved" presses that request's own
   Mark resolved button. Strict CSP: no inline handlers. */
(function () {
  'use strict';
  var bar = document.getElementById('cf');
  if (!bar) { return; }
  var chips = [].slice.call(bar.querySelectorAll('.cf-chip')), now = bar.querySelector('.cf-now'), done = bar.querySelector('[data-cf="done"]');
  var tr = function (en, fil) { return typeof window.T === 'function' ? window.T(en, fil) : en; };
  var cur = -1;
  function li(i) { return document.querySelector('.ss-concern-list li[data-cf-i="' + i + '"]'); }
  function show(i, quiet) {   // quiet: the first, automatic pick on load must not scroll the case card's body (it hid the Subject)
    if (i < 0 || i >= chips.length) { return; }
    cur = i;
    chips.forEach(function (c, k) { var on = k === i; c.classList.toggle('on', on); c.setAttribute('aria-pressed', on ? 'true' : 'false'); });
    [].forEach.call(document.querySelectorAll('.ss-concern-list li'), function (x) { x.classList.toggle('is-focus', x === li(i)); });
    var l = li(i), isDone = chips[i].getAttribute('data-done') === '1';
    now.textContent = '';
    var st = document.createElement('p'); st.className = 'cf-st'; st.textContent = isDone ? tr('Resolved', 'Nalutas') : tr('Open', 'Bukás'); now.appendChild(st);
    var note = l && l.querySelector('.p-sub'), rem = l && l.querySelector('.p-quote');
    [note, rem].forEach(function (n) { if (n && n.textContent.trim()) { var p = document.createElement('p'); p.className = 'cf-note'; p.textContent = n.textContent.trim(); now.appendChild(p); } });
    done.hidden = isDone || !(l && l.querySelector('form.ss-concern-act'));
    if (!quiet && l && l.scrollIntoView) { l.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); }
  }
  chips.forEach(function (c, k) { c.addEventListener('click', function () { show(k); }); });
  bar.querySelector('[data-cf="next"]').addEventListener('click', function () {
    for (var s = 1; s <= chips.length; s++) { var k = (cur + s) % chips.length; if (chips[k].getAttribute('data-done') !== '1' || s === chips.length) { show(k); return; } }
  });
  done.addEventListener('click', function () {
    var f = li(cur) && li(cur).querySelector('form.ss-concern-act');
    if (f) { if (f.requestSubmit) { f.requestSubmit(); } else { f.submit(); } }
  });
  var first = chips.findIndex(function (c) { return c.getAttribute('data-done') !== '1'; });
  show(first < 0 ? 0 : first, true);
})();
