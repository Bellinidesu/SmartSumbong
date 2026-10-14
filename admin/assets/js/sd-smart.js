// The SMART drawer on Spatial Distribution. Opening it makes the engine "think" (the glow the dashboard has), then the numbers
// count up and three layers can be switched onto the map: pins coloured by level, a pulse on the cases likely to be late, and rings
// round the recurring problems. Reads window.SS_SMART (set by spatial.php); uses the page's map, mapReady, byId and showDetail.
(function () {
  var D = window.SS_SMART;
  if (!D) return;
  var side = document.getElementById('smart-side'), btn = document.getElementById('smart-toggle');
  if (!side || !btn) return;
  var body = side.querySelector('.ss-drawer-body');
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  var COL = { urgent: '#E5383B', high: '#FF9800', normal: '#356CF9', low: '#8E9ABB' };
  var on = { halo: false, late: false, rings: false }, busy = false, revealed = false, lastRows = null, pulse = null;
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
    map.addLayer({ id: 'smart-rings', type: 'circle', source: 'smart-rings', layout: { visibility: 'none' },
      paint: { 'circle-radius': ['interpolate', ['exponential', 2], ['zoom'], 15, 14, 18, 110], 'circle-color': '#6A4FD3', 'circle-opacity': .12,
               'circle-stroke-color': '#6A4FD3', 'circle-stroke-width': 3, 'circle-stroke-opacity': .85 } }, before);
    map.addLayer({ id: 'smart-halo', type: 'circle', source: 'smart-halo', layout: { visibility: 'none' },
      paint: { 'circle-radius': ['interpolate', ['linear'], ['zoom'], 15, 15, 18, 25], 'circle-color': ['get', 'c'], 'circle-opacity': .38,
               'circle-stroke-color': ['get', 'c'], 'circle-stroke-width': 3, 'circle-stroke-opacity': .95, 'circle-translate': [0, -12] } }, before);
    map.addLayer({ id: 'smart-late', type: 'circle', source: 'smart-late', layout: { visibility: 'none' },
      paint: { 'circle-radius': 18, 'circle-color': 'rgba(229,56,59,0)', 'circle-stroke-color': '#E5383B', 'circle-stroke-width': 3, 'circle-stroke-opacity': .8, 'circle-translate': [0, -12] } }, before);
    var rings = (D.recur || []).map(function (r) { return pt(r.lng, r.lat); });
    map.getSource('smart-rings').setData({ type: 'FeatureCollection', features: rings });
  }

  function apply() {
    if (!map.getSource('smart-halo')) return;
    var vis = function (id, v) { if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', v ? 'visible' : 'none'); };
    vis('smart-halo', on.halo); vis('smart-late', on.late); vis('smart-rings', on.rings);
    side.querySelectorAll('[data-slayer]').forEach(function (b) { b.setAttribute('aria-pressed', String(!!on[b.dataset.slayer])); });
    if (on.late && !reduce) startPulse(); else stopPulse();
  }

  function redraw(rows) {
    lastRows = rows || lastRows;
    if (!lastRows) return;
    var go = function () {
      ensureLayers();
      var halos = [], late = [];
      lastRows.forEach(function (r) {
        var lv = D.levels[r.id];
        if (lv) halos.push(pt(r.longitude, r.latitude, { c: COL[lv] || COL.low }));
        if (lateSet[r.id]) late.push(pt(r.longitude, r.latitude));
      });
      map.getSource('smart-halo').setData({ type: 'FeatureCollection', features: halos });
      map.getSource('smart-late').setData({ type: 'FeatureCollection', features: late });
      apply();
    };
    if (typeof mapReady !== 'undefined') mapReady.then(go); else go();
  }

  function startPulse() {
    if (pulse) return;
    (function tick(t) {
      if (!on.late || !map.getLayer('smart-late')) { pulse = null; return; }
      var k = (t % 1800) / 1800;
      map.setPaintProperty('smart-late', 'circle-radius', 14 + 22 * k);
      map.setPaintProperty('smart-late', 'circle-stroke-opacity', .85 * (1 - k));
      pulse = requestAnimationFrame(tick);
    })(performance.now());
  }
  function stopPulse() {
    if (pulse) cancelAnimationFrame(pulse);
    pulse = null;
    if (map.getLayer('smart-late')) { map.setPaintProperty('smart-late', 'circle-radius', 18); map.setPaintProperty('smart-late', 'circle-stroke-opacity', .8); }
  }

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
  }

  side.addEventListener('click', function (e) {
    var tg = e.target.closest('[data-slayer]');
    if (tg) { on[tg.dataset.slayer] = !on[tg.dataset.slayer]; ensureLayers(); apply(); return; }
    var rc = e.target.closest('.ss-recur');
    if (rc) { map.flyTo({ center: [parseFloat(rc.dataset.lng), parseFloat(rc.dataset.lat)], zoom: 18, essential: true }); return; }
    var lt = e.target.closest('.ss-late');
    if (lt) {
      var r = typeof byId !== 'undefined' ? byId.get(lt.dataset.id) : null;
      if (r) { map.flyTo({ center: [+r.longitude, +r.latitude], zoom: 18.5, essential: true }); if (typeof showDetail === 'function') showDetail(r); }
    }
  });

  window.sdSmart = {
    isClosed: function () { return side.hasAttribute('hidden'); },
    toggle: function () { if (busy) return; if (side.hasAttribute('hidden')) open(); else close(); },
    close: close, redraw: redraw
  };
  if (typeof all !== 'undefined' && all.length) redraw(all);
})();
