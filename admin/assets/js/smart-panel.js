// The SMART engine's window on the dashboard: the brain button in the header opens it from the right; Escape, the scrim or the
// cross close it, and focus stays inside while it is open and goes back to the button when it closes.
(function () {
  var win = document.getElementById('ss-panel'), openB = document.getElementById('ss-win-open'), closeB = document.getElementById('ss-win-close'), scrim = document.getElementById('ss-win-scrim');
  if (!win || !openB || !closeB || !scrim) return;
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches, last = null;
  function countUp(root) {
    if (reduce) return;
    root.querySelectorAll('.ss-tile b').forEach(function (el) {
      var n = parseInt(el.textContent, 10);
      if (!(n > 0)) return;
      var t0 = null;
      (function step(t) {
        if (t0 === null) t0 = t;
        var k = Math.min(1, (t - t0) / 800), eased = 1 - Math.pow(1 - k, 3);
        el.textContent = String(Math.round(n * eased));
        if (k < 1) requestAnimationFrame(step); else el.textContent = String(n);
      })(performance.now());
    });
  }
  function isOpen() { return win.classList.contains('is-open'); }
  function open() {
    if (isOpen()) return;
    last = document.activeElement;
    win.classList.add('is-open'); scrim.classList.add('is-open'); win.setAttribute('aria-hidden', 'false'); openB.setAttribute('aria-expanded', 'true');
    countUp(win); setTimeout(function () { closeB.focus(); }, 30);
  }
  function close() {
    if (!isOpen()) return;
    win.classList.remove('is-open'); scrim.classList.remove('is-open'); win.setAttribute('aria-hidden', 'true'); openB.setAttribute('aria-expanded', 'false');
    if (last && last.focus) last.focus();
  }
  openB.setAttribute('aria-expanded', 'false');
  openB.addEventListener('click', open);
  closeB.addEventListener('click', close);
  scrim.addEventListener('click', close);
  document.addEventListener('keydown', function (e) {
    if (!isOpen()) return;
    if (e.key === 'Escape') { e.preventDefault(); close(); return; }
    if (e.key !== 'Tab') return;
    var f = [].slice.call(win.querySelectorAll('a[href], button, input, select, textarea, [tabindex]:not([tabindex="-1"])')).filter(function (x) { return x.offsetParent !== null; });
    if (!f.length) return;
    var first = f[0], lastEl = f[f.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); lastEl.focus(); }
    else if (!e.shiftKey && document.activeElement === lastEl) { e.preventDefault(); first.focus(); }
  });
})();
