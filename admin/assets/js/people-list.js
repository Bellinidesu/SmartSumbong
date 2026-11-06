/* Residents and Personnel: the List / Squares switch, ticking rows, and the review queue.
   - View: a class on #ss-people, remembered in this browser (the same rows, drawn two ways).
   - Ticking: "Review one after another" keeps the chosen ids in this tab (sessionStorage); the account page shows "Next in the queue".
   - It reads the DOM only, so the 20-second live refresh that rewrites the rows needs no special care. */
(function () {
  var KEY = 'ss-people-queue', VIEW = 'ss-people-view';
  function load() { try { return JSON.parse(sessionStorage.getItem(KEY) || '[]'); } catch (e) { return []; } }
  function save(q) { try { sessionStorage.setItem(KEY, JSON.stringify(q)); } catch (e) { /* the queue just is not kept */ } }
  var $ = function (id) { return document.getElementById(id); };

  // ---- account page: the queue bar ----
  var bar = $('ss-rqbar');
  if (bar) {
    var id = bar.dataset.id, self = bar.dataset.self, q = load(), at = q.indexOf(id);
    if (at > -1) { q.splice(at, 1); save(q); }
    if (q.length) {
      $('ss-rqbar-n').textContent = q.length;
      $('ss-rqbar-next').href = self + '?id=' + encodeURIComponent(q[0]);
      bar.hidden = false;
      $('ss-rqbar-drop').addEventListener('click', function () { save([]); bar.hidden = true; });
    }
    return;
  }

  // ---- list page ----
  // The press flow swaps the list in place (filters, chooser, pager, the 20-second refresh), so nothing here holds on to an element:
  // the switch, the ticks and the bulk bar are handled page-wide and look up what is on screen. Ticks are kept by id across a
  // refresh; a new view (a filter, a tab, a page) starts with none ticked, as a mail list does.
  if (!$('ss-people')) return;
  var strip = $('ss-rqstrip'), self2 = strip ? strip.dataset.self : 'residents.php';
  function view() { var v = 'list'; try { v = localStorage.getItem(VIEW) || 'list'; } catch (e) { /* default view */ } return v; }
  function setView(v) {
    var box = $('ss-people'); if (box) box.classList.toggle('ss-sq', v === 'sq');
    var sw = document.querySelector('.ss-viewsw'); if (sw) [].forEach.call(sw.querySelectorAll('button'), function (b) { b.setAttribute('aria-pressed', String(b.dataset.view === v)); });
  }
  setView(view());
  document.addEventListener('click', function (e) {
    var b = e.target.closest('.ss-viewsw button'); if (!b) return;
    setView(b.dataset.view); try { localStorage.setItem(VIEW, b.dataset.view); } catch (x) { /* not remembered */ }
  });

  var picked = {};
  function boxes() { var box = $('ss-people'); return box ? [].slice.call(box.querySelectorAll('.ss-cb')) : []; }
  function sync() {
    var n = 0, bs = boxes();
    bs.forEach(function (c) {
      var on = !!picked[c.value]; c.checked = on; if (on) n++;
      var tr = c.closest('tr'); if (tr) tr.classList.toggle('ss-picked', on);
    });
    if ($('ss-bulk-n')) $('ss-bulk-n').textContent = n; if ($('ss-bulk')) $('ss-bulk').hidden = n === 0;
    var all = $('ss-all'); if (all) all.checked = bs.length > 0 && bs.every(function (c) { return picked[c.value]; });
  }
  document.addEventListener('change', function (e) {
    if (!e.target.closest('#ss-people')) return;
    if (e.target.id === 'ss-all') { boxes().forEach(function (c) { picked[c.value] = e.target.checked; }); }
    else if (e.target.classList.contains('ss-cb')) { picked[e.target.value] = e.target.checked; }
    sync();
  });
  // the in-page redraw (without the press flow) rewrites the rows: tick them again from what is remembered
  var tb = $('accounts-tbody'); if (tb && window.MutationObserver) new MutationObserver(sync).observe(tb, { childList: true });
  // a swap: a quiet refresh keeps the ticks, a new view clears them; either way the view (list or squares) is drawn again
  document.addEventListener('htmx:afterSettle', function (e) {
    var c = e.detail && e.detail.requestConfig, quiet = !!(c && c.headers && c.headers['X-Press-Quiet']);
    if (!quiet) picked = {};
    setView(view()); sync();
  });
  document.addEventListener('click', function (e) {
    if (e.target.closest('#ss-bulk-clear')) { picked = {}; sync(); return; }
    if (!e.target.closest('#ss-bulk-go')) return;
    var ids = Object.keys(picked).filter(function (k) { return picked[k]; });
    if (!ids.length) return;
    var order = boxes().map(function (c) { return c.value; });   // in the order they are listed
    ids.sort(function (a, b) { return order.indexOf(a) - order.indexOf(b); });
    save(ids); location.href = self2 + '?id=' + encodeURIComponent(ids[0]);
  });

  // Personnel (super admin): the ticked tanods go to the committee picked; the form is posted with their ids
  document.addEventListener('submit', function (e) {
    var tcf = e.target; if (!tcf || tcf.id !== 'ss-bulk-tc') return;
    var ids = Object.keys(picked).filter(function (k) { return picked[k]; });
    if (!ids.length) { e.preventDefault(); return; }
    [].forEach.call(tcf.querySelectorAll('input[name="ids[]"]'), function (n) { n.remove(); });
    ids.forEach(function (id) { var i = document.createElement('input'); i.type = 'hidden'; i.name = 'ids[]'; i.value = id; tcf.appendChild(i); });
  }, true);

  // a queue left over from before: offer to continue it (again after a swap, which brings a new strip)
  function offerQueue() {
    var st = $('ss-rqstrip'), q2 = load(); if (!st || !q2.length) return;
    $('ss-rq-n').textContent = q2.length; $('ss-rq-go').href = (st.dataset.self || self2) + '?id=' + encodeURIComponent(q2[0]); st.hidden = false;
  }
  document.addEventListener('click', function (e) { if (e.target.closest('#ss-rq-drop')) { save([]); var st = $('ss-rqstrip'); if (st) st.hidden = true; } });
  document.addEventListener('htmx:afterSettle', offerQueue);
  offerQueue();
  sync();
})();
