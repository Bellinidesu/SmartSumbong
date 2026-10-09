// Spatial Distribution, City view (Bellinist, 9 Oct 2026): what the tilted map adds to the flat one, in the manner of
// Apple Maps' detailed city experience, built only from open data (OpenStreetMap through OpenFreeMap, plus
// assets/map/city-detail.json and buildings.json, which docs/map-data/build_city_detail.py and build_buildings.py make
// from OpenStreetMap and Overture Maps).
//   light and haze     a low sun on the walls, a sky and a fog that fades the far streets away
//   buildings          every building in assets/map/buildings.json (Overture and OpenStreetMap footprints): walls with
//                      windows (lit at night), pitched roofs in the colours this neighbourhood's roofs have
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
      roofFlat: '#5C6590', roofs: ['#8C4650', '#9A5E48', '#3B5391', '#35705F', '#646880', '#8E846C', '#54424A', '#9EA1B5'],
      canopy: ['#1F6B53', '#2E8A63'], canopy2: ['#27805F', '#3AA374'], palm: ['#2F7F4E', '#4C9A55'], trunk: '#2F2A3A', palmTrunk: '#5A5068', tshadow: ['#04060F', .38],
      area: { fairway: '#2F8A63', green: '#3FA878', tee: '#3FA878', bunker: '#77738F', water: '#1D3A86', driving_range: '#2A7A58', 'pitch:basketball': '#B06A4C', 'pitch:tennis': '#4A73B8', 'pitch:soccer': '#3C9A6B', 'pitch:football': '#3C9A6B', playground: '#B9877A', swimming_pool: '#2E78C0', track: '#A8604A', other: '#3A9068' }, areaLine: ['#E9ECFA', .55], cross: ['#FFFFFF', .6], lane: ['#AEB6DA', .5],
      haloText: 'rgba(18,21,42,.92)', poiStroke: '#14172A',
      wk: { cream: '#6E749D', white: '#7C82AC', tan: '#6B6489' }, trim: '#8189B2', tower: '#767CA6',
      rk: { blue: '#3B5391', green: '#2E6B5B', white: '#8D93B8', tan: '#7A7396', cream: '#8087AE', grey: '#6B7096', red: '#8C4650' },
    },
    day: {
      light: { anchor: 'map', color: '#FFFFFF', intensity: .4, position: [1.3, 215, 50] },
      sky: { 'sky-color': '#8FC1F0', 'horizon-color': '#E9F1FA', 'fog-color': '#E8EDF3', 'sky-horizon-blend': .5, 'horizon-fog-blend': .8, 'fog-ground-blend': .5 },
      wall: { lo: ['#EDE9E3', '#A9BAD2', '#B9CADF', .05], mid: ['#E6E4E2', '#9FB1CC', '#B6C8DF', .06], hi: ['#DCE1EA', '#8EA4C4', '#AFC3DD', .08] },
      roofFlat: '#F2EFEA', roofs: ['#C25446', '#D07A45', '#3F6FC4', '#3E8E6C', '#9A9DA6', '#E3D3AC', '#7A5A48', '#EDEDED'],
      canopy: ['#7FCB5E', '#5FB55A'], canopy2: ['#8DD66A', '#6BC262'], palm: ['#74C24E', '#5DB04A'], trunk: '#8A6B4F', palmTrunk: '#B09370', tshadow: ['#2E4A2A', .2],
      area: { fairway: '#9BDB82', green: '#7CD36A', tee: '#7CD36A', bunker: '#F6ECC9', water: '#7CC4F0', driving_range: '#A9DF92', 'pitch:basketball': '#E8A168', 'pitch:tennis': '#6FA3E6', 'pitch:soccer': '#86D073', 'pitch:football': '#86D073', playground: '#EBC9A5', swimming_pool: '#62BDF0', track: '#D98B6E', other: '#8FD27E' }, areaLine: ['#FFFFFF', .9], cross: ['#FFFFFF', .95], lane: ['#CBC7BE', .85],
      haloText: 'rgba(255,255,255,.95)', poiStroke: '#FFFFFF',
      wk: { cream: '#EDE4D0', white: '#F3F0EA', tan: '#D9C6A5' }, trim: '#C9C4BA', tower: '#E9E4D8',
      rk: { blue: '#2F5FB5', green: '#2F7F6F', white: '#F2EEE7', tan: '#D7C3A4', cream: '#EFE6D4', grey: '#B5B8C0', red: '#B5473A' },
    },
  };
  const pal = () => isDark() ? PAL.night : PAL.day;
  const H = ['coalesce', ['get', 'render_height'], 6], MH = ['coalesce', ['get', 'render_min_height'], 0];
  const roofColour = p => ['case', ['has', 'rk'], ['match', ['get', 'rk']].concat(...Object.keys(p.rk).map(k => [k, p.rk[k]]), [p.rk.grey]),
    ['match', ['get', 'c'], -1, p.roofFlat].concat(...p.roofs.map((c, i) => [i, c]), [p.roofs[0]])];
  const wallKey = p => ['match', ['get', 'w']].concat(...Object.keys(p.wk).map(k => [k, p.wk[k]]), [p.wk.cream]);
  const trimColour = p => ['match', ['get', 'k'], 'tw', p.tower, 'sp', p.rk.grey, p.trim];
  const canopyColour = (p, k) => ['case', ['==', ['get', 's'], 2], ['interpolate', ['linear'], ['get', 'v'], 0, p.palm[0], 1, p.palm[1]], ['interpolate', ['linear'], ['get', 'v'], 0, p[k][0], 1, p[k][1]]];
  const trunkColour = p => ['case', ['==', ['get', 's'], 2], p.palmTrunk, p.trunk];
  const areaColour = p => ['match', ['get', 'k']].concat(...Object.keys(p.area).filter(k => k !== 'other').map(k => [k, p.area[k]]), [p.area.other]);

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

  // ---- the buildings: walls, and a pitched roof built of a few stepped slabs (gable: the ridge runs along the long side) ----
  // The landmarks are modelled a little further, from what the satellite picture shows of them: real roof colours,
  // flat roofs with a parapet and plant boxes for the terminals, malls and the hospital, green sheet roofs on the schools,
  // a bell tower on the churches. Each is one of the buildings in the file, found by the landmark's own position.
  const MX = 107500, MY = 110574;
  const MODELS = [
    [/^Barangay 183 Hall/, { w: 'cream', rk: 'blue', type: 'gable' }],
    [/Terminal|One-Stop|Bureau of Immigration/, { w: 'white', rk: 'white', type: 'flat', parapet: 1, boxes: 1 }],
    [/Mall|Supermarket|Post Exchange/, { w: 'tan', rk: 'tan', type: 'flat', parapet: 1, boxes: 1 }],
    [/Hospital/, { w: 'cream', rk: 'cream', type: 'flat', parapet: 1, boxes: 1 }],
    [/School|College|Aeronautics/, { w: 'cream', rk: 'green', type: 'gable' }],
    [/Prayer Room/, { w: 'white', rk: 'grey', type: 'gable' }],
    [/Shrine|Chapel|Church|Ang Dating/, { w: 'white', rk: 'grey', type: 'gable', tower: 1 }],
  ];
  const hit01 = (a, b) => { const x = Math.sin(a * 12.9898 + b * 78.233) * 43758.5453; return x - Math.floor(x); };
  const inRing = (pt, ring) => { let c = false; for (let i = 0, j = ring.length - 2; i < ring.length; j = i, i += 2) { const ax = ring[i], ay = ring[i + 1], bx = ring[j], by = ring[j + 1]; if ((ay > pt[1]) !== (by > pt[1]) && pt[0] < (bx - ax) * (pt[1] - ay) / (by - ay) + ax) c = !c; } return c; };
  function bldShapes(d, lms) {
    const walls = [], roofs = [], lmWalls = [], trim = [], spec = new Map();
    (lms || []).forEach(l => {
      const m = MODELS.find(([re]) => re.test(l.n)); if (!m) return;
      let best = -1, bd = 1e9;
      d.b.forEach((b, i) => {
        const dx = Math.abs(b[4] - l.c[0]), dy = Math.abs(b[5] - l.c[1]); if (dx > .0009 || dy > .0009) return;
        if (inRing(l.c, b[0])) { best = i; bd = -1; return; }
        if (bd >= 0) { const dd = Math.hypot(dx * MX, dy * MY); if (dd < bd && dd < 28) { bd = dd; best = i; } }
      });
      if (best >= 0) spec.set(best, m[1]);
    });
    const box = (x0, y0, co, si, u, v, hl, hw) => [[-hl, -hw], [hl, -hw], [hl, hw], [-hl, hw], [-hl, -hw]].map(([a, b]) => [(x0 + (u + a) * co - (v + b) * si) / MX, (y0 + (u + a) * si + (v + b) * co) / MY]);
    d.b.forEach(([ring, h, rt, ci, cx, cy, L, W, th], idx) => {
      const poly = []; for (let i = 0; i < ring.length; i += 2) poly.push([ring[i], ring[i + 1]]); poly.push(poly[0]);
      const m = spec.get(idx), co = Math.cos(th), si = Math.sin(th), x0 = cx * MX, y0 = cy * MY;
      if (m) {
        lmWalls.push({ type: 'Feature', properties: { h, w: m.w }, geometry: { type: 'Polygon', coordinates: [poly] } });
        const pitched = m.type === 'gable' && L * W > 60 && L * W < 2500;
        if (!pitched) {
          roofs.push({ type: 'Feature', properties: { b: h - .02, t: h + .25, rk: m.rk }, geometry: { type: 'Polygon', coordinates: [poly] } });
          if (m.parapet) {   // a low wall round the roof's edge
            const inner = poly.map(([lng, lat]) => {
              const u = (lng * MX - x0) * co + (lat * MY - y0) * si, v = -(lng * MX - x0) * si + (lat * MY - y0) * co, fu = 1 - 1.1 / Math.max(2, L / 2), fv = 1 - 1.1 / Math.max(2, W / 2);
              const uu = u * fu, vv = v * fv; return [(x0 + uu * co - vv * si) / MX, (y0 + uu * si + vv * co) / MY];
            });
            trim.push({ type: 'Feature', properties: { b: h, t: h + .9, k: 'p' }, geometry: { type: 'Polygon', coordinates: [poly, inner.slice().reverse()] } });
          }
          if (m.boxes) {   // plant rooms and stair heads, set out the same way every time
            const n = Math.min(9, Math.floor(L * W / 350));
            for (let k = 0; k < n; k++) {
              const u = (hit01(cx, k + 1) - .5) * L * .72, v = (hit01(cy, k + 7) - .5) * W * .72, hl = 1.3 + hit01(cx + k, cy) * 2, hw = 1.2 + hit01(cy + k, cx) * 1.6;
              const q = box(x0, y0, co, si, u, v, hl, hw), cxm = (x0 + u * co - v * si) / MX, cym = (y0 + u * si + v * co) / MY;
              if (inRing([cxm, cym], ring)) trim.push({ type: 'Feature', properties: { b: h, t: h + 1.4 + hit01(k, cx) * 1.4, k: 'p' }, geometry: { type: 'Polygon', coordinates: [q] } });
            }
          }
        } else {
          const R = Math.max(.8, Math.min(2.4, W * .2)), step = R / 3;
          for (let k = 0; k < 3; k++) {
            const hl = (L + .6) / 2, hw = (W + .8) / 2 * (1 - k * .36);
            roofs.push({ type: 'Feature', properties: { b: h + k * step, t: h + (k + 1) * step, rk: m.rk }, geometry: { type: 'Polygon', coordinates: [box(x0, y0, co, si, 0, 0, hl, hw)] } });
          }
        }
        if (m.tower) {   // a bell tower at one end of the church, and a spire
          const u = L / 2 - 2.4, hh = h + 7.5;
          trim.push({ type: 'Feature', properties: { b: 0, t: hh, k: 'tw' }, geometry: { type: 'Polygon', coordinates: [box(x0, y0, co, si, u, 0, 1.7, 1.7)] } });
          [[hh, hh + 1.6, 1.3], [hh + 1.6, hh + 3.2, .8], [hh + 3.2, hh + 4.6, .35]].forEach(([b, t, r]) => trim.push({ type: 'Feature', properties: { b, t, k: 'sp' }, geometry: { type: 'Polygon', coordinates: [box(x0, y0, co, si, u, 0, r, r)] } }));
        }
        return;
      }
      walls.push({ type: 'Feature', properties: { h }, geometry: { type: 'Polygon', coordinates: [poly] } });
      if (!rt) { roofs.push({ type: 'Feature', properties: { b: h - .02, t: h + .25, c: -1 }, geometry: { type: 'Polygon', coordinates: [poly] } }); return; }
      const R = Math.max(.7, Math.min(2.4, W * .2)), step = R / 3;
      for (let k = 0; k < 3; k++) {
        const hl = (L + .6) / 2 * (rt === 2 ? 1 - k * .3 : 1), hw = (W + .8) / 2 * (1 - k * .36);
        roofs.push({ type: 'Feature', properties: { b: h + k * step, t: h + (k + 1) * step, c: ci }, geometry: { type: 'Polygon', coordinates: [box(x0, y0, co, si, 0, 0, hl, hw)] } });
      }
    });
    const fc = f => ({ type: 'FeatureCollection', features: f });
    return [fc(walls), fc(roofs), fc(lmWalls), fc(trim)];
  }

  let ready = null, on = false, TREES = [];
  const ngon = (cx, cy, r, n, rot) => {   // metres to degrees at this latitude
    const out = []; for (let i = 0; i <= n; i++) { const a = rot + i / n * Math.PI * 2; out.push([cx + Math.cos(a) * r / 107500, cy + Math.sin(a) * r / 110574]); } return out;
  };
  function treeShapes(trees) {
    const c1 = [], c2 = [], trunk = [], shade = [];
    const feat = (props, ring) => ({ type: 'Feature', properties: props, geometry: { type: 'Polygon', coordinates: [ring] } });
    const star = (cx, cy, R, r, n, rot) => { const out = []; for (let i = 0; i <= n * 2; i++) { const a = rot + i / (n * 2) * Math.PI * 2, rr = i % 2 ? r : R; out.push([cx + Math.cos(a) * rr / 107500, cy + Math.sin(a) * rr / 110574]); } return out; };
    trees.forEach((t, i) => {
      const [lng, lat, r, h, v, shape] = t, rot = (i * 2.399) % 6.283, s = shape || 0;
      const jx = (Math.sin(i * 7.7) * .5) * r * .3, jy = (Math.cos(i * 5.3) * .5) * r * .3;      // the upper crown sits a little off-centre, so no two trees are quite alike
      const ox = lng + jx / 107500, oy = lat + jy / 110574;
      if (s === 2) {          // a palm: a tall slim trunk, a flat crown of fronds, a small tuft on top
        c1.push(feat({ v, s, b: h * .86, h: h * .96 }, star(lng, lat, 3.4, 1.0, 8, rot)));
        c2.push(feat({ v, s, b: h * .96, h: h * 1.06 }, ngon(lng, lat, 1.0, 7, rot)));
        trunk.push(feat({ s, h: h * .88 }, ngon(lng, lat, .3, 5, rot)));
      } else if (s === 1) {   // an evergreen: wide at its foot, narrow at its top
        c1.push(feat({ v, s, b: h * .2, h: h * .6 }, ngon(lng, lat, r * .85, 8, rot)));
        c2.push(feat({ v, s, b: h * .5, h }, ngon(lng, lat, r * .42, 7, rot)));
        trunk.push(feat({ s, h: h * .35 }, ngon(lng, lat, .38, 5, rot)));
      } else {                // a round-crowned tree: a full lower crown and a narrower, off-centre upper one
        c1.push(feat({ v, s, b: h * .3, h: h * .7 }, ngon(lng, lat, r * (.92 + (v - .5) * .2), 9, rot)));
        c2.push(feat({ v, s, b: h * .58, h }, ngon(ox, oy, r * .68, 8, rot + .4)));
        trunk.push(feat({ s, h: h * .42 }, ngon(lng, lat, .38, 5, rot)));
      }
      shade.push(feat({}, ngon(lng + h * .22 / 107500, lat + h * .38 / 110574, (s === 2 ? 2.4 : r * .95), 9, rot)));   // the shadow on the ground, thrown away from the light
    });
    const fc = f => ({ type: 'FeatureCollection', features: f });
    return [fc(c1), fc(c2), fc(trunk), fc(shade)];
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
      const [detail, bld, lmj] = await Promise.all(['city-detail', 'buildings'].map(f => fetch('assets/map/' + f + '.json').then(r => r.json()).catch(() => null)).concat(fetch('assets/map/landmarks.geojson').then(r => r.json()).catch(() => null)));
      const lms = lmj ? lmj.features.map(f => ({ n: (f.properties && f.properties.name) || '', c: f.geometry.coordinates })).filter(x => x.n) : [];
      addWalls();
      const p = pal(), lyrs = map.getStyle().layers, i3 = lyrs.findIndex(l => l.id === 'building-3d'), above = i3 >= 0 && lyrs[i3 + 1] ? lyrs[i3 + 1].id : undefined;
      const firstLabel = (lyrs.find(l => l.type === 'symbol') || {}).id, hide = { visibility: 'none' }, src = map.getSource('openmaptiles');
      // the buildings: walls with windows by height, then their roofs (the map tiles' plain 3D buildings stay hidden underneath)
      if (bld && bld.b) {
        const [walls, roofs, lmw, trim] = bldShapes(bld, lms);
        map.addSource('cd-bld', { type: 'geojson', data: walls }); map.addSource('cd-roofs', { type: 'geojson', data: roofs }); map.addSource('cd-lm', { type: 'geojson', data: lmw }); map.addSource('cd-trim', { type: 'geojson', data: trim });
        const wall = (id, k, flt) => map.addLayer({ id, type: 'fill-extrusion', source: 'cd-bld', minzoom: 15, filter: flt, layout: hide,
          paint: { 'fill-extrusion-pattern': wallName(k), 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': 0, 'fill-extrusion-opacity': 1 } }, 'building-3d');
        wall('cd-w-lo', 'lo', ['<', ['get', 'h'], 9]); wall('cd-w-mid', 'mid', ['all', ['>=', ['get', 'h'], 9], ['<', ['get', 'h'], 30]]); wall('cd-w-hi', 'hi', ['>=', ['get', 'h'], 30]);
        map.addLayer({ id: 'cd-lm-wall', type: 'fill-extrusion', source: 'cd-lm', minzoom: 15, layout: hide,
          paint: { 'fill-extrusion-color': wallKey(p), 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': 0, 'fill-extrusion-opacity': 1 } }, 'building-3d');
        map.addLayer({ id: 'cd-lm-trim', type: 'fill-extrusion', source: 'cd-trim', minzoom: 15.6, layout: hide,
          paint: { 'fill-extrusion-color': trimColour(p), 'fill-extrusion-height': ['get', 't'], 'fill-extrusion-base': ['get', 'b'], 'fill-extrusion-opacity': 1 } }, 'building-3d');
        map.addLayer({ id: 'cd-roof', type: 'fill-extrusion', source: 'cd-roofs', minzoom: 16, layout: hide,
          paint: { 'fill-extrusion-color': roofColour(p), 'fill-extrusion-height': ['get', 't'], 'fill-extrusion-base': ['get', 'b'], 'fill-extrusion-opacity': 1 } }, 'building-3d');
      }
      // on the road: zebra crossings and the dashed lane lines
      if (detail && detail.crossings) {
        map.addSource('cd-cross', { type: 'geojson', data: detail.crossings });
        map.addLayer({ id: 'cd-cross', type: 'fill', source: 'cd-cross', minzoom: 16, layout: hide, paint: { 'fill-color': p.cross[0], 'fill-opacity': p.cross[1] } }, firstLabel);
      }
      if (detail && detail.areas) {   // the golf course as it is mapped, and the pitches, playgrounds and pools, drawn flat
        map.addSource('cd-areas', { type: 'geojson', data: detail.areas });
        map.addLayer({ id: 'cd-area', type: 'fill', source: 'cd-areas', minzoom: 15.4, layout: hide, paint: { 'fill-color': areaColour(p) } }, firstLabel);
        map.addLayer({ id: 'cd-area-line', type: 'line', source: 'cd-areas', minzoom: 16.4, layout: hide, filter: ['any', ['==', ['slice', ['get', 'k'], 0, 5], 'pitch'], ['==', ['get', 'k'], 'track']],
          paint: { 'line-color': p.areaLine[0], 'line-opacity': p.areaLine[1], 'line-width': ['interpolate', ['linear'], ['zoom'], 16.4, .6, 19, 1.6] } }, firstLabel);
      }
      if (src) map.addLayer({ id: 'cd-lane', type: 'line', source: 'openmaptiles', 'source-layer': 'transportation', minzoom: 16.4, layout: Object.assign({ 'line-cap': 'butt' }, hide),
        filter: ['in', ['get', 'class'], ['literal', ['motorway', 'trunk', 'primary', 'secondary', 'tertiary']]],
        paint: { 'line-color': p.lane[0], 'line-opacity': p.lane[1], 'line-width': ['interpolate', ['linear'], ['zoom'], 16.4, .7, 19, 1.6], 'line-dasharray': [3, 4] } }, firstLabel);
      // over the buildings: trees, places
      if (detail && detail.trees) {
        TREES = detail.trees; const [lo, hi, tr, sh] = treeShapes(TREES);
        map.addSource('cd-canopy', { type: 'geojson', data: lo }); map.addSource('cd-canopy2', { type: 'geojson', data: hi }); map.addSource('cd-trunk', { type: 'geojson', data: tr }); map.addSource('cd-tsh', { type: 'geojson', data: sh });
        map.addLayer({ id: 'cd-tshadow', type: 'fill', source: 'cd-tsh', minzoom: 16, layout: hide, paint: { 'fill-color': p.tshadow[0], 'fill-opacity': p.tshadow[1] } }, firstLabel);
        const fade = ['interpolate', ['linear'], ['zoom'], 15.6, 0, 16.4, .97];
        map.addLayer({ id: 'cd-trunk', type: 'fill-extrusion', source: 'cd-trunk', minzoom: 16, layout: hide, paint: { 'fill-extrusion-color': trunkColour(p), 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': 0, 'fill-extrusion-opacity': 1 } }, above);
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
  const LAYERS = ['cd-w-lo', 'cd-w-mid', 'cd-w-hi', 'cd-lm-wall', 'cd-lm-trim', 'cd-roof', 'cd-cross', 'cd-lane', 'cd-area', 'cd-area-line', 'cd-tshadow', 'cd-trunk', 'cd-canopy', 'cd-canopy2', 'cd-poi', 'cd-poi-name'];
  const has = id => !!map.getLayer(id), set = (id, k, v) => { if (has(id)) map.setPaintProperty(id, k, v); };
  function paint() {
    const p = pal();
    CLASSES.forEach(k => set('cd-w-' + k, 'fill-extrusion-pattern', wallName(k)));
    set('cd-roof', 'fill-extrusion-color', roofColour(p)); set('cd-lm-wall', 'fill-extrusion-color', wallKey(p)); set('cd-lm-trim', 'fill-extrusion-color', trimColour(p));
    set('cd-cross', 'fill-color', p.cross[0]); set('cd-cross', 'fill-opacity', p.cross[1]);
    set('cd-lane', 'line-color', p.lane[0]); set('cd-lane', 'line-opacity', p.lane[1]);
    set('cd-canopy', 'fill-extrusion-color', canopyColour(p, 'canopy')); set('cd-canopy2', 'fill-extrusion-color', canopyColour(p, 'canopy2')); set('cd-trunk', 'fill-extrusion-color', trunkColour(p));
    set('cd-area', 'fill-color', areaColour(p)); set('cd-area-line', 'line-color', p.areaLine[0]); set('cd-area-line', 'line-opacity', p.areaLine[1]); set('cd-tshadow', 'fill-color', p.tshadow[0]); set('cd-tshadow', 'fill-opacity', p.tshadow[1]);
    set('cd-poi', 'circle-stroke-color', p.poiStroke); set('cd-poi-name', 'text-halo-color', p.haloText);
    try { map.setLight(p.light); map.setSky(p.sky); } catch (e) { /* an older map */ }
  }
  // ---- how much detail: Auto draws the window walls and drops to plain walls if the map is running slowly on this
  // computer (Light also drops the pitched roofs); Full and Light (Settings, Appearance) fix it either way ----
  const WALLS = ['cd-w-lo', 'cd-w-mid', 'cd-w-hi'];
  const quality = () => { try { return localStorage.getItem('ss-city') || 'auto'; } catch (e) { return 'auto'; } };
  let slow = false;
  const plainWalls = p => ['step', H, p.wall.lo[0], 9, p.wall.mid[0], 30, p.wall.hi[0]];
  function detail() {
    const q = quality(), full = on && has('cd-w-lo') && (q === 'full' || (q === 'auto' && !slow));
    WALLS.forEach(id => { if (has(id)) map.setLayoutProperty(id, 'visibility', full ? 'visible' : 'none'); });
    ['cd-roof', 'cd-lm-wall', 'cd-lm-trim'].forEach(id => { if (has(id)) map.setLayoutProperty(id, 'visibility', full ? 'visible' : 'none'); });   // Light: plain boxes, no roofs, no models
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
    LAYERS.forEach(id => { if (has(id) && WALLS.indexOf(id) < 0 && ['cd-roof', 'cd-lm-wall', 'cd-lm-trim'].indexOf(id) < 0) map.setLayoutProperty(id, 'visibility', want ? 'visible' : 'none'); });
    detail();
    if (want) paint(); else { try { map.setSky({}); map.setLight({ anchor: 'viewport', color: '#ffffff', intensity: .5, position: [1.15, 210, 30] }); } catch (e) { /* nothing to undo */ } }
  }
  map.on('pitch', () => { const up = map.getPitch() > 8; if (up !== on) show(up); });
  window.addEventListener('themechange', () => { if (on) { paint(); detail(); } });
  window.addEventListener('storage', e => { if (e.key === 'ss-city') { slow = false; if (on) detail(); } });
})();
