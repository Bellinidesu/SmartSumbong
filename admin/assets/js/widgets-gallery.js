// The all-widgets page: search and a group filter, and each frame loads only when it scrolls near.
(function () {
  var grid = document.getElementById('wg-grid'), q = document.getElementById('wg-q');
  if (!grid) return;
  var cards = [].slice.call(grid.querySelectorAll('.wg-card')), heads = [].slice.call(grid.querySelectorAll('.wg-h')), group = '';
  var io = 'IntersectionObserver' in window ? new IntersectionObserver(function (es) {
    es.forEach(function (e) { if (e.isIntersecting) { var f = e.target.querySelector('iframe'); if (f && !f.src) f.src = f.dataset.src; io.unobserve(e.target); } });
  }, { rootMargin: '500px 0px' }) : null;
  cards.forEach(function (c) { if (io) io.observe(c); else c.querySelector('iframe').src = c.querySelector('iframe').dataset.src; });
  function apply() {
    var s = q.value.trim().toLowerCase(), seen = {};
    cards.forEach(function (c) { var on = (!group || c.dataset.g === group) && (!s || c.dataset.s.indexOf(s) >= 0); c.hidden = !on; if (on) seen[c.dataset.g] = 1; });
    heads.forEach(function (h) { h.hidden = !seen[h.dataset.g]; });
  }
  q.addEventListener('input', apply);
  document.querySelector('.wg-tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    group = b.dataset.g; [].forEach.call(this.children, function (x) { x.setAttribute('aria-pressed', String(x === b)); }); apply();
  });
})();
