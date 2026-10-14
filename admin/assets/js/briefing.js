// The briefing on Notifications: morning, afternoon or night. A tab makes the engine "think" for a moment (the same glow as the dashboard), then the numbers swap in.
(function () {
  var root = document.getElementById('ss-brief');
  if (!root) return;
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches, busy = false;
  function show(period) {
    root.querySelectorAll('[data-pane]').forEach(function (p) { p.hidden = p.dataset.pane !== period; });
    root.querySelectorAll('[data-period]').forEach(function (b) {
      var on = b.dataset.period === period;
      b.classList.toggle('p-on', on); b.setAttribute('aria-selected', String(on));
    });
    root.classList.remove('is-thinking'); root.classList.add('is-rise');
    setTimeout(function () { root.classList.remove('is-rise'); }, 700);
    busy = false;
  }
  root.querySelector('.ss-brief-tabs').addEventListener('click', function (e) {
    var b = e.target.closest('[data-period]');
    if (!b || busy || b.classList.contains('p-on')) return;
    if (reduce) { show(b.dataset.period); return; }
    busy = true; root.classList.add('is-thinking');
    setTimeout(function () { show(b.dataset.period); }, 650);
  });
})();
