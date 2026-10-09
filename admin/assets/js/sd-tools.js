// Spatial Distribution tools (Bellinist, 9 Oct 2026). Ideas taken from Google Maps and Apple Maps that need nothing
// new behind them: search, "What's here?", distance from the hall, open in Maps, a time slider, saved views,
// a compass that appears when the map is tilted, and, on a tablet, a case card that is a bottom sheet.
// Loaded after the page's own script, so it shares map, all, visible(), draw(), showDetail() and the rest.
(function () {
  'use strict';
  const sec = document.getElementById('s-spatial'), dock = sec.querySelector('.p-map-dock');
  if (!sec || !dock || typeof map === 'undefined') return;
  const HALL = { lng: 121.012596, lat: 14.525104 };   // Barangay 183 Hall, as in assets/map/landmarks.geojson
  const ic = n => sdIcon(n).replace('<svg ', '<svg width="18" height="18" ');
  const fmtM = m => m < 1000 ? Math.max(10, Math.round(m / 10) * 10) + ' m' : (m / 1000).toFixed(1) + ' km';
  const walkMin = m => Math.max(1, Math.round(m / 80));
  const gUrl = (lat, lng) => 'https://www.google.com/maps/search/?api=1&query=' + (+lat).toFixed(6) + ',' + (+lng).toFixed(6);
  const aUrl = (lat, lng, q) => 'https://maps.apple.com/?ll=' + (+lat).toFixed(6) + ',' + (+lng).toFixed(6) + '&q=' + encodeURIComponent(q || 'Pinned location');
  const coord = (lat, lng) => (+lat).toFixed(5) + ', ' + (+lng).toFixed(5);
  const reduced = () => window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  const mkBtn = (id, icon, title) => {
    const b = document.createElement('button'); b.className = 'p-dock-btn'; b.id = id; b.type = 'button';
    b.title = title; b.setAttribute('aria-label', title); b.innerHTML = ic(icon); return b;
  };
  const mkPop = (id, cls) => { const d = document.createElement('div'); d.id = id; d.className = 'ss-pop ' + cls; d.hidden = true; sec.appendChild(d); return d; };
  const place = (panel, btn) => {
    panel.hidden = false;
    const s = sec.getBoundingClientRect(), b = btn.getBoundingClientRect(), h = panel.offsetHeight;
    panel.style.top = Math.max(84, Math.min(s.height - h - 16, b.top - s.top + b.height / 2 - h / 2)) + 'px';
  };
  const copyText = (text, btn) => {
    const done = () => { if (!btn) return; btn.classList.add('ok'); setTimeout(() => btn.classList.remove('ok'), 1400); };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, done); else done();
  };

  // ---- a compass, only while the map is turned or tilted; the scale bar sits beside the Layers tile ----
  const tiltSync = () => sec.classList.toggle('ss-rot', Math.abs(map.getBearing()) > .5 || map.getPitch() > .5);
  map.on('rotate', tiltSync); map.on('pitch', tiltSync); map.on('moveend', tiltSync);

  // ---- pulse: a ring on a spot the map has flown to ----
  let pulseMk = null;
  function pulse(lng, lat, name) {
    if (pulseMk) pulseMk.remove();
    const el = document.createElement('div'); el.className = 'sx-pulse';
    el.innerHTML = '<i></i><i></i>' + (name ? '<b>' + esc(name) + '</b>' : '');
    pulseMk = new maplibregl.Marker({ element: el, anchor: 'center' }).setLngLat([lng, lat]).addTo(map);
    setTimeout(() => { if (pulseMk && pulseMk.getElement() === el) { pulseMk.remove(); pulseMk = null; } }, 6000);
  }
  const flyTo = (lng, lat, z) => map.flyTo({ center: [lng, lat], zoom: Math.max(z || 17, Math.min(map.getZoom(), 18)), duration: reduced() ? 0 : 900, essential: true });

  // ---- the panels share the right side, so opening one closes the rest ----
  const closers = {};
  if (typeof mapDrawer === 'function') {
    const base = mapDrawer;
    window.mapDrawer = function (which) { base(which); Object.keys(closers).forEach(k => { if (k !== which) closers[k](); }); };
  }
  const open = (which, btn, panel) => { window.mapDrawer(which); place(panel, btn); btn.setAttribute('aria-expanded', 'true'); };
  const shut = (btn, panel) => { panel.hidden = true; btn.setAttribute('aria-expanded', 'false'); };

  // ================= search =================
  const sBtn = mkBtn('search-btn', 'search', T('Search the map (/)', 'Maghanap sa mapa (/)'));
  sBtn.setAttribute('aria-expanded', 'false'); sBtn.setAttribute('aria-controls', 'ss-search');
  dock.insertBefore(sBtn, dock.firstChild);
  const sPanel = mkPop('ss-search', 'ss-search');
  sPanel.setAttribute('role', 'dialog'); sPanel.setAttribute('aria-label', T('Search the map', 'Maghanap sa mapa'));
  sPanel.innerHTML = '<label class="sx-in">' + ic('search') + '<input type="search" id="sx-q" placeholder="' + esc(T('A case, a place or a street', 'Kaso, lugar o kalye')) + '" autocomplete="off" spellcheck="false" aria-controls="sx-res"><kbd>/</kbd></label><div class="sx-res" id="sx-res" role="listbox"></div>';
  const sq = sPanel.querySelector('#sx-q'), sRes = sPanel.querySelector('#sx-res');
  let LM = null, sItems = [], sCur = 0;
  const landmarks = () => LM || (LM = fetch('assets/map/landmarks.geojson').then(r => r.json())
    .then(d => d.features.map(f => ({ n: (f.properties && f.properties.name) || '', g: (f.properties && f.properties.group) || '', c: f.geometry && f.geometry.coordinates })).filter(x => x.n && x.c)).catch(() => []));
  function streetsMatching(q) {
    if (!map.getSource('openmaptiles')) return [];
    const seen = new Map();
    try {
      map.querySourceFeatures('openmaptiles', { sourceLayer: 'transportation_name' }).forEach(f => {
        const n = f.properties && (f.properties['name:latin'] || f.properties.name);
        if (!n || seen.has(n) || !n.toLowerCase().includes(q)) return;
        const g = f.geometry, pts = g.type === 'LineString' ? g.coordinates : g.type === 'MultiLineString' ? g.coordinates[0] : null;
        if (pts && pts.length) seen.set(n, pts[Math.floor(pts.length / 2)]);
      });
    } catch (e) { /* tiles not in yet */ }
    return [...seen].map(([n, c]) => ({ n, c }));
  }
  const rank = (s, q) => s.toLowerCase().startsWith(q) ? 0 : 1;
  async function sFind(raw) {
    const q = raw.trim().toLowerCase(), out = [];
    const rows = q ? all.filter(r => [r.tracking_id, r.subject, r.location_label, label(r.category)].some(v => v && String(v).toLowerCase().includes(q)))
                         .sort((a, b) => rank(a.tracking_id || '', q) - rank(b.tracking_id || '', q)) : all.slice(0, 4);
    if (rows.length) out.push({ h: q ? T('Cases', 'Mga kaso') : T('Latest cases', 'Pinakabagong kaso') });
    rows.slice(0, 5).forEach(r => out.push({ k: 'case', col: catColour(r.category), glyph: (PIN_GLYPH[r.category] || PIN_GLYPH.other).replace(/__C__/g, '#fff'),
      t: r.subject || label(r.category), s: (r.tracking_id || '') + (r.location_label ? ' · ' + r.location_label : ''), go: () => { closeSearch(); showDetail(r); } }));
    if (q) {
      const lm = (await landmarks()).filter(x => x.n.toLowerCase().includes(q)).sort((a, b) => rank(a.n, q) - rank(b.n, q)).slice(0, 5);
      if (lm.length) out.push({ h: T('Places', 'Mga lugar') });
      lm.forEach(x => out.push({ k: 'place', col: '#2F6BFF', icon: 'pin', t: x.n, s: x.g ? x.g.replace(/_/g, ' ') : T('Place', 'Lugar'), go: () => { closeSearch(); flyTo(x.c[0], x.c[1], 17.5); pulse(x.c[0], x.c[1], x.n); } }));
      const st = streetsMatching(q).sort((a, b) => rank(a.n, q) - rank(b.n, q)).slice(0, 4);
      if (st.length) out.push({ h: T('Streets', 'Mga kalye') });
      st.forEach(x => out.push({ k: 'street', col: '#8A8F9C', icon: 'directions', t: x.n, s: T('Street', 'Kalye'), go: () => { closeSearch(); flyTo(x.c[0], x.c[1], 17); pulse(x.c[0], x.c[1], x.n); } }));
    }
    return out;
  }
  let sSeq = 0;
  async function sRender() {
    const my = ++sSeq, items = await sFind(sq.value); if (my !== sSeq) return;
    sItems = items.filter(i => !i.h); sCur = 0; let n = 0;
    sRes.innerHTML = items.length ? items.map(i => i.h ? '<div class="sx-h">' + esc(i.h) + '</div>' :
      '<button type="button" class="sx-r' + (n === 0 ? ' cur' : '') + '" role="option" data-i="' + (n++) + '" style="--c:' + i.col + '"><span class="sx-i">' +
      (i.glyph ? '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + i.glyph + '</svg>' : sdIcon(i.icon)) +
      '</span><span class="sx-t"><b>' + esc(i.t) + '</b><small>' + esc(i.s) + '</small></span></button>').join('')
      : '<p class="sx-none">' + esc(T('Nothing matches. Try a tracking ID, a landmark or a street name.', 'Walang tugma. Subukan ang tracking ID, landmark o pangalan ng kalye.')) + '</p>';
    if (sPanel.hidden === false) place(sPanel, sBtn);
  }
  const sMark = () => sRes.querySelectorAll('.sx-r').forEach((b, i) => { b.classList.toggle('cur', i === sCur); if (i === sCur) b.scrollIntoView({ block: 'nearest' }); });
  function openSearch() { open('search', sBtn, sPanel); sq.select(); sRender(); setTimeout(() => sq.focus(), 30); }
  function closeSearch() { shut(sBtn, sPanel); }
  closers.search = closeSearch;
  sBtn.addEventListener('click', e => { e.stopPropagation(); sPanel.hidden ? openSearch() : closeSearch(); });
  sq.addEventListener('input', sRender);
  sq.addEventListener('keydown', e => {
    if (e.key === 'ArrowDown') { e.preventDefault(); sCur = Math.min(sItems.length - 1, sCur + 1); sMark(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); sCur = Math.max(0, sCur - 1); sMark(); }
    else if (e.key === 'Enter' && sItems[sCur]) { e.preventDefault(); sItems[sCur].go(); }
  });
  sRes.addEventListener('click', e => { const b = e.target.closest('.sx-r'); if (b && sItems[+b.dataset.i]) sItems[+b.dataset.i].go(); });
  document.addEventListener('keydown', e => {
    if (e.key === '/' && !/^(INPUT|TEXTAREA|SELECT)$/.test((document.activeElement || {}).tagName || '') && !e.ctrlKey && !e.metaKey) { e.preventDefault(); openSearch(); }
    if (e.key === 'Escape') { if (!sPanel.hidden) closeSearch(); hereClose(); }
  });

  // ================= What's here? =================
  const hCard = mkPop('ss-here', 'ss-here');
  let hereMk = null, hereAt = 0;
  function hereClose() { hCard.hidden = true; if (hereMk) { hereMk.remove(); hereMk = null; } }
  closers.here = hereClose;
  function nearestStreet(lng, lat) {
    if (!map.getSource('openmaptiles')) return null;
    let best = null, bd = 70;
    const X = lo => (lo - lng) * 107500, Y = la => (la - lat) * 110600;
    try {
      map.querySourceFeatures('openmaptiles', { sourceLayer: 'transportation_name' }).forEach(f => {
        const n = f.properties && (f.properties['name:latin'] || f.properties.name); if (!n) return;
        const g = f.geometry, lines = g.type === 'LineString' ? [g.coordinates] : g.type === 'MultiLineString' ? g.coordinates : [];
        lines.forEach(L => { for (let i = 0; i < L.length - 1; i++) {
          const ax = X(L[i][0]), ay = Y(L[i][1]), bx = X(L[i + 1][0]), by = Y(L[i + 1][1]), dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
          const t = l2 ? Math.max(0, Math.min(1, -(ax * dx + ay * dy) / l2)) : 0, d = Math.hypot(ax + t * dx, ay + t * dy);
          if (d < bd) { bd = d; best = n; } } });
      });
    } catch (e) { /* tiles not in yet */ }
    return best;
  }
  function hereOpen(ll, pt) {
    if (Date.now() - hereAt < 700) return; hereAt = Date.now();
    closeSearch(); window.mapDrawer && window.mapDrawer('here');
    const lng = ll.lng, lat = ll.lat, street = nearestStreet(lng, lat), here = { lng, lat };
    const dHall = lkMetres(here, HALL), cases = all.filter(q => lkMetres(here, { lng: +q.longitude, lat: +q.latitude }) < 100).length;
    if (hereMk) hereMk.remove();
    const mk = document.createElement('div'); mk.className = 'sh-pin'; mk.innerHTML = '<i></i><i></i><b></b>';
    hereMk = new maplibregl.Marker({ element: mk, anchor: 'center' }).setLngLat([lng, lat]).addTo(map);
    const name = street ? T('Near ', 'Malapit sa ') + street : T('Dropped pin', 'Naka-pin na lugar');
    const canLook = typeof MLY !== 'undefined' && MLY && window.mapillary && typeof lkOpen === 'function';
    hCard.innerHTML =
      '<button type="button" class="sh-x" aria-label="' + esc(T('Close', 'Isara')) + '">&times;</button>' +
      '<p class="sh-eye">' + esc(T('What’s here?', 'Ano ang narito?')) + '</p><h4>' + esc(name) + '</h4>' +
      '<button type="button" class="sh-co" data-copy="' + esc(coord(lat, lng)) + '" title="' + esc(T('Copy the coordinates', 'Kopyahin ang coordinates')) + '"><span>' + esc(coord(lat, lng)) + '</span>' + ic('copy') + '<em>' + esc(T('Copied', 'Nakopya')) + '</em></button>' +
      '<ul class="sh-rows"><li>' + sdIcon('ruler') + '<span>' + esc(fmtM(dHall)) + T(' from Barangay 183 Hall', ' mula sa Barangay 183 Hall') + '<small>' + esc(T('About ' + walkMin(dHall) + ' min on foot · straight line', 'Mga ' + walkMin(dHall) + ' min lakad · tuwid na linya')) + '</small></span></li>' +
      '<li>' + sdIcon('radar') + '<span>' + cases + T(cases === 1 ? ' case within 100 m' : ' cases within 100 m', ' kaso sa loob ng 100 m') + '<small>' + esc(T('Counting every complaint, any status', 'Kasama ang lahat ng sumbong, anumang katayuan')) + '</small></span></li></ul>' +
      '<div class="sh-acts' + (canLook ? ' four' : '') + '"><button type="button" data-do="zoom">' + sdIcon('zoom') + '<b>' + esc(T('Zoom here', 'Lapitan')) + '</b></button>' +
      (canLook ? '<button type="button" data-do="look">' + sdIcon('view360') + '<b>' + esc(T('Look around', 'Luminga')) + '</b></button>' : '') +
      '<a href="' + gUrl(lat, lng) + '" target="_blank" rel="noopener">' + sdIcon('external') + '<b>Google Maps</b></a>' +
      '<a href="' + aUrl(lat, lng, street || '') + '" target="_blank" rel="noopener">' + sdIcon('external') + '<b>Apple Maps</b></a></div>';
    hCard.hidden = false;
    const cb = map.getContainer().getBoundingClientRect(), sb = sec.getBoundingClientRect(), w = hCard.offsetWidth, h = hCard.offsetHeight;
    const x = pt.x + cb.left - sb.left, y = pt.y + cb.top - sb.top;
    hCard.style.left = Math.max(12, Math.min(sb.width - w - 76, x + 22 + w > sb.width - 76 ? x - w - 22 : x + 22)) + 'px';
    hCard.style.top = Math.max(84, Math.min(sb.height - h - 16, y - 40)) + 'px';
    hCard.querySelector('.sh-x').addEventListener('click', hereClose);
    hCard.querySelector('.sh-co').addEventListener('click', e => copyText(e.currentTarget.dataset.copy, e.currentTarget));
    hCard.querySelector('[data-do=zoom]').addEventListener('click', () => { hCard.hidden = true; map.easeTo({ center: [lng, lat], zoom: 18, duration: reduced() ? 0 : 800 }); });
    const lb = hCard.querySelector('[data-do=look]');
    if (lb) lb.addEventListener('click', () => { hCard.hidden = true; lkOpen({ id: null, tracking_id: '', category: 'other', subject: name, location_label: street || '', longitude: lng, latitude: lat }); });
  }
  closers.sheet = () => {};
  map.on('contextmenu', e => { if (e.originalEvent) e.originalEvent.preventDefault(); hereOpen(e.lngLat, e.point); });
  // a long press on a touch screen
  { let timer = 0, from = null;
    const stop = () => { clearTimeout(timer); timer = 0; };
    map.on('touchstart', e => { stop(); if (e.points && e.points.length > 1) return; from = e.point; timer = setTimeout(() => { timer = 0; hereOpen(e.lngLat, e.point); }, 600); });
    map.on('touchmove', e => { if (timer && from && e.point.dist(from) > 9) stop(); });
    ['touchend', 'touchcancel', 'dragstart', 'zoomstart'].forEach(ev => map.on(ev, stop)); }
  map.on('click', e => { if (!hCard.hidden && Date.now() - hereAt > 1000) hereClose(); });

  // ================= distance from the hall + open in Maps, on the case card =================
  window.sdCaseRows = function (r) {
    const lng = +r.longitude, lat = +r.latitude; if (!isFinite(lng) || !isFinite(lat)) return '';
    const d = lkMetres({ lng, lat }, HALL), q = r.location_label || r.subject || r.tracking_id || '';
    return '<li>' + csIcon(SD_ICONS.ruler) + '<span>' + esc(fmtM(d)) + T(' from Barangay 183 Hall', ' mula sa Barangay 183 Hall') + '<small>' + esc(T('About ' + walkMin(d) + ' min on foot · straight line', 'Mga ' + walkMin(d) + ' min lakad · tuwid na linya')) + '</small></span></li>' +
      '<li class="cs-maps"><a href="' + gUrl(lat, lng) + '" target="_blank" rel="noopener">' + sdIcon('external') + '<b>Google Maps</b></a><a href="' + aUrl(lat, lng, q) + '" target="_blank" rel="noopener">' + sdIcon('external') + '<b>Apple Maps</b></a></li>';
  };

  // ================= the time slider =================
  const DAY = 864e5, TZ = 8 * 36e5;
  const dayOf = t => Math.floor((t + TZ) / DAY) * DAY - TZ;
  const loc = T('en-PH', 'fil-PH');
  const dLabel = ms => new Date(ms).toLocaleDateString(loc, { day: 'numeric', month: 'short', timeZone: 'Asia/Manila' });
  const TL = { on: false, win: 'week', idx: 0, start: 0, n: 0, playing: 0 };
  window.sdTime = { pass(t) {
    if (!TL.on || !TL.n) return true;
    const end = TL.start + (TL.idx + 1) * DAY, from = TL.win === 'day' ? end - DAY : TL.win === 'week' ? end - 7 * DAY : TL.start;
    return t >= from && t < end;
  } };
  const tBtn = mkBtn('tl-btn', 'clock', T('Time slider', 'Time slider')); tBtn.setAttribute('aria-pressed', 'false');
  dock.insertBefore(tBtn, document.getElementById('legend-toggle'));
  const tBar = mkPop('ss-tl', 'ss-tl');
  tBar.setAttribute('role', 'group'); tBar.setAttribute('aria-label', T('Time slider', 'Time slider'));
  tBar.innerHTML = '<button type="button" class="tl-play" aria-label="' + esc(T('Play', 'I-play')) + '"><span class="i-play">' + sdIcon('play') + '</span><span class="i-pause">' + sdIcon('pause') + '</span></button>' +
    '<div class="tl-mid"><div class="tl-bars" id="tl-bars"></div><input type="range" id="tl-rng" min="0" max="1" step="1" value="0" aria-label="' + esc(T('Day', 'Araw')) + '"><div class="tl-lbl"><b id="tl-day"></b><span id="tl-n"></span></div></div>' +
    '<div class="tl-seg" role="group"><button type="button" data-w="day">' + esc(T('Day', 'Araw')) + '</button><button type="button" data-w="week">' + esc(T('Week', 'Linggo')) + '</button><button type="button" data-w="all">' + esc(T('To date', 'Hanggang ngayon')) + '</button></div>' +
    '<button type="button" class="tl-x" aria-label="' + esc(T('Close the time slider', 'Isara ang time slider')) + '">&times;</button>';
  const rng = tBar.querySelector('#tl-rng'), bars = tBar.querySelector('#tl-bars');
  let tlBusy = false, tlAgain = false;
  async function tlDraw() { if (tlBusy) { tlAgain = true; return; } tlBusy = true; try { await draw(); } finally { tlBusy = false; if (tlAgain) { tlAgain = false; tlDraw(); } } }
  function tlBounds() {
    const rows = visible(true), ts = rows.map(r => new Date(r.created_at).getTime()).filter(isFinite);
    if (!ts.length) { TL.start = dayOf(Date.now()); TL.n = 0; return; }
    TL.start = dayOf(Math.min(...ts)); TL.n = Math.min(400, Math.round((dayOf(Math.max(...ts)) - TL.start) / DAY) + 1);
    const per = new Array(TL.n).fill(0); ts.forEach(t => { const i = Math.round((dayOf(t) - TL.start) / DAY); if (per[i] !== undefined) per[i]++; });
    const mx = Math.max(1, ...per);
    bars.innerHTML = '<svg viewBox="0 0 ' + TL.n + ' 20" preserveAspectRatio="none" aria-hidden="true">' + per.map((c, i) => c ? '<rect x="' + (i + .12) + '" y="' + (20 - Math.max(2, 20 * c / mx)) + '" width=".76" height="' + Math.max(2, 20 * c / mx) + '" rx=".2"/>' : '').join('') + '</svg>';
  }
  function tlLabel() {
    const end = TL.start + (TL.idx + 1) * DAY - 1, from = TL.win === 'day' ? TL.start + TL.idx * DAY : TL.win === 'week' ? end + 1 - 7 * DAY : TL.start;
    const left = Math.max(from, TL.start);
    document.getElementById('tl-day').textContent = TL.win === 'day' ? dLabel(left) : dLabel(left) + ' – ' + dLabel(end);
    const n = visible().length; document.getElementById('tl-n').textContent = n + T(n === 1 ? ' complaint' : ' complaints', ' sumbong');
    rng.style.setProperty('--p', (TL.n > 1 ? TL.idx / (TL.n - 1) * 100 : 100) + '%');
    tBar.querySelectorAll('.tl-seg button').forEach(b => b.classList.toggle('on', b.dataset.w === TL.win));
  }
  function tlStop() { if (TL.playing) { clearInterval(TL.playing); TL.playing = 0; } tBar.classList.remove('playing'); tBar.querySelector('.tl-play').setAttribute('aria-label', T('Play', 'I-play')); }
  function tlSet(i, redraw) { TL.idx = Math.max(0, Math.min(TL.n - 1, i)); rng.value = TL.idx; if (redraw !== false) tlDraw().then(tlLabel); tlLabel(); }
  function tlPlay() {
    if (TL.n < 2) return; if (TL.idx >= TL.n - 1) tlSet(0);
    tBar.classList.add('playing'); tBar.querySelector('.tl-play').setAttribute('aria-label', T('Pause', 'I-pause'));
    TL.playing = setInterval(() => { if (TL.idx >= TL.n - 1) { tlStop(); return; } tlSet(TL.idx + 1); }, reduced() ? 800 : TL.win === 'day' ? 420 : 300);
  }
  function tlOpen() {
    TL.on = true; tlBounds(); rng.max = Math.max(0, TL.n - 1); tBar.hidden = false; sec.classList.add('tl-open');
    tBtn.classList.add('on'); tBtn.setAttribute('aria-pressed', 'true'); rng.disabled = TL.n < 2; tBar.classList.toggle('flat', TL.n < 2);
    tlSet(TL.n - 1);
  }
  function tlClose() { tlStop(); TL.on = false; tBar.hidden = true; sec.classList.remove('tl-open'); tBtn.classList.remove('on'); tBtn.setAttribute('aria-pressed', 'false'); tlDraw(); }
  tBtn.addEventListener('click', () => TL.on ? tlClose() : tlOpen());
  tBar.querySelector('.tl-x').addEventListener('click', tlClose);
  tBar.querySelector('.tl-play').addEventListener('click', () => TL.playing ? tlStop() : tlPlay());
  rng.addEventListener('input', () => { tlStop(); tlSet(+rng.value); });
  tBar.querySelector('.tl-seg').addEventListener('click', e => { const b = e.target.closest('button'); if (!b) return; TL.win = b.dataset.w; tlDraw().then(tlLabel); tlLabel(); });
  // a new Apply changes which days there are
  document.getElementById('f-apply').addEventListener('click', () => { if (TL.on) setTimeout(() => { tlStop(); tlBounds(); rng.max = Math.max(0, TL.n - 1); rng.disabled = TL.n < 2; tBar.classList.toggle('flat', TL.n < 2); tlSet(Math.min(TL.idx, Math.max(0, TL.n - 1))); }, 60); });
  document.addEventListener('keydown', e => { if (TL.on && e.key === ' ' && document.activeElement === rng) { e.preventDefault(); TL.playing ? tlStop() : tlPlay(); } });

  // ================= saved views =================
  const KEY = 'ss-sd-views';
  const vRead = () => { try { return JSON.parse(localStorage.getItem(KEY) || '[]').filter(v => v && v.name); } catch (e) { return []; } };
  const vWrite = a => { try { localStorage.setItem(KEY, JSON.stringify(a.slice(0, 12))); return true; } catch (e) { return false; } };
  const vBtn = mkBtn('views-btn', 'bookmark', T('Saved views', 'Mga naka-save na view'));
  vBtn.setAttribute('aria-expanded', 'false'); vBtn.setAttribute('aria-controls', 'ss-views');
  dock.insertBefore(vBtn, document.getElementById('legend-toggle'));
  const vPanel = mkPop('ss-views', 'ss-views');
  vPanel.setAttribute('role', 'dialog'); vPanel.setAttribute('aria-label', T('Saved views', 'Mga naka-save na view'));
  const ID = { heat: 'f-heat', flood: 'f-flood', fog: 'f-fog', hot: 'f-hotspots' };
  const chk = id => { const c = document.getElementById(id); return !!(c && c.checked); };
  function capture(name) {
    const f = readFilters(), c = map.getCenter();
    const v = { name, cat: f.cat, st: f.st, allTime: f.allTime, period: f.period, from: f.from, to: f.to, tilt: !!tilted,
      cam: { c: [+c.lng.toFixed(6), +c.lat.toFixed(6)], z: +map.getZoom().toFixed(2) }, on: {}, layers: {} };
    Object.keys(ID).forEach(k => { v.on[k] = chk(ID[k]); });
    Object.keys(LAYER).forEach(k => { v.layers[k] = !!LAYER[k]; });
    return v;
  }
  function summary(v) {
    const bits = [];
    bits.push(v.cat ? label(v.cat) : T('All types', 'Lahat ng uri')); if (v.st) bits.push(label(v.st));
    bits.push(v.allTime ? T('All time', 'Lahat ng panahon') : (v.from && v.to ? v.from + ' → ' + v.to : v.period));
    const ons = []; if (v.on.heat) ons.push(T('Heatmap', 'Heatmap')); if (v.on.flood) ons.push(T('Flood zones', 'Bahaing lugar'));
    if (v.layers.transit) ons.push(T('Transit', 'Transit')); if (v.layers.aq) ons.push(T('Air quality', 'Kalidad ng hangin')); if (v.layers.safe) ons.push(T('Safe points', 'Ligtas na lugar')); if (v.tilt) ons.push(T('Tilted', 'Naka-tilt'));
    return bits.concat(ons).join(' · ');
  }
  const setVal = (id, val) => { const el = document.getElementById(id); if (!el) return; el.value = val; el.dispatchEvent(new Event('change', { bubbles: true })); };
  const setChk = (id, on) => { const el = document.getElementById(id); if (el && el.checked !== !!on) el.click(); };
  function apply(v) {
    tlStop(); if (TL.on) tlClose();
    setVal('f-category', v.cat || ''); setVal('f-status', v.st || '');
    setChk('f-period-all', v.allTime);
    if (!v.allTime) { setVal('f-period', v.period || ''); setVal('f-from', v.from || ''); setVal('f-to', v.to || ''); }
    document.getElementById('f-apply').click();
    Object.keys(ID).forEach(k => setChk(ID[k], v.on[k]));
    Object.keys(LAYER).forEach(k => setChk('lyr-' + k, v.layers[k]));
    if (!!v.tilt !== !!tilted) setTilt(!!v.tilt);
    map.easeTo({ center: v.cam.c, zoom: v.cam.z, pitch: v.tilt ? 52 : 0, bearing: v.tilt ? -14 : 0, duration: reduced() ? 0 : 1100 });
    vClose();
  }
  function vRender() {
    const list = vRead();
    vPanel.innerHTML = '<h4>' + esc(T('Saved views', 'Mga naka-save na view')) + '</h4>' +
      (list.length ? '<ul class="sv-list">' + list.map((v, i) => '<li><button type="button" class="sv-go" data-i="' + i + '"><span class="sv-i">' + sdIcon('bookmark') + '</span><span class="sv-t"><b>' + esc(v.name) + '</b><small>' + esc(summary(v)) + '</small></span></button><button type="button" class="sv-del" data-i="' + i + '" aria-label="' + esc(T('Delete ', 'Burahin ang ') + v.name) + '">' + sdIcon('trash') + '</button></li>').join('') + '</ul>'
        : '<p class="sv-none">' + esc(T('Nothing saved yet. Set the filters, layers and place you want, then save them as a view.', 'Wala pang naka-save. Ayusin ang mga filter, layer at lugar, saka i-save bilang view.')) + '</p>') +
      '<form class="sv-add" id="sv-add"><input type="text" id="sv-name" maxlength="40" placeholder="' + esc(T('Name this view', 'Pangalan ng view')) + '" autocomplete="off" aria-label="' + esc(T('Name this view', 'Pangalan ng view')) + '"><button type="submit" class="p-btn p-btn-primary p-btn-sm">' + esc(T('Save', 'I-save')) + '</button></form>' +
      '<small>' + esc(T('Kept in this browser. Filters, layers, tilt and where the map is looking.', 'Nasa browser na ito. Mga filter, layer, tilt at saan nakatingin ang mapa.')) + '</small>';
    if (!vPanel.hidden) place(vPanel, vBtn);
  }
  function vOpen() { vRender(); open('views', vBtn, vPanel); }
  function vClose() { shut(vBtn, vPanel); }
  closers.views = vClose;
  vBtn.addEventListener('click', e => { e.stopPropagation(); vPanel.hidden ? vOpen() : vClose(); });
  vPanel.addEventListener('click', e => {
    const go = e.target.closest('.sv-go'), del = e.target.closest('.sv-del'), list = vRead();
    if (go && list[+go.dataset.i]) apply(list[+go.dataset.i]);
    if (del) { list.splice(+del.dataset.i, 1); vWrite(list); vRender(); }
  });
  vPanel.addEventListener('submit', e => {
    e.preventDefault(); const inp = vPanel.querySelector('#sv-name'), name = inp.value.trim(); if (!name) { inp.focus(); return; }
    const list = vRead().filter(v => v.name.toLowerCase() !== name.toLowerCase()); list.unshift(capture(name)); vWrite(list); vRender();
  });
  document.addEventListener('click', e => {
    if (!sPanel.hidden && !e.target.closest('#ss-search, #search-btn')) closeSearch();
    if (!vPanel.hidden && !e.target.closest('#ss-views, #views-btn, .sdp-pop')) vClose();
  });

  // ================= the case card as a bottom sheet, on a tablet =================
  // Two stops: half the map, nearly all of it; pull it down to close.
  window.sdSheetDrag = function (el) {
    const hero = el.querySelector('.cs-hero'); if (!hero) return;
    const H = () => sec.getBoundingClientRect().height, stops = () => [Math.round(H() * .5), Math.round(H() * .9)];
    const set = px => el.style.setProperty('--sh', px + 'px');
    const pad = px => map.easeTo({ padding: { left: 0, top: 0, right: 0, bottom: px }, duration: 350 });
    set(stops()[0]);
    hero.addEventListener('pointerdown', e => {
      if (e.target.closest('button')) return;
      const y0 = e.clientY, h0 = el.getBoundingClientRect().height; let last = y0, dir = 0, moved = false;
      el.classList.add('cs-dragging'); hero.setPointerCapture(e.pointerId);
      const mv = ev => { const dy = y0 - ev.clientY; if (Math.abs(dy) > 5) moved = true; if (ev.clientY !== last) dir = ev.clientY < last ? 1 : -1; last = ev.clientY; set(Math.max(60, Math.min(H() * .94, h0 + dy))); };
      const up = () => {
        hero.removeEventListener('pointermove', mv); hero.removeEventListener('pointerup', up); hero.removeEventListener('pointercancel', up); el.classList.remove('cs-dragging');
        if (!moved) return;
        const h = el.getBoundingClientRect().height, [a, b] = stops();
        if (dir < 0 && h < a * .8) { closeCaseSheet(); return; }
        const to = dir > 0 ? (stops().find(s => s > h + 8) || b) : ([...stops()].reverse().find(s => s < h - 8) || a);
        set(to); pad(Math.min(to, a));
      };
      hero.addEventListener('pointermove', mv); hero.addEventListener('pointerup', up); hero.addEventListener('pointercancel', up);
    });
  };

  // ================= landmarks in 3D (free data only) =================
  // Tilt the map and the places an officer steers by stand up: the building that holds each landmark in
  // assets/map/landmarks.geojson (OpenStreetMap) is tinted by the kind of place, and a round badge floats over it,
  // as Apple Maps does. Heights are OpenStreetMap's own; nothing here is modelled by hand.
  const LM_COL = { hall: '#FF9D3C', school: '#9B6BFF', worship: '#22B8CF', safety: '#F0524F', health: '#34C46C', park: '#8BCB3A', shop: '#F063A8', transport: '#7C8AA5', military: '#B0A99F', government: '#4F7BFF', service: '#4F7BFF' };
  const LM_ICON = { hall: 'house', school: 'school', worship: 'church', safety: 'responder', health: 'health', park: 'tree', shop: 'bag', transport: 'plane', military: 'star', government: 'service', service: 'service' };
  const lmDark = () => document.documentElement.getAttribute('data-theme') === 'dark';
  const badgeSvg = (g, dark) => {
    const col = LM_COL[g] || '#7C8AA5', ic = (window.SD_ICONS[LM_ICON[g]] || '');
    return '<svg xmlns="http://www.w3.org/2000/svg" width="88" height="88" viewBox="0 0 88 88"><circle cx="44" cy="48" r="35" fill="rgba(0,0,0,.30)"/><circle cx="44" cy="44" r="35" fill="' + (dark ? '#17181D' : '#FFFFFF') + '" stroke="' + col + '" stroke-width="5"/>' +
      '<circle cx="44" cy="44" r="31.5" fill="none" stroke="' + (dark ? 'rgba(255,255,255,.16)' : 'rgba(0,0,0,.08)') + '" stroke-width="1"/>' +
      '<g transform="translate(24 24) scale(1.67)" fill="none" stroke="' + (dark ? '#FFFFFF' : col) + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + ic + '</g></svg>';
  };
  let lmReady = null, lmPts = [], lmOn = false;
  const lmBuild = {};   // landmark name -> its building features
  const inRing = (pt, ring) => { let c = false; for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) { const a = ring[i], b = ring[j]; if ((a[1] > pt[1]) !== (b[1] > pt[1]) && pt[0] < (b[0] - a[0]) * (pt[1] - a[1]) / (b[1] - a[1]) + a[0]) c = !c; } return c; };
  // The tiles merge thousands of buildings into one multipolygon, so work on the single polygon under the landmark, never the whole feature.
  const polysOf = g => g.type === 'Polygon' ? [g.coordinates] : g.type === 'MultiPolygon' ? g.coordinates : [];
  const hasPt = (pt, poly) => inRing(pt, poly[0]) && !poly.slice(1).some(h => inRing(pt, h));
  const edgeM = (pt, poly) => { let d = 1e9; poly[0].forEach(v => { d = Math.min(d, lkMetres({ lng: pt[0], lat: pt[1] }, { lng: v[0], lat: v[1] })); }); return d; };
  // Stand the footprint a little proud of the plain 3D building under it, so the tint is the one that is seen (no flicker).
  const proud = (poly, m) => {
    const ring = poly[0]; let w = 1e9, e = -1e9, s = 1e9, n = -1e9; ring.forEach(v => { w = Math.min(w, v[0]); e = Math.max(e, v[0]); s = Math.min(s, v[1]); n = Math.max(n, v[1]); });
    const cx = (w + e) / 2, cy = (s + n) / 2, hw = Math.max(1, (e - w) * 107500 / 2), hh = Math.max(1, (n - s) * 110600 / 2), fx = 1 + m / hw, fy = 1 + m / hh;
    return { type: 'Polygon', coordinates: [ring.map(v => [cx + (v[0] - cx) * fx, cy + (v[1] - cy) * fy])] };
  };
  function lmCollect() {
    if (!lmOn || !map.getSource('lm-bld') || !map.getSource('openmaptiles')) return;
    const todo = lmPts.filter(l => !lmBuild[l.n] && map.getBounds().contains(l.c));
    if (!todo.length) return;
    let feats; try { feats = map.querySourceFeatures('openmaptiles', { sourceLayer: 'building' }); } catch (e) { return; }
    if (!feats.length) return;
    let changed = false;
    todo.forEach(l => {
      let hit = null;
      for (const f of feats) { for (const poly of polysOf(f.geometry)) { if (hasPt(l.c, poly)) { hit = { poly, f }; break; } } if (hit) break; }
      if (!hit) {   // the point sits in a yard or a road: the nearest building within 28 m
        let bd = 28;
        feats.forEach(f => polysOf(f.geometry).forEach(poly => { const v = poly[0][0]; if (Math.abs(v[0] - l.c[0]) > .0012 || Math.abs(v[1] - l.c[1]) > .0012) return; const d = edgeM(l.c, poly); if (d < bd) { bd = d; hit = { poly, f }; } }));
      }
      if (!hit) return;
      lmBuild[l.n] = [{ type: 'Feature', properties: { g: l.g, h: Math.max(+hit.f.properties.render_height || 0, 11) + .6, b: +hit.f.properties.render_min_height || 0 }, geometry: proud(hit.poly, .7) }]; changed = true;
    });
    if (changed) map.getSource('lm-bld').setData({ type: 'FeatureCollection', features: [].concat(...Object.values(lmBuild)) });
  }
  const lmTint = dark => ['match', ['get', 'g']].concat(...Object.keys(LM_COL).map(k => [k, dark ? mixHex(LM_COL[k], '#17181D', .22) : LM_COL[k]]), ['#7C8AA5']);
  const mixHex = (a, b, t) => '#' + [1, 3, 5].map(i => Math.round(parseInt(a.substr(i, 2), 16) * (1 - t) + parseInt(b.substr(i, 2), 16) * t).toString(16).padStart(2, '0')).join('');
  async function lmInit() {
    if (lmReady) return lmReady;
    return (lmReady = (async () => {
      await mapReady; lmPts = await landmarks();
      if (typeof build3d === 'function') build3d();
      await Promise.all(Object.keys(LM_COL).flatMap(g => [addSvgImage('lm-' + g + '-d', badgeSvg(g, true)), addSvgImage('lm-' + g + '-l', badgeSvg(g, false))]));
      const lyrs = map.getStyle().layers, i = lyrs.findIndex(l => l.id === 'building-3d'), before = i >= 0 && lyrs[i + 1] ? lyrs[i + 1].id : undefined, dark = lmDark();
      map.addSource('lm-bld', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
      map.addLayer({ id: 'lm-bld', type: 'fill-extrusion', source: 'lm-bld', minzoom: 15, layout: { visibility: 'none' },
        paint: { 'fill-extrusion-color': lmTint(dark), 'fill-extrusion-height': ['get', 'h'], 'fill-extrusion-base': ['get', 'b'], 'fill-extrusion-opacity': .98 } }, before);
      map.addSource('lm-pts', { type: 'geojson', data: { type: 'FeatureCollection', features: lmPts.map(l => ({ type: 'Feature', properties: { name: l.n, group: LM_COL[l.g] ? l.g : 'service' }, geometry: { type: 'Point', coordinates: l.c } })) } });
      map.addLayer({ id: 'lm-badge', type: 'symbol', source: 'lm-pts', minzoom: 15.2,
        layout: { visibility: 'none', 'icon-image': ['concat', 'lm-', ['get', 'group'], dark ? '-d' : '-l'], 'icon-size': ['interpolate', ['linear'], ['zoom'], 15, .62, 18, .86], 'icon-anchor': 'center',
                  'icon-pitch-alignment': 'viewport', 'text-pitch-alignment': 'viewport', 'icon-allow-overlap': false, 'text-optional': true,
                  'text-field': ['get', 'name'], 'text-font': ['Noto Sans Bold'], 'text-size': 11.5, 'text-offset': [0, 2.35], 'text-anchor': 'top', 'text-max-width': 8 },
        paint: { 'icon-translate': [0, -16], 'text-translate': [0, -16], 'text-color': dark ? '#F4F5FA' : '#1B1C20', 'text-halo-color': dark ? 'rgba(17,18,22,.92)' : 'rgba(255,255,255,.95)', 'text-halo-width': 1.6 } }, typeof layerBefore === 'function' ? layerBefore() : undefined);
    })());
  }
  async function lmShow(on) {
    lmOn = on; await lmInit(); if (on !== lmOn) return;
    ['lm-bld', 'lm-badge'].forEach(id => { if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', on ? 'visible' : 'none'); });
    if (on) { lmCollect(); }
  }
  map.on('pitch', () => { const up = map.getPitch() > 8; if (up !== lmOn) lmShow(up); });
  map.on('moveend', lmCollect); map.on('idle', lmCollect);
  window.addEventListener('themechange', () => { if (!map.getLayer('lm-badge')) return; const dark = lmDark();
    map.setLayoutProperty('lm-badge', 'icon-image', ['concat', 'lm-', ['get', 'group'], dark ? '-d' : '-l']);
    map.setPaintProperty('lm-badge', 'text-color', dark ? '#F4F5FA' : '#1B1C20'); map.setPaintProperty('lm-badge', 'text-halo-color', dark ? 'rgba(17,18,22,.92)' : 'rgba(255,255,255,.95)');
    map.setPaintProperty('lm-bld', 'fill-extrusion-color', lmTint(dark)); });
})();
