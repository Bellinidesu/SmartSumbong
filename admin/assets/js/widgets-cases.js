// Workspace widgets: cases and numbers (17 Oct 2026). What needs a tanod, what is due, what is at risk, the month in
// rings and lines, the busiest streets, the latest activity and photos, and a search that jumps to a case.
(function () {
  var WS = window.WS, T = WS.T, A = WS.a, esc = WS.esc, n = WS.n, W = WS.w, L = WS.lvl;
  var ok = function (g) { return g && g.ok ? g.data : null; };
  var subj = function (x) { return x.sensitive ? T('Sensitive case', 'Maselang kaso') : esc(x.subject || ''); };
  var open = function (x) { return 'case.php?id=' + encodeURIComponent(x.report_id); };
  var lvlName = function (l) { return { urgent: T('Urgent', 'Madalian'), high: T('High', 'Mataas'), normal: T('Normal', 'Karaniwan'), low: T('Low', 'Mababa') }[l] || ''; };
  var go = function (label) { return '<span class="wx-go">' + label + WS.svg('up', 12, 2.6) + '</span>'; };
  var cases = function (arr, mk) { return '<div class="wx-list">' + arr.map(mk).join('') + '</div>'; };

  W.risk = {
    r: function () {
      var r = ok(WS.group('risk')), hi = r.filter(function (x) { return x.level >= 3; }).length;
      if (!r.length) return A.empty('check', T('No open case lies in a flood zone', 'Walang bukás na kasong nasa bahaing lugar'), T('Project NOAH flood and surge zones, checked live.', 'Mga bahaing lugar ng Project NOAH, sinusuri nang live.'));
      return '<div class="wx-row"><div class="wx-big" style="--c:' + L.high + '"><b data-n="' + r.length + '">' + r.length + '</b><span>' + T('open cases in flood zones', 'bukás na kaso sa bahaing lugar') + '</span></div>' + (hi ? A.pill(hi + ' ' + T('in the highest zone', 'sa pinakamataas na lugar'), L.urgent) : '') + '</div>' +
        cases(r.slice(0, 6), function (x) { var c = [L.low, '#F5D90A', L.high, L.urgent][x.level] || L.high; return A.item({ href: open(x), av: x.level + '', c: c, sq: 1, t: esc(x.tracking_id) + ' · ' + subj(x), s: esc(x.place || WS.catName(x.category)) + ' · ' + (x.hazard === 'surge' ? T('storm surge', 'storm surge') : T('flood', 'baha')) + ' ' + ['', T('low', 'mababa'), T('medium', 'katamtaman'), T('high', 'mataas')][x.level], r: go(T('Open', 'Buksan')) }); }) +
        '<div class="wx-row"><a class="wx-btn" href="spatial.php">' + T('See them on the map', 'Tingnan sa mapa') + '</a></div>';
    }, src: 'Project NOAH · SMART'
  };

  W.queue = {
    r: function () {
      var q = ok(WS.group('queue'));
      if (!q.length) return A.empty('check', T('Nobody is waiting for a tanod', 'Walang naghihintay ng tanod'), T('Every case that needs one has one, or is with a person.', 'Ang bawat kasong nangangailangan ay may tanod, o hawak ng tao.'));
      return '<div class="wx-row"><div class="wx-big" style="--c:' + L.urgent + '"><b data-n="' + q.length + '">' + q.length + '</b><span>' + T('waiting, most urgent first', 'naghihintay, pinakamadalian muna') + '</span></div></div>' +
        cases(q.slice(0, 6), function (x) { var c = L[x.level] || L.normal; return A.item({ href: open(x), av: esc((x.tracking_id || '').slice(-3)), c: c, t: esc(x.tracking_id) + ' · ' + esc(x.subject), s: lvlName(x.level) + ' · ' + WS.catName(x.category) + (x.waiting_since ? ' · ' + T('waiting ', 'naghihintay ') + WS.ago(x.waiting_since).replace(T(' ago', ' ang nakalipas'), '') : ''), r: A.pill(lvlName(x.level), c) }); }) +
        '<div class="wx-row"><a class="wx-btn is-pri" href="workspace.php?own=free">' + T('Send a tanod', 'Magpadala ng tanod') + '</a><a class="wx-btn" href="workspace.php">' + T('Open the board', 'Buksan ang tablero') + '</a></div>';
    }, src: 'SMART engine'
  };

  W.due = {
    r: function () {
      var d = ok(WS.group('due')), over = d.filter(function (x) { return x.overdue; }), soon = d.filter(function (x) { return !x.overdue; }).slice(0, 5);
      if (!d.length) return A.empty('check', T('Nothing is due this week', 'Walang takdang oras ngayong linggo'));
      return '<div class="wx-row"><div class="wx-big" style="--c:' + (over.length ? L.urgent : L.ok) + '"><b data-n="' + over.length + '">' + over.length + '</b><span>' + T('overdue now', 'lampas na ngayon') + '</span></div><div class="wx-big"><b data-n="' + soon.length + '">' + soon.length + '</b><span>' + T('due in the next 8 days', 'takda sa susunod na 8 araw') + '</span></div></div>' +
        cases(over.slice(0, 4).concat(soon).slice(0, 7), function (x) { var c = x.overdue ? L.urgent : L.normal; return A.item({ href: open(x), av: x.overdue ? '!' : WS.fmt.day(x.due_at).replace(/\D+/g, ''), c: c, t: esc(x.tracking_id) + ' · ' + subj(x), s: (x.handler ? esc(WS.name(x.handler)) : T('no one holds it', 'walang may hawak')), r: '<span style="color:' + c + '">' + esc(WS.until(x.due_at)) + '</span>' }); });
    }
  };

  W.rec = {
    r: function () {
      var r = ok(WS.group('recur')).filter(function (x) { return x.still_open > 0; });
      if (!r.length) return A.empty('check', T('Nothing keeps coming back', 'Walang paulit-ulit na problema'));
      return cases(r.slice(0, 6), function (x) { return A.item({ href: 'spatial.php', av: '↻', c: '#6A4FD3', sq: 1, t: esc(WS.catName(x.category)) + ' ' + T('keeps coming back', 'ay paulit-ulit'), s: T(x.reports + ' reports from ' + x.residents + ' residents over ' + x.weeks + ' weeks', x.reports + ' ulat mula sa ' + x.residents + ' residente sa loob ng ' + x.weeks + ' linggo') + (x.hazard ? ' · ' + esc(x.hazard) : ''), r: A.pill(x.still_open + ' ' + T('open', 'bukás'), L.high) }); }) + '<p class="wx-note">' + T('The same kind of problem, in the same place, over several weeks.', 'Parehong uri ng problema, sa parehong lugar, sa loob ng ilang linggo.') + '</p>';
    }, src: 'SMART engine'
  };

  W.mix = {
    r: function () {
      var c = ok(WS.group('numbers')).by_category, tot = c.reduce(function (s, x) { return s + x.n; }, 0);
      if (!tot) return A.empty('chart', T('No cases this month yet', 'Wala pang kaso ngayong buwan'));
      var R = 15.915, off = 25, ring = c.map(function (x) { var p = x.n / tot * 100, s = '<circle cx="21" cy="21" r="' + R + '" fill="none" stroke="' + WS.catColor(x.category) + '" stroke-width="6.5" stroke-dasharray="' + Math.max(0, p - .8).toFixed(2) + ' ' + (100 - Math.max(0, p - .8)).toFixed(2) + '" stroke-dashoffset="' + (-(off - 25)).toFixed(2) + '" class="seg" style="--d:' + (off * 8) + 'ms"/>'; off += p; return s; }).join('');
      return '<div class="wx-grid2"><div class="wx-card2" style="place-items:center"><div class="wx-donut"><svg viewBox="0 0 42 42" aria-hidden="true"><circle cx="21" cy="21" r="' + R + '" fill="none" class="t" stroke-width="6.5"/>' + ring + '</svg><div><b data-n="' + tot + '">' + tot + '</b><span>' + T('this month', 'ngayong buwan') + '</span></div></div></div><div class="wx-list">' + c.map(function (x) { return A.item({ av: Math.round(x.n / tot * 100) + '%', c: WS.catColor(x.category), t: esc(WS.catName(x.category)), r: x.n }); }).join('') + '</div></div>';
    }
  };

  W.pace = {
    r: function () {
      var p = ok(WS.group('numbers')).pace, d = p.days.map(function (x) { return x.hours; });
      var fmt = function (h) { return h == null ? '–' : h < 1 ? Math.round(h * 60) + ' min' : h < 48 ? (+h).toFixed(1) + ' h' : (h / 24).toFixed(1) + ' ' + T('d', 'araw'); };
      return '<div class="wx-grid2"><div class="wx-card2"><span class="wx-h">' + T('Time to a first response', 'Oras bago ang unang tugon') + '</span>' + A.big(fmt(p.avg_hours), T('average, last 7 days', 'karaniwan, huling 7 araw'), '#FF9800') + (d.some(function (x) { return x != null; }) ? A.spark(d, '#FF9800', { h: 64 }) : '') + '<div class="wx-ax"><span>' + esc(WS.fmt.wd(p.days[0].d + 'T12:00:00+08:00')) + '</span><span>' + esc(WS.fmt.wd(p.days[6].d + 'T12:00:00+08:00')) + '</span></div></div><div class="wx-card2">' + A.kv([[T('Fastest', 'Pinakamabilis'), p.fastest_minutes != null ? n(p.fastest_minutes) + ' min' : '–'], [T('Slowest', 'Pinakamabagal'), p.slowest_hours != null ? fmt(p.slowest_hours) : '–'], [T('Still waiting for a first response', 'Naghihintay pa ng unang tugon'), p.still_waiting]]) + '</div></div>';
    }
  };

  W.street = {
    r: function () {
      var s = ok(WS.group('numbers')).streets;
      if (!s.length) return A.empty('check', T('No street has open cases', 'Walang kalyeng may bukás na kaso'));
      var mx = s[0].open;
      return cases(s, function (x, i) { return '<a class="wx-item is-link" href="spatial.php" style="--c:' + WS.catColor(x.category) + '"><span class="wx-av">' + (i + 1) + '</span><span class="wx-it"><b>' + esc(x.place) + '</b><small>' + esc(WS.catName(x.category)) + '</small>' + A.bar(x.open / mx * 100, WS.catColor(x.category), 5) + '</span><span class="wx-r"><b style="font:800 16px Urbanist;color:var(--wx-ink)">' + x.open + '</b> ' + T('open', 'bukás') + '</span></a>'; });
    }
  };

  W.eff = {
    opt: ['sla'],
    r: function () {
      var m = ok(WS.group('numbers')).month, sl = ok(WS.group('sla')), pct = m.resolved_pct, d = m.last_resolved_pct != null && pct != null ? pct - m.last_resolved_pct : null;
      var ot = sl && sl.length ? Math.round(sl.reduce(function (s, x) { return s + (+x.on_time || 0); }, 0) / Math.max(1, sl.reduce(function (s, x) { return s + (+x.finished || 0); }, 0)) * 100) : null;
      var delta = function (a, b, good) { if (b == null || a == null) return ''; var x = a - b; return x ? '<span class="wx-dl ' + ((x > 0) === good ? 'up' : 'dn') + '">' + (x > 0 ? '▲ ' : '▼ ') + Math.abs(x) + '</span>' : ''; };
      return '<div class="wx-grid2"><div class="wx-card2" style="place-items:center">' + A.ring(pct == null ? 0 : pct, '#2E9E4F', pct == null ? '–' : pct + '%', T('resolved', 'nalutas')) + (d != null ? '<span class="wx-note">' + (d >= 0 ? '▲ ' : '▼ ') + Math.abs(d) + ' ' + T('points vs last month', 'puntos kumpara sa nakaraang buwan') + '</span>' : '') + '</div><div class="wx-tiles" style="grid-template-columns:repeat(2,1fr)">' +
        '<div class="wx-tile"><span>' + T('Received', 'Natanggap') + '</span><b>' + n(m.received) + ' ' + delta(m.received, m.last_received, false) + '</b></div><div class="wx-tile"><span>' + T('Resolved', 'Nalutas') + '</span><b>' + n(m.resolved) + '</b></div><div class="wx-tile"><span>' + T('Average time', 'Karaniwang oras') + '</span><b>' + (m.avg_hours == null ? '–' : m.avg_hours < 48 ? m.avg_hours + ' h' : (m.avg_hours / 24).toFixed(1) + ' d') + '</b></div><div class="wx-tile"><span>' + T('Overdue', 'Lampas na') + '</span><b style="color:' + (m.overdue ? L.urgent : 'inherit') + '">' + n(m.overdue) + '</b></div><div class="wx-tile"><span>' + T('Escalated', 'Inakyat') + '</span><b>' + n(m.escalated) + '</b></div><div class="wx-tile"><span>' + T('On time', 'Nasa oras') + '</span><b>' + (ot == null ? '–' : ot + '%') + '</b></div></div></div>';
    }, src: 'Case records'
  };

  W.minimap = {
    r: function () {
      var m = ok(WS.group('map')), hall = [14.5194, 121.0122];
      if (!m.length) return A.empty('check', T('No open cases to show', 'Walang bukás na kasong ipapakita'));
      var la = m.map(function (x) { return +x.lat; }).concat([hall[0]]), lo = m.map(function (x) { return +x.lng; }).concat([hall[1]]), a = Math.min.apply(null, la), b = Math.max.apply(null, la), c = Math.min.apply(null, lo), d = Math.max.apply(null, lo), pad = Math.max(.002, (b - a) * .12, (d - c) * .12);
      a -= pad; b += pad; c -= pad; d += pad;
      var X = function (g) { return 6 + (g - c) / (d - c) * 288; }, Y = function (g) { return 6 + (b - g) / (b - a) * 168; };
      var pins = m.map(function (x) { var col = L[x.level] || L.normal; return '<a href="' + open(x) + '"><circle cx="' + X(+x.lng).toFixed(1) + '" cy="' + Y(+x.lat).toFixed(1) + '" r="' + (x.level === 'urgent' ? 7 : 5.5) + '" fill="' + col + '"><title>' + esc(x.tracking_id) + '</title></circle></a>'; }).join('');
      return '<div class="wx-card2 wx-mm"><svg viewBox="0 0 300 180" role="img" aria-label="' + T('Open cases around the barangay', 'Mga bukás na kaso sa paligid ng barangay') + '"><defs><pattern id="wxmg" width="30" height="30" patternUnits="userSpaceOnUse"><path d="M30 0H0V30" fill="none" class="gl"/></pattern></defs><rect width="300" height="180" rx="12" class="bg"/><rect width="300" height="180" rx="12" fill="url(#wxmg)"/>' + pins + '<g transform="translate(' + X(hall[1]).toFixed(1) + ' ' + Y(hall[0]).toFixed(1) + ')"><circle r="9" class="hl"/><path d="M0-6l1.8 3.7 4 .6-2.9 2.8.7 4L0 3.2l-3.6 1.9.7-4L-5.800-1.700l4-.6z" class="hs"/></g></svg><div class="wx-row">' + ['urgent', 'high', 'normal', 'low'].map(function (k) { return '<span class="wx-key"><i style="background:' + L[k] + '"></i>' + lvlName(k) + ' ' + m.filter(function (x) { return x.level === k; }).length + '</span>'; }).join('') + '<a class="wx-btn is-sm" href="spatial.php" style="margin-left:auto">' + T('Open the map', 'Buksan ang mapa') + '</a></div></div>';
    }, src: 'Case records'
  };

  var KIND = { new: ['+', L.ok, T('New case', 'Bagong kaso')], status: ['↗', L.normal, T('Status changed', 'Nagbago ang katayuan')], dispatch: ['→', '#00A5B5', T('Tanod sent', 'Naipadala ang tanod')], handler_take: ['✋', '#6A4FD3', T('Taken by', 'Kinuha ni')], handler_release: ['↩', L.low, T('Released by', 'Binitawan ni')], handler_take_over: ['⇄', '#6A4FD3', T('Taken over by', 'Inagaw ni')], handler_escalate: ['▲', L.high, T('Passed up by', 'Iniakyat ni')], handler_return: ['▼', L.low, T('Returned by', 'Ibinalik ni')] };
  W.recent = {
    r: function () {
      var a = ok(WS.group('activity'));
      if (!a.length) return A.empty('list', T('Nothing has happened yet', 'Wala pang nangyayari'));
      return cases(a.slice(0, 8), function (x) { var k = KIND[x.kind] || ['•', L.low, '']; var who = x.kind === 'dispatch' ? T('to ', 'kay ') + esc(x.tanod || '') : x.by ? esc(x.by) : ''; return A.item({ href: open(x), av: k[0], c: k[1], t: esc(x.tracking_id) + ' · ' + subj(x), s: esc(k[2]) + (who ? ' ' + who : '') + (x.status ? ' · ' + esc(String(x.status).replace(/_/g, ' ')) : ''), r: WS.ago(x.at).replace(T(' ago', ' ang nakalipas'), '') }); });
    }
  };

  W.photos = {
    r: function () {
      var p = ok(WS.group('photos'));
      if (!p.length) return A.empty('camera', T('No photos yet', 'Wala pang larawan'), T('Photos from sensitive cases are never shown here.', 'Hindi kailanman ipinapakita rito ang mga larawan mula sa maseselang kaso.'));
      var th = function (u, w) { return typeof window.ssThumb === 'function' ? window.ssThumb(u, w, true) : u; };
      return '<div class="wx-photos">' + p.slice(0, 8).map(function (x, i) { return '<a href="case.php?id=' + encodeURIComponent(x.report_id) + '" style="--d:' + i * 50 + 'ms"><img src="' + esc(th(x.url, 320)) + '" alt="' + esc(x.tracking_id) + '" loading="lazy" decoding="async"><span>' + esc(x.tracking_id) + ' · ' + ({ resident: T('resident', 'residente'), staff: T('staff', 'kawani'), tanod: T('tanod', 'tanod') }[x.from] || '') + '</span></a>'; }).join('') + '</div>';
    }
  };

  W.search = {
    r: function () {
      return '<form class="wx-find" data-s="search:go" role="search"><label class="wx-search">' + WS.svg('search', 17) + '<input type="search" name="q" data-i="search:type" placeholder="' + T('A number, a subject or a street', 'Numero, paksa o kalye') + '" autocomplete="off" aria-label="' + T('Find a case', 'Maghanap ng kaso') + '"></label></form><div id="wx-found" class="wx-list" aria-live="polite">' + (W.search.last || '') + '</div>';
    },
    n: function (a, el) { clearTimeout(W.search.t); var q = el.value.trim(); W.search.t = setTimeout(function () { W.search.run(q); }, 280); },
    s: function (a, f) { W.search.run(f.q.value.trim()); },
    run: function (q) {
      var box = document.getElementById('wx-found'); if (!box) return;
      if (q.length < 2) { W.search.last = ''; box.innerHTML = '<p class="wx-note">' + T('Type at least two letters or digits.', 'Mag-type ng hindi bababa sa dalawang titik o numero.') + '</p>'; return; }
      fetch('widgets.php?find=' + encodeURIComponent(q), { credentials: 'same-origin' }).then(function (r) { return r.json(); }).then(function (j) {
        var r = j.results || []; if (!document.getElementById('wx-found')) return;
        W.search.last = r.length ? r.map(function (x) { return A.item({ href: open(x), av: esc((x.tracking_id || '').slice(-3)), c: WS.catColor(x.category), t: esc(x.tracking_id) + ' · ' + subj(x), s: esc(x.place || WS.catName(x.category)) + ' · ' + esc(String(x.status).replace(/_/g, ' ')), r: go(T('Open', 'Buksan')) }); }).join('') : A.empty('search', T('No case matches that', 'Walang kasong tugma roon'));
        document.getElementById('wx-found').innerHTML = W.search.last;
      }).catch(function () { box.innerHTML = '<p class="wx-note">' + T('The search did not answer. Try again.', 'Hindi sumagot ang paghahanap. Subukan muli.') + '</p>'; });
    }
  };

  W.trend = {
    r: function () {
      var d = ok(WS.group('numbers')).per_day, v = d.map(function (x) { return x.n; }), tot = v.reduce(function (s, x) { return s + x; }, 0), wk = v.slice(-7).reduce(function (s, x) { return s + x; }, 0), pw = v.slice(-14, -7).reduce(function (s, x) { return s + x; }, 0), mx = Math.max.apply(null, v), bi = v.indexOf(mx);
      return '<div class="wx-card2"><span class="wx-h">' + T('New cases, last 30 days', 'Bagong kaso, huling 30 araw') + '</span><div class="wx-row">' + A.big(n(tot), T('in 30 days', 'sa 30 araw'), '#356CF9', tot) + A.big(n(wk), T('this week', 'ngayong linggo'), '#FF9800', wk) + (pw ? '<span class="wx-dl ' + (wk <= pw ? 'up' : 'dn') + '">' + (wk > pw ? '▲ ' : '▼ ') + Math.abs(wk - pw) + ' ' + T('vs last week', 'kumpara sa nakaraang linggo') + '</span>' : '') + '</div>' + A.spark(v, '#356CF9', { h: 80 }) + '<div class="wx-ax"><span>' + esc(WS.fmt.day(d[0].d + 'T12:00:00+08:00')) + '</span><span>' + esc(WS.fmt.day(d[29].d + 'T12:00:00+08:00')) + '</span></div></div>' + (mx ? '<p class="wx-note">' + T('Busiest day: ', 'Pinakaabalang araw: ') + esc(WS.fmt.day(d[bi].d + 'T12:00:00+08:00')) + ' · ' + mx + ' ' + T('cases', 'kaso') + '</p>' : '');
    }
  };

  W.hours = {
    r: function () {
      var h = ok(WS.group('numbers')).per_hour, mx = Math.max.apply(null, h), pk = h.indexOf(mx), hr = function (i) { return (i % 12 || 12) + (i < 12 ? ' AM' : ' PM'); };
      return '<div class="wx-card2"><span class="wx-h">' + T('When cases arrive, last 90 days', 'Kailan dumarating ang kaso, huling 90 araw') + '</span>' + A.bars(h, '#FF9800', { h: 92, hi: pk }) + '<div class="wx-ax"><span>12 AM</span><span>6 AM</span><span>12 PM</span><span>6 PM</span><span>11 PM</span></div></div>' + (mx ? A.kv([[T('Busiest hour', 'Pinakaabalang oras'), hr(pk) + ' · ' + mx], [T('Quietest', 'Pinakatahimik'), hr(h.indexOf(Math.min.apply(null, h)))]]) + '<p class="wx-note">' + T('Put the strongest shift where the bars are tallest.', 'Ilagay ang pinakamalakas na shift kung saan pinakamataas ang mga bar.') + '</p>' : '');
    }
  };

  W.status = {
    r: function () {
      var s = ok(WS.group('numbers')).status, t = s.waiting + s.in_progress + s.resolved + s.rejected;
      if (!t) return A.empty('chart', T('No cases this month yet', 'Wala pang kaso ngayong buwan'));
      var parts = [[T('Waiting', 'Naghihintay'), s.waiting, L.urgent], [T('In progress', 'Ginagawa'), s.in_progress, L.high], [T('Resolved', 'Nalutas'), s.resolved, L.ok], [T('Rejected', 'Tinanggihan'), s.rejected, L.low]];
      return '<div class="wx-card2"><span class="wx-h">' + T('This month', 'Ngayong buwan') + '</span><div class="wx-stack">' + parts.map(function (p, i) { return p[1] ? '<i style="flex:' + p[1] + ';background:' + p[2] + ';--d:' + i * 90 + 'ms" title="' + esc(p[0]) + ' ' + p[1] + '"></i>' : ''; }).join('') + '</div></div><div class="wx-tiles">' + parts.map(function (p) { return '<div class="wx-tile" style="--c:' + p[2] + '"><span><i class="wx-sw" style="background:' + p[2] + '"></i>' + p[0] + '</span><b>' + p[1] + '</b><small class="wx-note">' + Math.round(p[1] / t * 100) + '%</small></div>'; }).join('') + '</div>';
    }
  };

  W.sla = {
    opt: ['numbers'],
    r: function () {
      var s = ok(WS.group('sla')), fin = s.reduce(function (a, x) { return a + (+x.finished || 0); }, 0), on = s.reduce(function (a, x) { return a + (+x.on_time || 0); }, 0), pct = fin ? Math.round(on / fin * 100) : null;
      if (!fin) return A.empty('check', T('No case has finished this month yet', 'Wala pang natapos na kaso ngayong buwan'));
      return '<div class="wx-grid2"><div class="wx-card2" style="place-items:center">' + A.ring(pct, pct >= 90 ? L.ok : pct >= 70 ? L.high : L.urgent, pct + '%', T('on time', 'nasa oras')) + '<span class="wx-note">' + on + ' ' + T('of', 'sa') + ' ' + fin + ' ' + T('answered within their deadline', 'natugunan sa takdang oras') + '</span></div><div class="wx-list">' + s.filter(function (x) { return x.finished > 0; }).sort(function (a, b) { return a.on_time_pct - b.on_time_pct; }).slice(0, 5).map(function (x) { var c = x.on_time_pct >= 90 ? L.ok : x.on_time_pct >= 70 ? L.high : L.urgent; return A.item({ av: Math.round(x.on_time_pct), c: c, t: esc(WS.catName(x.category)), s: x.on_time + '/' + x.finished + (x.overdue_now ? ' · ' + x.overdue_now + ' ' + T('overdue now', 'lampas ngayon') : ''), r: x.change_pct != null ? '<span class="wx-dl ' + (x.change_pct >= 0 ? 'up' : 'dn') + '">' + (x.change_pct >= 0 ? '▲ ' : '▼ ') + Math.abs(Math.round(x.change_pct)) + '</span>' : '' }); }).join('') + '</div></div>';
    }, src: 'SMART scorecard'
  };

  W.escal = {
    r: function () {
      var d = ok(WS.group('numbers')), e = d.escalations, p = d.escalation_requests;
      if (!e.length && !p) return A.empty('check', T('Nothing has been passed up', 'Walang iniakyat na kaso'));
      return (p ? '<div class="wx-card2" style="border-left:4px solid ' + L.high + '"><b>' + p + ' ' + T('request' + (p === 1 ? '' : 's') + ' to pass a case up waiting for a decision', 'kahilingang mag-akyat ng kaso ang naghihintay ng desisyon') + '</b></div>' : '') + cases(e, function (x) { return A.item({ href: open(x), av: x.tier === 2 ? 'C' : 'K', c: x.tier === 2 ? L.urgent : '#6A4FD3', t: esc(x.tracking_id) + ' · ' + subj(x), s: T('With ', 'Nasa ') + esc(x.to || (x.tier === 2 ? T('the Chairman', 'Punong Barangay') : T('a Kagawad', 'Kagawad'))), r: WS.ago(x.at).replace(T(' ago', ' ang nakalipas'), '') }); });
    }
  };

  W.today = {
    r: function () {
      var t = ok(WS.group('numbers')).resolved_today;
      if (!t.length) return A.empty('check', T('Nothing has been resolved yet today', 'Wala pang nalulutas ngayong araw'), T('A small win will show up here.', 'Dito lalabas ang maliliit na tagumpay.'));
      return '<div class="wx-big" style="--c:' + L.ok + '"><b data-n="' + t.length + '">' + t.length + '</b><span>' + T('resolved today', 'nalutas ngayon') + '</span></div>' + cases(t, function (x) { return A.item({ href: open(x), av: '✓', c: L.ok, t: esc(x.tracking_id) + ' · ' + subj(x), s: x.by ? T('Closed by ', 'Isinara ni ') + esc(x.by) : T('Closed', 'Isinara'), r: esc(WS.fmt.time(x.at)) }); });
    }
  };
})();
