// Once after each sign-in the dashboard draws itself in: cards rise, lines trace, rings sweep, numbers count up.
window.ssIntro = function () {
  if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  if (!Element.prototype.animate) return;
  var ease = 'cubic-bezier(.2,.8,.2,1)';
  document.querySelectorAll('.p-main .p-card, .p-main .ss-panel').forEach(function (el, i) {
    el.animate([{ opacity: 0, transform: 'translateY(14px)' }, { opacity: 1, transform: 'none' }], { duration: 520, delay: i * 70, easing: ease, fill: 'backwards' });
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
