/* The notice before the committee editor (16 Nov 2026, Ace). "New committee" and each committee's "Edit" open committee-editor.php, where the rest of the portal cannot be opened. The first
   time, a notice says so; "Do not show this again" is remembered in this browser, so later presses go straight in. No inline handlers (strict CSP). */
(function () {
  'use strict';
  var dlg = document.getElementById('ce-enter'), go = document.getElementById('ce-enter-go'), skipBox = document.getElementById('ce-skip');
  if (!dlg || !go || !skipBox) { return; }
  var KEY = 'ss-ce-skip';
  function skipped() { try { return localStorage.getItem(KEY) === '1'; } catch (e) { return false; } }
  // the capture phase, so the press flow (htmx) does not take the link first
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a[data-ce-go]');
    if (!a || skipped() || !dlg.showModal) { return; }
    e.preventDefault(); e.stopPropagation();
    go.setAttribute('href', a.getAttribute('href')); skipBox.checked = false; dlg.showModal();
  }, true);
  var no = dlg.querySelector('[data-ce-no]'); if (no) { no.addEventListener('click', function () { dlg.close(); }); }
  dlg.addEventListener('click', function (e) { if (e.target === dlg) { dlg.close(); } });
  go.addEventListener('click', function () { if (skipBox.checked) { try { localStorage.setItem(KEY, '1'); } catch (e) { /* private window: asked again next time */ } } });
})();
