// Spatial Distribution, City view (Bellinist, 9 Oct 2026): what the tilted map adds to the flat one, in the manner of
// Apple Maps' detailed city experience, built only from open data (OpenStreetMap through OpenFreeMap, plus
// assets/map/city-detail.json, which docs/map-data/build_city_detail.py makes from OpenStreetMap).
//   light and haze     a low warm sun on the walls, a sky and a fog that fades the far streets into the night
//   buildings          their own OpenStreetMap heights, each a little different in tone
//   trees              the 93 OpenStreetMap has mapped, and stylised ones planted in the parks and the golf course
//   zebra crossings    one for every crossing OpenStreetMap has, laid across the road it is on
//   places             small coloured dots for shops, food, clinics and schools, as the other maps do
// Loaded after sd-tools.js; it shares map and mapReady with the page and leaves the flat map as it was.
(function () {
  'use strict';
  if (typeof map === 'undefined' || typeof mapReady === 'undefined') return;
  const isDark = () => document.documentElement.getAttribute('data-theme') === 'dark';
  const rgb = h => [1, 3, 5].map(i => parseInt(h.substr(i, 2), 16));

  // ---- the two palettes: Bellinist night and a warm day ----
  const PAL = {
    night: {
      light: { anchor: 'map', color: '#D6E0FF', intensity: .55, position: [1.4, 200, 48] },
      sky: { 'sky-color': '#0E1018', 'horizon-color': '#2A2F44', 'fog-color': '#14151B', 'sky-horizon-blend': .55, 'horizon-fog-blend': .8, 'fog-ground-blend': .55 },
      walls: [[0, '#363B49'], [14, '#454B60'], [45, '#5A6485'], [120, '#6E7AA3']], vary: [7, 7, 9],
      canopy: ['#1D3A2C', '#2F5E41'], trunk: '#3B2F28', cross: ['#FFFFFF', .6], haloText: 'rgba(14,15,20,.92)', text: '#EEF0F6',
    },
    day: {
      light: { anchor: 'map', color: '#FFFFFF', intensity: .4, position: [1.3, 215, 50] },
      sky: { 'sky-color': '#9CC4EE', 'horizon-color': '#E9EEF6', 'fog-color': '#E7EAF0', 'sky-horizon-blend': .5, 'horizon-fog-blend': .8, 'fog-ground-blend': .5 },
      walls: [[0, '#F3EFE9'], [14, '#EAE7E3'], [45, '#DEE2EA'], [120, '#CED4E1']], vary: [6, 6, 6],
      canopy: ['#6FB560', '#4E9855'], trunk: '#7A5F47', cross: ['#FFFFFF', .95], haloText: 'rgba(255,255,255,.95)', text: '#1B1C20',
    },
  };
  const pal = () => isDark() ? PAL.night : PAL.day;
  // each building a little different in tone: a stable number from its height and base
  const wallColour = p => {
    const h = ['coalesce', ['get', 'render_height'], 6];
    const n = ['%', ['*', ['+', h, ['*', ['coalesce', ['get', 'render_min_height'], 0], 3.7]], 12.9898], 1];
    const at = c => { const [r, g, b] = rgb(c); return ['rgb', ['+', r, ['*', n, p.vary[0]]], ['+', g, ['*', n, p.vary[1]]], ['+', b, ['*', n, p.vary[2]]]]; };
    return ['interpolate', ['linear'], h].concat(...p.walls.map(([ht, c]) => [ht, at(c)]));
  };
  const canopyColour = p => ['interpolate', ['linear'], ['get', 'v'], 0, p.canopy[0], 1, p.canopy[1]];

  let ready = null, on = false, TREES = [];
  const ngon = (cx, cy, r, n, rot) => {   // metres to degrees at this latitude
    const out = []; for (let i = 0; i <= n; i++) { const a = rot + i / n * Math.PI * 2; out.push([cx + Math.cos(a) * r / 107500, cy + Math.sin(a) * r / 110574]); } return out;
  };
  function treeShapes(trees) {
    const canopy = [], trunk = [];
    trees.forEach((t, i) => {
      const [lng, lat, r, h, v, cone, real] = t, rot = (i * 2.399) % 6.283;
      canopy.push({ type: 'Feature', properties: { v, b: h * .38, h: h, real }, geometry: { type: 'Polygon', coordinates: [ngon(lng, lat, cone ? r * .72 : r, cone ? 6 : 8, rot)] } });
      trunk.push({ type: 'Feature', properties: { h: h * .42 }, geometry: { type: 'Polygon', coordinates: [ngon(lng, lat, .38, 5, rot)] } });
    });
    return [{ type: 'FeatureCollection', features: canopy }, { type: 'FeatureCollection', features: trunk }];
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
      const detail = await fetch('assets/map/city-detail.json').then(r => r.json()).catch(() => null);
      const p = pal(), lyrs = map.getStyle().layers, i3 = lyrs.findIndex(l => l.id === 'building-3d'), above = i3 >= 0 && lyrs[i3 + 1] ? lyrs[i3 + 1].id : undefined;
      const vis = { visibility: 'none' };
      // on the road: the zebra crossings (a soft shadow at each building's foot was tried and dropped: it cost the frame rate)
      if (detail && detail.crossings) {
        map.addSource('cd-cross', { type: 'geojson', data: detail.crossings });
        map.addLayer({ id: 'cd-cross', type: 'fill', source: 'cd-cross', minzoom: 16, layout: vis, paint: { 'fill-color': p.cross[0], 'fill-opacity': p.cross[1] } }, (lyrs.find(l => l.type === 'symbol') || {}).id);   // on the road, under the labels
      }
      // over them: trees, places
      if (detail && detail.trees) {
        TREES = detail.trees; const [cs, ts] = treeShapes(TREES);
        map.addSource('cd-canopy', { type: 'geojson', data: cs }); map.addSource('cd-trunk', { type: 'geojson', data: ts });
        map.addLayer({ id: 'cd-trunk', type: 'fill-extrusion', source: 'cd-trunk', minzoom: 16, layout: vis, paint: { 'fill-extrusion-color': p.trunk, 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': 0, 'fill-extrusion-opacity': 1 } }, above);
        map.addLayer({ id: 'cd-canopy', type: 'fill-extrusion', source: 'cd-canopy', minzoom: 15.6, layout: vis,
          paint: { 'fill-extrusion-color': canopyColour(p), 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': ['get', 'b'], 'fill-extrusion-opacity': ['interpolate', ['linear'], ['zoom'], 15.6, .0, 16.4, .96] } }, above);
      }
      if (map.getSource('openmaptiles')) {
        map.addLayer({ id: 'cd-poi', type: 'circle', source: 'openmaptiles', 'source-layer': 'poi', minzoom: 16, layout: vis,
          paint: { 'circle-color': poiColour(), 'circle-radius': ['interpolate', ['linear'], ['zoom'], 16, 3.5, 18, 6], 'circle-stroke-color': isDark() ? '#15161B' : '#FFFFFF', 'circle-stroke-width': 1.6, 'circle-pitch-alignment': 'viewport' } }, above);
        map.addLayer({ id: 'cd-poi-name', type: 'symbol', source: 'openmaptiles', 'source-layer': 'poi', minzoom: 17, filter: ['has', 'name'],
          layout: { visibility: 'none', 'text-field': ['coalesce', ['get', 'name:latin'], ['get', 'name']], 'text-font': ['Noto Sans Bold'], 'text-size': 11, 'text-offset': [0, .9], 'text-anchor': 'top', 'text-max-width': 7, 'text-optional': true, 'text-pitch-alignment': 'viewport' },
          paint: { 'text-color': poiColour(), 'text-halo-color': p.haloText, 'text-halo-width': 1.5 } }, above);
      }
    })());
  }
  const LAYERS = ['cd-cross', 'cd-trunk', 'cd-canopy', 'cd-poi', 'cd-poi-name'];
  function paint() {
    const p = pal();
    if (map.getLayer('building-3d')) { map.setPaintProperty('building-3d', 'fill-extrusion-color', wallColour(p)); map.setPaintProperty('building-3d', 'fill-extrusion-vertical-gradient', true); }
    if (map.getLayer('cd-cross')) { map.setPaintProperty('cd-cross', 'fill-color', p.cross[0]); map.setPaintProperty('cd-cross', 'fill-opacity', p.cross[1]); }
    if (map.getLayer('cd-canopy')) map.setPaintProperty('cd-canopy', 'fill-extrusion-color', canopyColour(p));
    if (map.getLayer('cd-trunk')) map.setPaintProperty('cd-trunk', 'fill-extrusion-color', p.trunk);
    if (map.getLayer('cd-poi')) map.setPaintProperty('cd-poi', 'circle-stroke-color', isDark() ? '#15161B' : '#FFFFFF');
    if (map.getLayer('cd-poi-name')) map.setPaintProperty('cd-poi-name', 'text-halo-color', p.haloText);
    try { map.setLight(p.light); map.setSky(p.sky); } catch (e) { /* an older map */ }
  }
  async function show(want) {
    on = want; await init(); if (want !== on) return;
    LAYERS.forEach(id => { if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', want ? 'visible' : 'none'); });
    if (want) paint(); else { try { map.setSky({}); map.setLight({ anchor: 'viewport', color: '#ffffff', intensity: .5, position: [1.15, 210, 30] }); } catch (e) { /* nothing to undo */ } }
  }
  map.on('pitch', () => { const up = map.getPitch() > 8; if (up !== on) show(up); });
  window.addEventListener('themechange', () => { if (on) paint(); });
})();
