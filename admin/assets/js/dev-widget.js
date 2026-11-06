// The DEV switcher as a floating pill (6 Nov 2026): drag it anywhere, it stays there on every page (remembered in this browser), a
// double-click puts it back, Escape or a click elsewhere closes its panel. The panel opens upward, or downward and leftward when
// the pill sits near the top or the right edge.
(function () {
  var box = document.getElementById('dv-float'); if (!box) return;
  var det = box.querySelector('details'), sum = box.querySelector('summary'), KEY = 'ss-dev-pos';
  var drag = null, moved = false;
  function read() { try { var v = JSON.parse(localStorage.getItem(KEY) || 'null'); return v && isFinite(v.x) && isFinite(v.y) ? v : null; } catch (e) { return null; } }
  function save(v) { try { if (v) localStorage.setItem(KEY, JSON.stringify(v)); else localStorage.removeItem(KEY); } catch (e) { /* it just does not stay */ } }
  function side() { var r = box.getBoundingClientRect(); box.classList.toggle('dv-down', r.top < 300); box.classList.toggle('dv-right', r.left + 280 > innerWidth); }
  function put(x, y) {
    var w = box.offsetWidth, h = box.offsetHeight;
    x = Math.max(8, Math.min(innerWidth - w - 8, x)); y = Math.max(8, Math.min(innerHeight - h - 8, y));
    box.style.left = x + 'px'; box.style.top = y + 'px'; box.style.right = 'auto'; box.style.bottom = 'auto'; side();
    return { x: x, y: y };
  }
  function home() { box.style.left = box.style.top = box.style.right = box.style.bottom = ''; side(); }
  var saved = read(); if (saved) put(saved.x, saved.y); else side();
  addEventListener('resize', function () { var v = read(); if (v) put(v.x, v.y); else side(); });

  sum.addEventListener('pointerdown', function (e) {
    if (e.button !== 0) return;
    var r = box.getBoundingClientRect(); drag = { dx: e.clientX - r.left, dy: e.clientY - r.top, sx: e.clientX, sy: e.clientY }; moved = false;
    try { sum.setPointerCapture(e.pointerId); } catch (x) { /* a browser without capture still drags */ }
  });
  sum.addEventListener('pointermove', function (e) {
    if (!drag) return;
    if (!moved && Math.abs(e.clientX - drag.sx) + Math.abs(e.clientY - drag.sy) < 6) return;
    moved = true; if (det.open) det.open = false; put(e.clientX - drag.dx, e.clientY - drag.dy);
  });
  function end() { if (drag && moved) { var r = box.getBoundingClientRect(); save({ x: r.left, y: r.top }); } drag = null; }
  sum.addEventListener('pointerup', end); sum.addEventListener('pointercancel', end);
  sum.addEventListener('click', function (e) { if (moved) { e.preventDefault(); moved = false; } });
  sum.addEventListener('dblclick', function () { save(null); home(); });
  det.addEventListener('toggle', side);
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && det.open) { det.open = false; sum.focus(); } });
  document.addEventListener('click', function (e) { if (det.open && !box.contains(e.target)) det.open = false; });
})();
