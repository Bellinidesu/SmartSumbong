/* The case page's tabs (15 Nov 2026, Ace): Report, Evidence, Timeline, Feedback share one scrolling body inside the cream card, so the page fits the window.
   The panels are the page's own blocks (data-cc-tab); the other tabs' blocks are hidden by the server, this only switches them. The chosen tab is kept for this
   case in this browser tab (a save reloads the page), a link with #timeline (or #evidence, #feedback, #report) opens that tab, and picking a request in focus or a
   link to a concern opens Report. Arrow keys move between tabs. No inline handlers (strict CSP). */
(function () {
  'use strict';
  var bar = document.querySelector('.cc-tabs'); if (!bar) { return; }
  var tabs = [].slice.call(bar.querySelectorAll('[data-cc-go]'));
  var key = 'cc-tab:' + location.search.replace(/[^a-z0-9=-]/gi, '');
  var NAMES = tabs.map(function (b) { return b.getAttribute('data-cc-go'); });
  function show(name, focus) {
    if (NAMES.indexOf(name) < 0) { name = 'report'; }
    tabs.forEach(function (b) {
      var on = b.getAttribute('data-cc-go') === name;
      b.setAttribute('aria-selected', on ? 'true' : 'false'); b.setAttribute('tabindex', on ? '0' : '-1');
      if (on && focus) { b.focus(); }
    });
    [].forEach.call(document.querySelectorAll('[data-cc-tab]'), function (el) { el.hidden = el.getAttribute('data-cc-tab') !== name; });
    document.getElementById('cc-body').setAttribute('aria-labelledby', 'cc-tab-' + name);
    var body = document.getElementById('cc-body'); if (body && !focus) { body.scrollTop = 0; }
    try { sessionStorage.setItem(key, name); } catch (e) { /* private mode: the tab just is not remembered */ }
    if (name === 'report') { try { window.dispatchEvent(new Event('resize')); } catch (e) { /* the map keeps its size */ } }   // the map (Where) was hidden while another tab showed
  }
  window.ccShowTab = show;
  bar.addEventListener('click', function (e) { var b = e.target.closest ? e.target.closest('[data-cc-go]') : null; if (b) { show(b.getAttribute('data-cc-go'), false); } });
  bar.addEventListener('keydown', function (e) {
    var i = tabs.indexOf(document.activeElement); if (i < 0) { return; }
    var j = e.key === 'ArrowRight' ? (i + 1) % tabs.length : e.key === 'ArrowLeft' ? (i + tabs.length - 1) % tabs.length : e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : -1;
    if (j >= 0) { e.preventDefault(); show(tabs[j].getAttribute('data-cc-go'), true); }
  });
  // picking a request in focus, or following a link to a concern, shows the concerns (they are on Report)
  document.addEventListener('click', function (e) { if (e.target.closest && e.target.closest('#cf')) { show('report', false); } });
  var h = (location.hash || '').replace('#', ''), saved = null;
  try { saved = sessionStorage.getItem(key); } catch (e) { saved = null; }
  show(NAMES.indexOf(h) > -1 ? h : (saved || 'report'), false);
  window.addEventListener('hashchange', function () { var n = (location.hash || '').replace('#', ''); if (NAMES.indexOf(n) > -1) { show(n, false); } });
})();
