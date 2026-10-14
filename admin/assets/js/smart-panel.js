// The SMART panel on the dashboard: a click opens it, the engine "thinks" for a moment, then the numbers count up.
(function () {
  var p = document.getElementById('ss-panel'), b = document.getElementById('ss-panel-btn');
  if (!p || !b) return;
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches, KEY = 'ss-smart-open', busy = false;
  function get() { try { return localStorage.getItem(KEY) === '1'; } catch (e) { return false; } }
  function set(v) { try { localStorage.setItem(KEY, v ? '1' : '0'); } catch (e) {} }
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
  function open(animate) {
    p.classList.add('is-open'); b.setAttribute('aria-expanded', 'true');
    if (animate) { p.classList.add('is-revealing'); countUp(p); }
  }
  function close() { p.classList.remove('is-open', 'is-revealing'); b.setAttribute('aria-expanded', 'false'); }

  p.classList.add('is-ready');
  if (get()) open(false);
  requestAnimationFrame(function () { requestAnimationFrame(function () { p.classList.add('is-armed'); }); });

  b.addEventListener('click', function () {
    if (busy) return;
    if (p.classList.contains('is-open')) { close(); set(false); return; }
    set(true);
    if (reduce) { open(false); return; }
    busy = true; p.classList.add('is-thinking'); b.setAttribute('aria-busy', 'true');
    setTimeout(function () { p.classList.remove('is-thinking'); b.removeAttribute('aria-busy'); open(true); busy = false; }, 1300);
  });
})();
