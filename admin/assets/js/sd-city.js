// Spatial Distribution, City view (Bellinist, 9 Oct 2026): what the tilted map adds to the flat one, in the manner of
// Apple Maps' detailed city experience, built only from open data (OpenStreetMap through OpenFreeMap, plus
// assets/map/city-detail.json and infill.json, which docs/map-data/build_city_detail.py and build_infill.py make
// from OpenStreetMap and Overture Maps).
//   light and haze     a low sun on the walls, a sky and a fog that fades the far streets away
//   buildings          their own OpenStreetMap heights; walls with windows (lit at night), a plain roof on top,
//                      each roof a slightly different tone; Overture's extra footprints as low plain blocks
//   trees              the 93 OpenStreetMap has mapped, and rounded ones planted in the parks and the golf course
//   road detail        zebra crossings (all 125 OpenStreetMap has) and dashed lane lines
//   places             small coloured dots for shops, food, clinics and schools
// Loaded after sd-tools.js; it shares map and mapReady with the page and leaves the flat map as it was.
(function () {
  'use strict';
  if (typeof map === 'undefined' || typeof mapReady === 'undefined') return;
  const isDark = () => document.documentElement.getAttribute('data-theme') === 'dark';
  const rgb = h => [1, 3, 5].map(i => parseInt(h.substr(i, 2), 16));

  // ---- Bellinist night and Bellinist day ----
  const PAL = {
    night: {
      light: { anchor: 'map', color: '#D6E0FF', intensity: .55, position: [1.4, 200, 48] },
      sky: { 'sky-color': '#0E1226', 'horizon-color': '#2A3156', 'fog-color': '#171B2C', 'sky-horizon-blend': .55, 'horizon-fog-blend': .8, 'fog-ground-blend': .55 },
      wall: { lo: ['#444C77', '#2C3150', '#FFD58A', .2], mid: ['#485079', '#292E4C', '#FFD08A', .3], hi: ['#535D8B', '#262B49', '#FFE0A0', .45] },
      roof: ['#626B98', 6], infill: '#3C4366',
      canopy: ['#1F6B53', '#2E8A63'], canopy2: ['#27805F', '#3AA374'], trunk: '#2F2A3A', cross: ['#FFFFFF', .6], lane: ['#AEB6DA', .5],
      haloText: 'rgba(18,21,42,.92)', poiStroke: '#14172A',
    },
    day: {
      light: { anchor: 'map', color: '#FFFFFF', intensity: .4, position: [1.3, 215, 50] },
      sky: { 'sky-color': '#8FC1F0', 'horizon-color': '#E9F1FA', 'fog-color': '#E8EDF3', 'sky-horizon-blend': .5, 'horizon-fog-blend': .8, 'fog-ground-blend': .5 },
      wall: { lo: ['#EDE9E3', '#A9BAD2', '#B9CADF', .05], mid: ['#E6E4E2', '#9FB1CC', '#B6C8DF', .06], hi: ['#DCE1EA', '#8EA4C4', '#AFC3DD', .08] },
      roof: ['#F5F2EE', 5], infill: '#E4E0DA',
      canopy: ['#7FCB5E', '#5FB55A'], canopy2: ['#8DD66A', '#6BC262'], trunk: '#8A6B4F', cross: ['#FFFFFF', .95], lane: ['#CBC7BE', .85],
      haloText: 'rgba(255,255,255,.95)', poiStroke: '#FFFFFF',
    },
  };
  const pal = () => isDark() ? PAL.night : PAL.day;
  const H = ['coalesce', ['get', 'render_height'], 6], MH = ['coalesce', ['get', 'render_min_height'], 0];
  // a stable number from a building's height and base: each roof a slightly different tone
  const N = ['%', ['*', ['+', H, ['*', MH, 3.7]], 12.9898], 1];
  const roofColour = p => { const [r, g, b] = rgb(p.roof[0]), v = p.roof[1]; return ['rgb', ['+', r - v, ['*', N, v]], ['+', g - v, ['*', N, v]], ['+', b - v, ['*', N, v]]]; };
  const canopyColour = (p, k) => ['interpolate', ['linear'], ['get', 'v'], 0, p[k][0], 1, p[k][1]];

  // ---- the window walls: a picture of a few floors of windows, some lit, repeated over the wall ----
  const CLASSES = ['lo', 'mid', 'hi'];
  function addWalls() {
    const rows = { lo: 16, mid: 24, hi: 32 };
    ['night', 'day'].forEach((t, ti) => CLASSES.forEach((k, ki) => {
      const [base, win, lit, chance] = PAL[t].wall[k], S = 256, cols = 16, nrows = rows[k], c = document.createElement('canvas'); c.width = c.height = S;
      const x = c.getContext('2d'); x.fillStyle = base; x.fillRect(0, 0, S, S);
      let s = 7 + ki * 12 + ti * 5; const rnd = () => { s = (s * 16807) % 2147483647; return s / 2147483647; };
      const cw = S / cols, ch = S / nrows, w = cw * .5, h = ch * .55;
      for (let r = 0; r < nrows; r++) {
        x.fillStyle = 'rgba(0,0,0,.10)'; x.fillRect(0, r * ch + ch - 2, S, 2);
        for (let q = 0; q < cols; q++) {
          const on = rnd() < chance, px = q * cw + (cw - w) / 2, py = r * ch + (ch - h) / 2;
          if (on) { x.fillStyle = t === 'night' ? 'rgba(255,230,170,.25)' : 'rgba(255,255,255,.4)'; x.fillRect(px - 1, py - 1, w + 2, h + 2); }
          x.fillStyle = on ? lit : win; x.fillRect(px, py, w, h);
        }
      }
      const d = x.getImageData(0, 0, S, S), name = 'cdw-' + k + '-' + (t === 'night' ? 'n' : 'd');
      if (!map.hasImage(name)) map.addImage(name, { width: S, height: S, data: new Uint8Array(d.data.buffer) }, { pixelRatio: 1 });
    }));
  }
  const wallName = k => 'cdw-' + k + '-' + (isDark() ? 'n' : 'd');

  let ready = null, on = false, TREES = [];
  const ngon = (cx, cy, r, n, rot) => {   // metres to degrees at this latitude
    const out = []; for (let i = 0; i <= n; i++) { const a = rot + i / n * Math.PI * 2; out.push([cx + Math.cos(a) * r / 107500, cy + Math.sin(a) * r / 110574]); } return out;
  };
  function treeShapes(trees) {
    const low = [], high = [], trunk = [];
    trees.forEach((t, i) => {
      const [lng, lat, r, h, v, cone] = t, rot = (i * 2.399) % 6.283, props = (b, top) => ({ v, b, h: top });
      if (cone) {   // a narrow tree, wide at its foot
        low.push({ type: 'Feature', properties: props(h * .25, h * .62), geometry: { type: 'Polygon', coordinates: [ngon(lng, lat, r * .8, 7, rot)] } });
        high.push({ type: 'Feature', properties: props(h * .55, h), geometry: { type: 'Polygon', coordinates: [ngon(lng, lat, r * .45, 7, rot)] } });
      } else {      // a round one: a full lower crown and a narrower upper one
        low.push({ type: 'Feature', properties: props(h * .3, h * .7), geometry: { type: 'Polygon', coordinates: [ngon(lng, lat, r, 9, rot)] } });
        high.push({ type: 'Feature', properties: props(h * .58, h), geometry: { type: 'Polygon', coordinates: [ngon(lng, lat, r * .66, 8, rot + .4)] } });
      }
      trunk.push({ type: 'Feature', properties: { h: h * .42 }, geometry: { type: 'Polygon', coordinates: [ngon(lng, lat, .38, 5, rot)] } });
    });
    const fc = f => ({ type: 'FeatureCollection', features: f });
    return [fc(low), fc(high), fc(trunk)];
  }
  const POI_COL = { restaurant: '#FF9A3D', fast_food: '#FF9A3D', cafe: '#FF9A3D', bar: '#FF9A3D', bakery: '#FF9A3D', ice_cream: '#FF9A3D', food_court: '#FF9A3D',
    shop: '#4F8CFF', grocery: '#4F8CFF', supermarket: '#4F8CFF', clothing_store: '#4F8CFF', convenience: '#4F8CFF', department_store: '#4F8CFF', mall: '#4F8CFF', jewelry: '#4F8CFF',
    hospital: '#F0524F', doctors: '#F0524F', pharmacy: '#F0524F', dentist: '#F0524F', clinic: '#F0524F', veterinary: '#F0524F',
    school: '#9B6BFF', college: '#9B6BFF', kindergarten: '#9B6BFF', library: '#9B6BFF', university: '#9B6BFF',
    lodging: '#D56FE0', hotel: '#D56FE0', fuel: '#2CC3D6', bank: '#34B36B', atm: '#34B36B', police: '#F0524F', fire_station: '#F0524F', place_of_worship: '#22B8CF', park: '#6BC25B', playground: '#6BC25B', sports_centre: '#6BC25B' };
  const poiColour = () => ['match', ['get', 'class']].concat(...Object.keys(POI_COL).map(k => [k, POI_COL[k]]), ['#8E97AB']);

  async function init() {
    if (ready) return ready;
    return (ready = (async () => {
      await mapReady;
      if (typeof build3d === 'function') build3d();
      const [detail, infill] = await Promise.all(['city-detail', 'infill'].map(f => fetch('assets/map/' + f + '.json').then(r => r.json()).catch(() => null)));
      addWalls();
      const p = pal(), lyrs = map.getStyle().layers, i3 = lyrs.findIndex(l => l.id === 'building-3d'), above = i3 >= 0 && lyrs[i3 + 1] ? lyrs[i3 + 1].id : undefined;
      const firstLabel = (lyrs.find(l => l.type === 'symbol') || {}).id, hide = { visibility: 'none' }, src = map.getSource('openmaptiles');
      // the buildings: walls with windows by height, then a plain roof over them (the plain 3D layer stays hidden underneath)
      if (src) {
        const wall = (id, k, flt) => map.addLayer({ id, type: 'fill-extrusion', source: 'openmaptiles', 'source-layer': 'building', minzoom: 15, filter: flt, layout: hide,
          paint: { 'fill-extrusion-pattern': wallName(k), 'fill-extrusion-height': H, 'fill-extrusion-base': MH, 'fill-extrusion-opacity': 1 } }, 'building-3d');
        wall('cd-w-lo', 'lo', ['<', H, 9]); wall('cd-w-mid', 'mid', ['all', ['>=', H, 9], ['<', H, 30]]); wall('cd-w-hi', 'hi', ['>=', H, 30]);
        map.addLayer({ id: 'cd-roof', type: 'fill-extrusion', source: 'openmaptiles', 'source-layer': 'building', minzoom: 15, layout: hide,
          paint: { 'fill-extrusion-color': roofColour(p), 'fill-extrusion-height': ['+', H, .25], 'fill-extrusion-base': ['-', H, .02], 'fill-extrusion-opacity': 1 } }, 'building-3d');
      }
      if (infill) {   // Overture's footprints that OpenStreetMap lacks: low plain blocks, heights estimated
        map.addSource('cd-infill', { type: 'geojson', data: infill });
        map.addLayer({ id: 'cd-infill', type: 'fill-extrusion', source: 'cd-infill', minzoom: 15.5, layout: hide,
          paint: { 'fill-extrusion-color': p.infill, 'fill-extrusion-height': ['get', 'render_height'], 'fill-extrusion-base': 0, 'fill-extrusion-opacity': 1 } }, 'building-3d');
      }
      // on the road: zebra crossings and the dashed lane lines
      if (detail && detail.crossings) {
        map.addSource('cd-cross', { type: 'geojson', data: detail.crossings });
        map.addLayer({ id: 'cd-cross', type: 'fill', source: 'cd-cross', minzoom: 16, layout: hide, paint: { 'fill-color': p.cross[0], 'fill-opacity': p.cross[1] } }, firstLabel);
      }
      if (src) map.addLayer({ id: 'cd-lane', type: 'line', source: 'openmaptiles', 'source-layer': 'transportation', minzoom: 16.4, layout: Object.assign({ 'line-cap': 'butt' }, hide),
        filter: ['in', ['get', 'class'], ['literal', ['motorway', 'trunk', 'primary', 'secondary', 'tertiary']]],
        paint: { 'line-color': p.lane[0], 'line-opacity': p.lane[1], 'line-width': ['interpolate', ['linear'], ['zoom'], 16.4, .7, 19, 1.6], 'line-dasharray': [3, 4] } }, firstLabel);
      // over the buildings: trees, places
      if (detail && detail.trees) {
        TREES = detail.trees; const [lo, hi, tr] = treeShapes(TREES);
        map.addSource('cd-canopy', { type: 'geojson', data: lo }); map.addSource('cd-canopy2', { type: 'geojson', data: hi }); map.addSource('cd-trunk', { type: 'geojson', data: tr });
        const fade = ['interpolate', ['linear'], ['zoom'], 15.6, 0, 16.4, .97];
        map.addLayer({ id: 'cd-trunk', type: 'fill-extrusion', source: 'cd-trunk', minzoom: 16, layout: hide, paint: { 'fill-extrusion-color': p.trunk, 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': 0, 'fill-extrusion-opacity': 1 } }, above);
        map.addLayer({ id: 'cd-canopy', type: 'fill-extrusion', source: 'cd-canopy', minzoom: 15.6, layout: hide, paint: { 'fill-extrusion-color': canopyColour(p, 'canopy'), 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': ['get', 'b'], 'fill-extrusion-opacity': fade } }, above);
        map.addLayer({ id: 'cd-canopy2', type: 'fill-extrusion', source: 'cd-canopy2', minzoom: 15.6, layout: hide, paint: { 'fill-extrusion-color': canopyColour(p, 'canopy2'), 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': ['get', 'b'], 'fill-extrusion-opacity': fade } }, above);
      }
      if (src) {
        map.addLayer({ id: 'cd-poi', type: 'circle', source: 'openmaptiles', 'source-layer': 'poi', minzoom: 16, layout: hide,
          paint: { 'circle-color': poiColour(), 'circle-radius': ['interpolate', ['linear'], ['zoom'], 16, 3.5, 18, 6], 'circle-stroke-color': p.poiStroke, 'circle-stroke-width': 1.6, 'circle-pitch-alignment': 'viewport' } }, above);
        map.addLayer({ id: 'cd-poi-name', type: 'symbol', source: 'openmaptiles', 'source-layer': 'poi', minzoom: 17, filter: ['has', 'name'],
          layout: { visibility: 'none', 'text-field': ['coalesce', ['get', 'name:latin'], ['get', 'name']], 'text-font': ['Noto Sans Bold'], 'text-size': 11, 'text-offset': [0, .9], 'text-anchor': 'top', 'text-max-width': 7, 'text-optional': true, 'text-pitch-alignment': 'viewport' },
          paint: { 'text-color': poiColour(), 'text-halo-color': p.haloText, 'text-halo-width': 1.5 } }, above);
      }
    })());
  }
  const LAYERS = ['cd-w-lo', 'cd-w-mid', 'cd-w-hi', 'cd-roof', 'cd-infill', 'cd-cross', 'cd-lane', 'cd-trunk', 'cd-canopy', 'cd-canopy2', 'cd-poi', 'cd-poi-name'];
  const has = id => !!map.getLayer(id), set = (id, k, v) => { if (has(id)) map.setPaintProperty(id, k, v); };
  function paint() {
    const p = pal();
    CLASSES.forEach(k => set('cd-w-' + k, 'fill-extrusion-pattern', wallName(k)));
    set('cd-roof', 'fill-extrusion-color', roofColour(p)); set('cd-infill', 'fill-extrusion-color', p.infill);
    set('cd-cross', 'fill-color', p.cross[0]); set('cd-cross', 'fill-opacity', p.cross[1]);
    set('cd-lane', 'line-color', p.lane[0]); set('cd-lane', 'line-opacity', p.lane[1]);
    set('cd-canopy', 'fill-extrusion-color', canopyColour(p, 'canopy')); set('cd-canopy2', 'fill-extrusion-color', canopyColour(p, 'canopy2')); set('cd-trunk', 'fill-extrusion-color', p.trunk);
    set('cd-poi', 'circle-stroke-color', p.poiStroke); set('cd-poi-name', 'text-halo-color', p.haloText);
    try { map.setLight(p.light); map.setSky(p.sky); } catch (e) { /* an older map */ }
  }
  // ---- how much detail: Auto draws the window walls and drops to plain walls if the map is running slowly on this
  // computer; Full and Light (Settings, Appearance) fix it either way ----
  const WALLS = ['cd-w-lo', 'cd-w-mid', 'cd-w-hi'];
  const quality = () => { try { return localStorage.getItem('ss-city') || 'auto'; } catch (e) { return 'auto'; } };
  let slow = false;
  const plainWalls = p => ['step', H, p.wall.lo[0], 9, p.wall.mid[0], 30, p.wall.hi[0]];
  function detail() {
    const q = quality(), full = on && has('cd-w-lo') && (q === 'full' || (q === 'auto' && !slow));
    WALLS.forEach(id => { if (has(id)) map.setLayoutProperty(id, 'visibility', full ? 'visible' : 'none'); });
    if (has('building-3d')) {
      map.setLayoutProperty('building-3d', 'visibility', on && !full ? 'visible' : 'none');
      if (on && !full) map.setPaintProperty('building-3d', 'fill-extrusion-color', plainWalls(pal()));
    }
  }
  // watch the frame rate while the map moves; when a quarter of the last ninety frames took over 28 ms, this screen cannot take the windows
  { let last = 0; const win = [];
    map.on('render', () => { if (!on || slow || quality() !== 'auto' || !map.isMoving()) { last = 0; win.length = 0; return; }
      const now = performance.now(), dt = last ? now - last : 0; last = now; if (!dt || dt > 400) return;
      win.push(dt > 28 ? 1 : 0); if (win.length > 90) win.shift();
      if (win.length === 90 && win.reduce((a, b) => a + b, 0) > 22) { slow = true; detail(); } }); }
  async function show(want) {
    on = want; await init(); if (want !== on) return;
    LAYERS.forEach(id => { if (has(id) && WALLS.indexOf(id) < 0) map.setLayoutProperty(id, 'visibility', want ? 'visible' : 'none'); });
    detail();
    if (want) paint(); else { try { map.setSky({}); map.setLight({ anchor: 'viewport', color: '#ffffff', intensity: .5, position: [1.15, 210, 30] }); } catch (e) { /* nothing to undo */ } }
  }
  map.on('pitch', () => { const up = map.getPitch() > 8; if (up !== on) show(up); });
  window.addEventListener('themechange', () => { if (on) { paint(); detail(); } });
  window.addEventListener('storage', e => { if (e.key === 'ss-city') { slow = false; if (on) detail(); } });
})();
