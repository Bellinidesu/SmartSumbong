/* Spatial Distribution: the column of buttons down the right can be moved (12 Nov 2026, Ace: "make em movable around").
   A small grip at its head is picked up with the mouse or a finger and dropped anywhere along the map; it settles on the nearer side
   (left or right) at the height it was left, and is remembered in this browser. Arrow keys on the grip move it too (up and down by a step,
   left and right to the other side), and a double press puts it back. While a panel is open the buttons do not widen with their words,
   so a panel is never covered by them (the CSS in sd-skin.css). Strict CSP: no inline handlers. */
(function () {
  'use strict';
  var dock = document.querySelector('.p-map-dock'), shell = document.getElementById('s-spatial');
  if (!dock || !shell) { return; }
  var KEY = 'ss-sd-dock', EDGE = 16, STEP = 32;
  var tr = function (en, fil) { return typeof window.T === 'function' ? window.T(en, fil) : en; };
  function rd() { try { var v = JSON.parse(localStorage.getItem(KEY)); return v && typeof v === 'object' ? v : null; } catch (e) { return null; } }
  function wr(v) { try { if (v) { localStorage.setItem(KEY, JSON.stringify(v)); } else { localStorage.removeItem(KEY); } } catch (e) { /* private window: it lasts until the page closes */ } }

  var grip = document.createElement('button');
  grip.type = 'button'; grip.className = 'sd-grip';
  grip.setAttribute('aria-label', tr('Move these buttons. Drag, or use the arrow keys; press twice to put them back.', 'Ilipat ang mga button na ito. I-drag, o gamitin ang mga arrow key; pindutin nang dalawang beses para ibalik.'));
  grip.title = tr('Move these buttons', 'Ilipat ang mga button na ito');
  grip.innerHTML = '<svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor" aria-hidden="true"><circle cx="8" cy="7" r="1.6"/><circle cx="16" cy="7" r="1.6"/><circle cx="8" cy="12" r="1.6"/><circle cx="16" cy="12" r="1.6"/><circle cx="8" cy="17" r="1.6"/><circle cx="16" cy="17" r="1.6"/></svg>';
  dock.insertBefore(grip, dock.firstChild);

  function box() { var p = (dock.offsetParent || shell).getBoundingClientRect(); return { l: p.left, t: p.top, w: p.width, h: p.height }; }
  function clampTop(t, b) { return Math.max(EDGE, Math.min(b.h - dock.offsetHeight - EDGE, t)); }
  function apply() {
    var v = rd(), b = box();
    if (!v) {
      dock.classList.remove('sd-moved', 'sd-left');
      dock.style.top = dock.style.left = dock.style.right = dock.style.bottom = '';
      return;
    }
    dock.classList.add('sd-moved'); dock.classList.toggle('sd-left', v.side === 'l');
    dock.style.top = clampTop(Number(v.top) || EDGE, b) + 'px'; dock.style.bottom = 'auto';
    dock.style.left = v.side === 'l' ? EDGE + 'px' : 'auto'; dock.style.right = v.side === 'l' ? 'auto' : EDGE + 'px';
  }

  var drag = null, moved = false;
  grip.addEventListener('pointerdown', function (e) {
    if (e.button !== 0) { return; }
    var r = dock.getBoundingClientRect(), b = box();
    drag = { x: e.clientX, y: e.clientY, l: r.left - b.l, t: r.top - b.t };
    moved = false;
    try { grip.setPointerCapture(e.pointerId); } catch (x) { /* the drag still works while the pointer stays over the grip */ }
  });
  grip.addEventListener('pointermove', function (e) {
    if (!drag) { return; }
    var dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    if (!moved && Math.hypot(dx, dy) < 5) { return; }
    if (!moved) { moved = true; dock.classList.add('sd-drag', 'sd-moved'); }
    var b = box();
    dock.style.left = Math.max(0, Math.min(b.w - dock.offsetWidth, drag.l + dx)) + 'px';
    dock.style.top = Math.max(0, Math.min(b.h - dock.offsetHeight, drag.t + dy)) + 'px';
    dock.style.right = 'auto'; dock.style.bottom = 'auto';
  });
  function end() {
    if (!drag) { return; }
    var was = moved; drag = null; moved = false;
    if (!was) { return; }
    dock.classList.remove('sd-drag');
    var b = box(), r = dock.getBoundingClientRect(), mid = r.left - b.l + r.width / 2;
    wr({ side: mid < b.w / 2 ? 'l' : 'r', top: Math.round(clampTop(r.top - b.t, b)) });
    dock.classList.add('sd-snap'); apply(); setTimeout(function () { dock.classList.remove('sd-snap'); }, 400);
  }
  grip.addEventListener('pointerup', end); grip.addEventListener('pointercancel', end); grip.addEventListener('lostpointercapture', end);
  grip.addEventListener('keydown', function (e) {
    var v = rd() || { side: 'r', top: Math.round(dock.getBoundingClientRect().top - box().t) };
    if (e.key === 'ArrowUp') { v.top -= STEP; } else if (e.key === 'ArrowDown') { v.top += STEP; }
    else if (e.key === 'ArrowLeft') { v.side = 'l'; } else if (e.key === 'ArrowRight') { v.side = 'r'; }
    else { return; }
    e.preventDefault(); wr(v); apply();
  });
  grip.addEventListener('dblclick', function () { wr(null); dock.classList.add('sd-snap'); apply(); setTimeout(function () { dock.classList.remove('sd-snap'); }, 400); });
  window.addEventListener('resize', apply);
  window.addEventListener('storage', function (e) { if (e.key === KEY) { apply(); } });
  apply();
})();
