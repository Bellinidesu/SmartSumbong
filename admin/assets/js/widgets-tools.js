// Workspace widgets: tools (17 Oct 2026). Evacuation centres, hotlines, quick links, a patrol timer, this week, a quick
// reference, the alarm test, quick SMS, a QR for the resident app, print shortcuts, holidays, Open in Maps and the
// relief tally. The QR is made right here: no outside service ever sees the address.
(function () {
  var WS = window.WS, T = WS.T, A = WS.a, esc = WS.esc, n = WS.n, W = WS.w, L = WS.lvl;
  var ok = function (g) { return g && g.ok ? g.data : null; };
  var field = function (label, html) { return '<label class="wx-f"><span>' + label + '</span>' + html + '</label>'; };
  var done = function (msg) { return function (r) { if (r && r.error) { WS.toast(r.error, true); return false; } if (msg) WS.toast(msg); WS.refresh(); return true; }; };
  var today = function () { return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' }); };
  var copyBtn = function (v, label) { return '<button type="button" class="wx-btn is-sm" data-a="hot:cp" data-v="' + esc(v) + '">' + (label || T('Copy', 'Kopyahin')) + '</button>'; };
  var dist = function (m) { return m < 1000 ? m + ' m' : (m / 1000).toFixed(1) + ' km'; };

  // ---- evacuation centres
  var ST = { open: [T('Open', 'Bukás'), L.ok], closed: [T('Closed', 'Sarado'), L.low], full: [T('Full', 'Puno'), L.urgent], unknown: [T('Not confirmed', 'Hindi pa kumpirmado'), '#F5A524'] };
  W.evac = {
    r: function () {
      var d = ok(WS.group('evac')), lead = WS.S.lead, ed = W.evac.edit;
      var row = function (x) {
        var s = ST[x.status] || ST.unknown, en = ed === x.id;
        return '<div class="wx-ev"><div class="wx-item" style="--c:' + s[1] + '"><span class="wx-av sq">' + WS.svg('shield', 17) + '</span><span class="wx-it"><b>' + esc(x.name) + '</b><small>' + esc(dist(x.m)) + ' · ' + esc(String(x.kind).replace(/_/g, ' ')) + (x.capacity ? ' · ' + T('takes ', 'kayang tumanggap ng ') + n(x.capacity) : '') + (x.note ? ' · ' + esc(x.note) : '') + '</small></span><span class="wx-r">' + (x.status === 'unknown' ? '' : A.pill(s[0], s[1])) + '</span></div><div class="wx-row wx-evb"><a class="wx-btn is-sm" target="_blank" rel="noopener noreferrer" href="https://www.google.com/maps/dir/?api=1&destination=' + x.lat + ',' + x.lng + '">' + T('Directions', 'Direksyon') + '</a>' + (lead ? '<button type="button" class="wx-btn is-sm" data-a="evac:edit" data-id="' + esc(x.id) + '">' + (en ? T('Close', 'Isara') : T('Update status', 'I-update ang kalagayan')) + '</button>' : '') + '</div>' +
          (en ? '<form class="wx-compose wx-inline" data-s="evac:save"><input type="hidden" name="osm_id" value="' + esc(x.id) + '"><input type="hidden" name="name" value="' + esc(x.name) + '">' + field(T('Takes', 'Kapasidad'), '<input type="number" name="capacity" min="0" max="100000" value="' + (x.capacity == null ? '' : x.capacity) + '">') + field(T('Status', 'Kalagayan'), '<select name="status">' + Object.keys(ST).map(function (k) { return '<option value="' + k + '"' + (k === x.status ? ' selected' : '') + '>' + ST[k][0] + '</option>'; }).join('') + '</select>') + field(T('Note', 'Tala'), '<input name="note" maxlength="300" value="' + esc(x.note || '') + '">') + '<button class="wx-btn is-pri">' + T('Save', 'I-save') + '</button></form>' : '') + '</div>';
      };
      return (d.points.length ? '<div class="wx-list">' + d.points.slice(0, 7).map(row).join('') + '</div>' : A.empty('shield', T('No evacuation centre found near the hall', 'Walang evacuation center sa malapit sa hall'))) + '<p class="wx-note">' + T('Places come from OpenStreetMap, nearest the barangay hall first. OpenStreetMap does not know capacity or whether a place is open; the Chairman or the Secretary sets that here.', 'Ang mga lugar ay mula sa OpenStreetMap, pinakamalapit sa barangay hall muna. Hindi alam ng OpenStreetMap ang kapasidad o kung bukás ang lugar; ang Punong Barangay o ang Kalihim ang nagtatakda nito rito.') + '</p>';
    },
    a: function (a, el) { if (a === 'edit') { W.evac.edit = W.evac.edit === el.dataset.id ? null : el.dataset.id; WS.rerender(); } },
    s: function (a, f) { WS.post({ action: 'safe_note', osm_id: f.osm_id.value, name: f.name.value, capacity: f.capacity.value, status: f.status.value, note: f.note.value }).then(function (r) { if (done(T('Saved.', 'Na-save.'))(r)) W.evac.edit = null; }); }, src: 'OpenStreetMap · barangay notes'
  };

  // ---- hotlines, quick links, SMS, print shortcuts
  W.hot = {
    r: function () {
      var g = ok(WS.group('hotlines')), by = {}; g.forEach(function (x) { by[x.parent || 'top'] = by[x.parent || 'top'] || []; by[x.parent || 'top'].push(x); });
      var show = g.filter(function (x) { return x.numbers.length; });
      if (!show.length) return A.empty('phone', T('No hotlines recorded', 'Walang naitalang hotline'));
      return '<div class="wx-list">' + show.map(function (x) { return '<div class="wx-card2"><b>' + esc(x.name) + '</b>' + x.numbers.map(function (p) { return '<div class="wx-num"><span>' + [p.label ? esc(p.label) : '', p.carrier ? '<small>' + esc(p.carrier) + '</small>' : ''].filter(Boolean).join(' · ') + '</span><a href="tel:' + esc(String(p.number).replace(/[^0-9+]/g, '')) + '">' + esc(p.number) + '</a>' + copyBtn(p.number) + '</div>'; }).join('') + '</div>'; }).join('') + '</div>';
    },
    a: function (a, el) { if (a === 'cp') WS.copy(el.dataset.v); }, src: 'Settings · Hotlines'
  };
  var PAGES = [['cases.php', T('Case Reports', 'Mga Sumbong'), 'list', '#356CF9'], ['workspace.php', T('Workspace', 'Tablero ng Gawain'), 'grid', '#FF9800'], ['spatial.php', T('Spatial Distribution', 'Distribusyon sa Mapa'), 'map', '#00A5B5'], ['summary.php', T('Report Summary', 'Buod ng Ulat'), 'chart', '#8E3FD0'], ['residents.php', T('Residents', 'Mga residente'), 'people', '#2E9E4F'], ['personnel.php', T('Personnel', 'Mga tauhan'), 'shield', '#E5383B'], ['notifications.php', T('Notifications', 'Mga abiso'), 'bell', '#F5A524'], ['activity.php', T('Activity', 'Gawain'), 'pulse', '#2D4FA8'], ['settings.php', T('Settings', 'Mga setting'), 'gear', '#8E9ABB']];
  W.links = {
    r: function () {
      var c = WS.mine.get('links', {}), l = PAGES.slice().sort(function (a, b) { return (c[b[0]] || 0) - (c[a[0]] || 0); });
      return '<div class="wx-links">' + l.map(function (p) { return '<a href="' + p[0] + '" data-a="links:use" data-p="' + p[0] + '" style="--c:' + p[3] + '"><span>' + WS.svg(p[2], 22) + '</span><b>' + esc(p[1]) + '</b>' + (c[p[0]] > 2 ? '<i>' + T('often', 'madalas') + '</i>' : '') + '</a>'; }).join('') + '</div><p class="wx-note">' + T('The ones you open most move to the front.', 'Ang mga madalas mong buksan ay lumilipat sa unahan.') + '</p>';
    },
    a: function (a, el) { var c = WS.mine.get('links', {}); c[el.dataset.p] = (c[el.dataset.p] || 0) + 1; WS.mine.set('links', c); }
  };
  W.sms = {
    r: function () { var M = [T('Tanod is on the way.', 'Papunta na ang tanod.'), T('Please send a clearer photo.', 'Pakipadala ng mas malinaw na larawan.'), T('Your report was received. We will update you.', 'Natanggap ang ulat mo. Ia-update ka namin.'), T('Your case has been resolved. Thank you!', 'Nalutas na ang kaso mo. Salamat!'), T('Please come to the barangay hall with a valid ID.', 'Pumunta po sa barangay hall dala ang valid ID.'), T('Is the problem still there?', 'Nandiyan pa ba ang problema?')];
      return '<div class="wx-list">' + M.map(function (m) { return '<div class="wx-sms"><span>' + esc(m) + '</span><button type="button" class="wx-btn is-sm" data-a="sms:cp" data-v="' + esc(m) + '">' + T('Copy', 'Kopyahin') + '</button></div>'; }).join('') + '</div>'; },
    a: function (a, el) { WS.copy(el.dataset.v); }
  };
  W.forms = {
    r: function () { var F = [['certificate.php', T('Certificate', 'Sertipiko'), 'book'], ['complaint-summary.php', T('Complaint summary', 'Buod ng sumbong'), 'note'], ['summary.php', T('Weekly and monthly summary', 'Buod kada linggo at buwan'), 'chart'], ['cases.php', T('Print a case from Case Reports', 'Mag-print ng kaso mula sa Mga Sumbong'), 'list']]; return '<div class="wx-links">' + F.map(function (p, i) { return '<a href="' + p[0] + '" style="--c:' + ['#FF9800', '#356CF9', '#8E3FD0', '#2E9E4F'][i] + '"><span>' + WS.svg(p[2], 22) + '</span><b>' + esc(p[1]) + '</b></a>'; }).join('') + '</div><p class="wx-note">' + T('Every printable page opens in the same editor.', 'Bawat napi-print na pahina ay bubukas sa iisang editor.') + '</p>'; }
  };
  W.maps = {
    r: function () { return '<form class="wx-find" data-s="maps:go"><label class="wx-search">' + WS.svg('map', 17) + '<input name="q" placeholder="' + T('An address or a place', 'Address o lugar') + '" autocomplete="off" aria-label="' + T('Address', 'Address') + '"></label><div class="wx-row"><button class="wx-btn is-pri">' + T('Open in Google Maps', 'Buksan sa Google Maps') + '</button><a class="wx-btn" href="spatial.php">' + T('Spatial Distribution', 'Distribusyon sa Mapa') + '</a></div></form><div class="wx-row"><a class="wx-btn" target="_blank" rel="noopener noreferrer" href="https://www.google.com/maps/search/?api=1&query=14.5194,121.0122">' + WS.svg('pin', 14) + T('The barangay hall', 'Ang barangay hall') + '</a></div>'; },
    s: function (a, f) { var q = f.q.value.trim(); if (q) window.open('https://www.google.com/maps/search/?api=1&query=' + encodeURIComponent(q + ' Pasay'), '_blank', 'noopener'); }
  };
  W.siren = {
    r: function () { return '<div class="wx-card2"><b>' + T('Test the alarm', 'Subukan ang alarma') + '</b><p>' + T('Shows the alarm and plays a short, quiet tone on this screen only. Nobody else sees or hears it.', 'Ipinapakita ang alarma at tumutugtog ng maikli at mahinang tunog sa screen na ito lamang. Walang ibang makakakita o makakarinig.') + '</p><div class="wx-row"><button type="button" class="wx-btn is-red" data-a="siren:go">' + WS.svg('bell', 15) + T('Test the alarm', 'Subukan ang alarma') + '</button></div></div><p class="wx-note">' + T('Which events ring it by themselves is chosen under Widgets, at the bottom.', 'Ang mga pangyayaring magpapatunog nito nang kusa ay pinipili sa Mga widget, sa ibaba.') + '</p>'; },
    a: function () { WS.ring(); }
  };

  // ---- this week, holidays, a quick reference
  W.hol = {
    r: function () {
      var h = ok(WS.group('holidays')).next, now = new Date(today() + 'T12:00:00+08:00');
      return '<div class="wx-list">' + h.slice(0, 7).map(function (x) { var d = Math.round((new Date(x.date + 'T12:00:00+08:00') - now) / 864e5); return A.item({ av: esc(x.date.slice(8)), c: '#2D4FA8', sq: 1, t: esc(WS.C.lang === 'fil' ? (x.local || x.name) : x.name), s: esc(WS.fmt.wdl(x.date + 'T12:00:00+08:00')) + ', ' + esc(WS.fmt.day(x.date + 'T12:00:00+08:00')) + (x.local && x.local !== x.name ? ' · ' + esc(WS.C.lang === 'fil' ? x.name : x.local) : ''), r: d === 0 ? A.pill(T('Today', 'Ngayon'), L.ok) : d === 1 ? T('Tomorrow', 'Bukas') : d + ' ' + T('days', 'araw') }); }).join('') + '</div>';
    }, src: 'Nager.Date'
  };
  W.cal = {
    opt: ['holidays', 'due', 'team'],
    r: function () {
      var hol = ok(WS.group('holidays')), due = ok(WS.group('due')) || [], tm = ok(WS.group('team')), days = [], base = new Date(today() + 'T12:00:00+08:00');
      for (var i = 0; i < 7; i++) days.push(new Date(base.getTime() + i * 864e5).toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' }));
      return '<div class="wx-cal">' + days.map(function (d, i) {
        var hs = hol ? hol.next.filter(function (x) { return x.date === d; }) : [], dc = due.filter(function (x) { return x.due_at && new Date(x.due_at).toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' }) === d; }), od = i === 0 ? due.filter(function (x) { return x.overdue; }).length : 0, rs = tm ? tm.roster.filter(function (x) { return x.date === d; }) : [], lv = tm ? tm.leave.filter(function (x) { return x.from <= d && x.to >= d; }) : [];
        return '<div class="cd' + (i === 0 ? ' now' : '') + '"><b>' + (i === 0 ? T('Today', 'Ngayon') : esc(WS.fmt.wd(d + 'T12:00:00+08:00'))) + '</b><span class="dd">' + esc(WS.fmt.day(d + 'T12:00:00+08:00')) + '</span>' + hs.map(function (x) { return '<i class="hl" title="' + esc(x.name) + '">' + esc(x.local || x.name) + '</i>'; }).join('') + (od ? '<i class="od">' + od + ' ' + T('overdue', 'lampas') + '</i>' : '') + (dc.length ? '<i class="du">' + dc.length + ' ' + T('due', 'takda') + '</i>' : '') + (rs.length ? '<i class="ro">' + rs.length + ' ' + T('on duty', 'naka-duty') + '</i>' : '') + (lv.length ? '<i class="lv">' + lv.length + ' ' + T('off', 'liban') + '</i>' : '') + '</div>';
      }).join('') + '</div>';
    }, src: 'Cases · roster · Nager.Date'
  };
  W.law = {
    r: function () {
      return '<div class="wx-grid2"><div class="wx-card2"><b>' + T('Katarungang Pambarangay, step by step', 'Katarungang Pambarangay, hakbang-hakbang') + '</b><ol class="wx-steps"><li>' + T('The complaint is filed with the Punong Barangay.', 'Isinasampa ang reklamo sa Punong Barangay.') + '</li><li>' + T('The Punong Barangay mediates within 15 days.', 'Namamagitan ang Punong Barangay sa loob ng 15 araw.') + '</li><li>' + T('If it is not settled, a Pangkat ng Tagapagkasundo is formed.', 'Kung hindi nareresolba, bubuo ng Pangkat ng Tagapagkasundo.') + '</li><li>' + T('The Pangkat has 15 days, which can be extended by another 15.', 'May 15 araw ang Pangkat, na maaaring pahabain ng isa pang 15.') + '</li><li>' + T('No settlement: a certificate to file action is issued.', 'Kung walang kasunduan: ilalabas ang sertipiko para magsampa ng kaso.') + '</li></ol></div>' +
        '<div class="wx-card2"><b>' + T('Sensitive cases', 'Mga maseselang kaso') + '</b><p>' + T('Violence against women or children is not mediated like other disputes. Pass it to a higher official at once and offer the hotlines below.', 'Ang karahasan laban sa kababaihan o bata ay hindi idinadaan sa pamamagitan tulad ng ibang alitan. Iakyat agad sa mas mataas na opisyal at ibigay ang mga hotline sa ibaba.') + '</p>' + [['911', T('Emergency', 'Emergency')], ['163', 'Bantay Bata'], ['0919 777 7377', 'PNP Aleng Pulis']].map(function (h) { return '<div class="wx-num"><span>' + esc(h[1]) + '</span><a href="tel:' + esc(h[0].replace(/\s/g, '')) + '">' + esc(h[0]) + '</a>' + copyBtn(h[0]) + '</div>'; }).join('') + '</div></div><p class="wx-note">' + T('A guide, not legal advice. Check the hotline numbers against the current published lists.', 'Gabay lamang, hindi payong legal. Suriin ang mga numero ng hotline sa pinakabagong opisyal na listahan.') + '</p>';
    },
    a: function (a, el) { WS.copy(el.dataset.v); }
  };
  // 'hot' buttons inside other widgets reuse the same copy
  W.law.a = W.hot.a;

  // ---- the relief tally
  W.donate = {
    r: function () {
      var d = ok(WS.group('relief')), ev = d.events;
      return (ev.length ? ev.slice(0, 2).map(function (e) { var mx = e.streets[0] ? e.streets[0].packs : 1; return '<div class="wx-card2"><b>' + esc(e.event) + '</b>' + A.big(n(e.total), T('packs given out', 'pakete ang naipamigay'), '#E8438B', e.total) + e.streets.slice(0, 5).map(function (s) { return '<div class="wx-sl"><span>' + esc(s.street) + '</span>' + A.bar(s.packs / mx * 100, '#E8438B', 6) + '<b>' + n(s.packs) + '</b></div>'; }).join('') + '</div>'; }).join('') : A.empty('heart', T('No relief recorded', 'Walang naitalang relief'))) +
        '<form class="wx-compose wx-inline" data-s="donate:add">' + field(T('Event', 'Pangyayari'), '<input name="event" maxlength="120" required value="' + esc(W.donate.ev || (ev[0] ? ev[0].event : '')) + '" placeholder="' + T('Typhoon name or event', 'Pangalan ng bagyo o pangyayari') + '">') + field(T('Street', 'Kalye'), '<input name="street" maxlength="120" required>') + field(T('Packs', 'Pakete'), '<input type="number" name="packs" min="1" max="100000" required>') + '<button class="wx-btn is-pri">' + T('Add', 'Idagdag') + '</button></form>' +
        (d.lines.length ? '<details class="wx-det"><summary>' + T('Recent lines', 'Mga huling tala') + '</summary><div class="wx-list">' + d.lines.slice(0, 8).map(function (l) { return A.item({ av: '+', c: '#E8438B', t: esc(l.street) + ' · ' + n(l.packs), s: esc(l.event) + ' · ' + esc(l.given_on), r: '<button type="button" class="wx-link" data-a="donate:rm" data-id="' + esc(l.id) + '">' + T('Remove', 'Alisin') + '</button>' }); }).join('') + '</div></details>' : '');
    },
    a: function (a, el) { if (a === 'rm') WS.post({ action: 'relief_remove', id: el.dataset.id }).then(done()); },
    s: function (a, f) { W.donate.ev = f.event.value; WS.post({ action: 'relief_add', event: f.event.value, street: f.street.value, packs: f.packs.value }).then(done(T('Added.', 'Naidagdag.'))); }
  };

  // ---- the patrol timer
  var tm = { sw: { run: false, t0: 0, acc: 0, laps: [] }, cd: { run: false, end: 0, left: 0 } };
  var fmt = function (ms) { var s = Math.floor(ms / 1000), m = Math.floor(s / 60); return (m < 10 ? '0' : '') + m + ':' + (s % 60 < 10 ? '0' : '') + (s % 60) + '.' + Math.floor(ms % 1000 / 100); };
  W.timer = {
    r: function () {
      var sw = tm.sw, cd = tm.cd;
      return '<div class="wx-grid2"><div class="wx-card2"><span class="wx-h">' + T('Stopwatch', 'Stopwatch') + '</span><div class="wx-clockbig" id="wx-sw">' + fmt(sw.acc + (sw.run ? Date.now() - sw.t0 : 0)) + '</div><div class="wx-row"><button type="button" class="wx-btn is-pri" data-a="timer:swgo">' + (sw.run ? T('Pause', 'Ihinto') : T('Start', 'Simulan')) + '</button><button type="button" class="wx-btn" data-a="timer:swlap"' + (sw.run ? '' : ' disabled') + '>' + T('Lap', 'Lap') + '</button><button type="button" class="wx-btn" data-a="timer:swreset">' + T('Reset', 'I-reset') + '</button></div>' + (sw.laps.length ? '<div class="wx-laps">' + sw.laps.slice(-4).map(function (l, i) { return '<span>' + (sw.laps.length - Math.min(4, sw.laps.length) + i + 1) + ' · ' + fmt(l) + '</span>'; }).join('') + '</div>' : '') + '</div>' +
        '<div class="wx-card2"><span class="wx-h">' + T('Check back in', 'Bumalik sa loob ng') + '</span><div class="wx-clockbig" id="wx-cd">' + fmt(cd.run ? Math.max(0, cd.end - Date.now()) : cd.left) + '</div><div class="wx-row">' + [5, 15, 30].map(function (m) { return '<button type="button" class="wx-btn" data-a="timer:cd" data-m="' + m + '">' + m + ' min</button>'; }).join('') + '<button type="button" class="wx-btn" data-a="timer:cdstop">' + T('Stop', 'Ihinto') + '</button></div></div></div>';
    },
    i: function () { WS.timer(function () { var a = document.getElementById('wx-sw'), b = document.getElementById('wx-cd'); if (a && tm.sw.run) a.textContent = fmt(tm.sw.acc + Date.now() - tm.sw.t0); if (b && tm.cd.run) { var l = tm.cd.end - Date.now(); if (l <= 0) { tm.cd.run = false; tm.cd.left = 0; b.textContent = fmt(0); WS.ring(); } else b.textContent = fmt(l); } }, 100); },
    a: function (a, el) {
      var sw = tm.sw, cd = tm.cd;
      if (a === 'swgo') { if (sw.run) { sw.acc += Date.now() - sw.t0; sw.run = false; } else { sw.t0 = Date.now(); sw.run = true; } }
      else if (a === 'swlap') sw.laps.push(sw.acc + Date.now() - sw.t0);
      else if (a === 'swreset') { sw.run = false; sw.acc = 0; sw.laps = []; }
      else if (a === 'cd') { cd.end = Date.now() + (+el.dataset.m) * 60000; cd.run = true; }
      else if (a === 'cdstop') { cd.run = false; cd.left = 0; }
      WS.rerender();
    }
  };

  // ---- the QR (byte mode, error-correction level L, versions 1 to 6; written here so no service sees the address)
  var GE = [], GL = [];
  (function () { var x = 1; for (var i = 0; i < 255; i++) { GE[i] = x; GL[x] = i; x <<= 1; if (x & 256) x ^= 285; } }());
  var gm = function (a, b) { return a && b ? GE[(GL[a] + GL[b]) % 255] : 0; };
  function rs(data, ec) { var g = [1]; for (var i = 0; i < ec; i++) { var ng = []; for (var q = 0; q <= g.length; q++) ng.push(0); for (var j = 0; j < g.length; j++) { ng[j] ^= g[j]; ng[j + 1] ^= gm(g[j], GE[i]); } g = ng; } var res = data.concat(new Array(ec).fill(0)); for (i = 0; i < data.length; i++) { var c = res[i]; if (c) for (j = 0; j < g.length; j++) res[i + j] ^= gm(g[j], c); } return res.slice(data.length); }
  var VER = [null, [26, 7, 1], [44, 10, 1], [70, 15, 1], [100, 20, 1], [134, 26, 1], [172, 18, 2]], ALN = [null, [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34]];
  function qr(text) {
    var bytes = unescape(encodeURIComponent(text)).split('').map(function (c) { return c.charCodeAt(0); }), v = 1;
    for (; v <= 6; v++) { var t = VER[v]; if (bytes.length <= t[0] - t[1] * t[2] - 2) break; }
    if (v > 6) return null;
    var tot = VER[v][0], ecn = VER[v][1], nb = VER[v][2], dcw = tot - ecn * nb, bits = '';
    var put = function (val, len) { for (var i = len - 1; i >= 0; i--) bits += (val >> i) & 1; };
    put(4, 4); put(bytes.length, 8); bytes.forEach(function (b) { put(b, 8); });
    var cap = dcw * 8; put(0, Math.min(4, cap - bits.length)); while (bits.length % 8) bits += '0';
    var cw = []; for (var i = 0; i < bits.length; i += 8) cw.push(parseInt(bits.substr(i, 8), 2));
    for (var pad = 0; cw.length < dcw; pad++) cw.push(pad % 2 ? 17 : 236);
    var per = dcw / nb, blocks = [], ecs = []; for (i = 0; i < nb; i++) { blocks.push(cw.slice(i * per, (i + 1) * per)); ecs.push(rs(blocks[i], ecn)); }
    var out = []; for (i = 0; i < per; i++) blocks.forEach(function (b) { out.push(b[i]); }); for (i = 0; i < ecn; i++) ecs.forEach(function (e) { out.push(e[i]); });
    var N = 17 + 4 * v, M = [], F = []; for (i = 0; i < N; i++) { M.push(new Array(N).fill(0)); F.push(new Array(N).fill(false)); }
    var set = function (r, c, val) { if (r >= 0 && c >= 0 && r < N && c < N) { M[r][c] = val ? 1 : 0; F[r][c] = true; } };
    var finder = function (r, c) { for (var y = -1; y <= 7; y++) for (var x = -1; x <= 7; x++) set(r + y, c + x, y >= 0 && y <= 6 && x >= 0 && x <= 6 && (y === 0 || y === 6 || x === 0 || x === 6 || (y >= 2 && y <= 4 && x >= 2 && x <= 4))); };
    finder(0, 0); finder(0, N - 7); finder(N - 7, 0);
    for (i = 8; i < N - 8; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0); }
    var al = ALN[v]; al.forEach(function (r) { al.forEach(function (c) { if (F[r][c]) return; for (var y = -2; y <= 2; y++) for (var x = -2; x <= 2; x++) set(r + y, c + x, Math.max(Math.abs(y), Math.abs(x)) !== 1); }); });
    set(N - 8, 8, 1);
    for (i = 0; i < 9; i++) { if (!F[8][i]) F[8][i] = true; if (!F[i][8]) F[i][8] = true; } for (i = 0; i < 8; i++) { F[8][N - 1 - i] = true; F[N - 1 - i][8] = true; }
    var data = []; out.forEach(function (b) { for (var k = 7; k >= 0; k--) data.push((b >> k) & 1); });
    var up = true, masked = function (m, r, c) { return [(r + c) % 2 === 0, r % 2 === 0, c % 3 === 0, (r + c) % 3 === 0, (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0, (r * c) % 2 + (r * c) % 3 === 0, ((r * c) % 2 + (r * c) % 3) % 2 === 0, ((r + c) % 2 + (r * c) % 3) % 2 === 0][m]; };
    var place = []; for (var col = N - 1; col > 0; col -= 2) { if (col === 6) col--; for (var k2 = 0; k2 < N; k2++) { var r = up ? N - 1 - k2 : k2; for (var d = 0; d < 2; d++) { var c = col - d; if (!F[r][c]) place.push([r, c]); } } up = !up; }
    var best = null, bp = 1e9;
    for (var m = 0; m < 8; m++) {
      var G = M.map(function (row) { return row.slice(); });
      place.forEach(function (p, j) { var b = j < data.length ? data[j] : 0; G[p[0]][p[1]] = b ^ (masked(m, p[0], p[1]) ? 1 : 0); });
      var fb = ((1 << 3) | m) << 10, rem = fb; for (i = 14; i >= 10; i--) if ((rem >> i) & 1) rem ^= 0x537 << (i - 10); var fmtb = (((1 << 3) | m) << 10 | rem) ^ 0x5412;
      for (i = 0; i < 15; i++) { var bit = (fmtb >> i) & 1; if (i < 6) G[i][8] = bit; else if (i < 8) G[i + 1][8] = bit; else G[N - 15 + i][8] = bit; if (i < 8) G[8][N - 1 - i] = bit; else if (i < 9) G[8][15 - i] = bit; else G[8][14 - i] = bit; if (i < 6) G[8][i] = bit; else if (i < 8) G[8][i + 1] = bit; }
      G[N - 8][8] = 1;
      var pen = 0; for (var y = 0; y < N; y++) { var run = 1; for (var x = 1; x < N; x++) { if (G[y][x] === G[y][x - 1]) { run++; if (run === 5) pen += 3; else if (run > 5) pen++; } else run = 1; } }
      for (x = 0; x < N; x++) { run = 1; for (y = 1; y < N; y++) { if (G[y][x] === G[y - 1][x]) { run++; if (run === 5) pen += 3; else if (run > 5) pen++; } else run = 1; } }
      if (pen < bp) { bp = pen; best = G; }
    }
    return best;
  }
  WS.qr = qr;
  W.qr = {
    r: function () {
      var meta = ok(WS.group('meta')), url = W.qr.url != null ? W.qr.url : (meta.app_url || ''), q = url ? qr(url) : null;
      var svg = q ? '<svg class="wx-qrsvg" viewBox="0 0 ' + (q.length + 8) + ' ' + (q.length + 8) + '" shape-rendering="crispEdges" role="img" aria-label="' + T('QR code for ', 'QR code para sa ') + esc(url) + '"><rect width="100%" height="100%" fill="#fff"/><path fill="#0E1428" d="' + q.map(function (row, y) { return row.map(function (v, x) { return v ? 'M' + (x + 4) + ' ' + (y + 4) + 'h1v1h-1z' : ''; }).join(''); }).join('') + '"/></svg>' : '';
      return '<div class="wx-grid2"><div class="wx-card2" style="place-items:center">' + (svg || A.empty('qr', T('Paste a link to make a QR', 'Mag-paste ng link para gumawa ng QR'))) + '</div><div class="wx-card2"><form class="wx-compose" data-s="qr:make">' + field(T('Link', 'Link'), '<input name="url" maxlength="120" value="' + esc(url) + '" placeholder="https://…" inputmode="url">') + '<div class="wx-row"><button class="wx-btn is-pri">' + T('Make the QR', 'Gumawa ng QR') + '</button>' + (q ? '<button type="button" class="wx-btn" data-a="qr:print">' + T('Print', 'I-print') + '</button>' : '') + '</div></form><p class="wx-note">' + T('Made on this screen; the link never leaves the portal. Up to 120 characters. ', 'Ginawa sa screen na ito; hindi lumalabas ang link sa portal. Hanggang 120 titik. ') + (meta.app_url ? '' : T('The Render setting RESIDENT_APP_URL fills this in for everyone.', 'Ang setting na RESIDENT_APP_URL sa Render ang pupuno nito para sa lahat.')) + '</p></div></div>';
    },
    s: function (a, f) { var u = f.url.value.trim(); if (u && !/^https?:\/\//i.test(u)) { WS.toast(T('Start the link with https://', 'Simulan ang link sa https://'), true); return; } if (u && !qr(u)) { WS.toast(T('That link is too long for the QR.', 'Masyadong mahaba ang link para sa QR.'), true); return; } W.qr.url = u; WS.rerender(); },
    a: function (a) { if (a === 'print') { var s = document.querySelector('.wx-qrsvg'); if (!s) return; var w = window.open('', '_blank', 'noopener'); if (!w) return; w.document.write('<title>QR</title><body style="display:grid;place-items:center;margin:0;min-height:100vh">' + s.outerHTML.replace('<svg ', '<svg width="480" height="480" ') + '</body>'); w.document.close(); setTimeout(function () { w.print(); }, 300); } }
  };
})();
