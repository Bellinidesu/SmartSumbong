/* The stack of pills in a cell (15 Nov 2026, Ace): at most four pills show; the rest wait behind a small "+N more" button that opens them all and closes them again.
   One rule for every page and every role (Case Reports, Residents, Personnel, Report Summary...): any .p-badges holding more than four pills is capped. It looks again
   whenever a page piece is swapped in or a list refreshes itself, so a redrawn row is capped too. No inline handlers (strict CSP). */
(function () {
  'use strict';
  var CAP = 4;
  var CHEV = '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg>';
  function tr(en, fil) { return typeof window.T === 'function' ? window.T(en, fil) : en; }
  function pillsOf(box) { return [].filter.call(box.children, function (c) { return c.classList.contains('p-badge'); }); }
  function paint(box, btn, pills, open) {
    pills.forEach(function (p, i) { p.classList.toggle('ps-hide', !open && i >= CAP); });
    var more = pills.length - CAP;
    btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    btn.innerHTML = '<span>' + (open ? tr('Show less', 'Ipakita nang kaunti') : '+' + more + ' ' + tr('more', 'pa')) + '</span>' + CHEV;
    btn.setAttribute('aria-label', open ? tr('Show fewer', 'Ipakita ang mas kaunti') : tr('Show all', 'Ipakita lahat') + ' (' + pills.length + ')');
  }
  function fix(box) {
    var pills = pillsOf(box), btn = box.querySelector(':scope > .ps-more');
    if (pills.length <= CAP) { if (btn) { btn.remove(); } pills.forEach(function (p) { p.classList.remove('ps-hide'); }); box._psn = 0; return; }
    if (btn && box._psn === pills.length) { return; }            // nothing changed since it was set up
    var open = !!btn && btn.getAttribute('aria-expanded') === 'true';
    if (!btn) { btn = document.createElement('button'); btn.type = 'button'; btn.className = 'ps-more'; box.appendChild(btn); }
    box._psn = pills.length; paint(box, btn, pills, open);
  }
  function scan(root) { [].forEach.call((root || document).querySelectorAll('.p-badges'), fix); }
  document.addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('.ps-more'); if (!b) { return; }
    e.preventDefault(); e.stopPropagation();
    var box = b.parentNode; paint(box, b, pillsOf(box), b.getAttribute('aria-expanded') !== 'true');
  });
  var queued = false;
  function later() { if (queued) { return; } queued = true; requestAnimationFrame(function () { queued = false; scan(document); }); }
  new MutationObserver(later).observe(document.documentElement, { childList: true, subtree: true });
  scan(document);
})();
