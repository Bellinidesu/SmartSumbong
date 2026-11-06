// Once after each sign-in the dashboard draws itself in: cards rise, lines trace, rings sweep, numbers count up.
window.ssIntro = function () {
  if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  if (!Element.prototype.animate) return;
  var ease = 'cubic-bezier(.2,.8,.2,1)';
  // the header row first: the greeting rises, the engine button pops, the month, the time and Live follow
  var top = document.querySelectorAll('.p-dash-top > *:not(.p-spacer):not(form), .p-dash-top form > *');
  [].forEach.call(top, function (el, i) {
    el.animate([{ opacity: 0, transform: 'translateY(-10px)' }, { opacity: 1, transform: 'none' }], { duration: 560, delay: i * 80, easing: ease, fill: 'backwards' });
  });
  var brain = document.querySelector('.p-dash-top .ss-brain-btn');
  if (brain) brain.animate([{ transform: 'scale(.5) rotate(-12deg)', opacity: 0 }, { transform: 'scale(1.12) rotate(3deg)', opacity: 1, offset: .65 }, { transform: 'none', opacity: 1 }], { duration: 760, delay: 220, easing: 'cubic-bezier(.2,.9,.3,1)', fill: 'backwards' });
  var live = document.getElementById('live-badge');
  if (live) live.animate([{ transform: 'scale(.7)', opacity: 0 }, { transform: 'scale(1.08)', opacity: 1, offset: .7 }, { transform: 'none', opacity: 1 }], { duration: 600, delay: 520, easing: ease, fill: 'backwards' });
  document.querySelectorAll('.p-main .p-card, .p-main .ss-panel').forEach(function (el, i) {
    el.animate([{ opacity: 0, transform: 'translateY(14px)' }, { opacity: 1, transform: 'none' }], { duration: 520, delay: 160 + i * 70, easing: ease, fill: 'backwards' });
  });
  // a month with nothing in it draws itself in too: the dotted ring spins up from nothing, the 0 settles, the words fade up under it
  document.querySelectorAll('.p-donut svg.is-empty .trk').forEach(function (c, i) {
    c.animate([{ opacity: 0, transform: 'rotate(-120deg) scale(.86)' }, { opacity: 1, transform: 'none' }], { duration: 1000, delay: 380 + i * 120, easing: ease, fill: 'backwards' });
  });
  document.querySelectorAll('.p-donut-card.is-empty .p-center').forEach(function (c, i) {
    c.animate([{ opacity: 0, transform: 'scale(.6)' }, { opacity: 1, transform: 'scale(1.08)', offset: .7 }, { opacity: 1, transform: 'none' }], { duration: 650, delay: 700 + i * 120, easing: ease, fill: 'backwards' });
  });
  document.querySelectorAll('.p-main .p-empty-state:not([hidden])').forEach(function (c, i) {
    c.animate([{ opacity: 0, transform: 'translateY(10px)' }, { opacity: 1, transform: 'none' }], { duration: 600, delay: 900 + i * 100, easing: ease, fill: 'backwards' });
  });
  ['tile-resolved-value', 'tile-escalated-value', 'tile-overdue-value'].forEach(function (id, i) {
    var el = document.getElementById(id);
    if (el && !(parseInt(el.textContent, 10) > 0)) el.animate([{ transform: 'scale(.5)', opacity: 0 }, { transform: 'scale(1.12)', opacity: 1, offset: .7 }, { transform: 'none', opacity: 1 }], { duration: 560, delay: 450 + i * 90, easing: ease, fill: 'backwards' });
  });
  document.querySelectorAll('#chart-received path[fill="none"], #chart-efficiency path[fill="none"]').forEach(function (path, i) {
    if (!path.getTotalLength) return;
    var len = path.getTotalLength(); if (!len) return;
    path.animate([{ strokeDasharray: len + ' ' + len, strokeDashoffset: len }, { strokeDasharray: len + ' ' + len, strokeDashoffset: 0 }], { duration: 1200, delay: 250 + i * 150, easing: ease, fill: 'backwards' });
  });
  document.querySelectorAll('#chart-received path[fill^="url"], #chart-efficiency path[fill^="url"]').forEach(function (path) {
    path.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 700, delay: 800, easing: 'ease-out', fill: 'backwards' });
  });
  document.querySelectorAll('#donut-status circle[data-i], #donut-category circle[data-i]').forEach(function (c, i) {
    var to = c.getAttribute('stroke-dasharray'); if (!to) return;
    c.animate([{ strokeDasharray: '0 100' }, { strokeDasharray: to }], { duration: 900, delay: 300 + i * 110, easing: ease, fill: 'backwards' });
  });
  ['tile-resolved-value', 'tile-escalated-value', 'tile-overdue-value', 'status-donut-total', 'category-donut-total'].forEach(function (id) {
    var el = document.getElementById(id), n = el ? parseInt(el.textContent, 10) : 0;
    if (!(n > 0)) return;
    var t0 = null;
    (function step(t) {
      if (t0 === null) t0 = t;
      var k = Math.min(1, (t - t0) / 1000), e = 1 - Math.pow(1 - k, 3);
      el.textContent = String(Math.round(n * e));
      if (k < 1) requestAnimationFrame(step); else el.textContent = String(n);
    })(performance.now());
  });
};
