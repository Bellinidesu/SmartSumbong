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
      // a background refresh never cancels something a person pressed: while a press is on its way it steps aside (the next round
      // of the refresh, or the press's own answer, brings the list up to date)
      if (typeof inflight !== 'undefined' && inflight.size) return null;
      // nor does it take away what someone is in the middle of: typing in the region, a dropdown open, a dialog open. It waits, and
      // runs when they leave it.
      if (editing(sel)) { pendingRefresh = sel; return null; }
      pendingRefresh = null;
      return htmx.ajax('GET', location.pathname + location.search, { target: sel, select: sel, swap: 'outerHTML', headers: { 'X-Press-Quiet': '1' } });
    }
  };
  var pendingRefresh = null;
  function editing(sel) {
    var region = document.querySelector(sel), el = document.activeElement;
    // typing: a text box or a text area (a tick box, a radio or a button is not; ticks are kept across a refresh anyway)
    var typing = el && (el.tagName === 'TEXTAREA' || el.isContentEditable || (el.tagName === 'INPUT' && /^(text|search|email|tel|url|number|password|date|month|week|time|datetime-local|)$/.test(el.type || '')));
    if (region && typing && region.contains(el)) return true;
    if (document.documentElement.classList.contains('sdp-live')) return true;   // one of the portal's dropdowns or calendars is open
    if (document.querySelector('dialog[open], .p-scrim.p-on, .cr-scrim')) return true;
    return false;
  }
  function retryRefresh() { setTimeout(function () { if (pendingRefresh && !editing(pendingRefresh)) window.ssPress.refresh(pendingRefresh); }, 60); }
  document.addEventListener('focusout', retryRefresh);
  document.addEventListener('click', retryRefresh);
  document.addEventListener('keyup', function (e) { if (e.key === 'Escape') retryRefresh(); });
  function quietReq(e) { var c = e && e.detail && e.detail.requestConfig; return !!(c && c.headers && c.headers['X-Press-Quiet']); }
  // the portal's own widgets: on the page they set themselves up; in swapped HTML they are set up here
  window.ssPress.ready(function (root) {
    if (root === document) return;
    if (window.ssPickersInit) window.ssPickersInit(root);
    if (window.ssChooserInit) window.ssChooserInit(root);
    if (window.ssPaintOpen) window.ssPaintOpen();   // who is looking at each case, drawn again into the new rows (presence.js)
  });
  function runInits(root) { inits.forEach(function (fn) { try { fn(root); } catch (e) { if (window.console) console.error(e); } }); }

  // ---- a polite live region for what changed
  var live = document.createElement('div');
  live.className = 'p-sr'; live.setAttribute('role', 'status'); live.setAttribute('aria-live', 'polite');
  document.body.appendChild(live);
  function announce(msg) { live.textContent = ''; setTimeout(function () { live.textContent = msg; }, 30); }

  // ---- the progress bar: it shows only for a request that takes longer than half a second (Hotwire Turbo's own default), and
  // finishes cleanly. Every press goes to the server (the Philippines to Singapore), so a bar after 120 ms showed on
  // every press; the pressed control and the chooser's pill already answer at once (7 Nov 2026).
  var bar = document.createElement('div');
  bar.className = 'ss-progress'; bar.setAttribute('aria-hidden', 'true');
  document.body.appendChild(bar);
  // Every request that started is tracked by itself until it finishes, is cancelled or fails (a newer press cancels an older one; a
  // cancelled request sends no "finished"), so the bar can never be left on. A watchdog clears anything older than 20 seconds.
  var inflight = new Map(), showT = null;
  function paintBar() {
    if (inflight.size) {
      if (!bar.classList.contains('is-on') && !showT) showT = setTimeout(function () { showT = null; if (inflight.size) bar.className = 'ss-progress is-on'; }, 500);
      return;
    }
    // (the page itself is not marked busy: an attribute on <html> that changes an inherited style made the browser restyle every
    // element twice per press, about 130 ms on a laptop-speed CPU)
    clearTimeout(showT); showT = null;
    if (bar.classList.contains('is-on')) { bar.className = 'ss-progress is-on is-done'; setTimeout(function () { if (!inflight.size) bar.className = 'ss-progress'; }, 380); }
  }
  function start(key) { inflight.set(key, Date.now()); paintBar(); }
  function end(key) { if (inflight.delete(key)) paintBar(); }
  setInterval(function () { var now = Date.now(), gone = false; inflight.forEach(function (t, k) { if (now - t > 20000) { inflight.delete(k); gone = true; } }); if (gone) paintBar(); }, 2000);

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
      start(f);
      var post = String(f.getAttribute('method') || 'get').toLowerCase() === 'post';
      f._pressT = setTimeout(function () { release(f); end(f); }, post ? 25000 : 6000);
    }, 0);
  });
  function release(f) {
    clearTimeout(f._pressT); delete f.dataset.pressSending; f.removeAttribute('aria-busy');
    f.querySelectorAll('.is-sending').forEach(function (b) { b.classList.remove('is-sending'); b.removeAttribute('aria-disabled'); });
    var id = f.id; if (id) document.querySelectorAll('[form="' + id + '"].is-sending').forEach(function (b) { b.classList.remove('is-sending'); b.removeAttribute('aria-disabled'); });
  }
  // a dropdown that sends its form on change (data-autosubmit) also shows the bar
  // a dropdown that sends its plain form on change shows the bar until the next page; one that htmx sends is tracked as its request
  document.addEventListener('change', function (e) {
    var el = e.target.closest && e.target.closest('[data-autosubmit]'); if (!el || !el.form) return;
    var f = el.form; if (f.closest('[hx-boost="true"]') || f.hasAttribute('hx-get') || f.hasAttribute('hx-post')) return;
    start(f); setTimeout(function () { end(f); }, 8000);
  });
  window.addEventListener('pageshow', function (e) { if (e.persisted) document.querySelectorAll('form[data-press-sending]').forEach(release); });

  if (!htmx) return;
  // no view transition on a swap (7 Nov 2026): the browser froze the page, took a picture of it and cross-faded, about 120 ms on
  // every press at laptop speed; the region's own short fade (press.css) stays
  htmx.config.globalViewTransitions = false;

  function xkey(e) { return (e.detail && (e.detail.xhr || (e.detail.requestConfig && e.detail.requestConfig.xhr))) || null; }
  document.addEventListener('htmx:beforeRequest', function (e) { var k = xkey(e); if (k && !quietReq(e)) start(k); });
  ['htmx:afterRequest', 'htmx:abort', 'htmx:sendAbort', 'htmx:sendError', 'htmx:responseError', 'htmx:timeout', 'htmx:swapError'].forEach(function (n) {
    document.addEventListener(n, function (e) { var k = xkey(e); if (k) end(k); });
  });
  document.addEventListener('htmx:afterSettle', function () { inflight.forEach(function (t, k) { if (k && k.readyState === 4) inflight.delete(k); }); paintBar(); });

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

  // a save sent in place: the message the server put on the page (its green or red line) comes as a toast, unless the region that is
  // swapped in already shows it; the save's region is announced
  var saveNote = null, sideNav = null, synced = null;
  document.addEventListener('htmx:beforeSwap', function (e) {
    var c = e.detail && e.detail.requestConfig; saveNote = null; sideNav = null; synced = null;
    if (!c || !e.detail.serverResponse) return;
    var doc; try { doc = new DOMParser().parseFromString(e.detail.serverResponse, 'text/html'); } catch (x) { return; }
    // the sidebar's counts (unread notifications, cases waiting) follow every answer, saves and live refreshes alike
    var nav = doc.getElementById('side-nav'); if (nav) sideNav = nav.innerHTML;
    // anything outside the region that shows the same view (data-press-sync with an id: a page's title line, its engine window)
    // follows the answer too, so the parts that stay put never contradict the part that changed
    document.querySelectorAll('[data-press-sync][id]').forEach(function (el) {
      var fresh = doc.getElementById(el.id); if (fresh) { synced = synced || []; synced.push([el.id, fresh.innerHTML]); }
    });
    if (String(c.verb).toLowerCase() === 'get') return;
    var sel = c.elt && c.elt.closest && c.elt.closest('[hx-select]'), region = sel ? doc.querySelector(sel.getAttribute('hx-select')) : null;
    var f = doc.querySelector('.p-flash[role="status"], .p-flash[role="alert"], .p-flash');
    if (f && !(region && region.contains(f)) && f.textContent.trim()) saveNote = f.textContent.replace(/\s+/g, ' ').trim();
  });
  document.addEventListener('htmx:afterSettle', function () {
    if (sideNav !== null) { var cur = document.getElementById('side-nav'); if (cur && cur.innerHTML !== sideNav) cur.innerHTML = sideNav; sideNav = null; }
    if (synced) { synced.forEach(function (p) { var el = document.getElementById(p[0]); if (el && el.innerHTML !== p[1]) el.innerHTML = p[1]; }); synced = null; }
  });
  document.addEventListener('htmx:afterSettle', function () { if (saveNote) { if (window.pToast) pToast(saveNote); saveNote = null; } });

  // focus: the pressed control keeps it when it is still on the page; otherwise the region that changed takes it (without scrolling)
  var pressed = null;
  var pressedId = '', pressedHref = '';
  document.addEventListener('htmx:beforeRequest', function (e) { if (!quietReq(e)) { pressed = document.activeElement; pressedId = pressed && pressed.id || ''; pressedHref = pressed && pressed.tagName === 'A' ? pressed.getAttribute('href') || '' : ''; } });
  document.addEventListener('htmx:afterSettle', function (e) {
    var t = e.detail && e.detail.target;
    // after an outerHTML swap htmx names the old target, which is no longer on the page: the new one is found by its id
    if (t && t.nodeType === 1 && !document.contains(t) && t.id) t = document.getElementById(t.id) || t;
    if (t && t.nodeType === 1) runInits(t);
    if (quietReq(e)) return;
    var same = null;
    if (!(pressed && document.contains(pressed))) {
      if (pressedId) same = document.getElementById(pressedId);
      // a link without an id (a chooser tab, a page number): the link to the same address in the new content keeps the place
      if (!same && pressedHref && t && t.querySelector) { try { same = t.querySelector('a[href="' + (window.CSS && CSS.escape ? CSS.escape(pressedHref) : pressedHref) + '"]'); } catch (x) { same = null; } }
    }
    if (pressed && document.contains(pressed)) { if (pressed !== document.activeElement && pressed.focus) pressed.focus({ preventScroll: true }); }
    else if (same && same.focus) {   // the same control in the new content (the search box keeps its cursor, at the end of what was typed)
      same.focus({ preventScroll: true });
      if (/^(INPUT|TEXTAREA)$/.test(same.tagName) && typeof same.setSelectionRange === 'function' && /^(text|search|tel|email|url|)$/.test(same.type || '')) { var n = same.value.length; try { same.setSelectionRange(n, n); } catch (x) {} }
    }
    else if (t && t.nodeType === 1) { if (!t.hasAttribute('tabindex')) t.setAttribute('tabindex', '-1'); t.focus({ preventScroll: true }); }
    pressed = null; pressedId = ''; pressedHref = '';
    var say = t && t.getAttribute && (t.getAttribute('data-announce') || t.getAttribute('aria-label'));
    announce(say ? say : TXT.updated);
  });

  // a page restored from the back-forward cache comes back without a stuck bar
  window.addEventListener('pageshow', function (e) { if (e.persisted) { inflight.clear(); paintBar(); } });
})();
