/* Shared behaviour for the preview design (p.css): dialogs, toasts, and a
   styled confirm for any form or button marked data-confirm. */
(function () {
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  window.pOpen = function (id) {
    var m = document.getElementById(id); if (!m) return;
    m.classList.add('p-on');
    var b = m.querySelector('button, [href], input, textarea, select'); if (b) b.focus();
  };
  window.pClose = function () { $$('.p-scrim.p-on').forEach(function (s) { s.classList.remove('p-on'); }); };
  document.addEventListener('click', function (e) {
    if (e.target.classList && e.target.classList.contains('p-scrim')) window.pClose();
    var c = e.target.closest('[data-p-close]'); if (c) { e.preventDefault(); window.pClose(); }
    var o = e.target.closest('[data-p-open]'); if (o) { e.preventDefault(); window.pOpen(o.getAttribute('data-p-open')); }
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') window.pClose(); });

  // Strict security policy (7 Oct 2026): no inline handlers. A select or
  // date marked data-autosubmit sends its form when changed; a form or
  // button marked data-native-confirm asks first with the browser's dialog.
  document.addEventListener('change', function (e) {
    var el = e.target.closest && e.target.closest('[data-autosubmit]');
    if (el && el.form) el.form.submit();
  });
  document.addEventListener('submit', function (e) {
    var m = e.target.getAttribute && e.target.getAttribute('data-native-confirm');
    if (m && !window.confirm(m)) { e.preventDefault(); e.stopImmediatePropagation(); }
  }, true);
  document.addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('button[data-native-confirm], a[data-native-confirm], input[data-native-confirm]');
    if (b && !window.confirm(b.getAttribute('data-native-confirm'))) { e.preventDefault(); e.stopImmediatePropagation(); }
  }, true);

  // Clickable table rows: <tr data-href="...">, links and buttons inside keep their own clicks.
  document.addEventListener('click', function (e) {
    var tr = e.target.closest('tr[data-href]');
    if (!tr || e.target.closest('a, button, input, select, textarea, label')) return;
    location.href = tr.getAttribute('data-href');
  });

  var toastT;
  window.pToast = function (msg) {
    var t = document.getElementById('p-toast'); if (!t) return;
    t.textContent = msg; t.classList.add('p-on');
    clearTimeout(toastT); toastT = setTimeout(function () { t.classList.remove('p-on'); }, 2400);
  };

  // data-confirm="Title|Body|Button label|tone" on a submit button or a form.
  var pending = null;
  document.addEventListener('click', function (e) {
    var b = e.target.closest('button[data-confirm], input[type=submit][data-confirm]');
    if (!b || b.dataset.confirmed) return;
    var form = b.form; if (!form) return;
    e.preventDefault();
    var parts = b.getAttribute('data-confirm').split('|');
    var tone = parts[3] || 'blue';
    var tones = { blue: ['var(--p-blue-50)', 'var(--p-link)', '#i-check'], red: ['var(--p-red-bg)', 'var(--p-red)', '#i-x'], amber: ['var(--p-amber-bg)', 'var(--p-amber)', '#i-up'] };
    var t = tones[tone] || tones.blue;
    $('#p-mc-ico').setAttribute('style', 'background:' + t[0] + ';color:' + t[1]);
    $('#p-mc-ico').innerHTML = '<svg width="26" height="26"><use href="' + t[2] + '"/></svg>';
    $('#p-mc-t').textContent = parts[0] || '';
    $('#p-mc-p').textContent = parts[1] || '';
    $('#p-mc-go').textContent = parts[2] || 'Confirm';
    $('#p-mc-go').className = 'p-btn ' + (tone === 'red' ? 'p-btn-danger-solid' : 'p-btn-primary');
    pending = b;
    window.pOpen('p-m-confirm');
  });
  document.addEventListener('click', function (e) {
    if (!e.target.closest('#p-mc-go') || !pending) return;
    var b = pending; pending = null; window.pClose();
    b.dataset.confirmed = '1';
    if (b.form.requestSubmit) b.form.requestSubmit(b); else b.click();
  });
})();
