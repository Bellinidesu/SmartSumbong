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
    announce: announce,
    // a live update: the region is fetched again at the address on screen, quietly (no bar, no focus move, nothing read out)
    refresh: function (sel) {
      if (!window.htmx || !document.querySelector(sel)) return null;
      return htmx.ajax('GET', location.pathname + location.search, { target: sel, select: sel, swap: 'outerHTML', headers: { 'X-Press-Quiet': '1' } });
    }
  };
  function quietReq(e) { var c = e && e.detail && e.detail.requestConfig; return !!(c && c.headers && c.headers['X-Press-Quiet']); }
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

  // ---- step 2: every save shows that it is working and cannot be sent twice (forms that load the next page the usual way).
  // The guard is set the moment the form is sent and lifted again if any script stopped the send (a confirm, the bot check, a
  // form handled by its own script), when the page comes back from the back-forward cache, or after a while for a form whose
  // answer does not replace the page (a download, a new tab), so a button is never left stuck.
  document.addEventListener('submit', function (e) {
    var f = e.target; if (!f || f.tagName !== 'FORM') return;
    if (f.hasAttribute('hx-post') || f.hasAttribute('hx-get') || f.hasAttribute('data-press-free')) return;   // htmx handles its own
    var sub = e.submitter || null;
    if (f.dataset.pressSending === '1') { e.preventDefault(); e.stopImmediatePropagation(); return; }   // a second press: ignored
    var newTab = (sub && sub.getAttribute('formtarget') === '_blank') || f.target === '_blank';
    f.dataset.pressSending = '1';
    setTimeout(function () {
      if (e.defaultPrevented || newTab) { release(f); return; }   // a script took over this send, or it opens elsewhere
      f.setAttribute('aria-busy', 'true');
      if (sub) { sub.classList.add('is-sending'); sub.setAttribute('aria-disabled', 'true'); }
      busy(true);
      var post = String(f.getAttribute('method') || 'get').toLowerCase() === 'post';
      f._pressT = setTimeout(function () { release(f); busy(false); }, post ? 25000 : 6000);
    }, 0);
  });
  function release(f) {
    clearTimeout(f._pressT); delete f.dataset.pressSending; f.removeAttribute('aria-busy');
    f.querySelectorAll('.is-sending').forEach(function (b) { b.classList.remove('is-sending'); b.removeAttribute('aria-disabled'); });
    var id = f.id; if (id) document.querySelectorAll('[form="' + id + '"].is-sending').forEach(function (b) { b.classList.remove('is-sending'); b.removeAttribute('aria-disabled'); });
  }
  // a dropdown that sends its form on change (data-autosubmit) also shows the bar
  document.addEventListener('change', function (e) { var el = e.target.closest && e.target.closest('[data-autosubmit]'); if (el && el.form) busy(true); });
  window.addEventListener('pageshow', function (e) { if (e.persisted) document.querySelectorAll('form[data-press-sending]').forEach(release); });

  if (!htmx) return;
  htmx.config.globalViewTransitions = !reduce && typeof document.startViewTransition === 'function';

  document.addEventListener('htmx:beforeRequest', function (e) { if (!quietReq(e)) busy(true); });
  document.addEventListener('htmx:afterRequest', function (e) { if (!quietReq(e)) busy(false); });

  // a failed fetch never strands the press: a GET opens the plain page instead; a POST says so and leaves the form as it was
  function fallback(e) {
    if (quietReq(e)) return;
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
  document.addEventListener('htmx:beforeRequest', function (e) { if (!quietReq(e)) pressed = document.activeElement; });
  document.addEventListener('htmx:afterSettle', function (e) {
    var t = e.detail && e.detail.target;
    if (t && t.nodeType === 1) runInits(t);
    if (quietReq(e)) return;
    if (pressed && document.contains(pressed)) { if (pressed !== document.activeElement && pressed.focus) pressed.focus({ preventScroll: true }); }
    else if (t && t.nodeType === 1) { if (!t.hasAttribute('tabindex')) t.setAttribute('tabindex', '-1'); t.focus({ preventScroll: true }); }
    pressed = null;
    var say = t && t.getAttribute && (t.getAttribute('data-announce') || t.getAttribute('aria-label'));
    announce(say ? say : TXT.updated);
  });

  // a page restored from the back-forward cache comes back without a stuck bar
  window.addEventListener('pageshow', function (e) { if (e.persisted) { inflight = 1; busy(false); } });
})();
