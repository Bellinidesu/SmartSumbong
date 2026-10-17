// The Workspace widgets: the engine (17 Oct 2026). A slim rail of the widgets a person chose, the pane of the one open,
// the library to choose them, and the alarm. The widgets themselves live in widgets-*.js, loaded the first time one of
// their kind is opened. Everything outside comes through widgets.php; nothing here calls another site.
(function () {
  'use strict';
  var C = window.SS_WS, root = document.getElementById('wsx');
  if (!C || !root) return;
  var WS = window.WS = { w: {}, a: {}, ic: {}, mods: {}, C: C };
  var fil = C.lang === 'fil', reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  var T = WS.T = function (en, tl) { return fil ? tl : en; };
  var S = WS.S = { tabs: C.tabs.slice(), tab: C.tab, data: {}, at: {}, err: {}, st: C.settings || null, lead: !!C.lead, dismissed: [], firing: [], busy2: new Set() };
  try { var dj = JSON.parse(sessionStorage.getItem('wsx-dismissed') || '[]'); S.dismissed = Array.isArray(dj) ? dj.filter(function (x) { return typeof x === 'string'; }).slice(-50) : []; } catch (e) {}

  // ---- small helpers every widget uses
  var esc = WS.esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  var nf = new Intl.NumberFormat(fil ? 'fil-PH' : 'en-PH');
  WS.n = function (v) { return v == null || isNaN(v) ? '–' : nf.format(v); };
  var tzf = function (o) { return new Intl.DateTimeFormat(fil ? 'fil-PH' : 'en-PH', Object.assign({ timeZone: 'Asia/Manila' }, o)); };
  var fT = tzf({ hour: 'numeric', minute: '2-digit' }), fD = tzf({ month: 'short', day: 'numeric' }), fW = tzf({ weekday: 'short' }), fWL = tzf({ weekday: 'long' }), fDT = tzf({ month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
  WS.fmt = { time: function (d) { return fT.format(new Date(d)); }, day: function (d) { return fD.format(new Date(d)); }, wd: function (d) { return fW.format(new Date(d)); }, wdl: function (d) { return fWL.format(new Date(d)); }, dt: function (d) { return fDT.format(new Date(d)); } };
  WS.ago = function (d) {
    var s = Math.max(0, (Date.now() - new Date(d).getTime()) / 1000);
    if (s < 90) return T('just now', 'ngayon lang');
    if (s < 3600) return Math.round(s / 60) + T(' min ago', ' min ang nakalipas');
    if (s < 86400) return Math.round(s / 3600) + T(' h ago', ' oras ang nakalipas');
    return Math.round(s / 86400) + T(' d ago', ' araw ang nakalipas');
  };
  WS.until = function (d) {
    var s = (new Date(d).getTime() - Date.now()) / 1000, a = Math.abs(s), u = a < 5400 ? Math.round(a / 60) + ' min' : a < 172800 ? Math.round(a / 3600) + ' h' : Math.round(a / 86400) + T(' d', ' araw');
    return s < 0 ? u + T(' overdue', ' lampas') : u + T(' left', ' natitira');
  };
  WS.name = function (n) { n = String(n == null ? '' : n); var c = n.indexOf(','); return c > 0 ? n.slice(c + 1).trim() + ' ' + n.slice(0, c).trim() : n; };
  WS.initials = function (n) { var p = WS.name(n).split(/\s+/).filter(Boolean); return ((p[0] || '')[0] || '?') + ((p.length > 1 ? p[p.length - 1][0] : '') || ''); };
  WS.lvl = { urgent: '#E5383B', high: '#FF9800', normal: '#356CF9', low: '#8E9ABB', ok: '#2E9E4F', purple: '#8E3FD0', amber: '#F5A524' };
  WS.catName = function (c) { return ({ street_obstruction: T('Street obstruction', 'Nakaharang sa kalsada'), public_safety_infrastructure: T('Public safety', 'Kaligtasan ng publiko'), environmental_waste_hazard: T('Environment and waste', 'Kapaligiran at basura'), animal_welfare: T('Animal welfare', 'Kapakanan ng hayop'), traffic_violation: T('Traffic', 'Trapiko'), barangay_service: T('Barangay service', 'Serbisyo ng barangay'), peace_order_nuisance: T('Peace and order', 'Kapayapaan at kaayusan'), other: T('Other', 'Iba pa') })[c] || String(c || ''); };
  WS.catColor = function (c) { return ({ street_obstruction: '#FF9800', public_safety_infrastructure: '#E5383B', environmental_waste_hazard: '#2E9E4F', animal_welfare: '#B7791F', traffic_violation: '#356CF9', barangay_service: '#00A5B5', peace_order_nuisance: '#8E3FD0', other: '#8E9ABB' })[c] || '#8E9ABB'; };
  WS.link = function (u) { return /^https?:\/\//i.test(u || '') ? u : ''; };

  // ---- icons (24x24, stroke): one per kind of widget
  var P = {
    brain: 'M9 4a3 3 0 0 0-3 3 3 3 0 0 0-2 2.8A3 3 0 0 0 5.4 13 3 3 0 0 0 7 18a3 3 0 0 0 5-1.2V5.5A2.5 2.5 0 0 0 9 4zM15 4a3 3 0 0 1 3 3 3 3 0 0 1 2 2.8 3 3 0 0 1-1.4 3.2A3 3 0 0 1 17 18a3 3 0 0 1-5-1.2',
    drop: 'M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z', storm: 'M12 12m-2 0a2 2 0 1 0 4 0 2 2 0 1 0-4 0M12 2c4 0 7 3 5 6M22 12c0 4-3 7-6 5M12 22c-4 0-7-3-5-6M2 12c0-4 3-7 6-5',
    cloud: 'M7 18a4 4 0 1 1 .7-7.9A5.5 5.5 0 0 1 18.5 11 3.5 3.5 0 0 1 18 18z', sun: 'M12 12m-4 0a4 4 0 1 0 8 0 4 4 0 1 0-8 0M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M19 5l-1.5 1.5M6.5 17.5L5 19',
    pin: 'M12 22s7-6.5 7-12a7 7 0 0 0-14 0c0 5.5 7 12 7 12zM12 10m-2.5 0a2.5 2.5 0 1 0 5 0 2.5 2.5 0 1 0-5 0', list: 'M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01',
    clock: 'M12 12m-9 0a9 9 0 1 0 18 0 9 9 0 1 0-18 0M12 7v5l3 2', chart: 'M4 20V10M10 20V4M16 20v-7M22 20H2', ring: 'M12 12m-9 0a9 9 0 1 0 18 0 9 9 0 1 0-18 0M12 3a9 9 0 0 1 9 9',
    pulse: 'M3 12h4l3-8 4 16 3-8h4', people: 'M9 8m-3.5 0a3.5 3.5 0 1 0 7 0 3.5 3.5 0 1 0-7 0M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M18 14.5a6.5 6.5 0 0 1 3.5 5.5',
    note: 'M5 3h14v12l-6 6H5zM13 21v-6h6', tool: 'M14.5 6.5a4 4 0 0 0 5 5L10 21a2.1 2.1 0 0 1-3-3z', search: 'M11 11m-6.5 0a6.5 6.5 0 1 0 13 0 6.5 6.5 0 1 0-13 0M16 16l5 5',
    wave: 'M2 12c3-4 5-4 8 0s5 4 8 0M2 18c3-4 5-4 8 0s5 4 8 0M2 6c3-4 5-4 8 0s5 4 8 0', wind: 'M3 8h11a3 3 0 1 0-3-3M3 16h15a3 3 0 1 1-3 3M3 12h8',
    temp: 'M14 14.8V5a2 2 0 0 0-4 0v9.8a4 4 0 1 0 4 0z', moon: 'M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z', quake: 'M2 12h3l2-6 3 12 3-9 2 3h7', rss: 'M5 5a14 14 0 0 1 14 14M5 11a8 8 0 0 1 8 8M6 19m-1 0a1 1 0 1 0 2 0 1 1 0 1 0-2 0',
    news: 'M4 5h13v14H6a2 2 0 0 1-2-2zM17 9h3v8a2 2 0 0 1-2 2M7 9h7M7 13h7', fuel: 'M5 21V5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v16M3 21h14M15 9h2a2 2 0 0 1 2 2v5a1.5 1.5 0 0 0 3 0V8l-3-3',
    cal: 'M5 5h14a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1zM4 10h16M8 3v4M16 3v4', phone: 'M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A15 15 0 0 1 3 6a2 2 0 0 1 2-2z',
    game: 'M6 9h12a4 4 0 0 1 4 4v1a3 3 0 0 1-5.2 2L15 14H9l-1.8 2A3 3 0 0 1 2 14v-1a4 4 0 0 1 4-4zM8 11v3M6.500 12.500h3M16 12h.01M18 13.500h.01', dice: 'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM8 8h.01M16 8h.01M12 12h.01M8 16h.01M16 16h.01',
    heart: 'M12 21s-8-5.5-8-11a4.5 4.5 0 0 1 8-2.8A4.5 4.5 0 0 1 20 10c0 5.5-8 11-8 11z', check: 'M5 12.5l4.5 4.5L19 7.500', star: 'M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.100L12 17l-5.4 2.900 1-6.100L3.200 9.500l6.100-.9z',
    shield: 'M12 3l8 3v6c0 5-3.500 8-8 9-4.500-1-8-4-8-9V6z', qr: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h3v3h-3zM20 14v.01M14 20h.01M17 20h3v-3', camera: 'M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1zM12 13m-3.500 0a3.500 3.500 0 1 0 7 0 3.500 3.500 0 1 0-7 0',
    bell: 'M6 16V11a6 6 0 0 1 12 0v5l2 2H4zM10 21a2 2 0 0 0 4 0', flag: 'M5 21V4M5 4h11l-2 4 2 4H5', map: 'M3 6l6-2 6 2 6-2v14l-6 2-6-2-6 2zM9 4v14M15 6v14', bolt: 'M13 2L4 14h6l-1 8 9-12h-6z',
    battery: 'M3 8h15a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1zM21 11v2M5 10.500v3', compass: 'M12 12m-9 0a9 9 0 1 0 18 0 9 9 0 1 0-18 0M15.500 8.500l-2 5-5 2 2-5z', plus: 'M12 5v14M5 12h14', cross: 'M6 6l12 12M18 6L6 18',
    up: 'M6 15l6-6 6 6', down: 'M6 9l6 6 6-6', grid: 'M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z', gear: 'M12 12m-3 0a3 3 0 1 0 6 0 3 3 0 1 0-6 0M19 12a7 7 0 0 0-.1-1.2l2-1.5-2-3.400-2.300.9a7 7 0 0 0-2-1.200L14 3h-4l-.6 2.600a7 7 0 0 0-2 1.200l-2.300-.9-2 3.400 2 1.500a7 7 0 0 0 0 2.400l-2 1.500 2 3.400 2.300-.9a7 7 0 0 0 2 1.200L10 21h4l.6-2.600a7 7 0 0 0 2-1.200l2.300.9 2-3.400-2-1.500c.1-.4.1-.8.1-1.200z',
    eye: 'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12zM12 12m-3 0a3 3 0 1 0 6 0 3 3 0 1 0-6 0',
    refresh: 'M20 11a8 8 0 0 0-14-4L4 9M4 4v5h5M4 13a8 8 0 0 0 14 4l2-2M20 20v-5h-5', warn: 'M12 3l10 18H2zM12 10v5M12 18v.01',
    book: 'M5 4h10a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3zM5 17a3 3 0 0 1 3-3h10', text: 'M5 6h14M12 6v13M9 19h6', ball: 'M12 12m-9 0a9 9 0 1 0 18 0 9 9 0 1 0-18 0M12 8m-2 0a2 2 0 1 0 4 0 2 2 0 1 0-4 0', coin: 'M12 12m-9 0a9 9 0 1 0 18 0 9 9 0 1 0-18 0M12 7v10M9 9.500c0-1 1-1.500 3-1.500s3 .7 3 1.700-1 1.300-3 1.800-3 .8-3 1.800S10 15 12 15s3-.5 3-1.500',
    key: 'M8 14a4 4 0 1 1 3.900-4.800L21 10v3h-2v2h-3v-2.500h-3.100A4 4 0 0 1 8 14z', link: 'M10 14a4 4 0 0 0 5.700 0l3-3a4 4 0 0 0-5.700-5.700L12 6.300M14 10a4 4 0 0 0-5.700 0l-3 3a4 4 0 0 0 5.700 5.700L12 17.700', mood: 'M12 12m-9 0a9 9 0 1 0 18 0 9 9 0 1 0-18 0M8 14.500a5 5 0 0 0 8 0M9 9.500h.01M15 9.500h.01'
  };
  var IC = { brief: 'brain', flood: 'drop', ty: 'storm', wx: 'cloud', heat: 'temp', quake: 'quake', aq: 'wind', tide: 'wave', sun: 'sun', news: 'news', fuel: 'fuel', uv: 'sun', wind: 'wind', hourly: 'clock', week: 'cal', press: 'pulse', sea: 'wave',
    risk: 'pin', queue: 'list', due: 'clock', rec: 'refresh', mix: 'ring', pace: 'pulse', street: 'map', eff: 'chart', minimap: 'map', recent: 'list', photos: 'camera', search: 'search', trend: 'chart', hours: 'clock', status: 'chart', sla: 'check', escal: 'up', today: 'check',
    duty: 'people', req: 'bell', dir: 'phone', note: 'note', shift: 'note', board: 'note', attend: 'check', bday: 'star', poll: 'chart', checkpt: 'flag', roster: 'cal', leave: 'people', train: 'shield', bull: 'bell',
    evac: 'shield', hot: 'phone', links: 'link', timer: 'clock', cal: 'cal', law: 'book', siren: 'bell', sms: 'note', qr: 'qr', forms: 'tool', hol: 'cal', maps: 'map', donate: 'heart',
    calc: 'grid', clock: 'clock', torch: 'bolt', compass: 'compass', convert: 'tool', dice: 'dice', coin: 'coin', pick: 'people', cpr: 'heart', fare: 'coin', battery: 'battery', quote: 'text', talk: 'text', code: 'text', aid: 'heart', stopw: 'clock', world: 'wave', rand: 'dice', pw: 'key', ball: 'ball', joke: 'mood', fact: 'book', tip: 'coin',
    rss: 'rss', rssmix: 'rss', rsskey: 'search', rsswater: 'drop', rsspower: 'bolt', rssphilstar: 'news', rssrappler: 'news', rssgma: 'news', rssgdacs: 'storm', rsswho: 'heart', rssusgs: 'quake', rsspna: 'news',
    ttt: 'game', mem: 'game', react: 'bolt', whack: 'game', hl: 'game', rps: 'game', snake: 'game', g2048: 'grid', wordl: 'text', sudoku: 'grid', mines: 'game', quiz: 'book', simon: 'game', type: 'text',
    todo: 'check', sticky: 'note', count: 'clock', water: 'drop', mood: 'mood', goal: 'flag', mantra: 'text', habit: 'check', shiftn: 'note' };
  WS.svg = function (name, size, w) { return '<svg viewBox="0 0 24 24" width="' + (size || 20) + '" height="' + (size || 20) + '" fill="none" stroke="currentColor" stroke-width="' + (w || 1.8) + '" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' + (P[name] || P.grid) + '"/></svg>'; };
  WS.icon = function (id, size) { return WS.svg(IC[id] || 'grid', size); };
  WS.name_of = function (id) { return (C.labels[id] || [id])[0]; };

  // ---- the atoms: every widget is made of these, so they all look like one family
  var A = WS.a;
  A.big = function (v, label, color, n) { return '<div class="wx-big"' + (color ? ' style="--c:' + color + '"' : '') + '><b' + (n != null ? ' data-n="' + n + '"' : '') + '>' + v + '</b><span>' + label + '</span></div>'; };
  A.kv = function (rows) { return '<div class="wx-kv">' + rows.map(function (r) { return '<div><span>' + r[0] + '</span><b>' + r[1] + '</b></div>'; }).join('') + '</div>'; };
  A.pill = function (t, c) { return '<span class="wx-pill" style="--c:' + (c || '#8E9ABB') + '">' + t + '</span>'; };
  A.bar = function (p, c, h) { return '<div class="wx-bar" style="--c:' + (c || 'var(--p-orange)') + (h ? ';--h:' + h + 'px' : '') + '"><i style="--p:' + Math.max(0, Math.min(100, p)) + '%"></i></div>'; };
  A.empty = function (ic, t, sub) { return '<div class="wx-empty">' + WS.svg(ic || 'check', 30, 1.5) + '<b>' + t + '</b>' + (sub ? '<span>' + sub + '</span>' : '') + '</div>'; };
  A.chips = function (l) { return '<div class="wx-chips">' + l.join('') + '</div>'; };
  A.item = function (o) {
    var tag = o.href ? 'a' : 'div', att = o.href ? ' href="' + esc(o.href) + '"' + (/^https?:/.test(o.href) ? ' target="_blank" rel="noopener noreferrer"' : '') : '';
    return '<' + tag + ' class="wx-item' + (o.href ? ' is-link' : '') + '"' + att + ' style="--c:' + (o.c || '#356CF9') + '"><span class="wx-av' + (o.sq ? ' sq' : '') + '">' + (o.av || '') + '</span><span class="wx-it"><b>' + (o.t || '') + '</b>' + (o.s ? '<small>' + o.s + '</small>' : '') + '</span>' + (o.r ? '<span class="wx-r">' + o.r + '</span>' : '') + '</' + tag + '>';
  };
  A.btn = function (label, act, o) { o = o || {}; return '<button type="button" class="wx-btn' + (o.p ? ' is-pri' : '') + '"' + (o.a ? ' data-a="' + o.a + '"' : '') + (act ? ' data-act="' + act + '"' : '') + (o.d ? ' ' + o.d : '') + '>' + label + '</button>'; };
  A.ring = function (p, c, mid, sub) {
    var r = 42, L = 2 * Math.PI * r, v = Math.max(0, Math.min(100, p));
    return '<div class="wx-ring" style="--c:' + c + '"><svg viewBox="0 0 100 100" aria-hidden="true"><circle cx="50" cy="50" r="' + r + '" class="t"/><circle cx="50" cy="50" r="' + r + '" class="v" style="stroke-dasharray:' + L.toFixed(1) + ';--off:' + (L * (1 - v / 100)).toFixed(1) + ';--len:' + L.toFixed(1) + '" transform="rotate(-90 50 50)"/></svg><div><b>' + mid + '</b>' + (sub ? '<span>' + sub + '</span>' : '') + '</div></div>';
  };
  A.spark = function (vals, c, o) {
    o = o || {}; var W = 240, H = o.h || 64, v = vals.filter(function (x) { return x != null; }), mx = Math.max.apply(null, v.concat([o.max || 0.0001])), mn = o.min != null ? o.min : Math.min.apply(null, v.concat([0])), n = vals.length;
    var X = function (i) { return n < 2 ? W / 2 : 4 + i * (W - 8) / (n - 1); }, Y = function (x) { return H - 6 - (x - mn) / ((mx - mn) || 1) * (H - 14); };
    var pts = [], area = '', last = null;
    vals.forEach(function (x, i) { if (x == null) return; pts.push(X(i).toFixed(1) + ',' + Y(x).toFixed(1)); last = [X(i), Y(x)]; });
    if (!pts.length) return '';
    area = 'M' + pts[0] + ' L' + pts.join(' L') + ' L' + X(vals.length - 1).toFixed(1) + ',' + (H - 2) + ' L' + X(0).toFixed(1) + ',' + (H - 2) + 'Z';
    return '<svg class="wx-spark" viewBox="0 0 ' + W + ' ' + H + '" style="--c:' + c + ';height:' + H + 'px" preserveAspectRatio="none" aria-hidden="true"><path class="a" d="' + area + '"/><polyline class="l" points="' + pts.join(' ') + '"/>' + (last ? '<circle cx="' + last[0].toFixed(1) + '" cy="' + last[1].toFixed(1) + '" r="3.4"/>' : '') + '</svg>';
  };
  A.bars = function (vals, c, o) {
    o = o || {}; var W = 240, H = o.h || 64, mx = Math.max.apply(null, vals.concat([o.max || 1])), n = vals.length, bw = W / n;
    return '<svg class="wx-bars" viewBox="0 0 ' + W + ' ' + H + '" style="--c:' + c + ';height:' + H + 'px" preserveAspectRatio="none" aria-hidden="true">' + vals.map(function (x, i) { var h = Math.max(x ? 3 : 1.5, x / mx * (H - 4)); return '<rect x="' + (i * bw + 1.5).toFixed(1) + '" y="' + (H - h).toFixed(1) + '" width="' + (bw - 3).toFixed(1) + '" height="' + h.toFixed(1) + '" rx="2.5"' + (o.hi === i ? ' class="hi"' : '') + ' style="--d:' + (i * 14) + 'ms"/>'; }).join('') + '</svg>';
  };
  A.ago = function (at, stale) { return at ? '<span class="wx-ago' + (stale ? ' is-old' : '') + '">' + (stale ? T('older reading · ', 'lumang basa · ') : '') + WS.ago(at) + '</span>' : ''; };
  A.src = function (s) { return '<span class="wx-src">' + esc(s) + '</span>'; };

  // ---- talking to the portal
  function url(q) { return 'widgets.php?' + q; }
  function post(data) {
    var b = new URLSearchParams(); b.append('csrf', C.csrf); Object.keys(data).forEach(function (k) { b.append(k, data[k]); });
    return fetch('workspace-act.php', { method: 'POST', body: b, credentials: 'same-origin' }).then(function (r) { return r.json().catch(function () { return { error: T('That did not work. Try again.', 'Hindi gumana. Subukan muli.') }; }); });
  }
  WS.post = post;
  WS.toast = function (msg, bad) {
    var t = document.getElementById('wsx-toast');
    if (!t) { t = document.createElement('div'); t.id = 'wsx-toast'; t.setAttribute('role', 'status'); t.setAttribute('aria-live', 'polite'); document.body.appendChild(t); }
    t.textContent = msg; t.className = 'wx-toast on' + (bad ? ' bad' : ''); clearTimeout(t._t); t._t = setTimeout(function () { t.className = 'wx-toast'; }, 3200);
  };
  function groupsFor(id) { return (C.cat[id] && C.cat[id].n) || []; }
  WS.fetch = function (ids, extra, force) {
    var q = 'w=' + encodeURIComponent(ids.join(',')) + (extra && extra.length ? '&g=' + extra.join(',') : '');
    return fetch(url(q), { credentials: 'same-origin', cache: 'no-store' }).then(function (r) {
      if (r.status === 401) { location.href = 'login.php?expired=1'; throw 0; }
      return r.json();
    }).then(function (j) {
      var now = Date.now(), jobs = [];
      Object.keys(j.groups || {}).forEach(function (g) { S.data[g] = j.groups[g]; S.at[g] = now; if (!j.groups[g].ok && WS.fallback && WS.fallback[g]) jobs.push(WS.fallback[g]().then(function (r) { if (r && r.ok) { S.data[g] = r; S.at[g] = Date.now(); } }).catch(function () {})); });
      return Promise.all(jobs).then(function () { return j; });
    });
  };
  WS.group = function (g) { return S.data[g] || null; };
  WS.mod = function (name, cb) {
    var m = WS.mods[name];
    if (m === true) return cb();
    if (m) return m.push(cb);
    WS.mods[name] = [cb];
    var s = document.createElement('script'); s.src = C.mods[name]; s.onload = function () { var q = WS.mods[name]; WS.mods[name] = true; q.forEach(function (f) { f(); }); };
    s.onerror = function () { var q = WS.mods[name]; delete WS.mods[name]; q.forEach(function (f) { f(true); }); };
    document.head.appendChild(s);
  };

  // ---- saving what a person chose
  var saveT = null, mineT = null;
  function saveTabs() { if (C.solo) return; clearTimeout(saveT); saveT = setTimeout(function () { post({ action: 'prefs', tabs: S.tabs.join(','), tab: S.tab || '' }); }, 500); }
  var mine = C.mine && typeof C.mine === 'object' && !Array.isArray(C.mine) ? C.mine : {};
  WS.mine = {
    get: function (k, d) { return mine[k] == null ? d : mine[k]; },
    set: function (k, v) { mine[k] = v; clearTimeout(mineT); mineT = setTimeout(function () { var s = JSON.stringify(mine); if (s.length > 30000) { WS.toast(T('Your notes are too long to save.', 'Masyadong mahaba ang mga tala mo para i-save.'), true); return; } post({ action: 'mine', mine: s }); }, 700); }
  };
  WS.score = function (game, score) {
    return post({ action: 'score', game: game, score: score }).then(function (r) { if (r.ok && r.new_best) WS.toast(T('New best!', 'Bagong pinakamataas!')); else if (r.error) WS.toast(r.error, true); return r; });
  };

  // ---- the rail and the pane
  var rail = root.querySelector('.wx-rail-list'), pane = root.querySelector('.wx-pane'), titleEl = root.querySelector('.wx-ptitle'), agoEl = root.querySelector('.wx-pago'), foot = root.querySelector('.wx-foot-src');
  var timers = [], after = [];
  WS.timer = function (fn, ms) { var t = setInterval(fn, ms); timers.push(t); return t; };
  WS.after = function (fn) { after.push(fn); };
  function dotFor(id) {
    var b = S.data.brief && S.data.brief.ok ? S.data.brief.data : null, h = S.data.hazards && S.data.hazards.ok ? S.data.hazards.data : null;
    if (id === 'flood' && h) { var lv = 0; (h.warnings || []).forEach(function (w) { if (w.metro) lv = Math.max(lv, w.level); }); return lv ? ['#FFD23F', '#FF9800', '#E5383B'][lv - 1] : null; }
    if (id === 'ty' && h && h.cyclone) return (h.cyclone.signal || 0) >= 3 ? '#E5383B' : WS.lvl.purple;
    if (id === 'queue' && b) return b.urgent_waiting > 0 ? WS.lvl.urgent : (b.high_waiting > 0 ? WS.lvl.high : null);
    if (id === 'due' && b) return b.overdue > 0 ? WS.lvl.urgent : null;
    if (id === 'brief' && b) return (b.urgent_waiting + b.high_waiting) > 0 ? WS.lvl.high : null;
    return null;
  }
  function drawRail() {
    rail.innerHTML = S.tabs.map(function (id) {
      var on = id === S.tab, d = dotFor(id);
      id = esc(id);
      return '<button type="button" role="tab" id="wxt-' + id + '" data-id="' + id + '" aria-selected="' + on + '" aria-controls="wxp" tabindex="' + (on ? 0 : -1) + '" title="' + esc(WS.name_of(id)) + '">' + WS.icon(id, 21) + '<span>' + esc(WS.name_of(id)) + '</span>' + (d ? '<i class="wx-dot" style="--c:' + d + '"></i>' : '') + '</button>';
    }).join('');
    var cur = rail.querySelector('[aria-selected="true"]'); if (cur && cur.scrollIntoView && !reduce) { try { cur.scrollIntoView({ block: 'nearest' }); } catch (e) {} }
  }
  function whyOf(gs) { for (var i = 0; i < gs.length; i++) { var d = S.data[gs[i]]; if (d && d.why) return d.why; } return ''; }
  function skeleton() { return '<div class="wx-skel" aria-hidden="true"><i></i><i></i><i></i></div>'; }
  function needsOf(id) { return groupsFor(id); }
  function paint(force) {
    var id = S.tab, def = WS.w[id];
    timers.forEach(clearInterval); timers = []; after = [];
    pane.setAttribute('aria-labelledby', 'wxt-' + id); titleEl.textContent = WS.name_of(id);
    root.dataset.w = id;
    if (!def) { pane.innerHTML = skeleton(); return; }
    var needs = needsOf(id), bad = needs.filter(function (g) { return !S.data[g] || !S.data[g].ok; });
    var optional = def.opt || [];
    bad = bad.filter(function (g) { return optional.indexOf(g) < 0; });
    var html;
    if (bad.length) {
      html = S.busy2.has(id) ? skeleton() : '<div class="wx-empty is-bad">' + WS.svg('warn', 30, 1.5) + '<b>' + T('This could not be read right now', 'Hindi mabasa ito sa ngayon') + '</b><span>' + T('The source did not answer. It will try again by itself.', 'Hindi sumagot ang pinagkukunan. Susubukan itong muli nang kusa.') + (whyOf(bad) ? ' (' + esc(whyOf(bad)) + ')' : '') + '</span>' + A.btn(WS.svg('refresh', 15) + T('Try again', 'Subukan muli'), 'refresh') + '</div>';
    } else {
      try { html = def.r({ D: S.data, S: S, id: id }); } catch (e) { html = '<div class="wx-empty is-bad">' + WS.svg('warn', 30, 1.5) + '<b>' + T('This widget hit a problem', 'May problema ang widget na ito') + '</b></div>'; if (window.console) console.error(e); }
    }
    pane.innerHTML = '<div class="wx-body">' + html + '</div>';
    Array.prototype.forEach.call(pane.querySelectorAll('.wx-body > *'), function (el, i) { el.style.setProperty('--i', Math.min(i, 8)); });
    var stale = needs.some(function (g) { return S.data[g] && S.data[g].stale; }), at = needs.length && S.data[needs[0]] ? S.data[needs[0]].at : null;
    agoEl.innerHTML = at ? A.ago(at, stale) : '';
    var srcs = [];
    needs.forEach(function (g) { var d = S.data[g]; if (d && d.ok && d.data && d.data.source && srcs.indexOf(d.data.source) < 0) srcs.push(d.data.source); });
    foot.textContent = def.src || srcs.join(' · ');
    if (!bad.length) {
      if (def.i) { try { def.i(pane, { D: S.data, S: S, id: id }); } catch (e) { if (window.console) console.error(e); } }
      after.forEach(function (f) { f(); });
      Array.prototype.forEach.call(pane.querySelectorAll('[data-n]'), function (el) {
        var to = parseFloat(el.dataset.n); if (isNaN(to)) return; if (reduce) { el.textContent = WS.n(to); return; }
        var t0 = performance.now(), dec = el.dataset.dec ? +el.dataset.dec : 0;
        (function f(t) { var k = Math.min(1, (t - t0) / 650), e = 1 - Math.pow(1 - k, 3), v = to * e; el.textContent = dec ? v.toFixed(dec) : WS.n(Math.round(v)); if (k < 1) requestAnimationFrame(f); }(t0));
      });
    }
  }
  WS.paint = paint;
  function load(id, force) {
    var def = WS.w[id], g = groupsFor(id);
    var ok = g.every(function (x) { return S.data[x] && S.data[x].ok && Date.now() - S.at[x] < 45000; });
    if (def && (ok && !force)) { paint(); return; }
    if (!g.length) { if (def) paint(); return; }
    S.busy2.add(id); if (!def || !(g.every(function (x) { return S.data[x] && S.data[x].ok; }))) paint();
    WS.fetch([id], []).catch(function () {}).then(function () { S.busy2.delete(id); if (S.tab === id) paint(); drawRail(); });
  }
  function ensure(id, then) {
    var m = C.cat[id] && C.cat[id].m;
    if (!m || WS.w[id]) return then();
    WS.mod(m, function (err) { if (err) { pane.innerHTML = '<div class="wx-empty is-bad">' + WS.svg('warn', 30, 1.5) + '<b>' + T('This widget could not load', 'Hindi ma-load ang widget na ito') + '</b>' + A.btn(T('Try again', 'Subukan muli'), 'refresh') + '</div>'; return; } then(); });
  }
  function open(id, focus) {
    if (S.tabs.indexOf(id) < 0) return;
    S.tab = id; drawRail(); pane.innerHTML = skeleton(); titleEl.textContent = WS.name_of(id);
    ensure(id, function () { if (S.tab === id) load(id); });
    saveTabs();
    if (focus) { var b = rail.querySelector('[data-id="' + id + '"]'); if (b) b.focus(); }
  }
  WS.open = open;
  WS.rerender = function () { paint(); };
  WS.refresh = function () { load(S.tab, true); };

  var xp = document.getElementById('ss-xp');
  if (xp) xp.classList.add('is-open');
  if (xp) xp.addEventListener('click', function () { var f = root.classList.toggle('is-folded'); xp.setAttribute('aria-expanded', String(!f)); xp.classList.toggle('is-open', !f); try { localStorage.setItem('wsx-folded', f ? '1' : '0'); } catch (x) {} });
  rail.addEventListener('click', function (e) { var b = e.target.closest('[data-id]'); if (b) open(b.dataset.id); });
  rail.addEventListener('keydown', function (e) {
    var i = S.tabs.indexOf(S.tab), n = S.tabs.length, k = e.key;
    var to = k === 'ArrowDown' || k === 'ArrowRight' ? (i + 1) % n : k === 'ArrowUp' || k === 'ArrowLeft' ? (i - 1 + n) % n : k === 'Home' ? 0 : k === 'End' ? n - 1 : -1;
    if (to >= 0) { e.preventDefault(); open(S.tabs[to], true); }
  });
  root.addEventListener('click', function (e) {
    var b = e.target.closest('[data-act]'); if (!b) return;
    var a = b.dataset.act;
    if (a === 'refresh') { WS.refresh(); }
    else if (a === 'library') { openLibrary(); }
  });
  // a widget's own buttons: data-a="widget:action" goes to that widget's a() handler
  pane.addEventListener('click', function (e) {
    var b = e.target.closest('[data-a]'); if (!b) return;
    var p = b.dataset.a.split(':'), def = WS.w[p[0]]; if (def && def.a) { def.a(p[1], b, e, { D: S.data, S: S, id: p[0] }); }
  });
  pane.addEventListener('input', function (e) { var b = e.target.closest('[data-i]'); if (!b) return; var p = b.dataset.i.split(':'), def = WS.w[p[0]]; if (def && def.n) def.n(p[1], b, e); });
  pane.addEventListener('change', function (e) { var b = e.target.closest('[data-c]'); if (!b) return; var p = b.dataset.c.split(':'), def = WS.w[p[0]]; if (def && def.ch) def.ch(p[1], b, e); });
  pane.addEventListener('submit', function (e) { var f = e.target.closest('[data-s]'); if (!f) return; e.preventDefault(); var p = f.dataset.s.split(':'), def = WS.w[p[0]]; if (def && def.s) def.s(p[1], f, e); });

  // ---- the alarm (its own option: a takeover above the widgets)
  var alarmEl = document.getElementById('wsx-alarm');
  var RULE = { red: [T('Red rainfall warning', 'Pulang babala sa ulan'), T('Flooding is threatening', 'Nagbabanta ang baha'), T('PAGASA has a Red warning for Metro Manila. Check the cases in flood zones before anyone goes out.', 'May Pulang babala ang PAGASA para sa Metro Manila. Tingnan ang mga kaso sa bahaing lugar bago lumabas ang sinuman.')],
    sig3: [T('Wind Signal 3 or higher', 'Signal ng hangin 3 pataas'), T('A typhoon is close', 'Malapit ang bagyo'), T('Plan tanod shifts and get the evacuation centres ready.', 'Ihanda ang mga shift ng tanod at ang mga evacuation center.')],
    urgent2h: [T('An urgent case is waiting', 'May madaliang kasong naghihintay'), T('Send a tanod now', 'Magpadala na ng tanod'), T('An urgent case has waited over two hours with nobody sent.', 'May madaliang kaso na mahigit dalawang oras nang naghihintay na walang naipadala.')],
    deadline: [T('A case will miss its deadline', 'May kasong lalampas sa takdang oras'), T('Deadlines are slipping', 'Lumalampas ang takdang oras'), T('The engine expects a case to miss its deadline.', 'Inaasahan ng engine na lalampas ang isang kaso sa takdang oras.')] };
  function drawAlarm(list, test) {
    if (!alarmEl) return;
    var f = test ? [{ rule: 'test', tab: 'brief', detail: '' }] : list.filter(function (x) { return S.dismissed.indexOf(x.rule + '|' + x.detail) < 0; });
    if (!f.length) { alarmEl.innerHTML = ''; alarmEl.hidden = true; return; }
    var x = f[0], r = RULE[x.rule] || [T('Test', 'Pagsubok'), T('This is only a test', 'Pagsubok lamang ito'), T('Nothing is wrong. This is how the alarm looks and sounds.', 'Walang problema. Ganito ang itsura ng alarma.')];
    alarmEl.hidden = false;
    alarmEl.innerHTML = '<div class="wx-alarm" role="alertdialog" aria-labelledby="wx-al-h" aria-describedby="wx-al-p"><div class="rg" aria-hidden="true"><i></i><i></i><i></i></div><span class="eb">' + T('Alarm', 'Alarma') + ' · ' + esc(r[0]) + '</span><div class="big" id="wx-al-h">' + esc(r[1]) + '</div><p id="wx-al-p">' + esc(r[2]) + (x.detail ? ' <b>' + esc(x.detail) + '</b>' : '') + '</p><div class="acts"><button type="button" class="w" data-al="go" data-tab="' + esc(x.tab) + '">' + T('Show me', 'Ipakita') + '</button><button type="button" class="g" data-al="off" data-key="' + esc(x.rule + '|' + x.detail) + '">' + T('Dismiss', 'Isara') + '</button></div></div>';
    if (test) beep();
    var g = alarmEl.querySelector('[data-al="go"]'); if (g && !test) { /* leave focus where it is: an alarm must not steal typing */ }
  }
  function beep() {
    try { var A = new (window.AudioContext || window.webkitAudioContext)(), o = A.createOscillator(), g = A.createGain(); o.type = 'sine'; o.frequency.value = 660; g.gain.value = 0.05; o.connect(g); g.connect(A.destination); o.start(); setTimeout(function () { o.frequency.value = 880; }, 250); setTimeout(function () { o.stop(); A.close(); }, 600); } catch (e) {}
  }
  WS.ring = function () { drawAlarm([], true); };
  if (alarmEl) alarmEl.addEventListener('click', function (e) {
    var b = e.target.closest('[data-al]'); if (!b) return;
    if (b.dataset.al === 'go') { alarmEl.hidden = true; alarmEl.innerHTML = ''; if (b.dataset.tab) { if (S.tabs.indexOf(b.dataset.tab) < 0) { S.tabs.push(b.dataset.tab); } open(b.dataset.tab, true); root.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' }); } }
    else { var k = b.dataset.key; if (k && k !== 'test|' && S.dismissed.indexOf(k) < 0) { S.dismissed.push(k); try { sessionStorage.setItem('wsx-dismissed', JSON.stringify(S.dismissed.slice(-50))); } catch (x) {} } drawAlarm(S.firing); }
  });

  // ---- the library: choose, order, and the barangay's switches
  var lib = null, libFocus = null, libQ = '', libG = '';
  function libHtml() {
    var cat = C.cat, ids = Object.keys(cat), q = libQ.toLowerCase();
    var chosen = S.tabs;
    var head = '<div class="wx-lh"><div><h3 id="wx-lt">' + T('Your widgets', 'Iyong mga widget') + '</h3><p>' + T(chosen.length + ' of ' + ids.length + ' on your Workspace. Press one to add or remove it.', chosen.length + ' sa ' + ids.length + ' ang nasa Workspace mo. Pindutin para idagdag o alisin.') + '</p></div><button type="button" class="wx-x" data-l="close" aria-label="' + T('Close', 'Isara') + '">' + WS.svg('cross', 18) + '</button></div>';
    var tools = '<div class="wx-ltools"><label class="wx-search">' + WS.svg('search', 16) + '<input type="search" id="wx-lq" placeholder="' + T('Search 120 widgets', 'Maghanap sa 120 widget') + '" value="' + esc(libQ) + '" autocomplete="off"></label><div class="wx-gtabs" role="group" aria-label="' + T('Group', 'Pangkat') + '"><button type="button" data-l="g" data-g="" aria-pressed="' + (libG === '') + '">' + T('All', 'Lahat') + '</button>' + Object.keys(C.groups).map(function (g) { return '<button type="button" data-l="g" data-g="' + g + '" aria-pressed="' + (libG === g) + '">' + esc(C.groups[g]) + '</button>'; }).join('') + '</div></div>';
    var mine_ = '<div class="wx-order" aria-label="' + T('Order of your widgets', 'Pagkakasunod ng mga widget mo') + '">' + chosen.map(function (id, i) { return '<span class="wx-oc" data-id="' + esc(id) + '">' + WS.icon(id, 15) + '<em>' + esc(WS.name_of(id)) + '</em><button type="button" data-l="mv" data-id="' + esc(id) + '" data-d="-1" aria-label="' + T('Move earlier', 'Ilipat pauna') + '"' + (i === 0 ? ' disabled' : '') + '>' + WS.svg('up', 13, 2.2) + '</button><button type="button" data-l="mv" data-id="' + esc(id) + '" data-d="1" aria-label="' + T('Move later', 'Ilipat pahuli') + '"' + (i === chosen.length - 1 ? ' disabled' : '') + '>' + WS.svg('down', 13, 2.2) + '</button></span>'; }).join('') + '</div>';
    var cards = Object.keys(C.groups).filter(function (g) { return !libG || libG === g; }).map(function (g) {
      var items = ids.filter(function (id) { var l = C.labels[id]; return cat[id].g === g && (!q || (l[0] + ' ' + l[1]).toLowerCase().indexOf(q) >= 0); });
      if (!items.length) return '';
      return '<section class="wx-lg"><h4>' + esc(C.groups[g]) + '</h4><div class="wx-lgrid">' + items.map(function (id) {
        var on = chosen.indexOf(id) >= 0, l = C.labels[id], eid = esc(id);
        return '<div class="wx-lw"><button type="button" class="wx-lc' + (on ? ' is-on' : '') + '" data-l="tg" data-id="' + eid + '" aria-pressed="' + on + '"><span class="ic">' + WS.icon(id, 22) + '</span><span class="tx"><b>' + esc(l[0]) + '</b><small>' + esc(l[1]) + '</small></span><span class="ck" aria-hidden="true">' + (on ? WS.svg('check', 14, 3) : WS.svg('plus', 14, 2.4)) + '</span></button><button type="button" class="wx-vw" data-l="vw" data-id="' + eid + '" aria-label="' + T('View', 'Tingnan') + ': ' + esc(l[0]) + '">' + WS.svg('eye', 14) + T('View', 'Tingnan') + '</button></div>';
      }).join('') + '</div></section>';
    }).join('') || '<p class="wx-none">' + T('No widget matches that.', 'Walang widget na tugma doon.') + '</p>';
    var st = S.st || {}, lead = S.lead, rules = st.alarm_rules || [];
    var rl = [['red', RULE.red[0]], ['sig3', RULE.sig3[0]], ['urgent2h', T('An urgent case waits 2 hours', 'Madaliang kasong 2 oras nang naghihintay')], ['deadline', T('A case will miss its deadline', 'May kasong lalampas sa takdang oras')]];
    var alarm = '<section class="wx-lg wx-lset"><h4>' + T('The alarm', 'Ang alarma') + '</h4><p class="wx-lnote">' + T('A full-width takeover above your widgets. It rings by itself when one of these happens' + (lead ? '.' : ' (the Chairman or the Secretary chooses which).'), 'Pumapatak ito sa itaas ng mga widget mo. Tumutunog nang kusa kapag nangyari ang isa rito' + (lead ? '.' : ' (ang Punong Barangay o ang Kalihim ang pumipili).')) + '</p><div class="wx-rules">' + rl.map(function (r) { var on = rules.indexOf(r[0]) >= 0; return '<button type="button" class="wx-rule' + (on ? ' is-on' : '') + '" data-l="rule" data-r="' + r[0] + '" aria-pressed="' + on + '"' + (lead ? '' : ' disabled') + '><span class="ck" aria-hidden="true">' + (on ? WS.svg('check', 12, 3.2) : '') + '</span>' + esc(r[1]) + '</button>'; }).join('') + '</div><div class="wx-lrow"><button type="button" class="wx-btn is-red" data-l="ring">' + WS.svg('bell', 15) + T('Ring the alarm', 'Patunugin ang alarma') + '</button>' + (lead ? '<button type="button" class="wx-rule' + (st.games_enabled ? ' is-on' : '') + '" data-l="games" aria-pressed="' + !!st.games_enabled + '"><span class="ck" aria-hidden="true">' + (st.games_enabled ? WS.svg('check', 12, 3.2) : '') + '</span>' + T('Allow minigames', 'Payagan ang mga minigame') + '</button>' : '') + '</div></section>';
    var foot2 = '<div class="wx-lf"><button type="button" class="wx-btn" data-l="reset">' + WS.svg('refresh', 15) + T('Back to the 12 I suggest', 'Bumalik sa 12 na iminumungkahi') + '</button><button type="button" class="wx-btn is-pri" data-l="close">' + T('Done', 'Tapos na') + '</button></div>';
    return head + tools + mine_ + '<div class="wx-lbody">' + cards + alarm + '</div>' + foot2;
  }
  function drawLib(keepScroll) {
    var body = lib.querySelector('.wx-lib-in'), sc = lib.querySelector('.wx-lbody'), top = sc ? sc.scrollTop : 0, qEl = document.activeElement && document.activeElement.id === 'wx-lq';
    body.innerHTML = libHtml(); if (keepScroll) lib.querySelector('.wx-lbody').scrollTop = top;
    if (qEl) { var i = document.getElementById('wx-lq'); i.focus(); i.setSelectionRange(i.value.length, i.value.length); }
  }
  function closePrev() { var p = lib && lib.querySelector('.wx-prev'); if (!p) return; var id = p.dataset.id; p.remove(); var b = lib.querySelector('.wx-vw[data-id="' + id + '"]'); if (b) b.focus(); }
  function showPrev(id) {
    if (!Object.prototype.hasOwnProperty.call(C.cat, id)) return;
    var l = C.labels[id], on = S.tabs.indexOf(id) >= 0, p = lib.querySelector('.wx-prev');
    if (p) p.remove();
    p = document.createElement('div'); p.className = 'wx-prev'; p.dataset.id = id;
    p.innerHTML = '<div class="wx-pv" role="dialog" aria-modal="true" aria-label="' + esc(l[0]) + '"><header><div><b>' + esc(l[0]) + '</b><small>' + T('Live preview. This does not change your Workspace.', 'Live na preview. Hindi nito binabago ang Workspace mo.') + '</small></div><button type="button" class="wx-btn' + (on ? '' : ' is-pri') + '" data-l="pvtg">' + (on ? T('Remove from my Workspace', 'Alisin sa Workspace ko') : T('Add to my Workspace', 'Idagdag sa Workspace ko')) + '</button><button type="button" class="wx-x" data-l="pvx" aria-label="' + T('Close preview', 'Isara ang preview') + '">' + WS.svg('cross', 18) + '</button></header><iframe src="widget-view.php?w=' + encodeURIComponent(id) + '" title="' + esc(l[0]) + '"></iframe></div>';
    lib.appendChild(p); var x = p.querySelector('[data-l="pvx"]'); if (x) x.focus();
  }
  function closeLib() { if (!lib) return; lib.remove(); lib = null; document.removeEventListener('keydown', libKey); if (libFocus && libFocus.focus) libFocus.focus(); drawRail(); if (S.tabs.indexOf(S.tab) < 0) open(S.tabs[0] || 'brief'); }
  function libKey(e) {
    if (e.key === 'Escape') { e.preventDefault(); if (lib.querySelector('.wx-prev')) closePrev(); else closeLib(); return; }
    if (e.key !== 'Tab') return;
    var f = lib.querySelectorAll('button:not([disabled]),input,[href]'); if (!f.length) return;
    var a = f[0], z = f[f.length - 1];
    if (e.shiftKey && document.activeElement === a) { e.preventDefault(); z.focus(); } else if (!e.shiftKey && document.activeElement === z) { e.preventDefault(); a.focus(); }
  }
  function openLibrary() {
    libFocus = document.activeElement; libQ = ''; libG = '';
    lib = document.createElement('div'); lib.className = 'wx-lib'; lib.innerHTML = '<div class="wx-lib-in" role="dialog" aria-modal="true" aria-labelledby="wx-lt"></div>';
    document.body.appendChild(lib); drawLib(); document.addEventListener('keydown', libKey);
    var c = lib.querySelector('[data-l="close"]'); if (c) c.focus();
    if (!S.st) { WS.fetch([], ['settings']).then(function (j) { var g = j.groups && j.groups.settings; if (g && g.ok) { S.st = g.data; S.lead = !!g.data.is_lead; if (lib) drawLib(true); } }).catch(function () {}); }
    lib.addEventListener('click', function (e) {
      if (e.target === lib) { closeLib(); return; }
      var b = e.target.closest('[data-l]'); if (!b) return;
      var a = b.dataset.l, id = b.dataset.id;
      if (a === 'close') closeLib();
      else if (a === 'g') { libG = b.dataset.g; drawLib(); }
      else if (a === 'tg') { var i = S.tabs.indexOf(id); if (i >= 0) { if (S.tabs.length > 1) S.tabs.splice(i, 1); else WS.toast(T('Keep at least one widget.', 'Magtira ng kahit isang widget.')); } else S.tabs.push(id); if (S.tabs.indexOf(S.tab) < 0) S.tab = S.tabs[0]; saveTabs(); drawLib(true); }
      else if (a === 'mv') { var j = S.tabs.indexOf(id), k = j + parseInt(b.dataset.d, 10); if (j >= 0 && k >= 0 && k < S.tabs.length) { S.tabs.splice(k, 0, S.tabs.splice(j, 1)[0]); saveTabs(); drawLib(true); var nb = lib.querySelector('.wx-oc[data-id="' + id + '"] [data-d="' + b.dataset.d + '"]'); if (nb && !nb.disabled) nb.focus(); } }
      else if (a === 'vw') showPrev(id);
      else if (a === 'pvx') closePrev();
      else if (a === 'pvtg') { var pid = lib.querySelector('.wx-prev').dataset.id, k2 = S.tabs.indexOf(pid); if (k2 >= 0) { if (S.tabs.length > 1) S.tabs.splice(k2, 1); else return WS.toast(T('Keep at least one widget.', 'Magtira ng kahit isang widget.')); } else S.tabs.push(pid); if (S.tabs.indexOf(S.tab) < 0) S.tab = S.tabs[0]; saveTabs(); drawLib(true); showPrev(pid); }
      else if (a === 'reset') { S.tabs = C.defaults.slice(); S.tab = S.tabs[0]; saveTabs(); drawLib(true); }
      else if (a === 'ring') { closeLib(); WS.ring(); }
      else if (a === 'rule' || a === 'games') {
        if (!S.lead) return; var st = S.st || (S.st = { alarm_rules: [] }), rules = (st.alarm_rules || []).slice(), data = { action: 'settings' };
        if (a === 'rule') { var r = b.dataset.r, x = rules.indexOf(r); if (x >= 0) rules.splice(x, 1); else rules.push(r); data.alarm_rules = rules.join(','); st.alarm_rules = rules; }
        else { st.games_enabled = !st.games_enabled; data.games_enabled = st.games_enabled ? '1' : '0'; }
        drawLib(true);
        post(data).then(function (r2) { if (r2.error) { WS.toast(r2.error, true); } else if (r2.settings) { S.st = Object.assign(S.st, r2.settings, { is_lead: true }); } });
      }
    });
    lib.addEventListener('input', function (e) { if (e.target.id === 'wx-lq') { libQ = e.target.value; drawLib(true); } });
  }

  // ---- keeping it fresh
  function poll() {
    if (document.hidden) return;
    var ids = ['flood', 'wx', 'brief'];
    WS.fetch(ids, ['alarm', 'settings']).then(function (j) {
      var a = j.groups && j.groups.alarm; S.firing = a && a.ok ? a.data.firing || [] : [];
      var st = j.groups && j.groups.settings; if (st && st.ok) { S.st = st.data; S.lead = !!st.data.is_lead; }
      if (!lib) drawAlarm(S.firing);
      drawRail();
      if (S.tab && (S.tab === 'brief' || S.tab === 'flood' || S.tab === 'wx')) paint();
    }).catch(function () {});
  }
  document.addEventListener('visibilitychange', function () { if (!document.hidden) { poll(); load(S.tab); } });
  var QUIET = ['games', 'apps', 'me'], BUSY = ['search', 'maps', 'poll', 'board', 'note', 'shift', 'bull', 'rss', 'rsskey', 'qr', 'evac', 'checkpt', 'roster', 'leave', 'train', 'bday', 'donate', 'timer', 'mood'];
  if (!C.solo) setInterval(function () { if (!document.hidden && !lib) { poll(); var g = C.cat[S.tab] && C.cat[S.tab].g; if (QUIET.indexOf(g) < 0 && BUSY.indexOf(S.tab) < 0) load(S.tab, true); } }, 120000);

  // ---- start
  try { if (localStorage.getItem('wsx-folded') === '1') { root.classList.add('is-folded'); if (xp) { xp.setAttribute('aria-expanded', 'false'); xp.classList.remove('is-open'); } } } catch (e) {}
  if (S.tabs.indexOf(S.tab) < 0) S.tab = S.tabs[0];
  drawRail(); pane.innerHTML = skeleton(); titleEl.textContent = WS.name_of(S.tab);
  ensure(S.tab, function () { load(S.tab); });
  if (!C.solo) poll();
  // a widget asked for elsewhere in the page can open here
  WS.openFromHash = function () { var m = /^#w=([a-z0-9]+)$/.exec(location.hash); if (m && Object.prototype.hasOwnProperty.call(C.cat, m[1])) { if (S.tabs.indexOf(m[1]) < 0) S.tabs.push(m[1]); open(m[1]); } };
  window.addEventListener('hashchange', WS.openFromHash); WS.openFromHash();
})();
