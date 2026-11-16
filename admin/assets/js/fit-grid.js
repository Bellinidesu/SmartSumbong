/* Grids whose last row is full (16 Nov 2026, Ace: "no dead space, no lone card"). A container marked data-fit="N" holds cards at least N px wide; this picks the number of columns so the cards
   fill every row: six cards go three by two, never four and two. A grid with fewer cards than columns uses only as many columns as it has cards, so they share the width. On a tile
   deck (data-tiles) it counts the small tiles, not the open group above them, and does nothing while the tiles are off. It looks again when the box is resized or the page swaps content. */
(function () {
  'use strict';
  var GAP = 14;
  function kids(g) { return [].filter.call(g.children, function (c) { return !c.classList.contains('tile-open') && c.offsetParent !== null; }); }
  function columns(n, w, min) {
    var max = Math.max(1, Math.floor((w + GAP) / (min + GAP)));
    if (n <= max) { return Math.max(1, n); }
    var c;
    for (c = max; c >= 2; c--) { if (n % c === 0) { return c; } }
    var best = max, rest = n % max || max;
    for (c = max; c >= 2; c--) { var r = n % c || c; if (r > rest) { best = c; rest = r; } }
    return best;
  }
  function fit(g) {
    if (g.hasAttribute('data-tiles') && !g.classList.contains('ss-tiles')) { g.style.gridTemplateColumns = ''; return; }
    var n = kids(g).length, w = g.clientWidth; if (!n || !w) { return; }
    g.style.gridTemplateColumns = 'repeat(' + columns(n, w, +g.getAttribute('data-fit') || 260) + ', minmax(0, 1fr))';
  }
  function all(root) { [].forEach.call((root || document).querySelectorAll('[data-fit]'), function (g) { fit(g); if (!g._fit && window.ResizeObserver) { g._fit = new ResizeObserver(function () { fit(g); }); g._fit.observe(g); } }); }
  document.addEventListener('htmx:afterSettle', function () { all(document); });
  if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', function () { all(document); }); } else { all(document); }
  window.addEventListener('load', function () { all(document); });
})();
