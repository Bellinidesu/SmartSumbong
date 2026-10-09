// Spatial Distribution, City view (Bellinist, 9 Oct 2026): what the tilted map adds to the flat one, in the manner of
// Apple Maps' detailed city experience, built only from open data (OpenStreetMap through OpenFreeMap, plus
// assets/map/city-detail.json and buildings.json, which docs/map-data/build_city_detail.py and build_buildings.py make
// from OpenStreetMap and Overture Maps).
//   light and haze     a low sun on the walls, a sky and a fog that fades the far streets away
//   buildings          every building in assets/map/buildings.json (Overture and OpenStreetMap footprints): walls with
//                      windows (lit at night), pitched roofs in the colours this neighbourhood's roofs have
//   shadows            baked ahead of time into one picture of the ground (docs/map-data/bake_shadows.py): what each
//                      building and tree throws, and the dark at the foot of a wall and down a lane; free while the map moves
//   wall faces         a thin plate over every wall face painted with its own baked light (docs/map-data/bake_detail.py): sun and
//                      sky by day, the warmth of the nearest street lamps by night
//   trees              the 93 OpenStreetMap has mapped, and rounded ones planted in the parks and the golf course
//   road detail        zebra crossings (all 125 OpenStreetMap has) and dashed lane lines
//   places             small coloured dots for shops, food, clinics and schools
// Plain colours, no textures: colours and textures cost frames and memory, so buildings are single colours and the shading
// (a tone for each building, the shadows on the ground) is baked ahead of time by docs/map-data/bake_shadows.py.
// Nothing is drawn outside the Barangay 183 boundary, and beyond its edge the ground fades into fog.
// Loaded after sd-tools.js; it shares map and mapReady with the page and leaves the flat map as it was.
(function () {
  'use strict';
  if (typeof map === 'undefined' || typeof mapReady === 'undefined') return;
  const isDark = () => document.documentElement.getAttribute('data-theme') === 'dark';
  const WINDOWS = false;   // the window-textured walls are kept behind this switch, off: textures eat memory and frames
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
      wpal: ['#554C86', '#5A5090', '#4A5C90', '#4F6A92', '#654F90', '#505890', '#655A88', '#4C6090'], wtall: ['#4C5490', '#5A64A0'], glow: [255, 150, 46],
      bake: .95, haloText: 'rgba(18,21,42,.92)', poiStroke: '#14172A',
      wk: { cream: '#6E749D', white: '#7C82AC', tan: '#6B6489' }, trim: '#8189B2', tower: '#767CA6',
      rk: { blue: '#3B5391', green: '#2E6B5B', white: '#8D93B8', tan: '#7A7396', cream: '#8087AE', grey: '#6B7096', red: '#8C4650' },
    },
    day: {
      light: { anchor: 'map', color: '#FFFFFF', intensity: .4, position: [1.3, 200, 50] },
      sky: { 'sky-color': '#8FC1F0', 'horizon-color': '#E9F1FA', 'fog-color': '#E8EDF3', 'sky-horizon-blend': .5, 'horizon-fog-blend': .8, 'fog-ground-blend': .5 },
      wall: { lo: ['#EEEAE4', '#CBD3DE', '#D3DAE4', .05], mid: ['#E8E6E4', '#C3CCD9', '#CBD4E0', .06], hi: ['#DEE2EA', '#B3C0D2', '#BFCADA', .08] },
      roofFlat: '#F2EFEA', roofs: ['#C25446', '#D07A45', '#3F6FC4', '#3E8E6C', '#9A9DA6', '#E3D3AC', '#7A5A48', '#EDEDED'],
      canopy: ['#7FCB5E', '#5FB55A'], canopy2: ['#8DD66A', '#6BC262'], palm: ['#74C24E', '#5DB04A'], trunk: '#8A6B4F', palmTrunk: '#B09370', tshadow: ['#2E4A2A', .2],
      area: { fairway: '#9BDB82', green: '#7CD36A', tee: '#7CD36A', bunker: '#F6ECC9', water: '#7CC4F0', driving_range: '#A9DF92', 'pitch:basketball': '#E8A168', 'pitch:tennis': '#6FA3E6', 'pitch:soccer': '#86D073', 'pitch:football': '#86D073', playground: '#EBC9A5', swimming_pool: '#62BDF0', track: '#D98B6E', other: '#8FD27E' }, areaLine: ['#FFFFFF', .9], cross: ['#FFFFFF', .95], lane: ['#CBC7BE', .85],
      wpal: ['#F5C2A6', '#F8DC9C', '#BEE2CB', '#B8D6F2', '#D3C2F0', '#F1ECE4', '#EBC590', '#D0D0D6'], wtall: ['#E6E4E2', '#D8DDE8'], glow: [0, 0, 0],
      bake: .6, haloText: 'rgba(255,255,255,.95)', poiStroke: '#FFFFFF',
      wk: { cream: '#EDE4D0', white: '#F3F0EA', tan: '#D9C6A5' }, trim: '#C9C4BA', tower: '#E9E4D8',
      rk: { blue: '#2F5FB5', green: '#2F7F6F', white: '#F2EEE7', tan: '#D7C3A4', cream: '#EFE6D4', grey: '#B5B8C0', red: '#B5473A' },
    },
  };
  // ---- looks: the lighting and shading of the City view, day and night. Everything here is baked or plain colour:
  // a tone per building, roofs painted in a lit half and a shaded half, shadows laid on the ground. Nothing is a texture. ----
  const mix = (a, b, t) => '#' + [1, 3, 5].map(i => Math.round(parseInt(a.substr(i, 2), 16) * (1 - t) + parseInt(b.substr(i, 2), 16) * t).toString(16).padStart(2, '0')).join('');
  const mixAll = (arr, b, t) => arr.map(c => mix(c, b, t));
  const LOOKS = {
    steps: { mode: 'steps', vg: true, toneK: 1 },     // the roofs as stepped slabs (what the City view had)
    // Apple Maps: soft, pastel, a high even light, every roof a gentle two-tone
    apple: { mode: 'halves', lit: 1.04, litN: 1.5, shade: .9, shadeN: .82, vg: true, toneK: 1, az: 200,
      day: { light: { anchor: 'map', color: '#FFFFFF', intensity: .26, position: [1.2, 200, 56] }, roofs: Array(8).fill('#F6F4F0'), roofFlat: '#F6F4F0', rk: { blue: '#F6F4F0', green: '#F6F4F0', white: '#F6F4F0', tan: '#F6F4F0', cream: '#F6F4F0', grey: '#F6F4F0', red: '#F6F4F0' }, bake: .62 },
      night: { light: { anchor: 'map', color: '#BFD0FF', intensity: .32, position: [1.3, 200, 52] }, sky: { 'sky-color': '#0E1226', 'horizon-color': '#4B3F72', 'fog-color': '#1A1E33', 'sky-horizon-blend': .6, 'horizon-fog-blend': .85, 'fog-ground-blend': .5 },
        roofs: Array(8).fill('#2C3256'), roofFlat: '#2C3256', rk: { blue: '#2C3256', green: '#2C3256', white: '#2C3256', tan: '#2C3256', cream: '#2C3256', grey: '#2C3256', red: '#2C3256' }, bake: .95 } },
    // two-tone roofs in the roofs' own colours, a strong lit side and shaded side
    halves: { mode: 'halves', lit: 1.12, shade: .72, vg: true, toneK: 1, az: 200 },
  };
  let LOOK = 'apple';   // Apple Soft is the look; the other two stay for comparison (sdCityLook('steps') or ('halves') in the console)
  try { LOOK = localStorage.getItem('ss-look') || 'apple'; } catch (e) { /* the default look */ }
  const look = () => LOOKS[LOOK] || LOOKS.apple;
  const pal = () => { const base = isDark() ? PAL.night : PAL.day, o = look()[isDark() ? 'night' : 'day'] || {}; return Object.assign({}, base, o, { wall: Object.assign({}, base.wall, o.wall || {}) }); };
  const H = ['coalesce', ['get', 'render_height'], 6], MH = ['coalesce', ['get', 'render_min_height'], 0];
  // a plain colour times the tone baked into each building (field 10 of buildings.json): the shading, without a texture
  const KTONE = ['coalesce', ['get', 'k'], 1];
  const toneExpr = () => look().toneStep ? ['step', KTONE, .7, .78, .82, .9, 1] : ['^', KTONE, look().toneK || 1];
  const HALF = ['coalesce', ['get', 's'], 1];   // a roof half's lit or shaded factor (1 for everything else)
  const ch = (hex, i) => parseInt(hex.substr(1 + i * 2, 2), 16);
  const shaded = (f, add) => { const t = toneExpr(), a = i => add ? ['+', ['*', f(i), t, HALF], add(i)] : ['*', f(i), t, HALF]; return ['rgb', ['min', 255, a(0)], ['min', 255, a(1)], ['min', 255, a(2)]]; };
  const roofColour = p => shaded(i => ['case', ['has', 'rk'], ['match', ['get', 'rk']].concat(...Object.keys(p.rk).map(k => [k, ch(p.rk[k], i)]), [ch(p.rk.grey, i)]),
    ['match', ['get', 'c'], -1, ch(p.roofFlat, i)].concat(...p.roofs.map((c, j) => [j, ch(c, i)]), [ch(p.roofs[0], i)])]);
  const wallKey = p => shaded(i => ['match', ['get', 'w']].concat(...Object.keys(p.wk).map(k => [k, ch(p.wk[k], i)]), [ch(p.wk.cream, i)]), i => ['*', ['coalesce', ['get', 'g'], 0], p.glow[i]]);
  // houses in a set of pastels (one for each, from where it stands), towers in neutrals; at night a house with its lights on adds warmth
  const wallPlain = p => shaded(i => ['case', ['>=', ['get', 'h'], 9], ['step', ['get', 'h'], ch(p.wtall[0], i), 30, ch(p.wtall[1], i)],
    ['match', ['get', 'wi']].concat(...p.wpal.map((c, j) => [j, ch(c, i)]), [ch(p.wpal[0], i)])], i => ['*', ['coalesce', ['get', 'g'], 0], p.glow[i]]);
  const faceColour = p => shaded(i => ['case', ['has', 'lw'], ['match', ['get', 'lw']].concat(...Object.keys(p.wk).map(k => [k, ch(p.wk[k], i)]), [ch(p.wk.cream, i)]), ['>=', ['get', 'h'], 9], ['step', ['get', 'h'], ch(p.wtall[0], i), 30, ch(p.wtall[1], i)],
    ['match', ['get', 'wi']].concat(...p.wpal.map((c, j) => [j, ch(c, i)]), [ch(p.wpal[0], i)])], i => ['*', p.glow[i], ['+', ['*', ['coalesce', ['get', 'g'], 0], .55], ['*', ['coalesce', ['get', 'w'], 0], 1.8]]]);
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
  // A thin plate over each wall face (outside it by a hand's width), in two bands: the foot, and the rest of the wall. Its colour is the
  // house's plain colour times the tone baked for that face; the lamp light baked for it is added warm at night.
  const dig = ch => '0123456789abcdefghijklmnopqrstuvwxyz'.indexOf(ch);
  function facePlates(d, faces) {
    const out = [], low = faces.lowBand || 4.5;
    d.b.forEach((b, idx) => {
      const row = faces.f[idx]; if (!row || b[1] < 2) return;
      const lmSpec = b._lm || null;
      const ring = b[0], k = ring.length / 2, h = b[1], tone = row[0].split('|'), lamp = row[1].split('|');
      if (tone[0].length !== k) return;
      let area = 0; for (let i = 0; i < k; i++) { const j = (i + 1) % k; area += ring[2 * i] * MX * ring[2 * j + 1] * MY - ring[2 * j] * MX * ring[2 * i + 1] * MY; }
      const sg = area > 0 ? 1 : -1, wi = Math.min(7, Math.floor(hit01(b[4], b[5]) * 8)), g = b[12] || 0;
      for (let i = 0; i < k; i++) {
        const j = (i + 1) % k, x0 = ring[2 * i] * MX, y0 = ring[2 * i + 1] * MY, x1 = ring[2 * j] * MX, y1 = ring[2 * j + 1] * MY, dx = x1 - x0, dy = y1 - y0, ln = Math.hypot(dx, dy);
        if (ln < 1.4) continue;
        const nx = sg * dy / ln * .15, ny = -sg * dx / ln * .15, ox = nx * .15 / .15 * .1, oy = ny * .1;
        const quad = [[x0 + ox, y0 + oy], [x1 + ox, y1 + oy], [x1 + nx + ox, y1 + ny + oy], [x0 + nx + ox, y0 + ny + oy], [x0 + ox, y0 + oy]].map(([a, c]) => [a / MX, c / MY]);
        const bands = h > low + 1 ? [[0, low, 0], [low, h, 1]] : [[0, h, 0]];
        bands.forEach(([bb, tt, up]) => out.push({ type: 'Feature', properties: Object.assign({ b: bb, t: tt, h, wi, g, k: .62 + .38 * (dig(tone[up][i]) / 35), w: dig(lamp[up][i]) / 35 }, lmSpec ? { lw: lmSpec.w } : {}), geometry: { type: 'Polygon', coordinates: [quad] } }));
      }
    });
    return { type: 'FeatureCollection', features: out };
  }
  function bldShapes(d, lms, lk) {
    lk = lk || LOOKS.steps;
    const sun = (lk.az === undefined ? 200 : lk.az) * Math.PI / 180, sx = Math.sin(sun), sy = Math.cos(sun);
    const walls = [], roofs = [], lmWalls = [], trim = [], spec = new Map();
    (lms || []).forEach(l => {
      const m = MODELS.find(([re]) => re.test(l.n)); if (!m) return;
      let best = -1, bd = 1e9;
      d.b.forEach((b, i) => {
        const dx = Math.abs(b[4] - l.c[0]), dy = Math.abs(b[5] - l.c[1]); if (dx > .0009 || dy > .0009) return;
        if (inRing(l.c, b[0])) { best = i; bd = -1; return; }
        if (bd >= 0) { const dd = Math.hypot(dx * MX, dy * MY); if (dd < bd && dd < 28) { bd = dd; best = i; } }
      });
      if (best >= 0) { spec.set(best, m[1]); d.b[best]._lm = 1; }
    });
    const box = (x0, y0, co, si, u, v, hl, hw) => [[-hl, -hw], [hl, -hw], [hl, hw], [-hl, hw], [-hl, -hw]].map(([a, b]) => [(x0 + (u + a) * co - (v + b) * si) / MX, (y0 + (u + a) * si + (v + b) * co) / MY]);
    // a pitched roof as two flat halves, one painted lit and one shaded: plain colours and one more polygon, no steps
    const halves = (x0, y0, co, si, hl, hw, h, rise, props) => [1, -1].map(side => {
      const lit = (-si * side) * sx + (co * side) * sy > 0, q = [[-hl, 0], [hl, 0], [hl, side * hw], [-hl, side * hw], [-hl, 0]].map(([a, b]) => [(x0 + a * co - b * si) / MX, (y0 + a * si + b * co) / MY]);
      return { type: 'Feature', properties: Object.assign({ b: h, t: h + rise, s: lit ? ((isDark() ? lk.litN : 0) || lk.lit || 1.1) : ((isDark() ? lk.shadeN : 0) || lk.shade || .75) }, props), geometry: { type: 'Polygon', coordinates: [q] } };
    });
    d.b.forEach(([ring, h, rt, ci, cx, cy, L, W, th, est, tone, rtone, lit], idx) => {
      const kk = tone || 1, rr = rtone || kk, gg = lit || 0, wi = Math.min(7, Math.floor(hit01(cx, cy) * 8));
      const poly = []; for (let i = 0; i < ring.length; i += 2) poly.push([ring[i], ring[i + 1]]); poly.push(poly[0]);
      const m = spec.get(idx), co = Math.cos(th), si = Math.sin(th), x0 = cx * MX, y0 = cy * MY;
      if (m) {
        lmWalls.push({ type: 'Feature', properties: { h, w: m.w, k: kk, g: gg }, geometry: { type: 'Polygon', coordinates: [poly] } });
        const pitched = m.type === 'gable' && L * W > 60 && L * W < 2500;
        if (!pitched) {
          roofs.push({ type: 'Feature', properties: { b: h - .02, t: h + .25, rk: m.rk, k: rr }, geometry: { type: 'Polygon', coordinates: [poly] } });
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
        } else if (lk.mode === 'halves') {
          halves(x0, y0, co, si, (L + .6) / 2, (W + .8) / 2, h, Math.max(.8, Math.min(2.4, W * .2)) * .6, { rk: m.rk, k: kk }).forEach(f => roofs.push(f));
        } else if (lk.mode === 'flat') {
          roofs.push({ type: 'Feature', properties: { b: h - .02, t: h + .25, rk: m.rk, k: rr }, geometry: { type: 'Polygon', coordinates: [poly] } });
        } else {
          const R = Math.max(.8, Math.min(2.4, W * .2)), step = R / 3;
          for (let k = 0; k < 3; k++) {
            const hl = (L + .6) / 2, hw = (W + .8) / 2 * (1 - k * .36);
            roofs.push({ type: 'Feature', properties: { b: h + k * step, t: h + (k + 1) * step, rk: m.rk, k: rr }, geometry: { type: 'Polygon', coordinates: [box(x0, y0, co, si, 0, 0, hl, hw)] } });
          }
        }
        if (m.tower) {   // a bell tower at one end of the church, and a spire
          const u = L / 2 - 2.4, hh = h + 7.5;
          trim.push({ type: 'Feature', properties: { b: 0, t: hh, k: 'tw' }, geometry: { type: 'Polygon', coordinates: [box(x0, y0, co, si, u, 0, 1.7, 1.7)] } });
          [[hh, hh + 1.6, 1.3], [hh + 1.6, hh + 3.2, .8], [hh + 3.2, hh + 4.6, .35]].forEach(([b, t, r]) => trim.push({ type: 'Feature', properties: { b, t, k: 'sp' }, geometry: { type: 'Polygon', coordinates: [box(x0, y0, co, si, u, 0, r, r)] } }));
        }
        return;
      }
      walls.push({ type: 'Feature', properties: { h, k: kk, g: gg, wi }, geometry: { type: 'Polygon', coordinates: [poly] } });
      if (!rt) { roofs.push({ type: 'Feature', properties: { b: h - .02, t: h + .25, c: -1, k: rr }, geometry: { type: 'Polygon', coordinates: [poly] } }); return; }
      if (lk.mode === 'halves') { halves(x0, y0, co, si, (L + .6) / 2, (W + .8) / 2, h, Math.max(.7, Math.min(2.4, W * .2)) * .6, { c: ci, k: rr }).forEach(f => roofs.push(f)); return; }
      if (lk.mode === 'flat') { roofs.push({ type: 'Feature', properties: { b: h - .02, t: h + .25, c: ci, k: rr }, geometry: { type: 'Polygon', coordinates: [poly] } }); return; }
      const R = Math.max(.7, Math.min(2.4, W * .2)), step = R / 3;
      for (let k = 0; k < 3; k++) {
        const hl = (L + .6) / 2 * (rt === 2 ? 1 - k * .3 : 1), hw = (W + .8) / 2 * (1 - k * .36);
        roofs.push({ type: 'Feature', properties: { b: h + k * step, t: h + (k + 1) * step, c: ci, k: rr }, geometry: { type: 'Polygon', coordinates: [box(x0, y0, co, si, 0, 0, hl, hw)] } });
      }
    });
    const fc = f => ({ type: 'FeatureCollection', features: f });
    return [fc(walls), fc(roofs), fc(lmWalls), fc(trim)];
  }

  let ready = null, on = false, TREES = [], FOG = null, FACES = null, BLD = null, LMS = [], BAKE = null;
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
  // Places, as Apple draws them: a small round badge in the colour of what the place is, its name beside it in the same colour.
  // They give way to each other (and to the landmarks) by importance, so only what fits on the screen is shown.
  const POI_CAT = {
    food: ['#FF9A3D', 'utensils', ['restaurant', 'fast_food', 'food_court', 'bar', 'bakery', 'ice_cream']],
    cafe: ['#FF9A3D', 'coffee', ['cafe']],
    shop: ['#4F8CFF', 'bag', ['shop', 'grocery', 'supermarket', 'clothing_store', 'convenience', 'department_store', 'mall', 'jewelry']],
    health: ['#F0524F', 'health', ['hospital', 'doctors', 'pharmacy', 'dentist', 'clinic', 'veterinary']],
    school: ['#9B6BFF', 'school', ['school', 'college', 'kindergarten', 'library', 'university']],
    lodging: ['#D56FE0', 'bed', ['lodging', 'hotel']],
    fuel: ['#2CC3D6', 'fuel', ['fuel']],
    bank: ['#34B36B', 'service', ['bank', 'atm']],
    worship: ['#22B8CF', 'church', ['place_of_worship']],
    safety: ['#F0524F', 'responder', ['police', 'fire_station']],
    park: ['#6BC25B', 'tree', ['park', 'playground', 'sports_centre']],
    other: ['#8E97AB', 'pin', []],
  };
  const poiBadge = (cat, dark) => {
    const [col, ic] = POI_CAT[cat], g = window.SD_ICONS[ic] || '';
    return '<svg xmlns="http://www.w3.org/2000/svg" width="56" height="56" viewBox="0 0 56 56"><circle cx="28" cy="30" r="22" fill="rgba(0,0,0,.28)"/><circle cx="28" cy="28" r="22" fill="' + col + '" stroke="' + (dark ? '#14172A' : '#FFFFFF') + '" stroke-width="3"/>' +
      '<g transform="translate(15 15) scale(1.08)" fill="none" stroke="#FFFFFF" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' + g + '</g></svg>';
  };
  const poiImage = () => ['concat', 'cdp-', ['match', ['get', 'class']].concat(...Object.keys(POI_CAT).filter(k => POI_CAT[k][2].length).map(k => [POI_CAT[k][2], k]), ['other']), isDark() ? '-n' : '-d'];
  const poiColour = () => ['match', ['get', 'class']].concat(...Object.keys(POI_CAT).filter(k => POI_CAT[k][2].length).map(k => [POI_CAT[k][2], POI_CAT[k][0]]), [POI_CAT.other[0]]);
  async function addPoiImages() {
    const load = (name, svg) => new Promise(res => { const im = new Image(); im.onload = () => { if (!map.hasImage(name)) map.addImage(name, im, { pixelRatio: 2 }); res(); }; im.onerror = res; im.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg); });
    await Promise.all(Object.keys(POI_CAT).flatMap(k => [load('cdp-' + k + '-n', poiBadge(k, true)), load('cdp-' + k + '-d', poiBadge(k, false))]));
  }

  async function init() {
    if (ready) return ready;
    return (ready = (async () => {
      await mapReady;
      if (typeof build3d === 'function') build3d();
      const bake = await fetch('assets/map/shadows.json').then(r => r.json()).catch(() => null);
      const faces = bake && bake.faces ? await fetch('assets/map/' + bake.faces).then(r => r.json()).catch(() => null) : null;
      const [detail, bld, lmj] = await Promise.all(['city-detail', 'buildings'].map(f => fetch('assets/map/' + f + '.json').then(r => r.json()).catch(() => null)).concat(fetch('assets/map/landmarks.geojson').then(r => r.json()).catch(() => null)));
      const lms = lmj ? lmj.features.map(f => ({ n: (f.properties && f.properties.name) || '', c: f.geometry.coordinates })).filter(x => x.n) : [];
      if (WINDOWS) addWalls();
      await addPoiImages();
      // The style draws the roads after the buildings; the City view draws the ground (roads, shadows, crossings) first and the
      // standing things over it, so the plain 3D layer moves up to just under the labels and everything of ours goes round it.
      { const first = (map.getStyle().layers.find(l => l.type === 'symbol') || {}).id; if (map.getLayer('building-3d') && first) map.moveLayer('building-3d', first); }
      const p = pal(), lyrs = map.getStyle().layers, i3 = lyrs.findIndex(l => l.id === 'building-3d'), above = i3 >= 0 && lyrs[i3 + 1] ? lyrs[i3 + 1].id : undefined;
      const firstLabel = (lyrs.find(l => l.type === 'symbol') || {}).id, hide = { visibility: 'none' }, src = map.getSource('openmaptiles');
      // the buildings: walls with windows by height, then their roofs (the map tiles' plain 3D buildings stay hidden underneath)
      if (bld && bld.b) {
        BLD = bld; LMS = lms; BAKE = bake;
        FACES = faces;
        if (window.sdGlow) window.sdGlow.init(map, { bld, faces, lamps: detail && detail.lamps }, firstLabel);
        const [walls, roofs, lmw, trim] = bldShapes(bld, lms, look());
        if (faces) { map.addSource('cd-faces', { type: 'geojson', data: facePlates(bld, faces) }); map.addLayer({ id: 'cd-face', type: 'fill-extrusion', source: 'cd-faces', minzoom: 16.2, layout: hide, paint: { 'fill-extrusion-color': faceColour(p), 'fill-extrusion-height': ['get', 't'], 'fill-extrusion-base': ['get', 'b'], 'fill-extrusion-opacity': 1 } }, 'building-3d'); }
        map.addSource('cd-bld', { type: 'geojson', data: walls }); map.addSource('cd-roofs', { type: 'geojson', data: roofs }); map.addSource('cd-lm', { type: 'geojson', data: lmw }); map.addSource('cd-trim', { type: 'geojson', data: trim });
        const wall = (id, k, flt) => map.addLayer({ id, type: 'fill-extrusion', source: 'cd-bld', minzoom: 15, filter: flt, layout: hide,
          paint: { 'fill-extrusion-pattern': wallName(k), 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': 0, 'fill-extrusion-opacity': 1 } }, 'building-3d');
        if (WINDOWS) { wall('cd-w-lo', 'lo', ['<', ['get', 'h'], 9]); wall('cd-w-mid', 'mid', ['all', ['>=', ['get', 'h'], 9], ['<', ['get', 'h'], 30]]); wall('cd-w-hi', 'hi', ['>=', ['get', 'h'], 30]); }
        else map.addLayer({ id: 'cd-wall', type: 'fill-extrusion', source: 'cd-bld', minzoom: 15, layout: hide, paint: { 'fill-extrusion-color': wallPlain(p), 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': 0, 'fill-extrusion-opacity': 1 } }, 'building-3d');
        map.addLayer({ id: 'cd-lm-wall', type: 'fill-extrusion', source: 'cd-lm', minzoom: 15, layout: hide,
          paint: { 'fill-extrusion-color': wallKey(p), 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': 0, 'fill-extrusion-opacity': 1 } }, 'building-3d');
        map.addLayer({ id: 'cd-lm-trim', type: 'fill-extrusion', source: 'cd-trim', minzoom: 15.6, layout: hide,
          paint: { 'fill-extrusion-color': trimColour(p), 'fill-extrusion-height': ['get', 't'], 'fill-extrusion-base': ['get', 'b'], 'fill-extrusion-opacity': 1 } }, 'building-3d');
        map.addLayer({ id: 'cd-roof', type: 'fill-extrusion', source: 'cd-roofs', minzoom: 16, layout: hide,
          paint: { 'fill-extrusion-color': roofColour(p), 'fill-extrusion-height': ['get', 't'], 'fill-extrusion-base': ['get', 'b'], 'fill-extrusion-opacity': 1 } }, 'building-3d');
      }
      // the ground, drawn under the first of our standing layers: the baked shadows, crossings, lane lines, the golf course and pitches
      const ground = map.getLayer('cd-wall') ? 'cd-wall' : map.getLayer('cd-w-lo') ? 'cd-w-lo' : 'building-3d';
      // the baked shadows: one picture laid over the ground, under the buildings (a building hides the part that falls on it)
      if (bake && bake.bounds) {
        const [bw, bs, be, bn] = bake.bounds;
        map.addSource('cd-bake', { type: 'image', url: 'assets/map/shadows.png', coordinates: [[bw, bn], [be, bn], [be, bs], [bw, bs]] });
        map.addLayer({ id: 'cd-bake', type: 'raster', source: 'cd-bake', minzoom: 15, layout: hide, paint: { 'raster-opacity': p.bake, 'raster-fade-duration': 0, 'raster-resampling': 'linear' } }, ground);
      }
      // the light, baked: a pool under every lamp and a spill from lit windows (night), a warm bounce beside sunlit walls (day)
      if (bake && bake.bounds && bake.glow) {
        const [bw, bs, be, bn] = bake.bounds, co = [[bw, bn], [be, bn], [be, bs], [bw, bs]];
        map.addSource('cd-glow', { type: 'image', url: 'assets/map/' + (bake.glowRt || bake.glow), coordinates: co });
        map.addLayer({ id: 'cd-glow', type: 'raster', source: 'cd-glow', minzoom: 15, layout: hide, paint: { 'raster-opacity': 1, 'raster-fade-duration': 0, 'raster-resampling': 'linear' } }, ground);
        map.addSource('cd-bounce', { type: 'image', url: 'assets/map/' + bake.bounce, coordinates: co });
        map.addLayer({ id: 'cd-bounce', type: 'raster', source: 'cd-bounce', minzoom: 15, layout: hide, paint: { 'raster-opacity': .8, 'raster-fade-duration': 0, 'raster-resampling': 'linear' } }, ground);
      }
      if (detail && detail.lamps) {   // the lamps themselves: small bright points, at night, close up
        map.addSource('cd-lamps', { type: 'geojson', data: { type: 'FeatureCollection', features: detail.lamps.map(l => ({ type: 'Feature', properties: { w: l[3] }, geometry: { type: 'Point', coordinates: [l[0], l[1]] } })) } });
        map.addLayer({ id: 'cd-lamp', type: 'circle', source: 'cd-lamps', minzoom: 17, layout: hide,
          paint: { 'circle-color': ['case', ['==', ['get', 'w'], 1], '#E6EEFF', '#FFD08A'], 'circle-radius': ['interpolate', ['linear'], ['zoom'], 17, 1.1, 19, 3], 'circle-blur': .6, 'circle-opacity': .95, 'circle-pitch-alignment': 'viewport' } }, above);
      }
      // the fog of war: outside the boundary the ground fades into haze (day) or dark (night); a flat dim covers what is beyond the picture
      if (bake && bake.fog) {
        const [fw, fs, fe, fn] = bake.fog.bounds, co = [[fw, fn], [fe, fn], [fe, fs], [fw, fs]], WORLD = [[-179.9, -85], [179.9, -85], [179.9, 85], [-179.9, 85], [-179.9, -85]];
        map.addSource('cd-fog-n', { type: 'image', url: 'assets/map/' + bake.fog.night, coordinates: co });
        map.addSource('cd-fog-d', { type: 'image', url: 'assets/map/' + bake.fog.day, coordinates: co });
        map.addSource('cd-fog-far', { type: 'geojson', data: { type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [WORLD, [[fw, fn], [fe, fn], [fe, fs], [fw, fs], [fw, fn]]] } } });
        ['n', 'd'].forEach(k => map.addLayer({ id: 'cd-fog-' + k, type: 'raster', source: 'cd-fog-' + k, layout: hide, paint: { 'raster-opacity': 1, 'raster-fade-duration': 0, 'raster-resampling': 'linear' } }, ground));
        map.addLayer({ id: 'cd-fog-far', type: 'fill', source: 'cd-fog-far', layout: hide, paint: { 'fill-color': '#0E1226', 'fill-opacity': .93 } }, ground);
        FOG = bake.fog;
      }
      // the day's ground, ray traced (docs/map-data/bake_ultra.py): bounced colour and soft contact shadow; the night keeps the lighter picture above
      if (bake && bake.bounds && bake.ultra) {
        const [bw, bs, be, bn] = bake.bounds;
        map.addSource('cd-bake-u', { type: 'image', url: 'assets/map/' + bake.ultra, coordinates: [[bw, bn], [be, bn], [be, bs], [bw, bs]] });
        map.addLayer({ id: 'cd-bake-u', type: 'raster', source: 'cd-bake-u', minzoom: 15, layout: hide, paint: { 'raster-opacity': 1, 'raster-fade-duration': 0, 'raster-resampling': 'linear' } }, ground);
      }
      // on the road: zebra crossings and the dashed lane lines
      if (detail && detail.crossings) {
        map.addSource('cd-cross', { type: 'geojson', data: detail.crossings });
        map.addLayer({ id: 'cd-cross', type: 'fill', source: 'cd-cross', minzoom: 16, layout: hide, paint: { 'fill-color': p.cross[0], 'fill-opacity': p.cross[1] } }, ground);
      }
      if (detail && detail.areas) {   // the golf course as it is mapped, and the pitches, playgrounds and pools, drawn flat
        map.addSource('cd-areas', { type: 'geojson', data: detail.areas });
        map.addLayer({ id: 'cd-area', type: 'fill', source: 'cd-areas', minzoom: 15.4, layout: hide, paint: { 'fill-color': areaColour(p) } }, ground);
        map.addLayer({ id: 'cd-area-line', type: 'line', source: 'cd-areas', minzoom: 16.4, layout: hide, filter: ['any', ['==', ['slice', ['get', 'k'], 0, 5], 'pitch'], ['==', ['get', 'k'], 'track']],
          paint: { 'line-color': p.areaLine[0], 'line-opacity': p.areaLine[1], 'line-width': ['interpolate', ['linear'], ['zoom'], 16.4, .6, 19, 1.6] } }, ground);
      }
      if (src) map.addLayer({ id: 'cd-lane', type: 'line', source: 'openmaptiles', 'source-layer': 'transportation', minzoom: 16.4, layout: Object.assign({ 'line-cap': 'butt' }, hide),
        filter: ['in', ['get', 'class'], ['literal', ['motorway', 'trunk', 'primary', 'secondary', 'tertiary']]],
        paint: { 'line-color': p.lane[0], 'line-opacity': p.lane[1], 'line-width': ['interpolate', ['linear'], ['zoom'], 16.4, .7, 19, 1.6], 'line-dasharray': [3, 4] } }, ground);
      // over the buildings: trees, places
      if (detail && detail.trees) {
        TREES = detail.trees; const [lo, hi, tr, sh] = treeShapes(TREES);
        map.addSource('cd-canopy', { type: 'geojson', data: lo }); map.addSource('cd-canopy2', { type: 'geojson', data: hi }); map.addSource('cd-trunk', { type: 'geojson', data: tr }); map.addSource('cd-tsh', { type: 'geojson', data: sh });
        if (!bake) map.addLayer({ id: 'cd-tshadow', type: 'fill', source: 'cd-tsh', minzoom: 16, layout: hide, paint: { 'fill-color': p.tshadow[0], 'fill-opacity': p.tshadow[1] } }, ground);   // the bake has them; this is the fallback
        const fade = ['interpolate', ['linear'], ['zoom'], 15.6, 0, 16.4, .97];
        map.addLayer({ id: 'cd-trunk', type: 'fill-extrusion', source: 'cd-trunk', minzoom: 16, layout: hide, paint: { 'fill-extrusion-color': trunkColour(p), 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': 0, 'fill-extrusion-opacity': 1 } }, above);
        map.addLayer({ id: 'cd-canopy', type: 'fill-extrusion', source: 'cd-canopy', minzoom: 15.6, layout: hide, paint: { 'fill-extrusion-color': canopyColour(p, 'canopy'), 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': ['get', 'b'], 'fill-extrusion-opacity': fade } }, above);
        map.addLayer({ id: 'cd-canopy2', type: 'fill-extrusion', source: 'cd-canopy2', minzoom: 15.6, layout: hide, paint: { 'fill-extrusion-color': canopyColour(p, 'canopy2'), 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': ['get', 'b'], 'fill-extrusion-opacity': fade } }, above);
      }
      if (src) {   // places: a badge and a name, the more important winning a crowded spot; names come in as you zoom
        map.addLayer({ id: 'cd-poi', type: 'symbol', source: 'openmaptiles', 'source-layer': 'poi', minzoom: 16.2,
          layout: { visibility: 'none', 'icon-image': poiImage(), 'icon-size': ['interpolate', ['linear'], ['zoom'], 16.2, .5, 18, .72], 'icon-padding': 3, 'icon-pitch-alignment': 'viewport', 'icon-allow-overlap': false,
                    'symbol-sort-key': ['get', 'rank'], 'text-field': ['coalesce', ['get', 'name:latin'], ['get', 'name']], 'text-font': ['Noto Sans Bold'], 'text-size': ['interpolate', ['linear'], ['zoom'], 17, 10.5, 18, 11.5],
                    'text-anchor': 'left', 'text-offset': [1.15, 0], 'text-max-width': 7, 'text-optional': true, 'text-pitch-alignment': 'viewport', 'text-padding': 3 },
          paint: { 'text-color': poiColour(), 'text-halo-color': p.haloText, 'text-halo-width': 1.5, 'text-opacity': ['interpolate', ['linear'], ['zoom'], 16.9, 0, 17.3, 1] } }, above);
      }
    })());
  }
  const LAYERS = ['cd-face', 'cd-bake', 'cd-bake-u', 'cd-glow', 'cd-bounce', 'cd-lamp', 'cd-wall', 'cd-w-lo', 'cd-w-mid', 'cd-w-hi', 'cd-lm-wall', 'cd-lm-trim', 'cd-roof', 'cd-cross', 'cd-lane', 'cd-area', 'cd-area-line', 'cd-tshadow', 'cd-trunk', 'cd-canopy', 'cd-canopy2', 'cd-poi'];
  const has = id => !!map.getLayer(id), set = (id, k, v) => { if (has(id)) map.setPaintProperty(id, k, v); };
  function paint() {
    const p = pal();
    CLASSES.forEach(k => set('cd-w-' + k, 'fill-extrusion-pattern', wallName(k)));
    set('cd-face', 'fill-extrusion-color', faceColour(p)); set('cd-wall', 'fill-extrusion-color', wallPlain(p)); set('cd-roof', 'fill-extrusion-color', roofColour(p)); set('cd-lm-wall', 'fill-extrusion-color', wallKey(p)); set('cd-lm-trim', 'fill-extrusion-color', trimColour(p));
    set('cd-cross', 'fill-color', p.cross[0]); set('cd-cross', 'fill-opacity', p.cross[1]);
    set('cd-lane', 'line-color', p.lane[0]); set('cd-lane', 'line-opacity', p.lane[1]);
    set('cd-canopy', 'fill-extrusion-color', canopyColour(p, 'canopy')); set('cd-canopy2', 'fill-extrusion-color', canopyColour(p, 'canopy2')); set('cd-trunk', 'fill-extrusion-color', trunkColour(p));
    set('cd-bake', 'raster-opacity', p.bake); set('cd-area', 'fill-color', areaColour(p)); set('cd-area-line', 'line-color', p.areaLine[0]); set('cd-area-line', 'line-opacity', p.areaLine[1]); set('cd-tshadow', 'fill-color', p.tshadow[0]); set('cd-tshadow', 'fill-opacity', p.tshadow[1]);
    if (has('cd-poi')) { map.setLayoutProperty('cd-poi', 'icon-image', poiImage()); map.setPaintProperty('cd-poi', 'text-halo-color', p.haloText); }
    try { map.setLight(p.light); map.setSky(p.sky); } catch (e) { /* an older map */ }
  }
  // ---- how much detail: Auto draws the window walls and drops to plain walls if the map is running slowly on this
  // computer (Light also drops the pitched roofs); Full and Light (Settings, Appearance) fix it either way ----
  const WALLS = ['cd-w-lo', 'cd-w-mid', 'cd-w-hi'];
  const quality = () => { try { return localStorage.getItem('ss-city') || 'auto'; } catch (e) { return 'auto'; } };
  let slow = false;
  const plainWalls = p => ['step', H, p.wall.lo[0], 9, p.wall.mid[0], 30, p.wall.hi[0]];
  function detail() {
    const q = quality(), full = on && (q === 'full' || (q === 'auto' && !slow)), plain = has('cd-wall') || has('cd-w-lo');
    // walls and the landmark walls always; roofs, models' trim and (behind the switch) window textures only at Full
    ['cd-wall', 'cd-lm-wall'].forEach(id => { if (has(id)) map.setLayoutProperty(id, 'visibility', on ? 'visible' : 'none'); });
    WALLS.forEach(id => { if (has(id)) map.setLayoutProperty(id, 'visibility', full ? 'visible' : 'none'); });
    if (window.sdGlow) window.sdGlow.show(full && isDark());   // the emissive light is the costliest part: Light and a slow screen leave it out
    ['cd-roof', 'cd-lm-trim', 'cd-face'].forEach(id => { if (has(id)) map.setLayoutProperty(id, 'visibility', full ? 'visible' : 'none'); });   // Light: plain boxes, no roofs, no model trim
    if (has('building-3d')) {   // the map tiles' own 3D buildings are only a fallback, when the buildings file did not load
      map.setLayoutProperty('building-3d', 'visibility', on && !plain ? 'visible' : 'none');
      if (on && !plain) map.setPaintProperty('building-3d', 'fill-extrusion-color', plainWalls(pal()));
    }
  }
  // the fog of war follows the Dim outside switch in Layers; the flat map's own dim hands over to it while the map is tilted
  // the night's light only at night, the day's bounce only by day
  function lightUpdate() {
    const night = isDark();
    ['cd-glow', 'cd-lamp'].forEach(id => { if (has(id)) map.setLayoutProperty(id, 'visibility', on && night ? 'visible' : 'none'); });
    if (has('cd-bounce')) map.setLayoutProperty('cd-bounce', 'visibility', on && !night && !has('cd-bake-u') ? 'visible' : 'none');   // the ray-traced day ground has its own bounce
    if (has('cd-bake-u')) { map.setLayoutProperty('cd-bake-u', 'visibility', on && !night ? 'visible' : 'none'); if (has('cd-bake')) map.setLayoutProperty('cd-bake', 'visibility', on && night ? 'visible' : 'none'); }
    else if (has('cd-bake')) map.setLayoutProperty('cd-bake', 'visibility', on ? 'visible' : 'none');
  }
  function fogUpdate() {
    const dim = document.getElementById('f-fog') ? document.getElementById('f-fog').checked : true, night = isDark();
    if (has('cd-fog-n')) map.setLayoutProperty('cd-fog-n', 'visibility', on && dim && night ? 'visible' : 'none');
    if (has('cd-fog-d')) map.setLayoutProperty('cd-fog-d', 'visibility', on && dim && !night ? 'visible' : 'none');
    if (has('cd-fog-far') && FOG) { map.setLayoutProperty('cd-fog-far', 'visibility', on && dim ? 'visible' : 'none'); map.setPaintProperty('cd-fog-far', 'fill-color', night ? '#0E1226' : '#EEF2F8'); map.setPaintProperty('cd-fog-far', 'fill-opacity', night ? FOG.alpha.night : FOG.alpha.day); }
    if (has('fog')) map.setLayoutProperty('fog', 'visibility', !on && dim ? 'visible' : 'none');
  }
  // nothing outside the boundary: places, lane lines and landmark badges are cut to it
  let clipped = false;
  function clip() {
    if (clipped || typeof rings === 'undefined' || !rings.length) return;
    const within = ['within', { type: 'MultiPolygon', coordinates: rings.map(r => [r]) }];
    if (has('cd-poi')) map.setFilter('cd-poi', within);
    if (has('cd-lane')) map.setFilter('cd-lane', ['all', ['in', ['get', 'class'], ['literal', ['motorway', 'trunk', 'primary', 'secondary', 'tertiary']]], within]);
    if (has('lm-badge')) map.setFilter('lm-badge', within);
    clipped = has('cd-poi') && has('cd-lane') && has('lm-badge');
  }
  // watch the frame rate while the map moves; when a quarter of the last ninety frames took over 28 ms, this screen cannot take the windows
  { let last = 0; const win = [];
    map.on('render', () => { if (!on || slow || quality() !== 'auto' || !map.isMoving()) { last = 0; win.length = 0; return; }
      const now = performance.now(), dt = last ? now - last : 0; last = now; if (!dt || dt > 400) return;
      win.push(dt > 28 ? 1 : 0); if (win.length > 90) win.shift();
      if (win.length === 90 && win.reduce((a, b) => a + b, 0) > 22) { slow = true; detail(); } }); }
  map.on('idle', () => { if (on && !clipped) clip(); });
  // swap the lighting and shading for another look (and the roofs, which are built differently in each)
  const EXTR = ['cd-wall', 'cd-roof', 'cd-lm-wall', 'cd-lm-trim'];
  function applyLook() {
    if (!ready || !BLD) return;
    const [walls, roofs, lmw, trim] = bldShapes(BLD, LMS, look());
    ['cd-bld', 'cd-roofs', 'cd-lm', 'cd-trim'].forEach((id, i) => { const src = map.getSource(id); if (src) src.setData([walls, roofs, lmw, trim][i]); });
    EXTR.forEach(id => set(id, 'fill-extrusion-vertical-gradient', look().vg !== false));
    if (BAKE && BAKE.bounds && map.getSource('cd-bake')) { const [bw, bs, be, bn] = BAKE.bounds; map.getSource('cd-bake').updateImage({ url: 'assets/map/' + (look().img || 'shadows.png'), coordinates: [[bw, bn], [be, bn], [be, bs], [bw, bs]] }); }
    paint(); if (on) detail();
  }
  window.sdCityLook = name => { if (!LOOKS[name]) return false; LOOK = name; try { localStorage.setItem('ss-look', name); } catch (e) { /* this visit only */ } applyLook(); return true; };
  window.sdCityLooks = () => Object.keys(LOOKS);
  async function show(want) {
    on = want; await init(); if (want !== on) return;
    LAYERS.forEach(id => { if (has(id) && WALLS.indexOf(id) < 0 && ['cd-wall', 'cd-roof', 'cd-lm-wall', 'cd-lm-trim', 'cd-face', 'cd-glow', 'cd-bounce', 'cd-lamp', 'cd-bake', 'cd-bake-u'].indexOf(id) < 0) map.setLayoutProperty(id, 'visibility', want ? 'visible' : 'none'); });
    detail(); fogUpdate(); lightUpdate(); clip();
    if (want) paint(); else { try { map.setSky({}); map.setLight({ anchor: 'viewport', color: '#ffffff', intensity: .5, position: [1.15, 210, 30] }); } catch (e) { /* nothing to undo */ } }
  }
  map.on('pitch', () => { const up = map.getPitch() > 8; if (up !== on) show(up); });
  window.addEventListener('themechange', () => { if (on) { applyLook(); fogUpdate(); lightUpdate(); } });
  { const f = document.getElementById('f-fog'); if (f) f.addEventListener('change', () => { if (ready) fogUpdate(); }); }
  window.addEventListener('storage', e => { if (e.key === 'ss-city') { slow = false; if (on) detail(); } });
})();
