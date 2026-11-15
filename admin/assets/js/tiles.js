/* Groups that turn into small tiles when there are many (15 Nov 2026, Ace). A container marked data-tiles holds children marked data-tile, each with a head marked data-tile-head.
   Up to three: they stay as they are, wide. Four or more: every group but one shrinks to its head (a small rectangle); the one that is open is wide on top and the rest sit
   in a tidy grid under it; pressing a tile opens it and the one that was open becomes a tile. Which one is open is remembered per container. No inline handlers (strict CSP). */
(function () {
  'use strict';
  var MIN = 4;
  function rd(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function wr(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* private window */ } }
  function setup(box) {
    var tiles = [].filter.call(box.children, function (c) { return c.hasAttribute('data-tile'); });
    var on = tiles.length >= MIN;
    box.classList.toggle('ss-tiles', on);
    tiles.forEach(function (t) {
      var h = t.querySelector(':scope > [data-tile-head]'); if (!h) { return; }
      if (!on) { t.classList.remove('tile-open'); h.removeAttribute('role'); h.removeAttribute('aria-expanded'); h.removeAttribute('tabindex'); if (h.dataset.tileHidden) { h.setAttribute('aria-hidden', 'true'); } return; }
      if (h.getAttribute('aria-hidden') === 'true') { h.dataset.tileHidden = '1'; h.removeAttribute('aria-hidden'); }
      h.setAttribute('role', 'button'); h.setAttribute('tabindex', '0');
    });
    if (!on) { return; }
    var key = 'ss-tile-' + (box.getAttribute('data-tiles') || 'x'), want = rd(key);
    var open = tiles.filter(function (t) { return t.getAttribute('data-tile') === want; })[0] || tiles[0];
    function show(t) {
      tiles.forEach(function (x) { var is = x === t; x.classList.toggle('tile-open', is); var h = x.querySelector(':scope > [data-tile-head]'); if (h) { h.setAttribute('aria-expanded', is ? 'true' : 'false'); } });
    }
    show(open);
    function pick(e) {
      var h = e.target.closest('[data-tile-head]'); if (!h || !box.classList.contains('ss-tiles')) { return; }
      var t = h.closest('[data-tile]'); if (!t || t.parentNode !== box || t.classList.contains('tile-open')) { return; }
      if (e.type === 'keydown' && e.key !== 'Enter' && e.key !== ' ') { return; }
      e.preventDefault(); show(t); wr(key, t.getAttribute('data-tile'));
      var top = t.getBoundingClientRect().top; if (top < 0) { t.scrollIntoView({ block: 'start' }); }
    }
    if (!box._tl) { box._tl = true; box.addEventListener('click', pick); box.addEventListener('keydown', pick); }
  }
  window.ssTiles = function (root) { [].forEach.call((root || document).querySelectorAll('[data-tiles]'), setup); };
  window.ssTiles(document);
})();
