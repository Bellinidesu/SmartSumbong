/* The portal's motion, the script half (12 Nov 2026). motion.css moves things; this keeps the moving cheap.
   1. First open: body.mo-in is what lets the blocks of a page rise in; it comes off once they have, so a later swap never replays it. A page that was
      prerendered in the background (body.mo-hold, from the Sec-Purpose header) waits to play until it is actually shown.
   2. Decorative loops (glows, sweeps, pulses) run only while they can be seen: out of view, in a hidden tab, or after a minute without a touch of the
      mouse, keyboard or screen, they are paused, and they pick up again on the next movement. Loading spinners are never paused.
   Strict CSP: no inline handlers. */
(function () {
  'use strict';
  var b = document.body;
  if (!b) { return; }

  /* ---------- first open ---------- */
  if (b.classList.contains('mo-in')) {
    var done = function () { setTimeout(function () { b.classList.remove('mo-in'); }, 1100); };
    if (document.prerendering) { b.classList.add('mo-hold'); document.addEventListener('prerenderingchange', function () { b.classList.remove('mo-hold'); done(); }, { once: true }); }
    else { b.classList.remove('mo-hold'); done(); }
  }

  /* ---------- decorative loops only while they can be seen ---------- */
  if (!document.getAnimations || !('IntersectionObserver' in window)) { return; }
  var seen = new WeakMap(), watched = new WeakSet(), mine = new WeakSet(), idle = false, last = Date.now(), timer = null;
  var io = new IntersectionObserver(function (es) { es.forEach(function (e) { seen.set(e.target, e.isIntersecting); }); sync(); }, { rootMargin: '80px' });
  function loops() {
    return document.getAnimations().filter(function (a) {
      var e = a.effect; if (!e || !e.target || !e.getComputedTiming || e.getComputedTiming().iterations !== Infinity) { return false; }
      return !/spin|load|busy/i.test(a.animationName || '');
    });
  }
  function sync() {
    var stop = idle || document.hidden;
    loops().forEach(function (a) {
      var t = a.effect.target, vis = seen.get(t);
      if (vis === undefined) { return; }
      var off = stop || !vis;
      if (off && a.playState === 'running') { a.pause(); mine.add(a); }
      else if (!off && a.playState === 'paused' && mine.has(a)) { a.play(); mine.delete(a); }
    });
  }
  function scan() {
    loops().forEach(function (a) { var t = a.effect.target; if (!watched.has(t)) { watched.add(t); io.observe(t); } });
    sync();
  }
  var scanT = null;
  function soon() { clearTimeout(scanT); scanT = setTimeout(scan, 250); }
  document.addEventListener('animationstart', soon, true);
  document.addEventListener('htmx:afterSettle', soon);
  document.addEventListener('visibilitychange', sync);
  function touch() { last = Date.now(); if (idle) { idle = false; sync(); } }
  ['pointermove', 'pointerdown', 'keydown', 'wheel', 'touchstart'].forEach(function (ev) { window.addEventListener(ev, touch, { passive: true, capture: true }); });
  window.addEventListener('scroll', touch, { passive: true, capture: true });
  timer = setInterval(function () { if (!idle && Date.now() - last > 60000) { idle = true; sync(); } }, 5000);
  window.addEventListener('pagehide', function () { clearInterval(timer); });
  setTimeout(scan, 700);
})();
