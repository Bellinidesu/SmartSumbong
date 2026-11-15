/* The barangay's places, a panel on Spatial Distribution (15 Nov 2026, Ace: they moved here from Settings, for now). The button on the side opens a dialog that loads places.php;
   its forms post to places.php, which sends the person back here (?places=1) and the panel opens again with the result. No inline handlers (strict CSP). */
(function () {
  'use strict';
  var btn = document.getElementById('pl-open'), dlg = document.getElementById('pl-dlg'), body = document.getElementById('pl-body');
  if (!btn || !dlg || !body) { return; }
  function load() {
    body.innerHTML = '<p class="st-note">' + (typeof window.T === 'function' ? window.T('Loading…', 'Naglo-load…') : 'Loading…') + '</p>';
    return fetch('places.php', { credentials: 'same-origin', headers: { 'Accept': 'text/html' } })
      .then(function (r) { return r.ok ? r.text() : Promise.reject(r.status); })
      .then(function (h) { body.innerHTML = h; if (window.ssPickersInit) { window.ssPickersInit(body); } })
      .catch(function () { body.innerHTML = '<p class="st-note">' + (typeof window.T === 'function' ? window.T('The places could not be loaded. Try again.', 'Hindi mai-load ang mga lugar. Subukan muli.') : 'The places could not be loaded.') + '</p>'; });
  }
  function open() { if (!dlg.open) { dlg.showModal(); } btn.setAttribute('aria-expanded', 'true'); return load(); }
  function close() { if (dlg.open) { dlg.close(); } }
  btn.addEventListener('click', open);
  dlg.addEventListener('click', function (e) { if (e.target === dlg || e.target.closest('[data-pl-close]')) { close(); } });
  dlg.addEventListener('close', function () { btn.setAttribute('aria-expanded', 'false'); if (/[?&]places=1/.test(location.search)) { history.replaceState(null, '', 'spatial.php'); } });
  if (/[?&]places=1/.test(location.search)) { open(); }
})();
