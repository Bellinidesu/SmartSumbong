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
})();
