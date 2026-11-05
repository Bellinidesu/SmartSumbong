// A chooser of links (Case Reports' committees) with the Report Summary tabs' motion: the chosen one is a pill, and when another is picked the
// pill slides to it and changes colour on the way. The links still load the page; the pill is drawn where the last pick was and glides to the new one.
//   <nav data-chooser="a.cm-chip"> ... </nav>      the chosen link has .p-on; its --g1/--g2/--g3/--ct colour the pill
(function () {
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.querySelectorAll('nav[data-chooser]').forEach(function (nav) {
    var items = [].slice.call(nav.querySelectorAll(nav.getAttribute('data-chooser') || 'a'));
    if (!items.length) return;
    var cur = nav.querySelector('.p-on') || items[0], key = 'ss-chooser:' + location.pathname;
    var ind = document.createElement('span'); ind.className = 'cm-ind'; ind.setAttribute('aria-hidden', 'true'); nav.insertBefore(ind, nav.firstChild);
    function paint(el, instant) {
      var cs = getComputedStyle(el);
      [['--ig1', '--g1'], ['--ig2', '--g2'], ['--ig3', '--g3'], ['--ict', '--ct']].forEach(function (p) { var v = cs.getPropertyValue(p[1]).trim(); if (v) ind.style.setProperty(p[0], v); });
      if (instant || reduce) ind.style.transition = 'none';
      ind.style.width = el.offsetWidth + 'px'; ind.style.height = el.offsetHeight + 'px'; ind.style.transform = 'translate(' + el.offsetLeft + 'px,' + el.offsetTop + 'px)';
      if (instant || reduce) { void ind.offsetWidth; ind.style.transition = ''; }
    }
    var from = -1;
    try { from = parseInt(sessionStorage.getItem(key), 10); sessionStorage.removeItem(key); } catch (e) { from = -1; }
    var start = items[from] && items[from] !== cur ? items[from] : cur;
    paint(start, true); nav.classList.add('has-ind');
    if (start !== cur) setTimeout(function () { paint(cur, false); }, 60);
    nav.addEventListener('click', function (e) {
      var a = e.target.closest('a'); if (!a || a.getAttribute('href') === '#' || e.ctrlKey || e.metaKey || e.shiftKey || e.button) return;
      try { sessionStorage.setItem(key, String(items.indexOf(cur))); } catch (x) {}
    });
    // a chooser that filters in the page (no reload): the pill follows the chosen one as its class moves
    if (window.MutationObserver) new MutationObserver(function () { var on = nav.querySelector('.p-on'); if (on && on !== cur) { cur = on; paint(cur, false); } }).observe(nav, { attributes: true, subtree: true, attributeFilter: ['class'] });
    // a chooser inside a tab that is hidden when the page loads has no size yet: it is drawn when it first has one, and whenever it changes
    if (window.ResizeObserver) new ResizeObserver(function () { if (nav.offsetWidth) paint(cur, true); }).observe(nav);
    window.addEventListener('resize', function () { paint(cur, true); });
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { paint(cur, true); });
  });
})();
