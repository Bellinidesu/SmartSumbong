/* The case page's "Why this level" card opens only when it is wanted (15 Nov 2026, Ace): a button beside the status pill opens it as a drawer; the close button,
   Escape and a click outside shut it. It is a <dialog>, so focus is held inside and returns to the button. No inline handlers (strict CSP). */
(function () {
  'use strict';
  var d = document.getElementById('smart-card');
  if (!d || typeof d.showModal !== 'function') { return; }
  var opener = null;
  document.addEventListener('click', function (e) {
    var open = e.target.closest ? e.target.closest('[data-smart-open]') : null;
    if (open) { opener = open; if (!d.open) { d.showModal(); } open.setAttribute('aria-expanded', 'true'); return; }
    if (!d.open) { return; }
    if (e.target.closest && e.target.closest('[data-smart-close]')) { d.close(); return; }
    var r = d.getBoundingClientRect();   // a click on the dim area outside the card (the dialog's own padding is inside its rectangle)
    if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) { d.close(); }
  });
  d.addEventListener('close', function () {
    var b = document.querySelector('[data-smart-open]');
    if (b) { b.setAttribute('aria-expanded', 'false'); if (opener) { opener.focus(); } }
  });
})();
