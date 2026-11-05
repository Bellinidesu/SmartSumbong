/* The press flow (7 Nov 2026): what happens when someone presses something, the same on every page.
 *
 * htmx (assets/vendor/htmx, 0BSD) fetches the page's own HTML and swaps only the part that changed; the server still renders every
 * page and still decides who may see what. This file is the portal's layer over it:
 *   - its configuration (no eval, no scripts run from swapped HTML, no page HTML kept in localStorage, same-origin only);
 *   - a thin progress bar while anything is in flight, so a press always answers;
 *   - when a fetch fails, a toast and the plain page load as a fallback, so a press is never lost;
 *   - focus kept on the pressed control, or moved to the region that changed, and the change read out to screen readers;
 *   - one registry (ssPress.ready) so the portal's widgets (pickers, choosers) attach themselves to new content as they do on load.
 * Without JavaScript, or without htmx, every link and form works the way it always has.
 */
(function () {
  'use strict';
  var htmx = window.htmx;
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  var lang = (document.documentElement.lang || 'en').slice(0, 2) === 'fi' ? 'fil' : 'en';
  var TXT = lang === 'en'
    ? { fail: 'That did not load. Opening it the usual way…', offline: 'You seem to be offline. Try again when you are back online.', updated: 'Updated' }
    : { fail: 'Hindi ito nag-load. Binubuksan sa karaniwang paraan…', offline: 'Mukhang offline ka. Subukan muli kapag online ka na.', updated: 'Na-update' };

  // ---- widgets that attach themselves to content: run now for the page, and again for every piece of HTML that is swapped in
  var inits = [];
  window.ssPress = {
    ready: function (fn) { inits.push(fn); try { fn(document); } catch (e) { if (window.console) console.error(e); } },
    announce: announce
  };
  // the portal's own widgets: on the page they set themselves up; in swapped HTML they are set up here
  window.ssPress.ready(function (root) {
    if (root === document) return;
    if (window.ssPickersInit) window.ssPickersInit(root);
    if (window.ssChooserInit) window.ssChooserInit(root);
  });
  function runInits(root) { inits.forEach(function (fn) { try { fn(root); } catch (e) { if (window.console) console.error(e); } }); }

  // ---- a polite live region for what changed
  var live = document.createElement('div');
  live.className = 'p-sr'; live.setAttribute('role', 'status'); live.setAttribute('aria-live', 'polite');
  document.body.appendChild(live);
  function announce(msg) { live.textContent = ''; setTimeout(function () { live.textContent = msg; }, 30); }

  // ---- the progress bar: it shows only for a request that takes longer than a blink, and finishes cleanly
  var bar = document.createElement('div');
  bar.className = 'ss-progress'; bar.setAttribute('aria-hidden', 'true');
  document.body.appendChild(bar);
  var inflight = 0, showT = null;
  function busy(on) {
    if (on) { if (inflight++ === 0) { clearTimeout(showT); showT = setTimeout(function () { bar.className = 'ss-progress is-on'; }, 120); } document.documentElement.setAttribute('aria-busy', 'true'); return; }
    if (--inflight > 0) return; inflight = 0; clearTimeout(showT);
    document.documentElement.removeAttribute('aria-busy');
    if (bar.classList.contains('is-on')) { bar.className = 'ss-progress is-on is-done'; setTimeout(function () { bar.className = 'ss-progress'; }, 380); }
  }

  if (!htmx) return;
  htmx.config.globalViewTransitions = !reduce && typeof document.startViewTransition === 'function';

  document.addEventListener('htmx:beforeRequest', function () { busy(true); });
  document.addEventListener('htmx:afterRequest', function () { busy(false); });

  // a failed fetch never strands the press: a GET opens the plain page instead; a POST says so and leaves the form as it was
  function fallback(e) {
    var d = e.detail || {}, cfg = d.requestConfig || {}, verb = String(cfg.verb || 'get').toLowerCase();
    if (!navigator.onLine) { window.pToast && pToast(TXT.offline); return; }
    if (verb === 'get' && cfg.path) { window.pToast && pToast(TXT.fail); location.href = cfg.path; return; }
    window.pToast && pToast(TXT.fail.replace(/ Opening.*$| Binubuksan.*$/, ''));
  }
  document.addEventListener('htmx:responseError', fallback);
  document.addEventListener('htmx:sendError', fallback);
  document.addEventListener('htmx:swapError', fallback);
  document.addEventListener('htmx:timeout', fallback);

  // focus: the pressed control keeps it when it is still on the page; otherwise the region that changed takes it (without scrolling)
  var pressed = null;
  document.addEventListener('htmx:beforeRequest', function (e) { pressed = document.activeElement; });
  document.addEventListener('htmx:afterSettle', function (e) {
    var t = e.detail && e.detail.target;
    if (t && t.nodeType === 1) runInits(t);
    if (pressed && document.contains(pressed)) { if (pressed !== document.activeElement && pressed.focus) pressed.focus({ preventScroll: true }); }
    else if (t && t.nodeType === 1) { if (!t.hasAttribute('tabindex')) t.setAttribute('tabindex', '-1'); t.focus({ preventScroll: true }); }
    pressed = null;
    var say = t && t.getAttribute && (t.getAttribute('data-announce') || t.getAttribute('aria-label'));
    announce(say ? say : TXT.updated);
  });

  // a page restored from the back-forward cache comes back without a stuck bar
  window.addEventListener('pageshow', function (e) { if (e.persisted) { inflight = 1; busy(false); } });
})();
