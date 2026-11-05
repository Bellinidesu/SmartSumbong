// A chooser of links (Case Reports' committees) with the Report Summary tabs' motion: the chosen one is a pill, and when another is picked the
// pill slides to it and changes colour on the way. The links still load the page; the pill is drawn where the last pick was and glides to the new one.
//   <nav data-chooser="a.cm-chip"> ... </nav>      the chosen link has .p-on; its --g1/--g2/--g3/--ct colour the pill
(function () {
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  // run for the page now, and by the press flow (press.js) for a chooser that arrives in swapped HTML; a chooser is set up once
  window.ssChooserInit = function (root) { root.querySelectorAll('nav[data-chooser]:not([data-chooser-on])').forEach(setup); };
  function setup(nav) {
    nav.setAttribute('data-chooser-on', '1');
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
    var carry = window.__ssChooserCarry && window.__ssChooserCarry[location.pathname]; if (window.__ssChooserCarry) delete window.__ssChooserCarry[location.pathname];
    if (carry) {   // a chooser that arrived in a swap starts where the old one's pill was, and slides on to the chosen tab
      ind.style.transition = 'none'; ind.style.width = carry.w + 'px'; ind.style.height = carry.h + 'px'; ind.style.transform = 'translate(' + carry.x + 'px,' + carry.y + 'px)';
      ['--ig1', '--ig2', '--ig3', '--ict'].forEach(function (k) { if (carry[k]) ind.style.setProperty(k, carry[k]); });
      void ind.offsetWidth; ind.style.transition = ''; nav.classList.add('has-ind');
      requestAnimationFrame(function () { paint(cur, false); });
    } else {
      paint(start, true); nav.classList.add('has-ind');
      if (start !== cur) setTimeout(function () { paint(cur, false); }, 60);
    }
    nav.addEventListener('click', function (e) {
      var a = e.target.closest('a'); if (!a || a.getAttribute('href') === '#' || e.ctrlKey || e.metaKey || e.shiftKey || e.button) return;
      // swapped in place (the press flow): the pill moves now, before the answer, and the new list carries it on
      if (window.htmx && nav.closest('[hx-boost="true"]')) { items.forEach(function (x) { x.classList.toggle('p-on', x === a); }); return; }
      try { sessionStorage.setItem(key, String(items.indexOf(cur))); } catch (x) {}
    });
    // a chooser that filters in the page (no reload): the pill follows the chosen one as its class moves
    if (window.MutationObserver) new MutationObserver(function () { var on = nav.querySelector('.p-on'); if (on && on !== cur) { cur = on; paint(cur, false); } }).observe(nav, { attributes: true, subtree: true, attributeFilter: ['class'] });
    // a chooser inside a tab that is hidden when the page loads has no size yet: it is drawn when it first has one, and whenever it changes
    if (window.ResizeObserver) new ResizeObserver(function () { if (nav.offsetWidth) paint(cur, true); }).observe(nav);
    window.addEventListener('resize', function () { paint(cur, true); });
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { paint(cur, true); });
  }
  window.ssChooserInit(document);
  // before a swap replaces a chooser, where its pill is now is kept for the one that replaces it
  document.addEventListener('htmx:beforeSwap', function (e) {
    var t = e.detail && e.detail.target; if (!t || !t.querySelectorAll) return;
    t.querySelectorAll('nav[data-chooser].has-ind').forEach(function (nav) {
      var ind = nav.querySelector('.cm-ind'); if (!ind) return;
      var r = ind.getBoundingClientRect(), n = nav.getBoundingClientRect(), cs = getComputedStyle(ind), c = { x: r.left - n.left - nav.clientLeft, y: r.top - n.top - nav.clientTop, w: r.width, h: r.height };
      ['--ig1', '--ig2', '--ig3', '--ict'].forEach(function (k) { c[k] = cs.getPropertyValue(k).trim(); });
      (window.__ssChooserCarry = window.__ssChooserCarry || {})[location.pathname] = c;
    });
  });
})();
