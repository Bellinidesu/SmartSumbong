// Workspace widgets: live conditions (17 Oct 2026). The day's briefing, flood and typhoon watch, the weather in all its
// views (heat, UV, wind, 24 hours, 7 days, barometer, sun and moon), the air, the tide and waves, and earthquakes.
(function () {
  var WS = window.WS, T = WS.T, A = WS.a, esc = WS.esc, n = WS.n, W = WS.w, L = WS.lvl;
  var ok = function (g) { return g && g.ok ? g.data : null; };
  var num = function (v, d) { return v == null || isNaN(v) ? '–' : (+v).toFixed(d || 0); };

  // ---- the weather words, the sky colours and the little icons
  function sky(code, day) {
    var k = code === 0 ? (day ? 'sun' : 'moon') : code === 1 ? (day ? 'sun' : 'moon') : code === 2 ? 'cloud' : code === 3 ? 'cloud' : (code === 45 || code === 48) ? 'fog' : (code >= 51 && code <= 67) || (code >= 80 && code <= 82) ? 'rain' : code >= 95 ? 'storm' : 'cloud';
    var lb = { sun: T('Clear', 'Maaliwalas'), moon: T('Clear night', 'Maaliwalas na gabi'), cloud: code === 2 ? T('Partly cloudy', 'Bahagyang maulap') : T('Cloudy', 'Maulap'), fog: T('Fog', 'Hamog'), rain: code >= 80 ? T('Rain showers', 'Pagulan') : code >= 61 ? T('Rain', 'Ulan') : T('Drizzle', 'Ambon'), storm: T('Thunderstorm', 'Pagkulog at pagkidlat') }[k];
    var g = day ? { sun: 'linear-gradient(135deg,#1E6BD6,#5BB0F5 60%,#FFD27A)', cloud: 'linear-gradient(135deg,#4A6C99,#8FA8C6)', fog: 'linear-gradient(135deg,#6B7A8F,#AEB8C6)', rain: 'linear-gradient(135deg,#2B3F66,#5F7FA8)', storm: 'linear-gradient(135deg,#231C4F,#5A3F8F)' }[k]
      : { moon: 'linear-gradient(135deg,#07102E,#1E2F5C)', cloud: 'linear-gradient(135deg,#0F1B38,#33425F)', fog: 'linear-gradient(135deg,#1B2538,#46556E)', rain: 'linear-gradient(135deg,#0F1B38,#33425F)', storm: 'linear-gradient(135deg,#150F33,#3B2A6B)', sun: 'linear-gradient(135deg,#07102E,#1E2F5C)' }[k];
    return { k: k, label: lb, grad: g || 'linear-gradient(135deg,#1B2342,#0E1428)', ic: k === 'moon' ? 'moon' : k === 'rain' ? 'drop' : k === 'storm' ? 'bolt' : k === 'fog' ? 'wind' : k === 'sun' ? 'sun' : 'cloud' };
  }
  WS.sky = sky;
  var DIRS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  var dir8 = function (d) { return DIRS[Math.round((d % 360) / 45) % 8]; };
  var BAND = { caution: [T('Caution', 'Mag-ingat'), '#F5D90A', T('Fatigue is possible with long exposure and activity.', 'Maaaring mapagod sa matagal na pagbabad at gawain.')], extreme_caution: [T('Extreme caution', 'Matinding pag-iingat'), '#FF9800', T('Heat cramps and exhaustion are possible. Water every hour on foot rounds.', 'Posibleng ma-cramp at mapagod sa init. Uminom ng tubig kada oras sa ronda.')], danger: [T('Danger', 'Panganib'), '#E5383B', T('Heat cramps and exhaustion are likely; heat stroke is possible. Rest in the shade.', 'Malamang ang cramps at pagkapagod; posible ang heat stroke. Magpahinga sa lilim.')], extreme_danger: [T('Extreme danger', 'Matinding panganib'), '#9B1C1F', T('Heat stroke is imminent. Stay indoors and out of the sun.', 'Nalalapit ang heat stroke. Manatili sa loob at iwasan ang araw.')] };
  var time = function (iso) { return iso ? WS.fmt.time(iso.length === 16 ? iso + ':00+08:00' : iso) : '–'; };

  // ---- the briefing
  W.brief = {
    r: function () {
      var b = ok(WS.group('brief')), who = (WS.C.me.name || '').split(' ')[0], hello = { morning: T('Good morning', 'Magandang umaga'), afternoon: T('Good afternoon', 'Magandang hapon'), night: T('Good evening', 'Magandang gabi') }[b.period];
      var wait = b.urgent_waiting + b.high_waiting;
      var line = b.period === 'morning' ? T(n(b.open) + ' cases are open and ' + n(wait) + ' wait for a tanod. ' + n(b.due_today) + ' are due today and ' + n(b.may_miss) + ' may miss their deadline.', n(b.open) + ' ang bukás na kaso at ' + n(wait) + ' ang naghihintay ng tanod. ' + n(b.due_today) + ' ang takdang oras ngayon at ' + n(b.may_miss) + ' ang maaaring lumampas.')
        : b.period === 'afternoon' ? T(n(b.in_today) + ' cases came in today and ' + n(b.out_today) + ' were resolved. ' + n(wait) + ' urgent or high still wait for a tanod; ' + n(b.overdue) + ' are overdue.', n(b.in_today) + ' ang pumasok ngayon at ' + n(b.out_today) + ' ang nalutas. ' + n(wait) + ' na madalian o mataas ang naghihintay pa ng tanod; ' + n(b.overdue) + ' ang lampas na.')
        : T(n(b.in_today) + ' filed and ' + n(b.out_today) + ' resolved today. ' + n(b.open) + ' stay open overnight and ' + n(b.overdue) + ' are overdue.', n(b.in_today) + ' ang naisampa at ' + n(b.out_today) + ' ang nalutas ngayon. ' + n(b.open) + ' ang mananatiling bukás at ' + n(b.overdue) + ' ang lampas na.');
      var tiles = [[T('Open', 'Bukás'), b.open, ''], [T('Wait for a tanod', 'Naghihintay ng tanod'), wait, wait ? L.urgent : ''], [T('Due today', 'Takdang oras ngayon'), b.due_today, ''], [T('Overdue', 'Lampas na'), b.overdue, b.overdue ? L.urgent : ''], [T('Filed today', 'Naisampa ngayon'), b.in_today, ''], [T('Resolved today', 'Nalutas ngayon'), b.out_today, L.ok], [T('May miss deadline', 'Maaaring lumampas'), b.may_miss, b.may_miss ? L.high : ''], [T('Recurring', 'Paulit-ulit'), b.recurring_open, '']];
      return '<div class="wx-hero wx-eng"><span class="eb">' + esc(hello + (who ? ', ' + who : '')) + '</span><div class="hb">' + (wait ? T(n(wait) + (wait === 1 ? ' case needs a tanod' : ' cases need a tanod'), n(wait) + ' kaso ang kailangan ng tanod') : T('All quiet right now', 'Tahimik sa ngayon')) + '</div><p class="hs">' + esc(line) + '</p><div class="hr"><a class="wx-btn" href="workspace.php?own=free">' + T('Show me', 'Ipakita') + '</a><a class="wx-btn" href="cases.php">' + T('All cases', 'Lahat ng kaso') + '</a></div></div>' +
        '<div class="wx-tiles">' + tiles.map(function (t) { return '<div class="wx-tile"' + (t[2] ? ' style="--c:' + t[2] + '"' : '') + '><span>' + t[0] + '</span><b' + (t[2] ? ' style="color:' + t[2] + '"' : '') + '>' + n(t[1]) + '</b></div>'; }).join('') + '</div>';
    }
  };

  // ---- flood watch
  W.flood = {
    opt: ['wx'],
    r: function () {
      var h = ok(WS.group('hazards')), wx = ok(WS.group('wx')), src = h.sources || {};
      var metro = (h.warnings || []).filter(function (w) { return w.metro; }), near = (h.warnings || []).filter(function (w) { return !w.metro; });
      var lv = 0; metro.forEach(function (w) { lv = Math.max(lv, w.level); });
      var rain = wx ? +wx.now.rain : 0; if (rain >= 7.5) lv = Math.max(lv, 2); else if (rain >= 2.5) lv = Math.max(lv, 1);
      var unknown = !src.pagasa_warnings && !wx, names = [T('Clear', 'Malinaw'), T('Yellow', 'Dilaw'), T('Orange', 'Kahel'), T('Red', 'Pula')], cols = ['#2E9E4F', '#F5D90A', '#FF9800', '#E5383B'];
      var head = unknown ? T('Unknown', 'Hindi alam') : names[lv] + (lv ? T(' warning', ' na babala') : '');
      var sub = !src.pagasa_warnings ? T("PAGASA's warnings could not be read right now.", 'Hindi mabasa ang mga babala ng PAGASA ngayon.') : metro.length ? esc(metro[0].type + ' · ' + metro[0].region) : near.length ? T('Warnings nearby, none naming Metro Manila.', 'May mga babala sa paligid, wala para sa Metro Manila.') : T('No rainfall warning for Metro Manila.', 'Walang babala sa ulan para sa Metro Manila.');
      var arc = [0, 1, 2, 3].map(function (i) { var a0 = Math.PI * (1 - i / 4), a1 = Math.PI * (1 - (i + .93) / 4), p = function (a) { return (60 + 50 * Math.cos(a)).toFixed(1) + ' ' + (62 - 50 * Math.sin(a)).toFixed(1); }; return '<path d="M' + p(a0) + ' A50 50 0 0 1 ' + p(a1) + '" style="stroke:' + cols[i] + ';opacity:' + (i <= lv && !unknown ? 1 : .2) + '"/>'; }).join('');
      var ang = Math.PI * (1 - (unknown ? 0 : (lv + .5) / 4)), nx = 60 + 38 * Math.cos(ang), ny = 62 - 38 * Math.sin(ang);
      var g = '<svg class="wx-gauge" viewBox="0 0 120 72" aria-hidden="true"><g fill="none" stroke-width="9" stroke-linecap="round">' + arc + '</g><line x1="60" y1="62" x2="' + nx.toFixed(1) + '" y2="' + ny.toFixed(1) + '" class="nd"/><circle cx="60" cy="62" r="5"/></svg>';
      var fc = h.forecast || [], mx = Math.max.apply(null, fc.map(function (x) { return x.mm; }).concat([2]));
      var cards = metro.concat(near).slice(0, 3).map(function (w) { var c = [L.low, '#F5D90A', '#FF9800', '#E5383B'][w.level] || L.low; return '<div class="wx-card2" style="border-left:4px solid ' + c + '"><b>' + esc(w.type) + ' ' + A.pill(esc(w.severity || names[w.level]), c) + (w.metro ? '' : ' ' + A.pill(T('nearby', 'malapit'), L.low)) + '</b><p>' + esc(w.text || w.areas) + '</p><span class="wx-note">' + (w.expires ? T('Until ', 'Hanggang ') + esc(w.expires) : '') + (w.url ? ' · <a href="' + esc(w.url) + '" target="_blank" rel="noopener noreferrer">' + T('PAGASA', 'PAGASA') + '</a>' : '') + '</span></div>'; }).join('');
      return '<div class="wx-grid2"><div class="wx-card2 wx-flood"><span class="wx-h">' + T('Level now', 'Antas ngayon') + '</span>' + g + '<div class="wx-fl"><b style="color:' + (unknown ? 'var(--wx-mute)' : cols[lv]) + '">' + head + '</b><span>' + sub + '</span></div>' + (wx ? '<div class="wx-row">' + A.pill(T('Rain now ', 'Ulan ngayon ') + num(rain, 1) + ' mm/h', rain >= 7.5 ? '#FF9800' : rain >= 2.5 ? '#F5D90A' : L.ok) + '</div>' : '') + '</div>' +
        '<div class="wx-card2"><span class="wx-h">' + T('Rain, next 12 hours', 'Ulan, susunod na 12 oras') + '</span>' + (fc.length ? A.bars(fc.map(function (x) { return x.mm; }), '#356CF9', { max: mx, h: 70 }) + '<div class="wx-ax"><span>' + esc(fc[0].h) + '</span><span>' + esc(fc[fc.length - 1].h) + '</span></div><p class="wx-note">' + T('Most: ', 'Pinakamarami: ') + num(Math.max.apply(null, fc.map(function (x) { return x.mm; })), 1) + ' mm/h · PAGASA, Port Area</p>' : '<p class="wx-note">' + T('The hourly forecast could not be read.', 'Hindi mabasa ang oras-oras na taya.') + '</p>') + '</div></div>' + (cards ? '<div class="wx-list">' + cards + '</div>' : '') +
        '<div class="wx-row"><a class="wx-btn" href="spatial.php">' + T('Open the map', 'Buksan ang mapa') + '</a><a class="wx-btn" href="https://bagong.pagasa.dost.gov.ph/" target="_blank" rel="noopener noreferrer">PAGASA</a></div>';
    }, src: 'PAGASA · Open-Meteo · Project NOAH'
  };

  // ---- typhoon watch
  function track(cy) {
    var p = (cy.path || []).slice(); if (p.length < 2) return '';
    var hall = [14.5194, 121.0122], pts = p.concat([hall]), la = pts.map(function (x) { return x[0]; }), lo = pts.map(function (x) { return x[1]; });
    var a = Math.min.apply(null, la), b = Math.max.apply(null, la), c = Math.min.apply(null, lo), d = Math.max.apply(null, lo), pad = 0.5;
    a -= pad; b += pad; c -= pad; d += pad;
    var X = function (g) { return 12 + (g - c) / (d - c) * 216; }, Y = function (g) { return 78 - (g - a) / (b - a) * 66; };
    var line = p.map(function (x) { return X(x[1]).toFixed(1) + ',' + Y(x[0]).toFixed(1); }).join(' '), cur = p[Math.max(0, p.length - 1 - (cy.ahead || 0))];
    return '<svg class="wx-track" viewBox="0 0 240 90" aria-hidden="true"><polyline points="' + line + '"/><circle class="h" cx="' + X(hall[1]).toFixed(1) + '" cy="' + Y(hall[0]).toFixed(1) + '" r="4.5"/><circle class="c" cx="' + X(cur[1]).toFixed(1) + '" cy="' + Y(cur[0]).toFixed(1) + '" r="6"/><circle class="r" cx="' + X(cur[1]).toFixed(1) + '" cy="' + Y(cur[0]).toFixed(1) + '" r="6"/></svg>';
  }
  W.ty = {
    r: function () {
      var h = ok(WS.group('hazards')), cy = h.cyclone, src = h.sources || {};
      if (!cy) {
        return '<div class="wx-hero" style="--hg:linear-gradient(135deg,#1C2A52,#3B2A6B);--hc:#8E3FD0"><span class="eb">' + T('Typhoon watch', 'Bantay-bagyo') + '</span><div class="hb">' + (src.pagasa_cyclone || src.gdacs ? T('No storm near the Philippines', 'Walang bagyo malapit sa Pilipinas') : T('Storm data unavailable', 'Walang datos ng bagyo')) + '</div><p class="hs">' + (src.pagasa_cyclone || src.gdacs ? T('PAGASA and GDACS show no tropical cyclone within reach of Barangay 183.', 'Walang tropical cyclone na malapit sa Barangay 183 ayon sa PAGASA at GDACS.') : T('Neither PAGASA nor GDACS answered. Try again in a few minutes.', 'Hindi sumagot ang PAGASA o GDACS. Subukan muli mamaya.')) + '</p></div><div class="wx-row"><a class="wx-btn" href="https://bagong.pagasa.dost.gov.ph/tropical-cyclone/severe-weather-bulletin" target="_blank" rel="noopener noreferrer">' + T('PAGASA bulletin', 'Bulletin ng PAGASA') + '</a></div>';
      }
      var sg = cy.signal, g = cy.gdacs, hot = sg >= 3, c = hot ? '#E5383B' : '#8E3FD0';
      return '<div class="wx-hero" style="--hg:linear-gradient(135deg,#231C4F,' + (hot ? '#8B1020' : '#5A3F8F') + ');--hc:' + c + '"><span class="eb">' + esc(cy.kind || T('Tropical cyclone', 'Tropical cyclone')) + (sg ? ' · ' + T('Signal ', 'Signal ') + sg : '') + '</span><div class="hb">' + esc(cy.name || T('Unnamed storm', 'Bagyong walang pangalan')) + '</div><p class="hs">' + T(n(cy.km) + ' km ' + cy.dir + ' of the barangay' + (cy.ahead ? ', ' + cy.ahead + ' forecast points ahead' : '') + '.', n(cy.km) + ' km ' + cy.dir + ' ng barangay' + (cy.ahead ? ', ' + cy.ahead + ' puntong taya pa' : '') + '.') + '</p></div>' +
        '<div class="wx-grid2"><div class="wx-card2"><span class="wx-h">' + T('Track', 'Daanan') + '</span>' + track(cy) + '<p class="wx-note">' + T('The dot ringed in purple is the storm; the orange dot is the barangay hall.', 'Ang lilang bilog ay ang bagyo; ang kahel ay ang barangay hall.') + '</p></div><div class="wx-card2"><span class="wx-h">' + T('What the sources say', 'Ayon sa mga pinagmulan') + '</span>' +
        A.kv([[T('Distance', 'Layo'), n(cy.km) + ' km ' + cy.dir], [T('Wind signal', 'Signal ng hangin'), sg ? T('Signal ', 'Signal ') + sg : T('none named', 'wala pang binanggit')], [T('Radius', 'Lawak'), cy.radius ? n(cy.radius) + ' km' : '–']].concat(g ? [['GDACS', esc(g.alert) + (g.wind ? ' · ' + g.wind + ' km/h' : '')]] : [])) + '</div></div>' +
        '<div class="wx-row"><a class="wx-btn" href="spatial.php">' + T('Open the map', 'Buksan ang mapa') + '</a><a class="wx-btn" href="https://bagong.pagasa.dost.gov.ph/tropical-cyclone/severe-weather-bulletin" target="_blank" rel="noopener noreferrer">' + T('PAGASA bulletin', 'Bulletin ng PAGASA') + '</a></div>';
    }, src: 'PAGASA · GDACS'
  };

  // ---- the weather and everything made of it
  W.wx = {
    r: function () {
      var w = ok(WS.group('wx')), c = w.now, s = sky(c.code, c.day), hrs = w.hours.slice(0, 8);
      return '<div class="wx-hero wx-sky" style="--hg:' + s.grad + ';--hc:#356CF9"><div class="wx-skyrow"><span class="wx-skyic k-' + s.k + '">' + WS.svg(s.ic, 44, 1.6) + '</span><div><div class="hb"><span data-n="' + num(c.temp) + '">' + num(c.temp) + '</span>°</div><span class="eb">' + esc(s.label) + '</span></div><span class="wx-feels">' + T('Feels like ', 'Pakiramdam ') + num(c.feels) + '°</span></div></div>' +
        '<div class="wx-tiles"><div class="wx-tile"><span>' + T('Humidity', 'Halumigmig') + '</span><b>' + num(c.humidity) + '%</b></div><div class="wx-tile"><span>' + T('Wind', 'Hangin') + '</span><b>' + num(c.wind) + ' <small>km/h ' + dir8(c.dir) + '</small></b></div><div class="wx-tile"><span>' + T('Rain now', 'Ulan ngayon') + '</span><b>' + num(c.rain, 1) + ' <small>mm</small></b></div><div class="wx-tile"><span>UV</span><b>' + num(c.uv, 1) + '</b></div></div>' +
        '<div class="wx-card2"><span class="wx-h">' + T('Next hours', 'Susunod na oras') + '</span><div class="wx-hrs">' + hrs.map(function (x) { var q = sky(x.code, true); return '<div><span>' + esc(time(x.t)) + '</span>' + WS.svg(q.ic, 18) + '<b>' + num(x.temp) + '°</b>' + (x.pop > 20 ? '<i>' + x.pop + '%</i>' : '<i></i>') + '</div>'; }).join('') + '</div></div>';
    }, src: 'Open-Meteo'
  };

  W.heat = {
    r: function () {
      var w = ok(WS.group('wx')), h = w.heat, b = BAND[h.band], p = h.peak, pct = function (x) { return Math.max(0, Math.min(100, (x - 24) / 32 * 100)); };
      return '<div class="wx-grid2"><div class="wx-card2"><span class="wx-h">' + T('Heat index now', 'Heat index ngayon') + '</span>' + A.big(h.c + '°', b ? b[0] : T('Comfortable', 'Maginhawa'), b ? b[1] : L.ok, h.c) + '<div class="wx-therm"><div class="tr"><i style="--p:' + pct(h.c) + '%"></i></div><div class="sc"><span>27</span><span>33</span><span>42</span><span>52°</span></div></div><p class="wx-note">' + (b ? b[2] : T('Below the caution range. Normal activity is fine.', 'Sa ilalim ng antas ng pag-iingat. Ayos ang karaniwang gawain.')) + '</p></div>' +
        '<div class="wx-card2"><span class="wx-h">' + T('Today', 'Ngayon') + '</span>' + A.kv([[T('Air temperature', 'Temperatura ng hangin'), num(w.now.temp) + '°'], [T('Humidity', 'Halumigmig'), num(w.now.humidity) + '%'], [T('Peak left today', 'Pinakamataas ngayon'), p ? p.c + '° · ' + esc(time(p.at)) : '–'], [T('Peak level', 'Antas sa rurok'), p && p.band && BAND[p.band] ? esc(BAND[p.band][0]) : T('Below caution', 'Sa ilalim ng pag-iingat')]]) + '</div></div>' +
        '<p class="wx-note">' + T("Worked out from temperature and humidity with the heat-index formula and PAGASA's four bands; it is not PAGASA's own station reading.", 'Kinuwenta mula sa temperatura at halumigmig gamit ang heat-index formula at ang apat na antas ng PAGASA; hindi ito mismong basa ng istasyon ng PAGASA.') + '</p>';
    }, src: 'Open-Meteo · PAGASA bands'
  };

  W.uv = {
    r: function () {
      var w = ok(WS.group('wx')), u = +w.now.uv, mx = w.days[0] ? +w.days[0].uv : u, lv = [[3, T('Low', 'Mababa'), '#2E9E4F'], [6, T('Moderate', 'Katamtaman'), '#F5D90A'], [8, T('High', 'Mataas'), '#FF9800'], [11, T('Very high', 'Napakataas'), '#E5383B'], [99, T('Extreme', 'Matindi'), '#8E3FD0']], l = lv.filter(function (x) { return u < x[0]; })[0] || lv[4];
      var burn = u >= 1 ? Math.round(200 / (u * 3)) : null, pos = Math.min(100, u / 12 * 100);
      return '<div class="wx-grid2"><div class="wx-card2"><span class="wx-h">' + T('UV index now', 'UV index ngayon') + '</span>' + A.big(num(u, 1), l[1], l[2]) + '<div class="wx-uvbar"><i style="left:' + pos + '%"></i></div><div class="wx-sc"><span>0</span><span>3</span><span>6</span><span>8</span><span>11+</span></div></div>' +
        '<div class="wx-card2"><span class="wx-h">' + T('Sun safety', 'Kaligtasan sa araw') + '</span>' + A.kv([[T('Highest today', 'Pinakamataas ngayon'), num(mx, 1)], [T('Rough burn time', 'Tantiyang oras bago mapaso'), burn ? '~' + burn + ' min' : T('no risk now', 'walang panganib ngayon')], [T('Cover up', 'Magtakip'), u >= 3 ? T('10 AM to 3 PM', '10 AM hanggang 3 PM') : T('not needed now', 'hindi kailangan ngayon')]]) + '<p class="wx-note">' + T('Burn time is a rough guide for fair skin (about 200 divided by 3 times the index).', 'Gabay lamang ang oras para sa maputing balat (humigit-kumulang 200 hinati sa 3 beses ng index).') + '</p></div></div>';
    }, src: 'Open-Meteo'
  };

  W.wind = {
    r: function () {
      var w = ok(WS.group('wx')), c = w.now, sp = +c.wind, bf = sp < 1 ? 0 : sp < 6 ? 1 : sp < 12 ? 2 : sp < 20 ? 3 : sp < 29 ? 4 : sp < 39 ? 5 : sp < 50 ? 6 : sp < 62 ? 7 : sp < 75 ? 8 : 9;
      var nm = [T('Calm', 'Tahimik'), T('Light air', 'Banayad'), T('Light breeze', 'Banayad na simoy'), T('Gentle breeze', 'Magaan na simoy'), T('Moderate breeze', 'Katamtamang simoy'), T('Fresh breeze', 'Malakas na simoy'), T('Strong breeze', 'Malakas na hangin'), T('Near gale', 'Halos bagyo'), T('Gale', 'Bagyo'), T('Strong gale or worse', 'Matinding bagyo')][bf];
      var gs = w.hours.slice(0, 12).map(function (x) { return x.gust || 0; });
      return '<div class="wx-grid2"><div class="wx-card2" style="place-items:center"><div class="wx-rose"><svg viewBox="0 0 120 120" aria-hidden="true"><circle cx="60" cy="60" r="52"/><circle cx="60" cy="60" r="34" class="in"/><g class="tk">' + [0, 1, 2, 3, 4, 5, 6, 7].map(function (i) { return '<line x1="60" y1="6" x2="60" y2="' + (i % 2 ? 11 : 15) + '" transform="rotate(' + i * 45 + ' 60 60)"/>'; }).join('') + '</g><g class="ar" style="transform:rotate(' + ((+c.dir + 180) % 360) + 'deg)"><path d="M60 16 L69 52 L60 46 L51 52Z"/><line x1="60" y1="46" x2="60" y2="98"/></g><text x="60" y="14" class="n">N</text></svg><div class="ct"><b>' + num(sp) + '</b><span>km/h</span></div></div><span class="wx-note">' + T('Blowing from ', 'Galing sa ') + dir8(c.dir) + ' (' + num(c.dir) + '°)</span></div>' +
        '<div class="wx-card2"><span class="wx-h">' + T('Now', 'Ngayon') + '</span>' + A.kv([[T('Gusts', 'Buga'), num(c.gust) + ' km/h'], [T('Beaufort', 'Beaufort'), bf + ' · ' + nm], [T('Strongest gust today', 'Pinakamalakas na buga ngayon'), w.days[0] ? num(w.days[0].gust) + ' km/h' : '–']]) + '<span class="wx-h">' + T('Gusts, next 12 hours', 'Buga, susunod na 12 oras') + '</span>' + A.bars(gs, '#00A5B5', { h: 56 }) + '</div></div>';
    }, src: 'Open-Meteo'
  };

  W.hourly = {
    r: function () {
      var w = ok(WS.group('wx')), h = w.hours, tp = h.map(function (x) { return x.temp; }), hi = tp.indexOf(Math.max.apply(null, tp)), mn = Math.min.apply(null, tp);
      var wet = h.filter(function (x) { return x.pop >= 50; })[0];
      return '<div class="wx-card2"><span class="wx-h">' + T('Temperature, next 24 hours', 'Temperatura, susunod na 24 oras') + '</span>' + A.spark(tp, '#FF9800', { h: 84, min: mn - 2 }) + '<div class="wx-ax"><span>' + esc(time(h[0].t)) + '</span><span>' + esc(time(h[12].t)) + '</span><span>' + esc(time(h[23].t)) + '</span></div></div>' +
        '<div class="wx-grid2"><div class="wx-card2"><span class="wx-h">' + T('Rain chance', 'Tsansa ng ulan') + '</span>' + A.bars(h.map(function (x) { return x.pop || 0; }), '#356CF9', { max: 100, h: 56 }) + '</div><div class="wx-card2">' + A.kv([[T('Warmest', 'Pinakamainit'), num(tp[hi]) + '° · ' + esc(time(h[hi].t))], [T('Coolest', 'Pinakamalamig'), num(mn) + '°'], [T('Rain likely from', 'Malamang ang ulan mula'), wet ? esc(time(wet.t)) + ' · ' + wet.pop + '%' : T('not in 24 hours', 'wala sa 24 oras')]]) + '</div></div>';
    }, src: 'Open-Meteo'
  };

  W.week = {
    r: function () {
      var w = ok(WS.group('wx')), mx = Math.max.apply(null, w.days.map(function (d) { return d.max; })), mn = Math.min.apply(null, w.days.map(function (d) { return d.min; }));
      return '<div class="wx-week">' + w.days.map(function (d, i) { var q = sky(d.code, true), top = (mx - d.max) / ((mx - mn) || 1) * 40, hh = Math.max(14, (d.max - d.min) / ((mx - mn) || 1) * 60); return '<div class="wk' + (i === 0 ? ' now' : '') + '"><span class="d">' + (i === 0 ? T('Today', 'Ngayon') : esc(WS.fmt.wd(d.d + 'T12:00:00+08:00'))) + '</span>' + WS.svg(q.ic, 24, 1.6) + '<div class="rg"><i style="margin-top:' + top.toFixed(0) + 'px;height:' + hh.toFixed(0) + 'px"></i></div><b>' + num(d.max) + '°</b><em>' + num(d.min) + '°</em><span class="r">' + (d.rain >= 0.2 ? num(d.rain, 1) + ' mm' : '–') + (d.pop >= 30 ? '<i>' + d.pop + '%</i>' : '') + '</span></div>'; }).join('') + '</div>';
    }, src: 'Open-Meteo'
  };

  W.press = {
    r: function () {
      var w = ok(WS.group('wx')), p = +w.now.pressure, d = w.pressure_3h, a = -90 + Math.max(0, Math.min(1, (p - 985) / 50)) * 180, fall = d != null && d <= -3, risk = d != null && d <= -1.5;
      return '<div class="wx-grid2"><div class="wx-card2" style="place-items:center"><svg class="wx-baro" viewBox="0 0 140 84" aria-hidden="true"><path class="t" d="M14 76A56 56 0 0 1 126 76"/><path class="z" d="M14 76A56 56 0 0 1 48 28" /><path class="y" d="M92 28A56 56 0 0 1 126 76"/><g style="transform:rotate(' + a.toFixed(1) + 'deg);transform-origin:70px 76px" class="nd"><line x1="70" y1="76" x2="70" y2="30"/></g><circle cx="70" cy="76" r="5"/></svg><div class="wx-big" style="justify-items:center"><b>' + num(p) + '</b><span>hPa</span></div></div>' +
        '<div class="wx-card2"><span class="wx-h">' + T('Trend, last 3 hours', 'Takbo, huling 3 oras') + '</span>' + A.big((d > 0 ? '+' : '') + num(d, 1), fall ? T('Falling fast', 'Mabilis ang pagbaba') : risk ? T('Falling', 'Bumababa') : d > 1.5 ? T('Rising', 'Tumataas') : T('Steady', 'Matatag'), fall ? L.urgent : risk ? L.high : L.ok) + '<p class="wx-note">' + (fall ? T('A fall of 3 hPa in 3 hours usually means a storm is close. Check the typhoon watch.', 'Ang pagbaba ng 3 hPa sa 3 oras ay karaniwang tanda na malapit ang bagyo. Tingnan ang bantay-bagyo.') : T('Pressure near 1010 hPa is normal. A quick fall warns of a storm.', 'Normal ang presyon na malapit sa 1010 hPa. Ang mabilis na pagbaba ay babala ng bagyo.')) + '</p></div></div>';
    }, src: 'Open-Meteo'
  };

  W.sun = {
    r: function () {
      var w = ok(WS.group('wx')), d = w.days[0], rise = new Date(d.sunrise + ':00+08:00'), set = new Date(d.sunset + ':00+08:00'), now = Date.now(), f = Math.max(0, Math.min(1, (now - rise) / (set - rise))), day = now >= rise && now <= set;
      var x = 20 + f * 200, y = 76 - 232 * f * (1 - f), m = w.moon, left = w.daylight_left_min, names = { new: T('New moon', 'Bagong buwan'), waxing_crescent: T('Waxing crescent', 'Lumalaking hugis-gasuklay'), first_quarter: T('First quarter', 'Unang kuwarto'), waxing_gibbous: T('Waxing gibbous', 'Lumalaking halos-bilog'), full: T('Full moon', 'Kabilugan ng buwan'), waning_gibbous: T('Waning gibbous', 'Lumiliit na halos-bilog'), last_quarter: T('Last quarter', 'Huling kuwarto'), waning_crescent: T('Waning crescent', 'Lumiliit na hugis-gasuklay') };
      var k = Math.cos(2 * Math.PI * m.phase), rx = (22 * Math.abs(k)).toFixed(1), wax = m.phase < .5, crescent = k > 0;
      var lit = 'M30 8A22 22 0 0 ' + (wax ? 1 : 0) + ' 30 52A' + rx + ' 22 0 0 ' + ((wax === crescent) ? 0 : 1) + ' 30 8Z';
      return '<div class="wx-grid2"><div class="wx-card2"><svg class="wx-arc" viewBox="0 0 240 92" aria-hidden="true"><path class="t" d="M20 76Q120 -40 220 76"/><line x1="8" y1="76" x2="232" y2="76"/>' + (day ? '<circle class="g" cx="' + x.toFixed(1) + '" cy="' + y.toFixed(1) + '" r="13"/><circle class="s" cx="' + x.toFixed(1) + '" cy="' + y.toFixed(1) + '" r="8"/>' : '') + '</svg><div class="wx-row" style="justify-content:space-between"><span><b>' + esc(time(d.sunrise)) + '</b> ' + T('sunrise', 'pagsikat') + '</span><span><b>' + esc(time(d.sunset)) + '</b> ' + T('sunset', 'paglubog') + '</span></div>' + A.kv([[T('Daylight left', 'Natitirang liwanag'), left ? Math.floor(left / 60) + ' h ' + (left % 60) + ' min' : T('night', 'gabi')], [T('Dark patrols from', 'Madilim na patrol mula'), esc(WS.fmt.time(new Date(set.getTime() + 25 * 60000)))]]) + '</div>' +
        '<div class="wx-card2" style="place-items:center;text-align:center"><svg class="wx-moon" viewBox="0 0 60 60" aria-hidden="true"><circle cx="30" cy="30" r="22" class="b"/>' + (m.lit > 1 ? '<path d="' + lit + '" class="l"/>' : '') + '</svg><b style="font:800 15px Urbanist">' + esc(names[m.name]) + '</b><span class="wx-note">' + m.lit + '% ' + T('lit', 'maliwanag') + ' · ' + T('day ', 'araw ') + num(m.age_days, 1) + '</span></div></div>';
    }, src: 'Open-Meteo'
  };

  // ---- air, tide, waves, quakes
  W.aq = {
    r: function () {
      var a = ok(WS.group('air')), v = +a.us_aqi, bands = [[50, T('Good', 'Mabuti'), '#2E9E4F', T('Air is clean. Enjoy being outside.', 'Malinis ang hangin. Ayos lumabas.')], [100, T('Moderate', 'Katamtaman'), '#F5D90A', T('Fine for most; the very sensitive may notice.', 'Ayos para sa karamihan; mararamdaman ng pinakasensitibo.')], [150, T('Unhealthy for sensitive groups', 'Hindi mabuti sa sensitibo'), '#FF9800', T('Children, elders and people with asthma should take it easy.', 'Magdahan-dahan ang bata, matatanda at may hika.')], [200, T('Unhealthy', 'Hindi mabuti'), '#E5383B', T('Everyone should cut down on time outside.', 'Bawasan ng lahat ang oras sa labas.')], [300, T('Very unhealthy', 'Napakasama'), '#8E3FD0', T('Stay indoors where you can.', 'Manatili sa loob hangga\'t maaari.')], [999, T('Hazardous', 'Mapanganib'), '#7E0023', T('Avoid going outside.', 'Iwasang lumabas.')]], b = bands.filter(function (x) { return v <= x[0]; })[0];
      return '<div class="wx-grid2"><div class="wx-card2" style="place-items:center">' + A.ring(Math.min(100, v / 300 * 100), b[2], num(v), 'AQI') + '<b style="font:800 15px Urbanist;color:' + b[2] + '">' + esc(b[1]) + '</b><p class="wx-note" style="text-align:center">' + esc(b[3]) + '</p></div><div class="wx-card2"><span class="wx-h">' + T('What is in the air', 'Ano ang nasa hangin') + '</span><div class="wx-tiles" style="grid-template-columns:repeat(2,1fr)">' + [['PM2.5', a.pm2_5, 'µg/m³', 35], ['PM10', a.pm10, 'µg/m³', 150], ['NO₂', a.nitrogen_dioxide, 'µg/m³', 100], ['O₃', a.ozone, 'µg/m³', 100]].map(function (p) { return '<div class="wx-tile"><span>' + p[0] + '</span><b>' + num(p[1], 1) + ' <small>' + p[2] + '</small></b>' + A.bar(Math.min(100, p[1] / p[3] * 100), p[1] > p[3] ? L.high : L.ok, 5) + '</div>'; }).join('') + '</div></div></div>';
    }, src: 'Open-Meteo (CAMS)'
  };

  W.tide = {
    r: function () {
      var t = ok(WS.group('marine')), cv = t.curve, ms = cv.map(function (x) { return x.m; }), mn = Math.min.apply(null, ms);
      return '<div class="wx-grid2"><div class="wx-card2"><span class="wx-h">' + T('Sea level, next 24 hours', 'Taas ng dagat, susunod na 24 oras') + '</span>' + A.big(num(t.level, 2) + ' m', t.rising ? T('rising', 'tumataas') : T('falling', 'bumababa'), t.rising ? '#2D7DD2' : '#00A5B5') + A.spark(ms, '#2D7DD2', { h: 70, min: mn - .1 }) + '<div class="wx-ax"><span>' + esc(time(cv[0].t)) + '</span><span>' + esc(time(cv[12].t)) + '</span><span>' + esc(time(cv[cv.length - 1].t)) + '</span></div></div>' +
        '<div class="wx-card2"><span class="wx-h">' + T('Next highs and lows', 'Susunod na taas at baba') + '</span><div class="wx-list">' + t.turns.map(function (x) { return A.item({ av: x.kind === 'high' ? '▲' : '▼', c: x.kind === 'high' ? '#2D7DD2' : '#00A5B5', t: (x.kind === 'high' ? T('High tide', 'Taas ng tubig') : T('Low tide', 'Baba ng tubig')) + ' · ' + esc(time(x.t)), s: num(x.m, 2) + ' m', sq: 1 }); }).join('') + '</div><p class="wx-note">' + T('A sea-level model for Manila Bay, not the official tide table.', 'Modelo ng taas ng dagat para sa Manila Bay, hindi ang opisyal na talaan ng tubig.') + '</p></div></div>';
    }, src: 'Open-Meteo Marine'
  };

  W.sea = {
    r: function () {
      var t = ok(WS.group('marine')), w = t.waves, h = +w.height, st = h < .5 ? [T('Calm', 'Tahimik'), L.ok] : h < 1.25 ? [T('Moderate', 'Katamtaman'), '#F5D90A'] : h < 2.5 ? [T('Rough', 'Magaspang'), L.high] : [T('Very rough', 'Napakagaspang'), L.urgent];
      return '<div class="wx-grid2"><div class="wx-card2"><span class="wx-h">' + T('Waves, Manila Bay', 'Alon, Manila Bay') + '</span>' + A.big(num(h, 1) + ' m', st[0], st[1]) + '<div class="wx-waves"><i></i><i></i><i></i></div></div><div class="wx-card2">' + A.kv([[T('Swell', 'Swell'), num(w.swell, 1) + ' m'], [T('Swell period', 'Haba ng swell'), num(w.period) + ' s'], [T('Direction', 'Direksyon'), w.dir != null ? dir8(w.dir) + ' (' + num(w.dir) + '°)' : '–']]) + '<p class="wx-note">' + T('A model, not a marine advisory. Small boats should check PAGASA before going out.', 'Modelo lamang, hindi abisong pandagat. Dapat tingnan ng maliliit na bangka ang PAGASA bago lumabas.') + '</p></div></div>';
    }, src: 'Open-Meteo Marine'
  };

  W.quake = {
    r: function () {
      var q = ok(WS.group('quake')).quakes, top = q.reduce(function (m, x) { return x.mag > m ? x.mag : m; }, 0), col = function (m) { return m >= 6 ? '#8E3FD0' : m >= 5 ? '#E5383B' : m >= 4 ? '#FF9800' : m >= 3.5 ? '#F5D90A' : '#2E9E4F'; };
      if (!q.length) return A.empty('check', T('No quakes of magnitude 3 or more near the Philippines this week', 'Walang lindol na magnitude 3 pataas malapit sa Pilipinas ngayong linggo'));
      return '<div class="wx-row"><div class="wx-big"><b>' + q.length + '</b><span>' + T('quakes, 7 days', 'lindol, 7 araw') + '</span></div><div class="wx-big"><b style="color:' + col(top) + '">M' + top.toFixed(1) + '</b><span>' + T('strongest', 'pinakamalakas') + '</span></div></div><div class="wx-list">' + q.slice(0, 5).map(function (x) { return A.item({ av: x.mag.toFixed(1), c: col(x.mag), t: esc(x.place), s: T(n(x.km) + ' km ' + x.dir + ' of the barangay · depth ' + x.depth_km + ' km', n(x.km) + ' km ' + x.dir + ' ng barangay · lalim ' + x.depth_km + ' km'), r: WS.ago(x.at), href: WS.link(x.url) }); }).join('') + '</div><p class="wx-note">' + T('PHIVOLCS publishes no public feed; this is the USGS list for the Philippine area.', 'Walang pampublikong feed ang PHIVOLCS; ito ang listahan ng USGS para sa Pilipinas.') + '</p>';
    }, src: 'USGS'
  };

  // ---- when the portal's own server is refused by a free weather source (shared hosting addresses sometimes are),
  // the browser asks the same public API itself and shapes the answer exactly as widgets.php does. The sky bar's tile
  // has always been read this way. Marked 'direct' so it is clear where it came from.
  var LAT = 14.5194, LNG = 121.0122, TZ = 'timeZone=Asia%2FManila';
  var get = function (u) { return fetch(u, { cache: 'no-store' }).then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); }); };
  var good = function (d) { return { ok: true, stale: false, at: new Date().toISOString(), data: d, direct: true }; };
  function heatIdx(tc, rh) {
    var t = tc * 9 / 5 + 32, hi = 0.5 * (t + 61 + (t - 68) * 1.2 + rh * 0.094);
    if ((hi + t) / 2 >= 80) {
      hi = -42.379 + 2.04901523 * t + 10.14333127 * rh - 0.22475541 * t * rh - 0.00683783 * t * t - 0.05481717 * rh * rh + 0.00122874 * t * t * rh + 0.00085282 * t * rh * rh - 0.00000199 * t * t * rh * rh;
      if (rh < 13 && t >= 80 && t <= 112) hi -= ((13 - rh) / 4) * Math.sqrt((17 - Math.abs(t - 95)) / 17); else if (rh > 85 && t >= 80 && t <= 87) hi += ((rh - 85) / 10) * ((87 - t) / 5);
    }
    return (hi - 32) * 5 / 9;
  }
  var heatBand = function (c) { c = Math.round(c); return c >= 52 ? 'extreme_danger' : c >= 42 ? 'danger' : c >= 33 ? 'extreme_caution' : c >= 27 ? 'caution' : null; };
  function moonOf(ts) {
    var p = ((ts / 1000 - 947182440) / (29.530588853 * 86400)) % 1; if (p < 0) p += 1;
    var lim = [[0.0339, 'new'], [0.216, 'waxing_crescent'], [0.284, 'first_quarter'], [0.466, 'waxing_gibbous'], [0.534, 'full'], [0.716, 'waning_gibbous'], [0.784, 'last_quarter'], [0.9661, 'waning_crescent'], [1.01, 'new']], name = 'new';
    for (var i = 0; i < lim.length; i++) if (p < lim[i][0]) { name = lim[i][1]; break; }
    return { phase: Math.round(p * 1000) / 1000, lit: Math.round(100 * (1 - Math.cos(2 * Math.PI * p)) / 2), name: name, age_days: Math.round(p * 295.30588853) / 10 };
  }
  var manilaNow = function () { return new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Manila', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }).format(new Date()).replace(' ', 'T'); };
  var fb = WS.fallback = WS.fallback || {};
  fb.wx = function () {
    return get('https://api.open-meteo.com/v1/forecast?latitude=' + LAT + '&longitude=' + LNG + '&' + TZ + '&forecast_days=7&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,pressure_msl,uv_index,is_day&hourly=temperature_2m,relative_humidity_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl,uv_index&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,sunrise,sunset,uv_index_max,wind_gusts_10m_max').then(function (j) {
      var c = j.current, h = j.hourly, d = j.daily, nowS = manilaNow(), start = 0, i;
      for (i = 0; i < h.time.length; i++) if (h.time[i] >= nowS.slice(0, 13) + ':00') { start = i; break; }
      var hours = [], peak = null, today = nowS.slice(0, 10);
      for (i = start; i < Math.min(h.time.length, start + 24); i++) hours.push({ t: h.time[i], temp: h.temperature_2m[i], pop: h.precipitation_probability[i], rain: h.precipitation[i], code: h.weather_code[i], wind: h.wind_speed_10m[i], gust: h.wind_gusts_10m[i], dir: h.wind_direction_10m[i], pressure: h.pressure_msl[i], uv: h.uv_index[i], heat: Math.round(heatIdx(h.temperature_2m[i], h.relative_humidity_2m[i])) });
      for (i = start; i < h.time.length; i++) { if (h.time[i].slice(0, 10) !== today) continue; var hv = heatIdx(h.temperature_2m[i], h.relative_humidity_2m[i]); if (!peak || hv > peak.c) peak = { c: Math.round(hv), at: h.time[i], band: heatBand(hv) }; }
      var days = d.time.map(function (t, k) { return { d: t, code: d.weather_code[k], max: d.temperature_2m_max[k], min: d.temperature_2m_min[k], rain: d.precipitation_sum[k], pop: d.precipitation_probability_max[k], sunrise: d.sunrise[k], sunset: d.sunset[k], uv: d.uv_index_max[k], gust: d.wind_gusts_10m_max[k] }; });
      var hn = heatIdx(c.temperature_2m, c.relative_humidity_2m), set = new Date(days[0].sunset + ':00+08:00');
      return good({ now: { temp: c.temperature_2m, feels: c.apparent_temperature, humidity: c.relative_humidity_2m, rain: c.precipitation, code: c.weather_code, wind: c.wind_speed_10m, dir: c.wind_direction_10m, gust: c.wind_gusts_10m, pressure: c.pressure_msl, uv: c.uv_index, day: !!c.is_day, at: c.time }, heat: { c: Math.round(hn), band: heatBand(hn), peak: peak }, pressure_3h: start >= 3 ? Math.round((h.pressure_msl[start] - h.pressure_msl[start - 3]) * 10) / 10 : null, hours: hours, days: days, moon: moonOf(Date.now()), daylight_left_min: set > new Date() ? Math.round((set - new Date()) / 60000) : 0, source: 'Open-Meteo' });
    });
  };
  fb.air = function () {
    return get('https://air-quality-api.open-meteo.com/v1/air-quality?latitude=' + LAT + '&longitude=' + LNG + '&' + TZ + '&current=us_aqi,pm2_5,pm10,nitrogen_dioxide,ozone,carbon_monoxide').then(function (j) {
      var c = j.current, a = +c.us_aqi; c.band = a <= 50 ? 'good' : a <= 100 ? 'moderate' : a <= 150 ? 'sensitive' : a <= 200 ? 'unhealthy' : a <= 300 ? 'very_unhealthy' : 'hazardous'; c.source = 'Open-Meteo (CAMS)'; return good(c);
    });
  };
  fb.marine = function () {
    return get('https://marine-api.open-meteo.com/v1/marine?latitude=14.53&longitude=120.96&' + TZ + '&forecast_days=3&hourly=sea_level_height_msl,wave_height,swell_wave_height,swell_wave_period,wave_direction').then(function (j) {
      var h = j.hourly, now = manilaNow().slice(0, 13) + ':00', i0 = 0, lv = h.sea_level_height_msl, turns = [], curve = [], i;
      for (i = 0; i < h.time.length; i++) if (h.time[i] <= now) i0 = i;
      for (i = Math.max(1, i0); i < Math.min(lv.length - 1, i0 + 36); i++) { if (lv[i] == null || lv[i - 1] == null || lv[i + 1] == null) continue; if (lv[i] > lv[i - 1] && lv[i] >= lv[i + 1]) turns.push({ kind: 'high', t: h.time[i], m: lv[i] }); if (lv[i] < lv[i - 1] && lv[i] <= lv[i + 1]) turns.push({ kind: 'low', t: h.time[i], m: lv[i] }); }
      for (i = i0; i < Math.min(lv.length, i0 + 24); i++) curve.push({ t: h.time[i], m: lv[i] });
      return good({ level: lv[i0], rising: lv[i0 + 1] > lv[i0], turns: turns.slice(0, 4), curve: curve, waves: { height: h.wave_height[i0], swell: h.swell_wave_height[i0], period: h.swell_wave_period[i0], dir: h.wave_direction[i0] }, model: true, source: 'Open-Meteo Marine' });
    });
  };
  fb.quake = function () {
    var from = new Date(Date.now() - 7 * 864e5).toISOString().slice(0, 19);
    return get('https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&starttime=' + from + '&minmagnitude=3&minlatitude=4&maxlatitude=21.5&minlongitude=116&maxlongitude=127&orderby=time&limit=30').then(function (j) {
      var rad = Math.PI / 180, km = function (la, lo) { var a = Math.sin((la - LAT) * rad / 2) ** 2 + Math.cos(LAT * rad) * Math.cos(la * rad) * Math.sin((lo - LNG) * rad / 2) ** 2; return 2 * 6371 * Math.asin(Math.min(1, Math.sqrt(a))); };
      var dir = function (la, lo) { var y = Math.sin((lo - LNG) * rad) * Math.cos(la * rad), x = Math.cos(LAT * rad) * Math.sin(la * rad) - Math.sin(LAT * rad) * Math.cos(la * rad) * Math.cos((lo - LNG) * rad); return DIRS[Math.round(((Math.atan2(y, x) / rad + 360) % 360) / 45) % 8]; };
      return good({ quakes: j.features.map(function (f) { var p = f.properties, g = f.geometry.coordinates; return { mag: Math.round(p.mag * 10) / 10, place: p.place || '', at: new Date(p.time).toISOString(), depth_km: Math.round(g[2]), km: Math.round(km(g[1], g[0])), dir: dir(g[1], g[0]), lat: g[1], lng: g[0], url: /^https:\/\/earthquake\.usgs\.gov\//.test(p.url || '') ? p.url : '' }; }), source: 'USGS' });
    });
  };
})();
