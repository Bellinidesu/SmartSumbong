// The SMART drawer on Spatial Distribution (layout C, locked 17 Oct 2026). Opening it makes the engine "think", then it says in a sentence what it sees,
// ranks the cases that need an administrator most, and offers three marks for the map, each written as what you will see. A ranked case is joined to its
// pin: hover it and its pin is ringed, press it and the map flies there and opens it, and the top five wear a number on the map while the drawer is open.
// Reads window.SS_SMART (set by spatial.php); uses the page's map, mapReady, all, byId, showDetail and T.
(function () {
  var D = window.SS_SMART;
  if (!D) return;
  var side = document.getElementById('smart-side'), btn = document.getElementById('smart-toggle');
  if (!side || !btn) return;
  var body = side.querySelector('.ss-drawer-body');
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  var COL = { urgent: '#E5383B', high: '#FF9800', normal: '#356CF9', low: '#8E9ABB' };
  var on = { halo: false, late: false, rings: false }, busy = false, revealed = false, lastRows = null, pulse = null;
  var vis = null, zf = 1, pills = {}, leafCache = {}, syncing = false, zooming = false;
  var busySet = {}, recurSet = {}, ranked = [], badges = [], showAll = false, OPENS = ['pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation'];
  (D.busy || []).forEach(function (id) { busySet[id] = true; }); (D.recurIds || []).forEach(function (id) { recurSet[id] = true; });
  var tr = function (en, fil) { return typeof T === 'function' ? T(en, fil) : en; };
  var esc = function (v) { return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  var LVW = { urgent: ['Urgent', 'Madalian'], high: ['High', 'Mataas'], normal: ['Normal', 'Katamtaman'], low: ['Low', 'Mababa'] };
  var lateSet = {};
  (D.late || []).forEach(function (id) { lateSet[id] = true; });
  var EMPTY = { type: 'FeatureCollection', features: [] };

  function pt(lng, lat, props) { return { type: 'Feature', properties: props || {}, geometry: { type: 'Point', coordinates: [+lng, +lat] } }; }

  function ensureLayers() {
    if (map.getSource('smart-halo')) return;
    var before = map.getLayer('clusters') ? 'clusters' : (map.getLayer('pins') ? 'pins' : undefined);
    map.addSource('smart-halo', { type: 'geojson', data: EMPTY });
    map.addSource('smart-late', { type: 'geojson', data: EMPTY });
    map.addSource('smart-rings', { type: 'geojson', data: EMPTY });
    map.addSource('smart-focus', { type: 'geojson', data: EMPTY });
    map.addLayer({ id: 'smart-rings', type: 'circle', source: 'smart-rings', layout: { visibility: 'none' },
      paint: { 'circle-radius': ['interpolate', ['exponential', 2], ['zoom'], 15, 14, 18, 110], 'circle-color': '#6A4FD3', 'circle-opacity': .07,
               'circle-stroke-color': '#6A4FD3', 'circle-stroke-width': 2, 'circle-stroke-opacity': .55 } }, before);
    map.addLayer({ id: 'smart-halo', type: 'circle', source: 'smart-halo', layout: { visibility: 'none' },
      paint: { 'circle-radius': ['interpolate', ['linear'], ['zoom'], 15, 12.5, 16, 14.5, 18, 18], 'circle-color': 'rgba(0,0,0,0)', 'circle-opacity': 0,
               'circle-stroke-color': ['get', 'c'], 'circle-stroke-width': 3, 'circle-stroke-opacity': .95 } }, before);
    map.addLayer({ id: 'smart-late', type: 'circle', source: 'smart-late', layout: { visibility: 'none' },
      paint: { 'circle-radius': 14, 'circle-color': 'rgba(229,56,59,0)', 'circle-stroke-color': '#E5383B', 'circle-stroke-width': 2.5, 'circle-stroke-opacity': .8 } }, before);
    map.addLayer({ id: 'smart-focus', type: 'circle', source: 'smart-focus',
      paint: { 'circle-radius': 22, 'circle-color': 'rgba(255,152,0,.14)', 'circle-stroke-color': '#FF9800', 'circle-stroke-width': 3, 'circle-stroke-opacity': .95 } });
    var rings = (D.recur || []).map(function (r) { return pt(r.lng, r.lat); });
    map.getSource('smart-rings').setData({ type: 'FeatureCollection', features: rings });
  }

  function apply() {
    if (!map.getSource('smart-halo')) return;
    var vis = function (id, v) { if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', v ? 'visible' : 'none'); };
    vis('smart-halo', on.halo); vis('smart-late', on.late); vis('smart-rings', on.rings);
    side.querySelectorAll('[data-slayer]').forEach(function (b) { b.setAttribute('aria-pressed', String(!!on[b.dataset.slayer])); });
    if (on.late && !reduce) startPulse(); else stopPulse();
    onMapKey();
  }

  function redraw(rows) {
    lastRows = rows || lastRows;
    if (!lastRows) return;
    var go = function () {
      ensureLayers();
      var halos = [], late = [];
      lastRows.forEach(function (r) {
        if (vis && !vis[r.id]) return;               // folded into a cluster: the cluster carries the mark instead
        var lv = D.levels[r.id];
        if (lv) halos.push(pt(r.longitude, r.latitude, { c: COL[lv] || COL.low }));
        if (lateSet[r.id]) late.push(pt(r.longitude, r.latitude));
      });
      map.getSource('smart-halo').setData({ type: 'FeatureCollection', features: halos });
      map.getSource('smart-late').setData({ type: 'FeatureCollection', features: late });
      apply();
      refresh();
    };
    if (typeof mapReady !== 'undefined') mapReady.then(go); else go();
  }

  function startPulse() {
    if (pulse) return;
    (function tick(t) {
      if (!on.late || !map.getLayer('smart-late')) { pulse = null; return; }
      var k = (t % 1800) / 1800;
      map.setPaintProperty('smart-late', 'circle-radius', 14 + 14 * k);
      map.setPaintProperty('smart-late', 'circle-stroke-opacity', .85 * (1 - k) * zf);
      pulse = requestAnimationFrame(tick);
    })(performance.now());
  }
  function stopPulse() {
    if (pulse) cancelAnimationFrame(pulse);
    pulse = null;
    if (map.getLayer('smart-late')) { map.setPaintProperty('smart-late', 'circle-radius', 14); map.setPaintProperty('smart-late', 'circle-stroke-opacity', .8); }
  }

  var OPEN_NOW = function (r) { return OPENS.indexOf(r.status) >= 0; };
  var hoursSince = function (d) { return Math.max(0, (Date.now() - new Date(d).getTime()) / 36e5); };
  var fmtH = function (h) { return h < 1 ? tr('new', 'bago') : h < 48 ? Math.round(h) + ' h' : Math.round(h / 24) + ' d'; };

  function rank() {
    var rows = (typeof all !== 'undefined' ? all : []).filter(OPEN_NOW);
    ranked = rows.map(function (r) {
      var lv = D.levels[r.id] || 'low', age = hoursSince(r.created_at), waiting = (r.status === 'pending_review' || r.status === 'validated') && (lv === 'urgent' || lv === 'high') && !busySet[r.id];
      var li = (D.lateInfo || {})[r.id], rec = !!recurSet[r.tracking_id];
      var score = { urgent: 40, high: 25, normal: 10, low: 0 }[lv] + (waiting ? 25 : 0) + (li ? 25 : 0) + (rec ? 8 : 0) + Math.min(24, age / 2);
      var why = [];
      if (waiting) why.push(tr('no tanod yet', 'wala pang tanod'));
      if (li) why.push(tr('may miss its deadline, ' + Math.round(li.left) + ' h left', 'maaaring maantala, ' + Math.round(li.left) + ' oras na lang'));
      if (rec) why.push(tr('same problem again', 'umuulit na problema'));
      if (!why.length) why.push(tr('open for ' + fmtH(age).replace(' h', ' hours').replace(' d', ' days'), 'bukas nang ' + fmtH(age)));
      return { r: r, lv: lv, age: age, waiting: waiting, late: !!li, rec: rec, score: score, why: why };
    }).sort(function (a, b) { return b.score - a.score; });
  }

  function say() {
    var w = ranked.filter(function (x) { return x.waiting; }), lt = ranked.filter(function (x) { return x.late; }).length;
    var t = document.getElementById('ss-say-t'), s = document.getElementById('ss-say-s');
    if (!t) return;
    if (w.length) {
      var long = Math.round(Math.max.apply(null, w.map(function (x) { return x.age; })));
      t.textContent = tr(w.length + ' urgent or high ' + (w.length === 1 ? 'case is' : 'cases are') + ' waiting for a tanod.', w.length + ' madalian o mataas na kaso ang naghihintay ng tanod.');
      s.textContent = tr('Nobody has been sent yet. The longest wait is ' + long + ' hours.', 'Wala pang naipapadala. Pinakamatagal na paghihintay: ' + long + ' oras.');
    } else {
      t.textContent = ranked.length ? tr('Every urgent case has a tanod.', 'May tanod na ang lahat ng madalian.') : tr('No open cases right now.', 'Walang bukas na kaso ngayon.');
      s.textContent = tr('Nothing is waiting for a tanod right now.', 'Walang naghihintay ng tanod ngayon.');
    }
    var extra = [];
    if (lt) extra.push(tr(lt + (lt === 1 ? ' may miss its deadline' : ' may miss their deadline'), lt + ' ang maaaring maantala'));
    if (D.recurring) extra.push(tr(D.recurring + (D.recurring === 1 ? ' problem keeps coming back' : ' problems keep coming back'), D.recurring + ' problema ang umuulit'));
    if (D.spikes) extra.push(tr(D.spikes + (D.spikes === 1 ? ' kind is up this week' : ' kinds are up this week'), D.spikes + ' uri ang tumaas ngayong linggo'));
    if (extra.length) s.textContent += ' ' + extra.join(' · ') + '.';
  }

  function renderQueue() {
    var box = document.getElementById('ss-queue'), more = document.getElementById('ss-more'), n = document.getElementById('ss-q-n');
    if (!box) return;
    var cap = showAll ? 12 : 5, list = ranked.slice(0, cap);
    n.textContent = String(ranked.length);
    if (!ranked.length) { box.innerHTML = '<p class="p-hint">' + esc(tr('Nothing is open.', 'Walang bukas.')) + '</p>'; more.hidden = true; return; }
    box.innerHTML = list.map(function (x, i) {
      var col = COL[x.lv] || COL.low, r = x.r;
      return '<button type="button" class="sq-row" data-id="' + esc(r.id) + '" style="--c:' + col + '"><span class="sq-n">' + (i + 1) + '</span><span class="sq-t"><b>' + esc(r.subject || r.tracking_id) + '</b><small>' + esc(tr(LVW[x.lv][0], LVW[x.lv][1])) + ' · ' + esc(x.why.slice(0, 2).join(' · ')) + '</small></span><span class="sq-w">' + esc(fmtH(x.age)) + '</span></button>';
    }).join('');
    more.hidden = ranked.length <= 5;
    more.textContent = showAll ? tr('Show fewer', 'Ipakita nang kaunti') : tr('Show ' + Math.min(7, ranked.length - 5) + ' more', 'Ipakita ang ' + Math.min(7, ranked.length - 5) + ' pa');
    placeBadges();
  }

  function clearBadges() { badges.forEach(function (m) { m.remove(); }); badges = []; }
  function placeBadges() { clearBadges(); }   // no numbers on the map: hovering a case in the list rings its pin
  function focusPin(r) {
    ensureLayers();
    var src = map.getSource('smart-focus'); if (!src) return;
    src.setData(r ? { type: 'FeatureCollection', features: [pt(r.longitude, r.latitude)] } : EMPTY);
  }
  function onMapKey() {
    var el = document.getElementById('ss-onmap'); if (!el) return;
    var k = [];
    if (on.halo) k.push(['#E5383B', 'Ring colour: how urgent (red urgent, orange high, blue normal, grey low)', 'Kulay ng bilog: antas (pula madalian, kahel mataas, asul katamtaman, abo mababa)']);
    if (on.late) k.push(['#E5383B', 'Pulsing red ring: may miss its deadline', 'Pumipintig na pulang bilog: maaaring maantala']);
    if (on.rings) k.push(['#6A4FD3', 'Purple area: a problem that keeps coming back here', 'Lilang bahagi: umuulit na problema dito']);
    el.hidden = !k.length;
    el.innerHTML = k.length ? '<b>' + esc(tr('On the map now', 'Nasa mapa ngayon')) + '</b>' + k.map(function (x) { return '<span><i style="background:' + x[0] + '"></i>' + esc(tr(x[1], x[2])) + '</span>'; }).join('') : '';
  }
  function visibleIds() {
    if (!map.getLayer('pins')) return null;
    var s = {}; map.queryRenderedFeatures({ layers: ['pins'] }).forEach(function (f) { if (f.properties && f.properties.id) s[f.properties.id] = 1; });
    return s;
  }
  function fade(k) {
    zf = k;
    var set = function (id, prop, v) { if (map.getLayer(id)) map.setPaintProperty(id, prop, v); };
    [['smart-halo', 'circle-stroke-opacity', .95], ['smart-rings', 'circle-opacity', .07], ['smart-rings', 'circle-stroke-opacity', .55]].forEach(function (a) { set(a[0], a[1], a[2] * k); });
    if (!on.late || k === 0) set('smart-late', 'circle-stroke-opacity', k ? .8 : 0);
    badges.forEach(function (m) { var el = m.getElement(); el.classList.toggle('off', k === 0 || !!(vis && !vis[el.dataset.id])); });
    Object.keys(pills).forEach(function (id) { pills[id].marker.getElement().classList.toggle('off', k === 0); });
  }
  // A cluster hides its cases, so the mark moves onto the cluster: a small pill with how many of them are urgent or high.
  function clusterPills() {
    if (!map.getSource('reports') || typeof maplibregl === 'undefined') return;
    var want = {};
    if (on.halo && !side.hasAttribute('hidden')) {
      map.queryRenderedFeatures({ layers: ['clusters'] }).forEach(function (f) { var id = f.properties.cluster_id; if (id != null && !want[id]) want[id] = f; });
    }
    Object.keys(pills).forEach(function (id) { if (!want[id]) { pills[id].marker.remove(); delete pills[id]; } });
    Object.keys(want).forEach(function (id) {
      var f = want[id], n = f.properties.point_count, w = n < 10 ? 50 : n < 50 ? 64 : 82;
      var put = function (info) {
        if (!info || pills[id] || !info.hot) return;
        var el = document.createElement('div'); el.className = 'sq-cdot' + (info.late ? ' late' : '') + (zf ? '' : ' off'); el.style.setProperty('--c', COL[info.worst]);
        el.textContent = String(info.hot);
        el.title = tr(info.hot + ' ' + info.worst + ' case' + (info.hot === 1 ? '' : 's') + ' in here. Zoom in to see them.', info.hot + ' ' + (info.worst === 'urgent' ? 'madalian' : 'mataas') + ' na kaso dito. Mag-zoom para makita.');
        var rim = Math.round(w / 2 * 0.72);
        pills[id] = { marker: new maplibregl.Marker({ element: el, anchor: 'center', offset: [rim, -rim] }).setLngLat(f.geometry.coordinates).addTo(map) };
      };
      var key = id + ':' + n;
      if (leafCache[key]) { put(leafCache[key]); return; }
      map.getSource('reports').getClusterLeaves(+id, 300, 0).then(function (leaves) {
        var u = 0, h = 0, late = false;
        leaves.forEach(function (l) { var lv = D.levels[l.properties.id]; if (lv === 'urgent') u++; else if (lv === 'high') h++; if (lateSet[l.properties.id]) late = true; });
        leafCache[key] = { hot: u || h, worst: u ? 'urgent' : 'high', late: late };   // the count is of the worst level in there, so the word on the pill is true
        if (on.halo) put(leafCache[key]);
      }).catch(function () {});
    });
  }
  function sync() {
    if (syncing || !map.getLayer('pins')) return;
    syncing = true;
    vis = visibleIds();
    if (lastRows) redraw(lastRows);
    clusterPills();
    fade(1); zooming = false;
    badges.forEach(function (m) { var el = m.getElement(); el.classList.toggle('off', !!(vis && !vis[el.dataset.id])); });
    syncing = false;
  }
  function refresh() { rank(); say(); renderQueue(); }

  function countUp() {
    if (reduce) return;
    side.querySelectorAll('[data-count]').forEach(function (el) {
      var n = parseInt(el.textContent, 10);
      if (!(n > 0)) return;
      var t0 = null;
      (function step(t) {
        if (t0 === null) t0 = t;
        var k = Math.min(1, (t - t0) / 800);
        el.textContent = String(Math.round(n * (1 - Math.pow(1 - k, 3))));
        if (k < 1) requestAnimationFrame(step); else el.textContent = String(n);
      })(performance.now());
    });
  }

  function open() {
    side.removeAttribute('hidden'); btn.setAttribute('aria-expanded', 'true'); btn.classList.add('is-open');
    refresh();
    if (revealed || reduce) { body.hidden = false; revealed = true; return; }
    busy = true; side.classList.add('is-thinking'); body.hidden = true;
    setTimeout(function () {
      side.classList.remove('is-thinking'); body.hidden = false; side.classList.add('is-rise');
      revealed = true; busy = false; countUp();
      setTimeout(function () { side.classList.remove('is-rise'); }, 800);
    }, 1100);
  }
  function close() {
    side.setAttribute('hidden', ''); btn.setAttribute('aria-expanded', 'false'); btn.classList.remove('is-open');
    clearBadges(); focusPin(null); Object.keys(pills).forEach(function (id) { pills[id].marker.remove(); delete pills[id]; });
  }

  side.addEventListener('click', function (e) {
    var tg = e.target.closest('[data-slayer]');
    if (tg) { on[tg.dataset.slayer] = !on[tg.dataset.slayer]; ensureLayers(); apply(); sync(); return; }
    var rc = e.target.closest('.ss-recur');
    if (rc) { map.flyTo({ center: [parseFloat(rc.dataset.lng), parseFloat(rc.dataset.lat)], zoom: 18, essential: true }); return; }
    var sq = e.target.closest('.sq-row');
    if (sq) {
      var rr = typeof byId !== 'undefined' ? byId.get(sq.dataset.id) : null;
      if (rr) { map.flyTo({ center: [+rr.longitude, +rr.latitude], zoom: 18.5, essential: true }); if (typeof showDetail === 'function') showDetail(rr); }
      return;
    }
    if (e.target.closest('#ss-more')) { showAll = !showAll; renderQueue(); return; }
    var lt = e.target.closest('.ss-late');
    if (lt) {
      var r = typeof byId !== 'undefined' ? byId.get(lt.dataset.id) : null;
      if (r) { map.flyTo({ center: [+r.longitude, +r.latitude], zoom: 18.5, essential: true }); if (typeof showDetail === 'function') showDetail(r); }
    }
  });

  side.addEventListener('pointerover', function (e) { var q = e.target.closest('.sq-row'); if (q && typeof byId !== 'undefined') focusPin(byId.get(q.dataset.id)); });
  side.addEventListener('pointerout', function (e) { if (e.target.closest('.sq-row') && !(e.relatedTarget && e.relatedTarget.closest && e.relatedTarget.closest('.sq-row'))) focusPin(null); });
  side.addEventListener('focusin', function (e) { var q = e.target.closest('.sq-row'); if (q && typeof byId !== 'undefined') focusPin(byId.get(q.dataset.id)); });
  side.addEventListener('focusout', function () { focusPin(null); });

  if (typeof map !== 'undefined') {
    map.on('zoomstart', function () { if (side.hasAttribute('hidden') && !on.halo && !on.late && !on.rings) return; zooming = true; fade(0); });
    var live = function () { return !side.hasAttribute('hidden') || on.halo || on.late || on.rings; }, later = null;
    var soon = function () { clearTimeout(later); later = setTimeout(function () { if (live()) sync(); }, 160); };
    map.on('idle', function () { if (live()) sync(); });
    map.on('zoomend', soon); map.on('moveend', soon);   // not only on idle: a slow tile must not leave the marks faded
  }
  window.sdSmart = {
    isClosed: function () { return side.hasAttribute('hidden'); },
    toggle: function () { if (busy) return; if (side.hasAttribute('hidden')) open(); else close(); },
    close: close, redraw: redraw, sync: sync
  };
  if (typeof all !== 'undefined' && all.length) redraw(all);
})();
