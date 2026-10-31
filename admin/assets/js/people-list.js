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
  var box = $('ss-people'); if (!box) return;
  var strip = $('ss-rqstrip'), self2 = strip ? strip.dataset.self : 'residents.php';
  var sw = document.querySelector('.ss-viewsw');
  function setView(v) {
    box.classList.toggle('ss-sq', v === 'sq');
    if (sw) [].forEach.call(sw.querySelectorAll('button'), function (b) { b.setAttribute('aria-pressed', String(b.dataset.view === v)); });
  }
  var saved = 'list'; try { saved = localStorage.getItem(VIEW) || 'list'; } catch (e) { /* default view */ }
  setView(saved);
  if (sw) sw.addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    setView(b.dataset.view); try { localStorage.setItem(VIEW, b.dataset.view); } catch (x) { /* not remembered */ }
  });

  var picked = {};
  function boxes() { return [].slice.call(box.querySelectorAll('.ss-cb')); }
  function sync() {
    var n = 0, bs = boxes();
    bs.forEach(function (c) {
      var on = !!picked[c.value]; c.checked = on; if (on) n++;
      var tr = c.closest('tr'); if (tr) tr.classList.toggle('ss-picked', on);
    });
    $('ss-bulk-n').textContent = n; $('ss-bulk').hidden = n === 0;
    var all = $('ss-all'); if (all) all.checked = bs.length > 0 && bs.every(function (c) { return picked[c.value]; });
  }
  box.addEventListener('change', function (e) {
    if (e.target.id === 'ss-all') { boxes().forEach(function (c) { picked[c.value] = e.target.checked; }); }
    else if (e.target.classList.contains('ss-cb')) { picked[e.target.value] = e.target.checked; }
    sync();
  });
  // a live refresh rewrites the rows: tick them again from what is remembered
  var tb = $('accounts-tbody'); if (tb && window.MutationObserver) new MutationObserver(sync).observe(tb, { childList: true });
  $('ss-bulk-clear').addEventListener('click', function () { picked = {}; sync(); });
  $('ss-bulk-go').addEventListener('click', function () {
    var ids = Object.keys(picked).filter(function (k) { return picked[k]; });
    if (!ids.length) return;
    var order = boxes().map(function (c) { return c.value; });   // in the order they are listed
    ids.sort(function (a, b) { return order.indexOf(a) - order.indexOf(b); });
    save(ids); location.href = self2 + '?id=' + encodeURIComponent(ids[0]);
  });

  // Personnel (super admin): the ticked tanods go to the committee picked; the form is posted with their ids
  var tcf = $('ss-bulk-tc');
  if (tcf) tcf.addEventListener('submit', function (e) {
    var ids = Object.keys(picked).filter(function (k) { return picked[k]; });
    if (!ids.length) { e.preventDefault(); return; }
    [].forEach.call(tcf.querySelectorAll('input[name="ids[]"]'), function (n) { n.remove(); });
    ids.forEach(function (id) { var i = document.createElement('input'); i.type = 'hidden'; i.name = 'ids[]'; i.value = id; tcf.appendChild(i); });
  });

  // a queue left over from before: offer to continue it
  var q2 = load();
  if (strip && q2.length) {
    $('ss-rq-n').textContent = q2.length; $('ss-rq-go').href = self2 + '?id=' + encodeURIComponent(q2[0]); strip.hidden = false;
    $('ss-rq-drop').addEventListener('click', function () { save([]); strip.hidden = true; });
  }
  sync();
})();
