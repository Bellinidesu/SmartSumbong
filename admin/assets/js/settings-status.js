/* Settings > System status and Plan and usage (16 Nov 2026, Ace's preview). Moved out of settings.php so it is a file (strict CSP, no inline handlers).
   System status: a health banner, the services as live rows (a new check every 45 seconds while the tab is open and visible) with a history bar of the last 36 checks made from this browser,
   and a drawer for every row and card (what it does, the reading, what a failure means, what the person may do). The checks are the same as before: the portal's server for Supabase, sign-in,
   photos and push alerts (settings.php?check=server), this browser for the rest.
   Plan and usage: the plans on one side, the usage against their limits on the other; hovering a plan focuses its rows, pressing it keeps them. */
(function () {
  'use strict';
  var cfgEl = document.getElementById('st-cfg'), cfg = {}; try { cfg = JSON.parse(cfgEl ? cfgEl.textContent : '{}'); } catch (e) { cfg = {}; }
  var T = window.T || function (en) { return en; };
  var $ = function (id) { return document.getElementById(id); }, $$ = function (s, r) { return [].slice.call((r || document).querySelectorAll(s)); };
  var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  var LOCALE = window.LANG === 'fil' ? 'fil-PH' : 'en-US', REDUCED = !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);

  // ---------- the services ----------
  var S = [
    { key: 'db', job: T('Database', 'Database'), prov: 'Supabase', side: 'L', url: 'https://status.supabase.com', what: T('Where every complaint, account and message is kept.', 'Kung saan nakatago ang bawat sumbong, account at mensahe.'),
      down: T('Complaints and accounts can’t be read or saved.', 'Hindi mabasa o maisave ang mga sumbong at account.') },
    { key: 'auth', job: T('Sign-in', 'Pag-sign in'), prov: 'Supabase Auth', side: 'L', url: 'https://status.supabase.com', what: T('Checks who is signing in.', 'Sinusuri kung sino ang nag-sign in.'),
      down: T('Nobody can sign in to the portal or the app.', 'Walang makapag-sign in sa portal o sa app.') },
    { key: 'live', job: T('Live updates', 'Live na update'), prov: 'Supabase Realtime', side: 'L', url: 'https://status.supabase.com', what: T('Makes new complaints and messages appear without refreshing the page.', 'Nagpapalitaw ng bagong sumbong at mensahe nang hindi nire-refresh ang pahina.'),
      down: T('New complaints won’t appear until the page is refreshed.', 'Hindi lalabas ang bagong sumbong hangga’t hindi nire-refresh.') },
    { key: 'media', job: T('Photos and videos', 'Larawan at video'), prov: 'Cloudinary', side: 'L', url: 'https://status.cloudinary.com', what: T('Stores and shows photos and proof.', 'Nag-iimbak at nagpapakita ng larawan at patunay.'),
      down: T('Residents’ photos and videos won’t upload or show.', 'Hindi maa-upload o makikita ang mga larawan at video.') },
    { key: 'push', job: T('Push alerts', 'Push alert'), prov: 'Firebase, via send-dispatch-push', side: 'L', url: 'https://status.firebase.google.com', what: T('Sends alerts to tanods’ and residents’ phones.', 'Nagpapadala ng alerto sa telepono ng mga tanod at residente.'),
      down: T('Push alerts to tanod phones are not going out. Call or text the tanod on duty.', 'Hindi naipapadala ang push alert sa mga tanod. Tawagan o i-text ang naka-duty.') },
    { key: 'tiles', job: T('Map tiles', 'Mapa'), prov: 'OpenFreeMap', side: 'R', browser: 1, url: 'https://openfreemap.org', what: T('Draws the map’s pictures.', 'Iginuguhit ang mga larawan ng mapa.'),
      down: T('The map shows no streets.', 'Walang kalye sa mapa.') },
    { key: 'geo', job: T('Address lookup', 'Paghahanap ng address'), prov: 'OpenStreetMap Nominatim', side: 'R', browser: 1, url: 'https://nominatim.org', what: T('Turns a typed address into a place on the map.', 'Ginagawang lugar sa mapa ang tinype na address.'),
      down: T('New pins won’t get a street address.', 'Walang address ang bagong pin.') },
    { key: 'rain', job: T('Rain data', 'Datos ng ulan'), prov: 'Open-Meteo · flood watch', side: 'R', browser: 1, url: 'https://open-meteo.com', what: T('Rain and flood readings for the flood watch and storm mode.', 'Sukat ng ulan at baha para sa bantay-baha at storm mode.'),
      down: T('Flood watch shows offline; flood zones stay manual.', 'Offline ang bantay-baha.') },
    { key: 'noah', job: T('Flood zones', 'Bahaing lugar'), prov: 'Project NOAH map, stored with the portal', side: 'R', local: 1, what: T('The flood map layers the portal draws itself.', 'Ang mga layer ng mapa ng baha na iginuguhit ng portal mismo.'),
      down: T('The flood zones can’t be drawn on the map.', 'Hindi maiguguhit ang mga bahaing lugar.') }
  ];
  var PLACES = cfg.places || {}, SB_URL = cfg.sbUrl || '', SB_KEY = cfg.sbKey || '';
  var R = {}, SLOW = 1500, busy = false, lastAt = 0, built = false;
  var BADGE = { ok: ['p-b-done', T('Working', 'Gumagana'), '#22c55e'], slow: ['p-b-pending', T('Slow', 'Mabagal'), '#f59e0b'], down: ['p-b-denied', T('Down', 'Hindi gumagana'), '#ef4444'], checking: ['p-b-grey', T('Checking…', 'Sinusuri…'), '#9AA1AB'] };
  var fmtMs = function (ms) { return ms == null ? '—' : ms >= 1000 ? (ms / 1000).toFixed(1) + ' s' : ms + ' ms'; };
  var svc = function (k) { return S.filter(function (s) { return s.key === k; })[0]; };
  var reading = function (s) { var r = R[s.key] || {}; return r.state === 'checking' || !r.state ? '…' : (s.local && r.state === 'ok' ? T('local', 'lokal') : fmtMs(r.ms)); };

  // ---------- history: the last 36 checks made from this browser, kept across visits ----------
  var HKEY = 'ss-st-hist-v1', HMAX = 36, H = {};
  try { H = JSON.parse(localStorage.getItem(HKEY) || '{}') || {}; } catch (e) { H = {}; }
  function pushH(key, state, ms) { var a = H[key] = H[key] || []; a.push([Date.now(), state === 'ok' ? 0 : state === 'slow' ? 1 : 2, ms]); if (a.length > HMAX) a.splice(0, a.length - HMAX); try { localStorage.setItem(HKEY, JSON.stringify(H)); } catch (e) { /* not kept */ } }
  function ago(t) { var m = Math.round((Date.now() - t) / 60000); return m < 1 ? T('just now', 'ngayon lang') : m < 60 ? m + T(' min ago', ' min ang nakalipas') : Math.round(m / 60) + T(' h ago', ' oras ang nakalipas'); }
  function bars(key, big, intro) {
    var a = H[key] || [], out = '', pad = HMAX - a.length, i;
    for (i = 0; i < pad; i++) out += '<i class="e" style="--i:' + i + '"></i>';
    a.forEach(function (c, j) { var k = pad + j, last = j === a.length - 1;
      out += '<i class="' + (c[1] === 1 ? 'w' : c[1] === 2 ? 'x' : '') + '" style="--i:' + k + '" data-tip="' + esc((last ? T('Latest check', 'Pinakabagong pagsusuri') : ago(c[0])) + ': ' + [T('answered fast', 'mabilis sumagot'), T('was slow', 'mabagal'), T('did not answer', 'hindi sumagot')][c[1]] + (c[2] != null ? ' (' + fmtMs(c[2]) + ')' : '')) + '"></i>'; });
    return '<span class="st-bars' + (big ? ' big' : '') + (intro ? ' intro' : '') + '" aria-hidden="true">' + out + '</span>';
  }

  // ---------- the checks (as before) ----------
  function timed(p) { var t0 = performance.now(); return p.then(function (ok) { return { ok: ok, ms: Math.round(performance.now() - t0) }; }, function () { return { ok: false, ms: null }; }); }
  function reach(url) { return timed(fetch(url, { cache: 'no-store', mode: 'cors' }).then(function (r) { return r.ok; })); }
  function realtime() {
    return timed(new Promise(function (res) {
      var done = false, ws = new WebSocket(SB_URL.replace(/^http/, 'ws') + '/realtime/v1/websocket?apikey=' + encodeURIComponent(SB_KEY) + '&vsn=1.0.0');
      var end = function (ok) { if (done) return; done = true; try { ws.close(); } catch (e) { /* closed */ } res(ok); };
      ws.onopen = function () { end(true); }; ws.onerror = function () { end(false); }; setTimeout(function () { end(false); }, 8000);
    }));
  }
  function set(key, r) { var st = !r.ok ? 'down' : (r.ms != null && r.ms > SLOW ? 'slow' : 'ok'); R[key] = { state: st, ms: r.ms }; pushH(key, st, r.ms); paintRow(key); paintHero(); if (mapOn) paintMap(); if (openKey === key) fillDrawerService(key, true); }
  function checkServer() { return fetch('settings.php?check=server', { cache: 'no-store' }).then(function (r) { return r.json(); }).catch(function () { return null; }); }
  function checkOne(key) {
    var s = svc(key); R[key] = { state: 'checking' }; paintRow(key);
    if (key === 'tiles') return reach('https://tiles.openfreemap.org/planet').then(function (r) { set('tiles', r); });
    if (key === 'geo') return reach('https://nominatim.openstreetmap.org/status?format=json').then(function (r) { set('geo', r); });
    if (key === 'rain') return reach('https://api.open-meteo.com/v1/forecast?latitude=14.5269&longitude=121.0155&current=precipitation').then(function (r) { set('rain', r); });
    if (key === 'noah') return reach('assets/map/hazards.geojson').then(function (r) { set('noah', r); });
    if (key === 'live') return realtime().then(function (r) { set('live', r); });
    return checkServer().then(function (sv) { set(key, sv && sv[key] ? sv[key] : { ok: false, ms: null }); }).then(function () { return s; });
  }
  function check() {
    if (busy) return Promise.resolve(); busy = true;
    S.forEach(function (s) { R[s.key] = { state: 'checking' }; paintRow(s.key); }); paintHero();
    reach('https://tiles.openfreemap.org/planet').then(function (r) { set('tiles', r); });
    reach('https://nominatim.openstreetmap.org/status?format=json').then(function (r) { set('geo', r); });
    reach('https://api.open-meteo.com/v1/forecast?latitude=14.5269&longitude=121.0155&current=precipitation').then(function (r) { set('rain', r); });
    reach('assets/map/hazards.geojson').then(function (r) { set('noah', r); });
    realtime().then(function (r) { set('live', r); });
    return checkServer().then(function (sv) {
      ['db', 'auth', 'push', 'media'].forEach(function (k) { set(k, sv && sv[k] ? sv[k] : { ok: false, ms: null }); });
      lastAt = Date.now(); busy = false; paintMap(); paintLive();
    });
  }

  // ---------- painting ----------
  function paintHero() {
    var el = $('st-banner'); if (!el) return;
    var st = function (k) { return (R[k] || {}).state || 'checking'; };
    var bad = S.filter(function (s) { return st(s.key) === 'down'; }), slow = S.filter(function (s) { return st(s.key) === 'slow'; }), checking = S.some(function (s) { return st(s.key) === 'checking'; });
    var tone = bad.length ? 'down' : slow.length ? 'slow' : checking ? 'checking' : 'ok';
    el.dataset.tone = tone;
    var head = tone === 'checking' ? T('Checking every connection…', 'Sinusuri ang bawat koneksyon…') : tone === 'ok' ? T('Everything is working', 'Gumagana ang lahat')
      : [bad.length ? bad.length + T(bad.length === 1 ? ' service down' : ' services down', ' hindi gumagana') : '', slow.length ? slow.length + T(' slow', ' mabagal') : ''].filter(Boolean).join(', ');
    var names = function (a) { return a.map(function (s) { return s.job; }).join(T(' and ', ' at ')); };
    var why = tone === 'ok' ? T('Complaints, sign-in, photos, push alerts, maps and flood data are all reachable.', 'Naaabot ang lahat ng serbisyo.') : tone === 'checking' ? '' :
      (bad.length ? bad.map(function (s) { return s.down; }).join(' ') + ' ' : '') + (slow.length ? T('Slow to answer: ', 'Mabagal sumagot: ') + names(slow) + '.' : '') + (S.length - bad.length - slow.length > 0 ? ' ' + T('Everything else is working.', 'Gumagana ang iba.') : '');
    var good = S.filter(function (s) { return st(s.key) === 'ok'; }).length;
    var mem = cfg.memNow != null ? cfg.memNow + ' MB' : '—';
    el.innerHTML = '<span class="st-hdot" aria-hidden="true"></span><span class="st-ht"><b>' + esc(head) + '</b><small>' + esc(why) + '</small></span>' +
      '<span class="st-hmini"><span><b>' + good + T(' of ', ' sa ') + S.length + '</b><small>' + esc(T('services answering well', 'serbisyong mabilis sumasagot')) + '</small></span>' +
      '<span><b>' + esc(cfg.up7 || '—') + '</b><small>' + esc(T('uptime, last 7 days', 'uptime, nakaraang 7 araw')) + '</small></span>' +
      '<span><b>' + esc(mem) + '</b><small>' + esc(cfg.memLimit ? T('of ', 'sa ') + cfg.memLimit + ' MB ' + T('memory', 'memorya') : T('memory', 'memorya')) + '</small></span>' +
      '<span><b>' + esc(cfg.smartLast || '—') + '</b><small>' + esc(T('SMART last ran', 'huling tumakbo ang SMART')) + '</small></span></span>';
  }
  function rowHtml(s) {
    var r = R[s.key] || {}, B = BADGE[r.state || 'checking'], pl = PLACES[s.key] || ['', ''];
    return '<span class="st-d" style="background:' + B[2] + '"></span><span class="st-rn"><b>' + esc(s.job) + '</b><small>' + esc(s.prov) + '</small></span><span class="st-where"><span class="st-cc">' + esc(pl[0]) + '</span>' + esc(pl[1]) + '</span>' +
      '<span data-bars>' + bars(s.key, false, !built) + '</span><span class="st-ms">' + esc(reading(s)) + '</span><span class="p-badge ' + B[0] + '">' + esc(B[1]) + '</span><span class="st-chev" aria-hidden="true"></span>';
  }
  function paintRow(key) {
    var box = $('st-rows'); if (!box) return; var s = svc(key), el = box.querySelector('[data-st-svc="' + key + '"]');
    if (!el) { el = document.createElement('button'); el.type = 'button'; el.className = 'st-row'; el.dataset.stSvc = key; box.appendChild(el); }
    var r = R[key] || {};
    el.setAttribute('data-tip', s.job + ': ' + (r.state === 'checking' ? T('checking', 'sinusuri') : s.local && r.state === 'ok' ? T('drawn by the portal itself', 'iginuguhit ng portal mismo') : T('answered in ', 'sumagot sa ') + fmtMs(r.ms)) + '. ' + T('Tap for details.', 'Pindutin para sa detalye.'));
    el.setAttribute('aria-label', s.job + ', ' + (BADGE[r.state || 'checking'][1]) + '. ' + T('Open details', 'Buksan ang detalye'));
    el.innerHTML = rowHtml(s);
  }
  var mapOn = false;
  function paintMap() {
    var host = $('st-map'); if (!host || !mapOn) return;
    var W = 900, Hh = 470, cx = 450, cy = 235, NW = 262, NH = 54, L = S.filter(function (s) { return s.side === 'L'; }), Rt = S.filter(function (s) { return s.side === 'R'; });
    var ys = function (arr, i) { return 14 + i * ((Hh - 28 - NH) / Math.max(1, arr.length - 1)); };
    var short = { db: 'Supabase', auth: 'Supabase', live: 'Supabase', media: 'Cloudinary', push: 'Firebase', tiles: 'OpenFreeMap', geo: 'Nominatim', rain: 'Open-Meteo', noah: 'Project NOAH' };
    var nodes = []; L.forEach(function (s, i) { nodes.push([s, 8, ys(L, i)]); }); Rt.forEach(function (s, i) { nodes.push([s, W - 8 - NW, ys(Rt, i)]); });
    var svg = '<svg viewBox="0 0 ' + W + ' ' + Hh + '" role="group" aria-label="' + esc(T('Diagram of the portal and the services it connects to. Each service opens its details.', 'Diagram ng portal at mga serbisyo. Bawat serbisyo ay nagbubukas ng detalye.')) + '">';
    var paths = '', dots = '', cards = '';
    nodes.forEach(function (n, k) {
      var s = n[0], x = n[1], y = n[2], r = R[s.key] || {}, B = BADGE[r.state || 'checking'], c = B[2], left = s.side === 'L';
      var x0 = left ? x + NW : x, x1 = left ? cx - 98 : cx + 98, y0 = y + NH / 2, y1 = cy + (y0 - cy) * .18, mx = (x0 + x1) / 2;
      var d = 'M' + x0 + ' ' + y0 + ' C ' + mx + ' ' + y0 + ' ' + mx + ' ' + y1 + ' ' + x1 + ' ' + y1;
      paths += '<path class="st-flowbg" stroke="' + c + '" d="' + d + '"/><path class="st-flow' + (r.state === 'down' ? ' st-bad' : '') + '" stroke="' + c + '" d="' + d + '" style="animation-delay:' + (-k * 0.23).toFixed(2) + 's"/>';
      if (!REDUCED && r.state !== 'down' && r.state !== 'checking') dots += '<circle r="4.2" fill="' + c + '"><animateMotion dur="' + (2.2 + (k % 4) * 0.35).toFixed(2) + 's" begin="-' + (k * 0.4).toFixed(1) + 's" repeatCount="indefinite" path="' + d + '"/></circle>';
      cards += '<g class="st-node" style="--sc:' + c + '" data-st-svc="' + s.key + '" tabindex="0" role="button" aria-label="' + esc(s.job + ', ' + B[1] + '. ' + T('Open details', 'Buksan ang detalye')) + '" data-tip="' + esc(s.job + ': ' + B[1] + (s.local && r.state === 'ok' ? '' : ' · ' + reading(s))) + '">' +
        '<rect class="st-nbg" x="' + x + '" y="' + y + '" width="' + NW + '" height="' + NH + '" rx="14"/><rect x="' + x + '" y="' + (y + 12) + '" width="5" height="' + (NH - 24) + '" rx="2.5" fill="' + c + '"/>' +
        '<circle class="' + (r.state === 'checking' ? 'st-pulse' : '') + '" cx="' + (x + 24) + '" cy="' + (y + NH / 2) + '" r="5.5" fill="' + c + '"/>' +
        '<text x="' + (x + 40) + '" y="' + (y + 23) + '" class="st-t">' + esc(s.job.length > 24 ? s.job.slice(0, 23) + '…' : s.job) + '</text><text x="' + (x + 40) + '" y="' + (y + 41) + '" class="st-s">' + esc(short[s.key]) + ' · ' + esc(reading(s)) + '</text>' +
        '<text x="' + (x + NW - 14) + '" y="' + (y + 23) + '" text-anchor="end" class="st-w" fill="' + c + '">' + esc(B[1]) + '</text></g>';
    });
    var good = S.filter(function (s) { return (R[s.key] || {}).state === 'ok'; }).length;
    svg += '<defs><linearGradient id="st-hubg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1B4FD1"/><stop offset="1" stop-color="#00308F"/></linearGradient></defs>' + paths +
      '<circle class="st-ring" cx="' + cx + '" cy="' + cy + '" r="64"/><circle class="st-ring b" cx="' + cx + '" cy="' + cy + '" r="64"/>' +
      '<rect x="' + (cx - 98) + '" y="' + (cy - 46) + '" width="196" height="92" rx="22" fill="url(#st-hubg)"/>' +
      '<text x="' + cx + '" y="' + (cy - 8) + '" text-anchor="middle" class="st-hub">SmartSumbong</text><text x="' + cx + '" y="' + (cy + 12) + '" text-anchor="middle" class="st-hub2">portal · Render</text>' +
      '<text x="' + cx + '" y="' + (cy + 32) + '" text-anchor="middle" class="st-hub2">' + good + T(' of ', ' sa ') + S.length + T(' working', ' gumagana') + '</text>' + dots + cards;
    host.innerHTML = svg + '</svg>';
  }
  function setView(v) {
    mapOn = v === 'map';
    $$('[data-st-view]').forEach(function (b) { var on = b.dataset.stView === v; b.classList.toggle('p-on', on); b.setAttribute('aria-pressed', String(on)); });
    var rows = $('st-rows'), wrap = $('st-mapwrap'); if (rows) rows.hidden = mapOn; if (wrap) wrap.hidden = !mapOn;
    try { localStorage.setItem('ss-st-view', v); } catch (e) { /* not kept */ }
    paintMap();
  }
  var agoN = 0;
  function paintLive() {
    var u = $('st-checked'); if (!u) return;
    agoN = lastAt ? Math.round((Date.now() - lastAt) / 1000) : 0;
    u.textContent = lastAt ? T('Live · checked ', 'Live · sinuri ') + (agoN < 2 ? T('just now', 'ngayon lang') : agoN + T(' s ago', ' s ang nakalipas')) : T('Checking…', 'Sinusuri…');
  }

  // ---------- the drawer ----------
  var drawer = $('st-drawer'), openKey = null, tipEl = null;
  function sec(h, inner) { return '<div class="st-drs"><div class="p-eyebrow">' + esc(h) + '</div>' + inner + '</div>'; }
  function copyBtn(text) { return '<button type="button" class="p-btn p-btn-ghost p-btn-sm" data-st-copy="' + esc(text) + '">' + esc(T('Copy a note', 'Kopyahin bilang tala')) + '</button>'; }
  function fillDrawerService(key, live) {
    var s = svc(key); if (!s || !drawer) return; var r = R[key] || {}, B = BADGE[r.state || 'checking'], pl = PLACES[key] || ['', ''];
    if (live && !$('st-dr-body').querySelector('[data-dr-ms]')) return;
    $('st-dr-t').textContent = s.job; $('st-dr-sub').textContent = s.prov + (pl[1] ? ' · ' + pl[1] : '');
    var say = r.state === 'checking' || !r.state ? T('Checking now…', 'Sinusuri ngayon…') : s.local ? T('This is drawn by the portal itself, so there is no waiting time.', 'Ito ay iginuguhit ng portal mismo, kaya walang paghihintay.') :
      r.state === 'down' ? T('It did not answer.', 'Hindi ito sumagot.') : T('It answered in ', 'Sumagot ito sa ') + fmtMs(r.ms) + T('. Under 1.5 seconds counts as working; slower is slow.', '. Mas mababa sa 1.5 segundo ang gumagana; mas mabagal ay mabagal.');
    var note = 'Smart Sumbong status, ' + s.job + ' (' + s.prov + '): ' + BADGE[r.state || 'checking'][1] + (s.local ? '' : ', ' + fmtMs(r.ms)) + '. ' + s.what;
    $('st-dr-body').innerHTML = '<div class="st-bigr" data-dr-ms><b>' + esc(reading(s)) + '</b><span class="p-badge ' + B[0] + '">' + esc(B[1]) + '</span></div><p>' + esc(say) + '</p>' +
      sec(T('What it does', 'Ano ang ginagawa nito'), '<p>' + esc(s.what) + '</p>') +
      sec(T('The last 36 checks', 'Ang huling 36 na pagsusuri'), bars(key, true, false) + '<div class="st-legend"><span class="st-lg"><i class="g"></i>' + esc(T('Answered fast', 'Mabilis sumagot')) + '</span><span class="st-lg"><i class="a"></i>' + esc(T('Slow', 'Mabagal')) + '</span><span class="st-lg"><i class="r"></i>' + esc(T('No answer', 'Walang sagot')) + '</span><span class="st-ax">' + esc(T('oldest on the left, newest on the right', 'pinakamatanda sa kaliwa, pinakabago sa kanan')) + '</span></div><p class="st-hnote">' + esc(T('These are the checks made from this browser. They build up each time the page is open.', 'Ito ang mga pagsusuring ginawa mula sa browser na ito. Dumarami ito tuwing bukas ang pahina.')) + '</p>') +
      sec(T('If it fails', 'Kapag pumalpak'), '<p>' + esc(s.down) + '</p>') + (s.browser ? sec(T('Good to know', 'Mabuting malaman'), '<p>' + esc(T('This one is checked from this browser, so a slow reading can also be this computer’s internet connection.', 'Sinusuri ito mula sa browser na ito, kaya ang mabagal na sukat ay maaari ring dahil sa internet ng computer na ito.')) + '</p>') : '') +
      sec(T('What you can do', 'Ang magagawa mo'), '<div class="st-acts"><button type="button" class="p-btn p-btn-primary p-btn-sm" data-st-recheck="' + key + '">' + esc(T('Check again', 'Suriin muli')) + '</button>' +
        (s.url ? '<a class="p-btn p-btn-ghost p-btn-sm" href="' + esc(s.url) + '" target="_blank" rel="noopener noreferrer">' + esc(T('See the provider’s status page', 'Tingnan ang status page ng provider')) + '</a>' : '') + copyBtn(note) + '</div>' +
        '<p class="st-hnote">' + esc(T('Nothing here changes the service itself. It is the provider’s to fix, and slow readings usually clear by themselves. If one lasts a day, tell the developers and send the copied note.', 'Walang binabago rito sa mismong serbisyo. Ang provider ang mag-aayos, at kusang nawawala ang mabagal na sukat. Kung tumagal ng isang araw, sabihin sa mga developer at ipadala ang kinopyang tala.')) + '</p>');
  }
  function openDrawer() { if (drawer.showModal) { if (!drawer.open) drawer.showModal(); } else { drawer.setAttribute('open', ''); } }
  function closeDrawer() { openKey = null; if (drawer.close) drawer.close(); else drawer.removeAttribute('open'); }
  function openService(key) { openKey = key; fillDrawerService(key, false); openDrawer(); }
  function openTemplate(id) {
    var t = $('st-t-' + id); if (!t) return; openKey = null; var f = t.content.cloneNode(true);
    $('st-dr-t').textContent = f.querySelector('[data-title]').textContent; $('st-dr-sub').textContent = f.querySelector('[data-sub]').textContent;
    var b = $('st-dr-body'); b.innerHTML = ''; b.appendChild(f.querySelector('[data-body]')); openDrawer();
  }
  function openError(el) {
    var src = el.dataset.src, plain = src === 'browser' ? T('A page of the portal reported this from someone’s browser. A few of these are harmless (an animation cancelled because the tab was in the background). If one keeps coming back, copy it and send it to the developers.', 'Iniulat ito ng isang pahina ng portal mula sa browser ng isang tao. Ang ilan ay walang masama (isang animation na nakansela dahil nasa likod ang tab). Kung paulit-ulit, kopyahin at ipadala sa mga developer.')
      : src === 'function' ? T('An Edge Function (a small job that runs on Supabase) reported this. If it keeps coming back, copy it and send it to the developers.', 'Iniulat ito ng isang Edge Function (maliit na gawain sa Supabase). Kung paulit-ulit, kopyahin at ipadala sa mga developer.')
      : T('The portal’s own server reported this. If it keeps coming back, copy it and send it to the developers.', 'Iniulat ito ng server ng portal. Kung paulit-ulit, kopyahin at ipadala sa mga developer.');
    var text = 'Smart Sumbong error (' + src + '): ' + el.dataset.msg + ' (' + el.dataset.page + ', ' + el.dataset.count + ' times, last ' + el.dataset.last + ')';
    openKey = null; $('st-dr-t').textContent = el.dataset.msg; $('st-dr-sub').textContent = el.dataset.page + ' · ' + el.dataset.count + T(' time(s) · ', ' beses · ') + el.dataset.last;
    $('st-dr-body').innerHTML = sec(T('In plain words', 'Sa simpleng salita'), '<p>' + esc(plain) + '</p>') + sec(T('What you can do', 'Ang magagawa mo'), '<div class="st-acts">' + copyBtn(text) + '</div><p class="st-hnote">' + esc(T('Errors leave this list on their own when they stop happening. Nothing here can be changed from the portal.', 'Kusang nawawala ang mga error sa listahang ito kapag tumigil na. Walang mababago rito mula sa portal.')) + '</p>');
    openDrawer();
  }
  function copyText(t, btn) {
    var done = function () { var o = btn.textContent; btn.textContent = T('Copied', 'Nakopya'); setTimeout(function () { btn.textContent = o; }, 1600); };
    var fb = function () { var a = document.createElement('textarea'); a.value = t; a.style.position = 'fixed'; a.style.opacity = '0'; document.body.appendChild(a); a.select(); try { document.execCommand('copy'); } catch (e) { /* the text stays selected */ } a.remove(); done(); };
    if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(t).then(done, fb); } else { fb(); }
  }

  // the hover note
  function tip(e) {
    var t = e.target.closest && e.target.closest('[data-tip]');
    if (!t) { if (tipEl) tipEl.hidden = true; return; }
    if (!tipEl) { tipEl = document.createElement('div'); tipEl.className = 'st-tip'; tipEl.setAttribute('role', 'tooltip'); document.body.appendChild(tipEl); }
    tipEl.textContent = t.getAttribute('data-tip'); tipEl.hidden = false;
    var r = t.getBoundingClientRect(), w = tipEl.offsetWidth;
    tipEl.style.left = Math.max(8, Math.min(innerWidth - w - 8, r.left + r.width / 2 - w / 2)) + 'px'; tipEl.style.top = Math.max(8, r.top - tipEl.offsetHeight - 8) + 'px';
  }
  document.addEventListener('mouseover', tip); document.addEventListener('focusin', tip);
  document.addEventListener('mouseout', function (e) { if (tipEl && !(e.relatedTarget && e.relatedTarget.closest && e.relatedTarget.closest('[data-tip]'))) tipEl.hidden = true; });
  document.addEventListener('focusout', function () { if (tipEl) tipEl.hidden = true; }); window.addEventListener('scroll', function () { if (tipEl) tipEl.hidden = true; }, true);

  document.addEventListener('click', function (e) {
    var t = e.target.closest && e.target.closest('[data-st-view], [data-st-svc], [data-st-open], [data-st-err], [data-st-close], [data-st-recheck], [data-st-copy], [data-st-go]');
    if (!t) { if (drawer && e.target === drawer) closeDrawer(); return; }
    if (t.dataset.stView) setView(t.dataset.stView);
    else if (t.dataset.stSvc) openService(t.dataset.stSvc);
    else if (t.dataset.stOpen) openTemplate(t.dataset.stOpen);
    else if (t.hasAttribute('data-st-err')) openError(t);
    else if (t.hasAttribute('data-st-close')) closeDrawer();
    else if (t.dataset.stRecheck) { var o = t.textContent; t.textContent = T('Checking…', 'Sinusuri…'); t.disabled = true; checkOne(t.dataset.stRecheck).then(function () { lastAt = Date.now(); paintLive(); paintMap(); t.disabled = false; t.textContent = T('Checked just now', 'Kakasuri lang'); setTimeout(function () { t.textContent = o; }, 1600); }); }
    else if (t.dataset.stCopy) copyText(t.dataset.stCopy, t);
    else if (t.dataset.stGo) { closeDrawer(); var tb = document.querySelector('.st-tabs [data-st="' + t.dataset.stGo + '"]'); if (tb) tb.click(); }
  });
  document.addEventListener('keydown', function (e) { var g = e.target.closest && e.target.closest('g[data-st-svc]'); if (g && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); openService(g.dataset.stSvc); return; } var c = e.target.closest && e.target.closest('[data-st-open]'); if (c && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); openTemplate(c.dataset.stOpen); } });
  if (drawer) drawer.addEventListener('close', function () { openKey = null; });

  // ---------- Plan and usage ----------
  var U = null, planSel = '';
  var mb = function (b) { return b == null ? '—' : b >= 1073741824 ? (b / 1073741824).toFixed(2) + ' GB' : (b / 1048576).toFixed(1) + ' MB'; };
  function word(p) { return p >= 90 ? T('Almost full', 'Halos puno na') : p >= 75 ? T('Getting full', 'Napupuno na') : T('Plenty of room', 'Maluwag pa'); }
  function plans() {
    var u = U || {}, sb = u.supabase, P = u.plans || {}, cl = u.cloudinary, ph = u.photos, of = T(' of ', ' sa ');
    var list = [
      { id: 'sb', l: 'S', n: 'Supabase', plan: P.supabase || 'Free', c: '#3ECF8E', dash: 'https://supabase.com/dashboard', note: T('Free projects pause after a week with no activity. Data sent out is shown only in Supabase’s dashboard.', 'Humihinto ang libreng proyekto pagkalipas ng isang linggong walang aktibidad. Ang datos na lumabas ay makikita lamang sa dashboard ng Supabase.'),
        limit: T('If the database reaches 500 MB it stops accepting new data until space is freed or the plan is upgraded.', 'Kapag umabot sa 500 MB ang database, titigil itong tumanggap ng bagong datos hanggang may maluwag o ma-upgrade ang plano.'),
        items: sb ? [[T('Database', 'Database'), mb(sb.db_bytes), '500 MB', sb.db_bytes / 524288000 * 100], [T('File storage', 'Imbakan'), mb(sb.storage_bytes), '1 GB', sb.storage_bytes / 1073741824 * 100], [T('Active users this month', 'Aktibong user ngayong buwan'), Number(sb.active_users || 0).toLocaleString(), '50,000', (sb.active_users || 0) / 50000 * 100]] : [],
        info: sb ? [] : [[T('Database size and active users', 'Laki ng database at aktibong user'), T('need migration 0078', 'kailangan ang migration 0078')]] },
      { id: 'cl', l: 'C', n: 'Cloudinary', plan: (cl && cl.plan) || P.cloudinary || 'Free', c: '#3448C5', dash: 'https://console.cloudinary.com', note: T('1 credit = 1 GB stored, 1 GB served or 1,000 resizes. Photos on record are counted from the database.', '1 credit = 1 GB imbak, 1 GB ipinadala o 1,000 resize. Ang mga larawan sa talaan ay binibilang mula sa database.'),
        limit: T('When the monthly credits run out, photos stop loading until next month or an upgrade.', 'Kapag naubos ang buwanang credit, hihinto ang pag-load ng larawan hanggang sa susunod na buwan o upgrade.'),
        items: cl && cl.credits_limit ? [[T('Monthly credits', 'Buwanang credit'), (+cl.credits_used).toFixed(1), String(cl.credits_limit), cl.credits_used / cl.credits_limit * 100]] : [],
        info: (cl && cl.credits_limit ? [] : [[T('Credits', 'Mga credit'), T('not connected yet', 'hindi pa nakakonekta')]]).concat(ph ? [[T('Complaint photos on record', 'Mga larawan sa talaan'), ph.files.toLocaleString() + ' · ' + mb(ph.bytes)]] : []) },
      { id: 'rn', l: 'R', n: 'Render', plan: P.render || 'Free', c: '#6E5CF6', dash: 'https://dashboard.render.com', note: T('On the Free plan the portal sleeps after 15 minutes with no visitors; the next visit takes about a minute to wake it. Open it a minute before presenting.', 'Natutulog ang portal pagkalipas ng 15 minutong walang bisita; ang susunod na bisita ay aabutin ng mga isang minuto para gisingin ito. Buksan ito isang minuto bago mag-presenta.'),
        limit: T('The Free plan gives 750 instance hours a month. After that the portal stops until the month turns over.', 'Ang Free plan ay may 750 oras bawat buwan. Pagkatapos nito, titigil ang portal hanggang magbago ang buwan.'), items: [], info: [[T('Instance hours', 'Oras ng instance'), T('750 a month on the Free plan', '750 bawat buwan sa Free plan')]] },
      { id: 'fb', l: 'F', n: 'Firebase push', plan: T('No cost', 'Walang bayad'), c: '#F5A623', dash: 'https://console.firebase.google.com', note: T('Cloud Messaging has no usage charge.', 'Walang singil ang Cloud Messaging.'), limit: T('There is no limit to reach.', 'Walang limitasyong aabutin.'), items: [], info: u.alerts != null ? [[T('Dispatch alerts this month', 'Dispatch alert ngayong buwan'), Number(u.alerts).toLocaleString()]] : [] },
      { id: 'om', l: 'O', n: 'Open-Meteo', plan: 'Free', c: '#2D9CDB', dash: 'https://open-meteo.com', note: T('Free for non-commercial use. Each open map checks every 10 minutes.', 'Libre para sa hindi pangkomersyo. Bawat bukas na mapa ay sumusuri kada 10 minuto.'),
        limit: T('Above 10,000 rain checks a day the service may refuse requests until the next day.', 'Kapag lumampas sa 10,000 pagsuri ng ulan kada araw, maaaring tumanggi ang serbisyo hanggang sa susunod na araw.'), items: [], info: [[T('Rain checks allowed', 'Pinapayagang pagsuri'), T('10,000 a day', '10,000 bawat araw')]] },
      { id: 'nm', l: 'N', n: 'Nominatim · OpenFreeMap', plan: 'Free', c: '#7EBC6F', dash: 'https://nominatim.org', note: T('Address lookups at most 1 per second. OpenFreeMap tiles have no limit.', 'Hanggang 1 paghahanap ng address bawat segundo. Walang limitasyon ang tiles ng OpenFreeMap.'),
        limit: T('Lookups faster than 1 a second are refused for a moment, then work again.', 'Ang paghahanap na mas mabilis sa 1 bawat segundo ay tinatanggihan sandali, saka gagana ulit.'), items: [], info: [[T('Address lookups', 'Paghahanap ng address'), T('at most 1 per second', 'hanggang 1 bawat segundo')], [T('Map tiles', 'Mga tile ng mapa'), T('no limit', 'walang limitasyon')]] }
    ];
    list.forEach(function (p) { p.items = p.items.filter(function (m) { return isFinite(m[3]); }); });   // a meter needs a real reading
    return list;
  }
  function meterHtml(p, m, all) {
    var v = Math.max(0, Math.min(100, m[3])), c = v >= 90 ? 'b' : v >= 75 ? 'w' : '', cls = v >= 90 ? 'red' : v >= 75 ? 'amber' : 'ok';
    return '<div class="st-um" data-plan="' + p.id + '"><div class="st-mh"><b>' + esc(m[0]) + (all ? ' <span class="st-tier">' + esc(p.n) + '</span>' : '') + '</b><span>' + esc(m[1]) + T(' of ', ' sa ') + esc(m[2]) + '</span></div>' +
      '<div class="st-bar tk" role="img" aria-label="' + esc(word(v)) + ', ' + Math.round(v) + '%"><i class="' + c + '" style="width:' + Math.max(1.5, v) + '%"></i></div>' +
      '<div class="st-mh sub"><span class="' + cls + '">' + esc(word(v)) + '</span><span>' + (v < 1 ? T('under 1', 'wala pang 1') : v < 10 && v % 1 ? v.toFixed(1) : Math.round(v)) + '% ' + esc(T('used', 'nagamit')) + '</span></div></div>';
  }
  function usageUI() {
    var host = $('st-usage'); if (!host) return;
    var failed = !U;   // the plans still list; only the measured meters are missing
    var PL = plans(), sel = planSel, ps = sel ? PL.filter(function (p) { return p.id === sel; }) : PL, rows = [], info = '', all = !sel;
    ps.forEach(function (p) { p.items.forEach(function (m) { rows.push([p, m]); }); p.info.forEach(function (i) { info += '<div class="st-um info" data-plan="' + p.id + '"><div class="st-mh"><b>' + esc(i[0]) + (all ? ' <span class="st-tier">' + esc(p.n) + '</span>' : '') + '</b><span>' + esc(i[1]) + '</span></div></div>'; }); });
    rows.sort(function (a, b) { return b[1][3] - a[1][3]; });
    var allM = []; PL.forEach(function (p) { p.items.forEach(function (m) { allM.push([p, m]); }); }); allM.sort(function (a, b) { return b[1][3] - a[1][3]; });
    var top = allM[0], over = allM.filter(function (x) { return x[1][3] >= 75; }).length, free = PL.filter(function (p) { return /free|no cost|walang bayad|libre/i.test(p.plan); }).length;
    var next = new Date(); next.setMonth(next.getMonth() + 1, 1);
    var kp = '<div class="st-uk"><div><small>' + esc(T('Services', 'Mga serbisyo')) + '</small><b>' + PL.length + '</b><span>' + esc(free === PL.length ? T('all on a free plan', 'lahat ay libreng plano') : free + T(' on a free plan', ' ang libreng plano')) + '</span></div>' +
      '<div><small>' + esc(T('Closest to a limit', 'Pinakamalapit sa limitasyon')) + '</small><b>' + (top ? Math.round(top[1][3]) + '%' : '—') + '</b><span>' + esc(top ? top[0].n + ' · ' + top[1][0] : '') + '</span></div>' +
      '<div><small>' + esc(T('Next reset', 'Susunod na reset')) + '</small><b>' + esc(next.toLocaleDateString(LOCALE, { month: 'short', day: 'numeric' })) + '</b><span>' + esc(T('monthly limits start over', 'nagsisimula muli ang buwanang limitasyon')) + '</span></div>' +
      '<div><small>' + esc(T('Over a warning line', 'Lampas sa babala')) + '</small><b>' + over + '</b><span>' + esc(over ? T('amber or red', 'dilaw o pula') : T('nothing amber or red', 'walang dilaw o pula')) + '</span></div></div>';
    var p0 = sel ? ps[0] : null;
    var left = '<div class="st-ulh"><div><h2>' + esc(p0 ? p0.n + T(' usage', ' paggamit') : T('Usage against limits', 'Paggamit laban sa limitasyon')) + '</h2><small>' + esc(p0 ? T('Only what ', 'Ang nililimitahan o sinusukat lamang ng ') + p0.n + T(' limits or measures.', '.') : T('Everything the barangay uses, fullest first. Hover a plan on the right to focus it; press it to keep it.', 'Lahat ng ginagamit ng barangay, pinakapuno muna. Ilagay ang cursor sa isang plano sa kanan para i-focus; pindutin para panatilihin.')) + '</small></div>' + (p0 ? '<button type="button" class="p-btn p-btn-ghost p-btn-sm" data-st-plan-clear>' + esc(T('Show all', 'Ipakita lahat')) + '</button>' : '') + '</div>' +
      '<div class="st-legend"><span>' + esc(T('The bar fills as the limit is used.', 'Napupuno ang guhit habang nagagamit ang limitasyon.')) + '</span><span class="st-lg"><i class="g"></i>' + esc(T('Under 75%', 'Wala pang 75%')) + '</span><span class="st-lg"><i class="a"></i>' + esc(T('75% and over', '75% pataas')) + '</span><span class="st-lg"><i class="r"></i>' + esc(T('90% and over', '90% pataas')) + '</span></div>' +
      (rows.length ? rows.map(function (r) { return meterHtml(r[0], r[1], all); }).join('') : '') + (info ? '<div class="st-infos">' + info + '</div>' : '');
    if (p0) {
      left += sec(T('About this plan', 'Tungkol sa planong ito'), '<p>' + esc(p0.note) + '</p>') + sec(T('At the limit', 'Sa limitasyon'), '<p>' + esc(p0.limit) + '</p>') +
        sec(T('What you can do', 'Ang magagawa mo'), '<div class="st-acts"><a class="p-btn p-btn-primary p-btn-sm" href="' + esc(p0.dash) + '" target="_blank" rel="noopener noreferrer">' + esc(T('Open ', 'Buksan ang ') + p0.n + T('’s dashboard', ' dashboard')) + '</a>' + copyBtn('Smart Sumbong plan note, ' + p0.n + ' (' + p0.plan + '): ' + p0.note + ' At the limit: ' + p0.limit) + '</div><p class="st-hnote">' + esc(T('Plans are changed in the provider’s own dashboard; this page only shows how close the barangay is.', 'Sa mismong dashboard ng provider binabago ang plano; ipinapakita lamang ng pahinang ito kung gaano kalapit ang barangay.')) + '</p>');
    }
    var right = '<div class="st-ulh"><h2>' + esc(T('Plans', 'Mga plano')) + '</h2><small>' + esc(T('Hover to focus · press to keep', 'Ilagay ang cursor para i-focus · pindutin para panatilihin')) + '</small></div>' +
      PL.map(function (p) { return '<button type="button" class="st-pl" data-st-plan="' + p.id + '" aria-pressed="' + (sel === p.id) + '"><span class="st-mono" style="--ac:' + p.c + '" aria-hidden="true">' + esc(p.l) + '</span><span><span class="st-plh"><b>' + esc(p.n) + '</b><span class="st-tier">' + esc(p.plan) + '</span></span><small>' + esc(p.note) + '</small></span></button>'; }).join('');
    host.innerHTML = (failed ? '<p class="st-note">' + esc(T('The measured usage could not be loaded just now. Press Check again to try once more.', 'Hindi ma-load ang nasukat na paggamit ngayon. Pindutin ang Suriin muli.')) + '</p>' : '') + kp + '<div class="st-ugrid"><div class="p-card p-card-pad st-ul" id="st-ul">' + left + '</div><div class="p-card p-card-pad st-ur">' + right + '</div></div>';
    $$('[data-st-plan]', host).forEach(function (b) {
      b.addEventListener('click', function () { var id = b.dataset.stPlan; planSel = planSel === id ? '' : id; usageUI(); var n = host.querySelector('[data-st-plan="' + id + '"]'); if (n) n.focus(); });
      b.addEventListener('mouseenter', function () { if (!planSel) dimTo(b.dataset.stPlan); }); b.addEventListener('mouseleave', function () { if (!planSel) dimTo(''); });
      b.addEventListener('focus', function () { if (!planSel) dimTo(b.dataset.stPlan); }); b.addEventListener('blur', function () { if (!planSel) dimTo(''); });
    });
    var clr = host.querySelector('[data-st-plan-clear]'); if (clr) clr.addEventListener('click', function () { planSel = ''; usageUI(); });
  }
  function dimTo(id) { $$('#st-ul .st-um').forEach(function (u) { u.classList.toggle('dim', !!id && u.dataset.plan !== id); }); }
  function usage() { return fetch('settings.php?usage=1', { cache: 'no-store' }).then(function (r) { return r.json(); }).catch(function () { return null; }).then(function (u) { U = u; usageUI(); }); }

  // ---------- SMART > Rules: the scale follows the three inputs ----------
  (function () {
    var sc = $('ss-scale'); if (!sc) return;
    var ins = { n: $('lv-normal_from'), h: $('lv-high_from'), u: $('lv-urgent_from') };
    function upd() { ['n', 'h', 'u'].forEach(function (k) { var v = ins[k] ? Math.max(1, Math.min(100, +ins[k].value || 0)) : null; if (v == null) return; sc.style.setProperty('--' + k, v); var sp = sc.querySelector({ n: '.ss-sn', h: '.ss-sh', u: '.ss-su' }[k] + ' i'); if (sp) sp.textContent = v; }); }
    ['n', 'h', 'u'].forEach(function (k) { if (ins[k]) ins[k].addEventListener('input', upd); });
  })();

  // ---------- the tabs, the Check again button, the live timer ----------
  function statusVisible() { var b = $('st-banner'); return !!b && !b.closest('.st-pane').hidden && document.visibilityState === 'visible'; }
  $$('.st-tabs [data-st]').forEach(function (b) { b.addEventListener('click', function () {
    $$('.st-tabs [data-st]').forEach(function (x) { x.classList.toggle('p-on', x === b); });
    $$('.st-pane').forEach(function (p) { p.hidden = p.dataset.pane !== b.dataset.st; });
    document.body.classList.toggle('st-smart-on', b.dataset.st === 'smart');   // 15 Nov 2026 (Ace): the SMART tab turns the whole page navy
    var live = b.dataset.st === 'status' || b.dataset.st === 'usage'; $('st-check').hidden = !live; $('st-checked').hidden = b.dataset.st !== 'status';
  }); });
  var checkBtn = $('st-check'); if (checkBtn) checkBtn.addEventListener('click', function () { check(); usage(); });
  var since = 0;
  setInterval(function () { paintLive(); since++; if (since >= 45 && statusVisible() && !busy) { since = 0; check(); } }, 1000);
  document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible' && statusVisible() && lastAt && Date.now() - lastAt > 45000 && !busy) check(); });

  S.forEach(function (s) { R[s.key] = { state: 'checking' }; paintRow(s.key); }); built = true; paintHero(); var v0 = 'list'; try { v0 = localStorage.getItem('ss-st-view') === 'map' ? 'map' : 'list'; } catch (e) { /* list */ } setView(v0); check(); usage();
})();
