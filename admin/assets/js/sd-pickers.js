/* Dropdowns and a month picker in the portal's own look, replacing the browser's.
 * Each one is a layer over the real <select> / <input type="month">: the real control
 * keeps the value, fires its own change event and still works without this file.
 *   sdPickers.select(selectEl, { dot: value => '#hex' | null })
 *   sdPickers.month(inputEl, { allTime: checkboxEl })
 */
(function () {
  if (window.sdPickers) return;
  var lang = (document.documentElement.lang || 'en').slice(0, 2) === 'fi' ? 'fil-PH' : 'en-US';
  var TXT = lang === 'en-US' ? { clear: 'All time', now: 'This month', prev: 'Previous year', next: 'Next year' } : { clear: 'Lahat ng panahon', now: 'Ngayong buwan', prev: 'Nakaraang taon', next: 'Susunod na taon' };
  var CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg>';
  var CAL = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/></svg>';
  var TICK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l5 5 9-10"/></svg>';
  var open = null;

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function close(refocus) {
    if (!open) return;
    var o = open; open = null; document.documentElement.classList.remove('sdp-live');
    o.pop.classList.remove('in'); o.pop.classList.add('out');
    o.btn.setAttribute('aria-expanded', 'false'); o.btn.classList.remove('open');
    setTimeout(function () { o.pop.remove(); }, 160);
    document.removeEventListener('pointerdown', onOutside, true); document.removeEventListener('keydown', onKey, true); window.removeEventListener('resize', onResize);
    if (refocus) o.btn.focus();
  }
  function onOutside(e) { if (open && !open.pop.contains(e.target) && !open.btn.contains(e.target)) close(false); }
  function onResize() { close(false); }
  function onKey(e) { if (open && open.key) open.key(e); }
  function place(btn, pop) {
    var r = btn.getBoundingClientRect(), w = Math.max(pop.offsetWidth, r.width), h = pop.offsetHeight, below = innerHeight - r.bottom, up = below < h + 16 && r.top > below;
    pop.style.minWidth = r.width + 'px';
    var left = Math.min(Math.max(8, r.left), innerWidth - w - 8);
    pop.style.left = left + 'px'; pop.style.top = (up ? Math.max(8, r.top - h - 8) : r.bottom + 8) + 'px';
    pop.style.transformOrigin = (up ? 'bottom' : 'top') + ' left';
  }
  function show(btn, pop, key) {
    close(false); document.body.appendChild(pop); place(btn, pop);
    void pop.offsetWidth; pop.classList.add('in');
    btn.setAttribute('aria-expanded', 'true'); btn.classList.add('open');
    open = { btn: btn, pop: pop, key: key }; document.documentElement.classList.add('sdp-live');
    document.addEventListener('pointerdown', onOutside, true); document.addEventListener('keydown', onKey, true); window.addEventListener('resize', onResize);
  }
  function hideNative(el) { el.classList.add('sdp-native'); el.tabIndex = -1; el.setAttribute('aria-hidden', 'true'); }

  /* ---------------- select ---------------- */
  function select(sel, opts) {
    if (!sel || sel.dataset.sdp) return; sel.dataset.sdp = '1'; opts = opts || {};
    var btn = document.createElement('button'); btn.type = 'button'; btn.className = 'sdp-btn'; btn.setAttribute('aria-haspopup', 'listbox'); btn.setAttribute('aria-expanded', 'false');
    var lab = sel.closest('label'), name = lab && lab.querySelector('.p-sr'); if (name) btn.setAttribute('aria-label', name.textContent.trim());
    sel.parentNode.insertBefore(btn, sel); hideNative(sel);
    function paint() {
      var o = sel.options[sel.selectedIndex], v = o ? o.value : '', c = v && opts.dot ? opts.dot(v) : null;
      btn.innerHTML = (c ? '<i class="sdp-dot" style="--c:' + c + '"></i>' : '') + '<span>' + esc(o ? o.textContent.trim() : '') + '</span>' + CHEV;
      btn.classList.toggle('set', !!v);
    }
    paint(); sel.addEventListener('change', paint);
    btn.addEventListener('click', function () {
      if (open && open.btn === btn) { close(true); return; }
      var pop = document.createElement('div'); pop.className = 'sdp-pop sdp-list'; pop.setAttribute('role', 'listbox'); pop.tabIndex = -1;
      var items = Array.prototype.map.call(sel.options, function (o, i) {
        var c = o.value && opts.dot ? opts.dot(o.value) : null, row = document.createElement('button');
        row.type = 'button'; row.className = 'sdp-opt' + (i === sel.selectedIndex ? ' on' : ''); row.setAttribute('role', 'option'); row.setAttribute('aria-selected', String(i === sel.selectedIndex)); row.dataset.i = i;
        row.style.setProperty('--d', (i * 18) + 'ms');
        row.innerHTML = (c ? '<i class="sdp-dot" style="--c:' + c + '"></i>' : '<i class="sdp-dot none"></i>') + '<span>' + esc(o.textContent.trim()) + '</span>' + TICK;
        pop.appendChild(row); return row;
      });
      var cur = sel.selectedIndex;
      function focusRow(i) { cur = (i + items.length) % items.length; items.forEach(function (r, k) { r.classList.toggle('hot', k === cur); }); items[cur].scrollIntoView({ block: 'nearest' }); }
      function pick(i) { sel.selectedIndex = i; sel.dispatchEvent(new Event('change', { bubbles: true })); close(true); }
      var typed = '', tt;
      show(btn, pop, function (e) {
        if (e.key === 'Escape') { e.preventDefault(); close(true); }
        else if (e.key === 'ArrowDown') { e.preventDefault(); focusRow(cur + 1); }
        else if (e.key === 'ArrowUp') { e.preventDefault(); focusRow(cur - 1); }
        else if (e.key === 'Home') { e.preventDefault(); focusRow(0); }
        else if (e.key === 'End') { e.preventDefault(); focusRow(items.length - 1); }
        else if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pick(cur); }
        else if (e.key.length === 1) { typed += e.key.toLowerCase(); clearTimeout(tt); tt = setTimeout(function () { typed = ''; }, 700); var k = Array.prototype.findIndex.call(sel.options, function (o) { return o.textContent.trim().toLowerCase().indexOf(typed) === 0; }); if (k >= 0) focusRow(k); }
      });
      focusRow(sel.selectedIndex);
      pop.addEventListener('click', function (e) { var r = e.target.closest('.sdp-opt'); if (r) pick(Number(r.dataset.i)); });
      pop.addEventListener('mousemove', function (e) { var r = e.target.closest('.sdp-opt'); if (r) { cur = Number(r.dataset.i); items.forEach(function (x, k) { x.classList.toggle('hot', k === cur); }); } });
    });
  }

  /* ---------------- month ---------------- */
  function month(inp, opts) {
    if (!inp || inp.dataset.sdp) return; inp.dataset.sdp = '1'; opts = opts || {};
    var btn = document.createElement('button'); btn.type = 'button'; btn.className = 'sdp-btn sdp-month'; btn.setAttribute('aria-haspopup', 'dialog'); btn.setAttribute('aria-expanded', 'false');
    var lab = inp.closest('label'), name = lab && lab.querySelector('.p-sr'); if (name) btn.setAttribute('aria-label', name.textContent.trim());
    inp.parentNode.insertBefore(btn, inp); hideNative(inp);
    var fmt = new Intl.DateTimeFormat(lang, { month: 'long', year: 'numeric' }), short = new Intl.DateTimeFormat(lang, { month: 'short' });
    function parse(v) { var m = /^(\d{4})-(\d{2})$/.exec(v || ''); return m ? { y: +m[1], m: +m[2] - 1 } : null; }
    function paint() { var p = parse(inp.value); btn.innerHTML = '<span>' + esc(p ? fmt.format(new Date(p.y, p.m, 1)) : (lang === 'en-US' ? 'All months' : 'Lahat ng buwan')) + '</span>' + CHEV; btn.disabled = inp.disabled; }
    paint(); inp.addEventListener('change', paint);
    new MutationObserver(paint).observe(inp, { attributes: true, attributeFilter: ['disabled'] });
    btn.addEventListener('click', function () {
      if (open && open.btn === btn) { close(true); return; }
      var now = new Date(), nowY = now.getFullYear(), nowM = now.getMonth(), p = parse(inp.value) || { y: nowY, m: nowM }, year = p.y;
      var pop = document.createElement('div'); pop.className = 'sdp-pop sdp-cal'; pop.setAttribute('role', 'dialog');
      function pick(y, m) { inp.value = y + '-' + String(m + 1).padStart(2, '0'); inp.disabled = false; inp.dispatchEvent(new Event('change', { bubbles: true })); close(true); }
      function render() {
        var sel = parse(inp.value), cells = '';
        for (var m = 0; m < 12; m++) {
          var on = sel && sel.y === year && sel.m === m, is = year === nowY && m === nowM;
          cells += '<button type="button" class="sdp-m' + (on ? ' on' : '') + (is ? ' now' : '') + '" data-m="' + m + '" style="--d:' + (m * 14) + 'ms">' + esc(short.format(new Date(2000, m, 1)).replace('.', '')) + '</button>';
        }
        pop.innerHTML = '<div class="sdp-yr"><button type="button" class="sdp-nav" data-d="-1" aria-label="' + TXT.prev + '">' + CHEV + '</button><b>' + year + '</b><button type="button" class="sdp-nav r" data-d="1" aria-label="' + TXT.next + '">' + CHEV + '</button></div>' +
          '<div class="sdp-grid">' + cells + '</div><div class="sdp-foot"><button type="button" data-clear>' + TXT.clear + '</button><button type="button" data-now>' + TXT.now + '</button></div>';
      }
      render();
      pop.addEventListener('click', function (e) {
        var n = e.target.closest('.sdp-nav'), m = e.target.closest('.sdp-m');
        if (n) { year += Number(n.dataset.d); render(); var g = pop.querySelector('.sdp-grid'); g.classList.add('flip'); return; }
        if (m) { pick(year, Number(m.dataset.m)); return; }
        if (e.target.closest('[data-now]')) { pick(nowY, nowM); return; }
        if (e.target.closest('[data-clear]')) { if (opts.allTime) { if (!opts.allTime.checked) opts.allTime.click(); } else { inp.value = ''; inp.dispatchEvent(new Event('change', { bubbles: true })); } close(true); }
      });
      show(btn, pop, function (e) {
        if (e.key === 'Escape') { e.preventDefault(); close(true); }
        else if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') { e.preventDefault(); year += e.key === 'ArrowLeft' ? -1 : 1; render(); }
      });
    });
  }

  /* ---------------- range: days of a month, each box filled by how busy the day was ----------------
     sdPickers.range(button-host input, { from: inputEl, to: inputEl, counts: (y, m) => ({ day: n }), allTime: checkboxEl, label: fn })
     Press and drag across days, or press one and then another; the footer says what is chosen. */
  function range(host, opts) {
    if (!host || host.dataset.sdp) return; host.dataset.sdp = '1'; opts = opts || {};
    var from = opts.from, to = opts.to;
    var btn = document.createElement('button'); btn.type = 'button'; btn.className = 'sdp-btn sdp-month'; btn.setAttribute('aria-haspopup', 'dialog'); btn.setAttribute('aria-expanded', 'false');
    var lab = host.closest('label'), name = lab && lab.querySelector('.p-sr'); if (name) btn.setAttribute('aria-label', name.textContent.trim());
    host.parentNode.insertBefore(btn, host); hideNative(host);
    var dfmt = new Intl.DateTimeFormat(lang, { month: 'short', day: 'numeric' }), yfmt = new Intl.DateTimeFormat(lang, { year: 'numeric' }), mfmt = new Intl.DateTimeFormat(lang, { month: 'long', year: 'numeric' });
    var ALL = lang === 'en-US' ? 'All time' : 'Lahat ng panahon', APPLY = lang === 'en-US' ? 'Apply' : 'I-apply', MON1 = lang === 'en-US' ? 'This month' : 'Ngayong buwan', DAYS = lang === 'en-US' ? ' days' : ' araw', DAY1 = lang === 'en-US' ? ' day' : ' araw';
    var ymd = function (d) { return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); };
    var parse = function (v) { var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v || ''); return m ? new Date(+m[1], +m[2] - 1, +m[3]) : null; };
    function text() {
      if (opts.allTime && opts.allTime.checked) return ALL;
      var a = parse(from.value), b = parse(to.value); if (!a || !b) return ALL;
      if (a.getTime() === b.getTime()) return dfmt.format(a) + ', ' + yfmt.format(a);
      if (a.getDate() === 1 && b.getDate() === new Date(b.getFullYear(), b.getMonth() + 1, 0).getDate() && a.getMonth() === b.getMonth() && a.getFullYear() === b.getFullYear()) return mfmt.format(a);
      return dfmt.format(a) + ' – ' + dfmt.format(b) + (a.getFullYear() === b.getFullYear() ? ', ' + yfmt.format(b) : ' ' + yfmt.format(b));
    }
    function paint() { btn.innerHTML = '<span>' + esc(text()) + '</span>' + CHEV; }
    paint();
    btn.addEventListener('click', function () {
      if (open && open.btn === btn) { close(true); return; }
      var now = new Date(), a0 = parse(from.value), b0 = parse(to.value), st = { a: a0, b: b0, anchor: null, drag: false };
      var view = new Date((a0 || now).getFullYear(), (a0 || now).getMonth(), 1);
      var pop = document.createElement('div'); pop.className = 'sdp-pop sdp-cal sdp-rng'; pop.setAttribute('role', 'dialog');
      function inR(d) { return st.a && st.b && d >= Math.min(st.a, st.b) && d <= Math.max(st.a, st.b); }
      function render() {
        var y = view.getFullYear(), m = view.getMonth(), first = new Date(y, m, 1).getDay(), n = new Date(y, m + 1, 0).getDate(), cnt = (opts.counts && opts.counts(y, m)) || {}, mx = 0;
        Object.keys(cnt).forEach(function (k) { mx = Math.max(mx, cnt[k]); });
        var lo = st.a && st.b ? Math.min(st.a, st.b) : null, hi = st.a && st.b ? Math.max(st.a, st.b) : null, cells = '';
        for (var i = 0; i < first; i++) cells += '<span class="sdp-d e"></span>';
        for (var d = 1; d <= n; d++) {
          var dt = new Date(y, m, d), c = cnt[d] || 0, lv = !c ? 0 : mx && c / mx > .66 ? 3 : mx && c / mx > .33 ? 2 : 1;
          var cls = 'sdp-d l' + lv + (inR(dt) ? ' in' : '') + (lo && dt.getTime() === lo ? ' a' : '') + (hi && dt.getTime() === hi ? ' z' : '') + (ymd(dt) === ymd(now) ? ' now' : '');
          cells += '<button type="button" class="' + cls + '" data-d="' + ymd(dt) + '" title="' + (c ? c + (lang === 'en-US' ? ' complaints' : ' sumbong') : '') + '"><b>' + d + '</b></button>';
        }
        var days = lo ? Math.round((hi - lo) / 864e5) + 1 : 0;
        pop.innerHTML = '<div class="sdp-yr"><button type="button" class="sdp-nav" data-d="-1" aria-label="' + TXT.prev + '">' + CHEV + '</button><b class="mn">' + esc(mfmt.format(view)) + '</b><button type="button" class="sdp-nav r" data-d="1" aria-label="' + TXT.next + '">' + CHEV + '</button></div>' +
          '<div class="sdp-wk">' + [0, 1, 2, 3, 4, 5, 6].map(function (k) { return '<span>' + esc(new Intl.DateTimeFormat(lang, { weekday: 'narrow' }).format(new Date(2026, 9, 4 + k))) + '</span>'; }).join('') + '</div>' +
          '<div class="sdp-dg">' + cells + '</div>' +
          (mx ? '<div class="sdp-key"><i></i>' + (lang === 'en-US' ? 'Fuller = more complaints that day' : 'Mas puno = mas maraming sumbong') + '</div>' : '') +
          '<div class="sdp-foot rng"><span class="sdp-rt">' + (lo ? esc(dfmt.format(lo) + (days > 1 ? ' – ' + dfmt.format(hi) : '')) + ' · ' + days + (days > 1 ? DAYS : DAY1) : (lang === 'en-US' ? 'Pick a day, or drag across days' : 'Pumili ng araw, o i-drag')) + '</span><button type="button" class="sdp-go" data-go' + (lo ? '' : ' disabled') + '>' + APPLY + '</button></div>' +
          '<div class="sdp-pre"><button type="button" data-all>' + ALL + '</button><button type="button" data-month>' + MON1 + '</button></div>';
      }
      function apply() {
        var lo = new Date(Math.min(st.a, st.b)), hi = new Date(Math.max(st.a, st.b));
        from.value = ymd(lo); to.value = ymd(hi); if (opts.allTime && opts.allTime.checked) { opts.allTime.checked = false; opts.allTime.dispatchEvent(new Event('change', { bubbles: true })); }
        from.dispatchEvent(new Event('change', { bubbles: true })); to.dispatchEvent(new Event('change', { bubbles: true })); paint(); close(true); if (opts.onApply) opts.onApply();
      }
      render();
      function dayAt(e) { var t = e.target.closest('.sdp-d[data-d]'); return t ? parse(t.dataset.d) : null; }
      pop.addEventListener('pointerdown', function (e) { var d = dayAt(e); if (!d) return; e.preventDefault(); st.drag = true; st.moved = false; st.start = d; if (st.anchor && st.anchor.getTime() !== d.getTime()) { st.a = st.anchor; st.b = d; st.anchor = null; st.done = true; } else { st.a = d; st.b = d; st.done = false; } render(); });
      pop.addEventListener('pointerover', function (e) { if (!st.drag) return; var d = dayAt(e); if (!d || st.done) return; if (d.getTime() !== st.start.getTime()) st.moved = true; st.b = d; render(); });
      window.addEventListener('pointerup', function up() { window.removeEventListener('pointerup', up); if (!st.drag) return; st.drag = false; if (!st.done && !st.moved) st.anchor = st.start; else st.anchor = null; render(); });
      pop.addEventListener('click', function (e) {
        var n = e.target.closest('.sdp-nav'); if (n) { view = new Date(view.getFullYear(), view.getMonth() + Number(n.dataset.d), 1); render(); return; }
        if (e.target.closest('[data-go]')) { if (st.a && st.b) apply(); return; }
        if (e.target.closest('[data-all]')) { if (opts.allTime && !opts.allTime.checked) { opts.allTime.checked = true; opts.allTime.dispatchEvent(new Event('change', { bubbles: true })); } paint(); close(true); if (opts.onApply) opts.onApply(); return; }
        if (e.target.closest('[data-month]')) { st.a = new Date(now.getFullYear(), now.getMonth(), 1); st.b = new Date(now.getFullYear(), now.getMonth() + 1, 0); apply(); }
      });
      show(btn, pop, function (e) { if (e.key === 'Escape') { e.preventDefault(); close(true); } else if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') { e.preventDefault(); view = new Date(view.getFullYear(), view.getMonth() + (e.key === 'ArrowLeft' ? -1 : 1), 1); render(); } else if (e.key === 'Enter' && st.a && st.b && !e.target.closest('button')) { apply(); } });
    });
    if (opts.allTime) opts.allTime.addEventListener('change', paint);
    [from, to].forEach(function (i) { i.addEventListener('change', paint); });
    host.paint = paint;
  }

  window.sdPickers = { select: select, month: month, range: range, close: close };
})();
