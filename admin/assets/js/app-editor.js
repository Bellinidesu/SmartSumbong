/* The Control Room's live view of the resident app: the phone follows the forms as they are typed in (nothing is saved until a form is). */
(function () {
  'use strict';
  var wrap = document.getElementById('ed-wrap'), phone = document.getElementById('ed-phone');
  if (!wrap || !phone) return;
  var MAP = {}; try { MAP = JSON.parse(wrap.dataset.map || '{}'); } catch (e) {}
  var ICON_OF = { street_obstruction: 'obstruction', public_safety_infrastructure: 'infra', environmental_waste_hazard: 'waste', animal_welfare: 'animal', traffic_violation: 'traffic', barangay_service: 'service', peace_order_nuisance: 'noise', other: 'other' };
  var q = function (s, r) { return (r || document).querySelector(s); }, qa = function (s, r) { return [].slice.call((r || document).querySelectorAll(s)); };

  function draw(svg, name) {
    svg.setAttribute('fill', 'none'); svg.setAttribute('stroke', 'currentColor'); svg.setAttribute('stroke-width', '2'); svg.setAttribute('stroke-linecap', 'round'); svg.setAttribute('stroke-linejoin', 'round');
    var I = window.SD_ICONS || {}; svg.innerHTML = I[name] || I.other || '';
  }

  /* ---- which screen ---- */
  function show(sc) {
    wrap.dataset.screen = sc || 'none';
    if (!sc) return;
    qa('.ed-sc', phone).forEach(function (s) { s.classList.toggle('ed-hide', s.dataset.sc !== sc); });
    qa('.ed-switch [data-go]', phone).forEach(function (b) { b.classList.toggle('p-on', b.dataset.go === sc); });
  }
  var tabs = q('.st-tabs');
  function current() { var on = tabs && q('[data-st].p-on', tabs); return on ? on.dataset.st : ''; }
  function sync() { var t = current(); show(Object.prototype.hasOwnProperty.call(MAP, t) ? MAP[t] : 'report'); }
  if (tabs) tabs.addEventListener('click', function () { setTimeout(sync, 0); });
  qa('.ed-switch [data-go]', phone).forEach(function (b) { b.addEventListener('click', function () { show(b.dataset.go); }); });
  sync();

  /* ---- complaint types: the Report screen ---- */
  var types = document.getElementById('types-card'), cats = document.getElementById('ed-cats');
  function tile(key) { return q('.ed-cat[data-key="' + key + '"]', phone); }
  function selectCat(key) {
    qa('.ed-cat', phone).forEach(function (t) { t.classList.toggle('ed-sel', t.dataset.key === key); });
    qa('.ed-opts', phone).forEach(function (o) { o.classList.toggle('ed-hide', o.dataset.for !== key); });
    var sc = q('.ed-sc[data-sc="report"]', phone), shown = q('.ed-opts[data-for="' + key + '"]', phone);
    if (sc && shown && !sc.classList.contains('ed-hide')) sc.scrollTo({ top: Math.max(0, shown.offsetTop - 120), behavior: 'smooth' });
  }
  function recount() {
    if (!cats) return;
    qa('.ed-cat', phone).forEach(function (t) {
      var list = q('.ed-opts[data-for="' + t.dataset.key + '"]', phone), n = list ? qa('.ed-opt:not(.ed-off):not(.ed-new)', list).length : 0;
      var c = q('.ed-cc', t); if (c) c.textContent = (n === 1 ? cats.dataset.one : cats.dataset.many).replace('%d', n);
    });
  }
  if (types && cats) {
    var keyOf = function (f) { var k = q('input[name="key"]', f); return k ? k.value : ''; };
    var onType = function (e) {
      var f = e.target.closest && e.target.closest('form'); if (!f) return;
      var act = (q('input[name="action"]', f) || {}).value, n = e.target.name;
      if (act === 'cat_save') {
        var key = keyOf(f), t = key ? tile(key) : q('.ed-cat.ed-pend', phone);
        if (!key) {   // a category being made: a dashed tile
          var name = (q('input[name="label_en"]', f) || {}).value || '';
          if (!t && name) {
            t = document.createElement('button'); t.type = 'button'; t.className = 'ed-cat ed-pend'; t.dataset.key = '';
            t.innerHTML = '<i class="ed-ic"><svg class="cm-ic" viewBox="0 0 24 24" aria-hidden="true"></svg></i><b class="ed-cn"></b><small class="ed-cc"></small>';
            cats.appendChild(t);
          }
          if (t && !name) { t.remove(); return; }
        }
        if (!t) return;
        if (n === 'label_en') q('.ed-cn', t).textContent = e.target.value || '…';
        if (n === 'colour') t.style.setProperty('--c', e.target.value);
        if (n === 'active') t.classList.toggle('ed-off', !e.target.checked);
        if (n === 'icon' || !key) { var icon = (q('select[name="icon"]', f) || {}).value; var svg = q('svg', t); if (svg) draw(svg, ICON_OF[icon] || icon || 'other'); var col = (q('input[name="colour"]', f) || {}).value; if (col) t.style.setProperty('--c', col); }
        if (key) selectCat(key);
      } else if (act === 'opt_save') {
        var id = (q('input[name="id"]', f) || {}).value, cat = (q('input[name="category"]', f) || {}).value;
        selectCat(cat);
        var li = id ? q('.ed-opt[data-oid="' + id + '"]', phone) : q('.ed-opts[data-for="' + cat + '"] .ed-new', phone);
        if (!li) return;
        if (n === 'label_en') { q('.ed-ol', li).textContent = e.target.value; if (!id) li.classList.toggle('ed-hide', !e.target.value); }
        if (n === 'active') li.classList.toggle('ed-off', !e.target.checked);
      }
      recount();
    };
    types.addEventListener('input', onType); types.addEventListener('change', onType);
    types.addEventListener('toggle', function (e) { var d = e.target; if (d.matches && d.matches('details.ty-cat') && d.open) { var k = q('input[name="key"]', d); if (k && k.value) selectCat(k.value); } }, true);
    cats.addEventListener('click', function (e) {   // a tile in the phone opens its category in the form
      var t = e.target.closest('.ed-cat'); if (!t || !t.dataset.key) return; selectCat(t.dataset.key);
      var d = qa('details.ty-cat', types).filter(function (x) { var k = q('input[name="key"]', x); return k && k.value === t.dataset.key; })[0];
      if (d) { d.open = true; d.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); }
    });
    phone.addEventListener('click', function (e) {   // an option in the phone puts the cursor in its field
      var li = e.target.closest('.ed-opt'); if (!li || !li.dataset.oid || li.dataset.oid === 'new') return;
      var inp = document.getElementById('oe-' + li.dataset.oid); if (inp) { var d = inp.closest('details'); if (d) d.open = true; inp.focus(); inp.scrollIntoView({ block: 'center', behavior: 'smooth' }); }
    });
  }

  /* ---- emergency numbers ---- */
  var hl = document.getElementById('hotlines-card');
  function groupCounts() {
    qa('.ed-hg', phone).forEach(function (g) {
      var n = qa(':scope > ul > .ed-hn:not(.ed-off)', g).length, c = q(':scope > h4 .ed-gcount', g);
      if (c) c.textContent = g.dataset.display === 'inline' ? '' : n + (n === 1 ? ' number' : ' numbers');
    });
  }
  groupCounts();
  if (hl) {
    var onHl = function (e) {
      var f = e.target.closest && e.target.closest('form'); if (!f) return;
      var act = (q('input[name="action"]', f) || {}).value, n = e.target.name, id = (q('input[name="id"]', f) || {}).value;
      if (act === 'hl_group' && id) {
        var g = q('.ed-hg[data-gid="' + id + '"]', phone); if (!g) return;
        if (n === 'name') q(':scope > h4 .ed-gname', g).textContent = e.target.value;
        if (n === 'active') g.classList.toggle('ed-off', !e.target.checked);
        if (n === 'display') g.dataset.display = e.target.value;
      } else if (act === 'hl_number') {
        var li = id ? q('.ed-hn[data-nid="' + id + '"]', phone) : null;
        if (!li && !id) {   // a number being added: it shows in its group as it is typed
          var grp = (q('input[name="group"], input[name="group_id"]', f) || {}).value, g2 = grp && q('.ed-hg[data-gid="' + grp + '"]', phone);
          var lab = (q('input[name="label"]', f) || {}).value, num = (q('input[name="number"]', f) || {}).value;
          li = g2 && q(':scope > ul > .ed-hn.ed-pend', g2);
          if (g2 && !li && (lab || num)) { li = document.createElement('li'); li.className = 'ed-hn ed-pend'; li.innerHTML = '<span><b class="ed-nl"></b><small class="ed-nn"></small></span><i class="ed-call" aria-hidden="true"></i>'; q(':scope > ul', g2).appendChild(li); }
          if (li && !lab && !num) { li.remove(); li = null; }
        }
        if (!li) return;
        if (n === 'label' || li.classList.contains('ed-pend')) q('.ed-nl', li).textContent = (q('input[name="label"]', f) || {}).value || '…';
        if (n === 'number' || li.classList.contains('ed-pend')) q('.ed-nn', li).textContent = (q('input[name="number"]', f) || {}).value;
        if (n === 'active') li.classList.toggle('ed-off', !e.target.checked);
      }
      groupCounts();
    };
    hl.addEventListener('input', onHl); hl.addEventListener('change', onHl);
    phone.addEventListener('click', function (e) {
      var li = e.target.closest('.ed-hn'); if (!li || !li.dataset.nid) return;
      var inp = document.getElementById('hl-n-' + li.dataset.nid); if (inp) { var d = inp.closest('details'); while (d) { d.open = true; d = d.parentElement && d.parentElement.closest('details'); } inp.focus(); inp.scrollIntoView({ block: 'center', behavior: 'smooth' }); }
    });
  }

  /* ---- parts of the system ---- */
  var parts = document.getElementById('acc-switches'), hid = document.getElementById('ed-hidden');
  function hiddenNote() {
    if (!hid) return;
    var off = qa('.ed-sw.ed-off b', phone).map(function (b) { return b.textContent; });
    hid.hidden = !off.length; hid.textContent = off.length ? 'Hidden from residents: ' + off.join(', ') : '';
  }
  hiddenNote();
  if (parts) parts.addEventListener('change', function (e) {
    var f = e.target.closest('form'), k = f && q('input[name="key"]', f), sw = k && q('.ed-sw[data-key="' + k.value + '"]', phone);
    if (sw && e.target.name === 'on') { sw.classList.toggle('ed-off', !e.target.checked); hiddenNote(); show('home'); }
  });

  /* ---- the barangay ---- */
  var brgy = document.getElementById('brgy-card');
  if (brgy) {
    brgy.addEventListener('input', function (e) {
      if (e.target.name === 'name') qa('.ed-bn', phone).forEach(function (x) { x.textContent = e.target.value; });
      if (e.target.name === 'place') qa('.ed-pl', phone).forEach(function (x) { x.textContent = e.target.value; });
    });
    brgy.addEventListener('change', function (e) {
      if (e.target.type !== 'file' || !e.target.files || !e.target.files[0]) return;
      var r = new FileReader(); r.onload = function () { qa('img.ed-sealimg', phone).forEach(function (i) { i.src = r.result; }); }; r.readAsDataURL(e.target.files[0]);
    });
  }

  /* ---- showing it on a real phone (developer mode, 0160) ---- */
  var live = document.getElementById('ed-live');
  if (live && window.supabase) (function () {
    var cfg = {}; try { cfg = JSON.parse(live.dataset.cfg || '{}'); } catch (e) {}
    var T = cfg.t || {};
    var sb = window.supabase.createClient(cfg.url, cfg.key, { accessToken: window.ssAccessToken(cfg.token) });
    var go = q('#ed-live-go'), box = q('.ed-live-box', live), codeEl = q('#ed-live-code'), cnt = q('#ed-live-count'), st = q('#ed-live-state'), end = q('#ed-live-end'), err = q('#ed-live-err');
    var sess = null, ch = null, ready = false, tick = null, poll = null, beat = null, deb = null;
    var val = function (f, n) { var e = f && q('[name="' + n + '"]', f); return e ? e.value : ''; };
    var on = function (f, n) { var e = f && q('[name="' + n + '"]', f); return !!(e && e.checked); };

    /* what the forms say right now: the draft the phone should show (what saving would publish) */
    function opts(d, add) {
      var o = qa('form.ty-opt:not(.ty-add)', d).map(function (f) { return { id: +val(f, 'id') || null, label_en: val(f, 'label_en'), label_fil: val(f, 'label_fil'), active: on(f, 'active') }; });
      qa('form.ty-add', d).forEach(function (f) { if (val(f, 'label_en').trim()) o.push({ id: null, label_en: val(f, 'label_en'), label_fil: val(f, 'label_fil'), active: true }); });
      return o;
    }
    function group(d) {
      var f = q(':scope > form.hl-row', d);
      var nums = qa(':scope > ul form.hl-num:not(.ty-add)', d).map(function (n) { return { id: val(n, 'id'), label: val(n, 'label'), number: val(n, 'number'), carrier: val(n, 'carrier'), active: on(n, 'active') }; });
      qa(':scope > ul form.hl-num.ty-add', d).forEach(function (n) { if (val(n, 'number').trim()) nums.push({ id: null, label: val(n, 'label'), number: val(n, 'number'), carrier: val(n, 'carrier'), active: true }); });
      return { id: val(f, 'id'), name: val(f, 'name'), display: val(f, 'display'), active: on(f, 'active'), numbers: nums, groups: qa(':scope > details.hl-g', d).map(group) };
    }
    function model() {
      var cats = qa('#types-card details.ty-cat').map(function (d) {
        var f = q('form.ty-row', d);
        return { key: val(f, 'key'), label_en: val(f, 'label_en'), label_fil: val(f, 'label_fil'), colour: val(f, 'colour'), icon: val(f, 'icon'), active: on(f, 'active'), options: opts(d) };
      });
      var nf = q('#types-card form.ty-new');
      if (nf && val(nf, 'label_en').trim()) cats.push({ key: null, label_en: val(nf, 'label_en'), label_fil: val(nf, 'label_fil'), colour: val(nf, 'colour'), icon: val(nf, 'icon'), active: true, options: [] });
      var bf = document.getElementById('brgy-card');
      return {
        v: 1, at: Date.now(), cats: cats,
        hotlines: qa('#hotlines-card > details.hl-g').map(group),
        switches: qa('#acc-switches form').map(function (f) { return { key: val(f, 'key'), on: on(f, 'on') }; }),
        barangay: { name: val(bf, 'name'), place: val(bf, 'place') }
      };
    }
    function send() { var m = model(); if (window.__edHook) window.__edHook(m); /* a seam for the tests */ if (ch && ready) ch.send({ type: 'broadcast', event: 'draft', payload: m }); }
    function queue() { clearTimeout(deb); deb = setTimeout(send, 250); }
    document.addEventListener('input', function () { if (sess) queue(); });
    document.addEventListener('change', function () { if (sess) queue(); });

    function stop(msg) {
      clearInterval(tick); clearInterval(poll); clearInterval(beat); clearTimeout(deb);
      if (ch) { try { sb.removeChannel(ch); } catch (e) {} }
      ch = null; ready = false; sess = null; box.hidden = true; go.hidden = false;
      err.hidden = !msg; err.textContent = msg || '';
    }
    function begin() {
      codeEl.textContent = sess.code.slice(0, 4) + ' ' + sess.code.slice(4);
      st.textContent = T.wait || ''; box.hidden = false; go.hidden = true;
      ch = sb.channel('pv:' + sess.channel, { config: { broadcast: { self: false } } });
      ch.on('broadcast', { event: 'hello' }, function () { st.textContent = T.live || ''; queue(); })
        .subscribe(function (s) { if (s === 'SUBSCRIBED') { ready = true; send(); } });
      var count = function () {
        var ms = new Date(sess.expires_at) - Date.now();
        if (ms <= 0) { stop(T.ran); return; }
        cnt.textContent = Math.floor(ms / 60000) + ':' + ('0' + (Math.floor(ms / 1000) % 60)).slice(-2);
      };
      count(); tick = setInterval(count, 1000);
      poll = setInterval(function () {
        if (!sess) return;
        sb.from('preview_sessions').select('paired_at,paired_device,ended_at').eq('id', sess.id).maybeSingle().then(function (r) {
          var d = r && r.data; if (!d || !sess) return;
          if (d.ended_at) { stop(T.ended); return; }
          if (d.paired_at && st.textContent !== T.live) st.textContent = (T.paired || '%s').replace('%s', d.paired_device || T.phone);
        });
      }, 4000);
      beat = setInterval(send, 5000);
    }
    go.addEventListener('click', function () {
      err.hidden = true; go.disabled = true;
      sb.rpc('preview_start').then(function (r) {
        go.disabled = false;
        if (r.error || !r.data) { err.textContent = (r.error && r.error.message) || T.fail || ''; err.hidden = false; return; }
        sess = r.data; begin();
      });
    });
    end.addEventListener('click', function () {
      var id = sess && sess.id; stop('');
      if (id) sb.rpc('preview_end', { p_id: id });
    });
    window.addEventListener('pagehide', function () { if (sess) sb.rpc('preview_end', { p_id: sess.id }); });
  })();
})();
