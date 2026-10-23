// The command center on Spatial Distribution (SMART Iteration 4, 0143). One situation at a time: Fire Surroundings,
// Quake Check, Flood Watch or Typhoon Board. SMART suggests a mode in a banner over the map (with the reason in words);
// an administrator turns it on, or looks first. While a mode is on, a bar across the top says so, the drawer holds the
// board, the checklist, the feed and the handover, and the map draws what the mode reads: depth or damage by 100 m
// cell, the rings around a reported fire, the buildings a quake check walks through. Nothing here predicts: every line
// is what was reported, where, and when. Everything is read from and written to command-act.php; the rules are the
// database's. Reads window.SS_CMD (set by spatial.php); uses the page's map, mapReady and T.
(function () {
  var C = window.SS_CMD;
  if (!C) return;
  var side = document.getElementById('cc-side'), btn = document.getElementById('cc-toggle'),
      bar = document.getElementById('cc-bar'), sug = document.getElementById('cc-suggest');
  if (!side || !btn) return;
  var body = side.querySelector('.cc-body'), head = side.querySelector('.cc-head');
  var tr = function (en, fil) { return typeof T === 'function' ? T(en, fil) : en; };
  var esc = function (v) { return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  var nm = function (o, k) { return o ? tr(o[k + 'en'] || o.en, o[k + 'fil'] || o.fil) : ''; };
  var tm = function (iso) { if (!iso) return ''; var d = new Date(iso); return isNaN(d) ? '' : d.toLocaleTimeString('en-PH', { hour: 'numeric', minute: '2-digit' }); };
  var day = function (iso) { var d = new Date(iso); return isNaN(d) ? '' : d.toLocaleDateString('en-PH', { month: 'short', day: 'numeric' }) + ', ' + tm(iso); };
  var who = function (n) { return n ? esc(n) : tr('SMART (auto switch)', 'SMART (auto switch)'); };
  var EMPTY = { type: 'FeatureCollection', features: [] };
  var COL = { fire: '#E5383B', quake: '#8D6E63', flood: '#1E88E5', typhoon: '#6A4FD3' };
  var ICON = {
    fire: '<path d="M12 3c1.3 3.4 5 4.8 5 9.5a5 5 0 0 1-10 0c0-2 .8-3.6 2-4.8.3 1.8 1.1 2.9 2.2 3.3C11 8.7 11.3 5.6 12 3z"/>',
    quake: '<path d="M3 12h3l2-5 3 10 3-8 2 3h5"/>',
    flood: '<path d="M3 15c2 0 2-1.5 4.5-1.5S10 15 12 15s2-1.5 4.5-1.5S19 15 21 15"/><path d="M3 19c2 0 2-1.5 4.5-1.5S10 19 12 19s2-1.5 4.5-1.5S19 19 21 19"/><path d="M12 3v8M9 8l3 3 3-3"/>',
    typhoon: '<path d="M12 12m-2 0a2 2 0 1 0 4 0a2 2 0 1 0-4 0"/><path d="M5 9c2-5 9-6 12-2"/><path d="M19 15c-2 5-9 6-12 2"/>'
  };
  var ico = function (m, s) { return '<svg width="' + (s || 18) + '" height="' + (s || 18) + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICON[m] || '') + '</svg>'; };
  var WHAT = {
    fire: ['Each reported fire, and what is within 50, 100 and 200 m of it: fuel stations, schools, clinics, the nearest tanods.', 'Bawat naiulat na sunog, at ang nasa loob ng 50, 100 at 200 m nito: gasolinahan, paaralan, klinika, ang pinakamalapit na tanod.'],
    quake: ['Damage reported since the quake, by 100 m square, and the public buildings to check one by one.', 'Pinsalang naiulat mula nang lumindol, bawat 100 m na parisukat, at ang mga pampublikong gusaling susuriin isa-isa.'],
    flood: ['How deep residents say the water is, on MMDA\'s flood gauge, by 100 m square, with Project NOAH\'s flood zones.', 'Gaano kalalim ang tubig ayon sa mga residente, sa flood gauge ng MMDA, bawat 100 m na parisukat, kasama ang flood zones ng Project NOAH.'],
    typhoon: ['PAGASA\'s wind signal, storm mode, and the damage residents report: fallen trees, power lines, roofing, flood water.', 'Ang wind signal ng PAGASA, storm mode, at ang pinsalang iniuulat: natumbang puno, kawad ng kuryente, bubong, baha.']
  };
  var S = { board: null, signal: null, mode: null, tab: 'board', picking: null, feed: null, timer: null, quiet: {} };

  function req(url, opts) {
    return fetch(url, Object.assign({ credentials: 'same-origin', headers: { Accept: 'application/json' } }, opts || {}))
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { if (!r.ok || j.error) throw new Error(j.error || tr('Something went wrong. Try again.', 'May nangyaring mali. Subukan muli.')); return j; }); });
  }
  function act(data) {
    var f = new FormData(); f.append('csrf', C.csrf);
    Object.keys(data).forEach(function (k) { if (data[k] != null) f.append(k, data[k]); });
    return req('command-act.php', { method: 'POST', body: f });
  }
  function load() {
    var m = S.board && S.board.active ? null : S.mode;
    return req('command-act.php?do=board' + (m ? '&mode=' + m : '')).then(function (j) {
      S.board = j.board || {}; S.signal = j.signal;
      if (S.board.active) S.mode = null;
      paint();
      if (S.tab === 'feed' && !side.hidden) loadFeed();
    }).catch(function (e) { if (!side.hidden) body.innerHTML = '<p class="cc-err" role="alert">' + esc(e.message) + '</p>'; });
  }
  function loadFeed() {
    return req('command-act.php?do=feed').then(function (j) { S.feed = j.feed || []; if (S.tab === 'feed') paintBody(); }).catch(function () {});
  }
  function say(msg, bad) {
    var t = document.getElementById('cc-toast'); if (!t) return;
    t.textContent = msg; t.className = 'cc-toast' + (bad ? ' cc-toast--bad' : ''); t.hidden = false;
    clearTimeout(t._h); t._h = setTimeout(function () { t.hidden = true; }, 4200);
  }

  // ---- the bar across the top, and the suggestion ---------------------------
  function paintBar() {
    var a = S.board && S.board.active;
    document.body.classList.toggle('cc-on', !!a);
    ['fire', 'quake', 'flood', 'typhoon'].forEach(function (m) { document.body.classList.toggle('ccm-' + m, !!a && a.mode === m); });
    if (!a) { bar.hidden = true; return; }
    var c = S.board.counts || {};
    bar.hidden = false;
    bar.style.setProperty('--cc', COL[a.mode]);
    bar.innerHTML = '<span class="cc-bar-ic">' + ico(a.mode, 18) + '</span>' +
      '<span class="cc-bar-t"><b>' + esc(nm(a)) + '</b><small>' + esc(tr('On since', 'Naka-on mula')) + ' ' + esc(day(a.started_at)) + ' · ' + who(a.started_by) +
      ' · ' + esc(tr('as of', 'as of')) + ' ' + esc(tm(S.board.as_of)) + '</small></span>' +
      '<span class="cc-bar-n"><b>' + (c.reports || 0) + '</b><small>' + esc(tr('reports', 'ulat')) + '</small></span>' +
      '<span class="cc-bar-n"><b>' + (c.open || 0) + '</b><small>' + esc(tr('open', 'bukas')) + '</small></span>' +
      '<button type="button" class="cc-bar-b" data-go="board">' + esc(tr('Board', 'Pisara')) + '</button>' +
      '<button type="button" class="cc-bar-b" data-go="handover">' + esc(tr('Hand over', 'I-handover')) + '</button>';
  }
  function paintSuggest() {
    var s = S.board && S.board.suggestion;
    if (!s || S.quiet[s.mode]) { sug.hidden = true; return; }
    sug.hidden = false;
    sug.style.setProperty('--cc', COL[s.mode]);
    // just under the map's title box, wherever it ends
    var shell = document.getElementById('s-spatial'), sr = document.getElementById('map-search');
    if (shell && sr) sug.style.top = Math.round(sr.getBoundingClientRect().bottom - shell.getBoundingClientRect().top + 10) + 'px';
    var on = S.board.active ? tr('Switch to', 'Lumipat sa') : tr('Turn on', 'I-on ang');
    sug.innerHTML = '<span class="cc-sug-ic">' + ico(s.mode, 20) + '</span><div class="cc-sug-t"><b>' + esc(tr('SMART suggests', 'Mungkahi ng SMART:')) + ' ' + esc(nm(s, 'name_')) + '</b>' +
      '<small>' + esc(tr(s.why_en, s.why_fil)) + '</small></div>' +
      '<button type="button" class="p-btn p-btn-sm cc-sug-on" data-mode="' + esc(s.mode) + '">' + esc(on + ' ' + nm(s, 'name_')) + '</button>' +
      '<button type="button" class="p-btn p-btn-ghost p-btn-sm cc-sug-no" data-mode="' + esc(s.mode) + '">' + esc(tr('Not now', 'Hindi muna')) + '</button>';
  }
  sug.addEventListener('click', function (e) {
    var on = e.target.closest('.cc-sug-on'), no = e.target.closest('.cc-sug-no');
    if (on) { var s = S.board.suggestion; on.disabled = true;
      act({ action: 'start', mode: on.dataset.mode, how: 'suggested', reason: tr(s.why_en, s.why_fil) })
        .then(function (j) { say(j.message); S.mode = null; S.picking = null; S.tab = 'board'; openSide(); return load(); })
        .catch(function (x) { say(x.message, true); on.disabled = false; }); }
    if (no) { S.quiet[no.dataset.mode] = true; paintSuggest();
      act({ action: 'dismiss', mode: no.dataset.mode }).then(function (j) { say(j.message); }).catch(function (x) { say(x.message, true); }); }
  });
  bar.addEventListener('click', function (e) { var b = e.target.closest('[data-go]'); if (!b) return; S.tab = b.dataset.go; openSide(); paint(); });

  // ---- the drawer ----------------------------------------------------------
  function paintHead() {
    var b = S.board || {}, m = b.mode, a = b.active;
    var title = m ? nm(b) : tr('Command center', 'Sentro ng Pamamahala');
    side.setAttribute('data-m', m || '');
    head.innerHTML = '<span class="cc-head-ic" style="--cc:' + (COL[m] || 'var(--p-primary)') + '">' + ico(m || 'quake', 20) + '</span>' +
      '<div><b>' + esc(title) + '</b><small>' + (m ? (b.live ? esc(tr('On', 'Naka-on')) + ' · ' + esc(tr('as of', 'as of')) + ' ' + esc(tm(b.as_of))
        : esc(tr('Looking only: nothing is on', 'Tinitingnan lamang: walang naka-on'))) : esc(tr('Nothing is on', 'Walang naka-on'))) + '</small></div>' +
      (m && !a ? '<button type="button" class="cc-back" data-back="1">' + esc(tr('All modes', 'Lahat ng mode')) + '</button>' : '');
  }
  function tabs() {
    var b = S.board;
    if (!b || !b.mode) return '';
    var t = [['board', tr('Board', 'Pisara')], ['checklist', tr('Checklist', 'Checklist')], ['feed', tr('Feed', 'Feed')]];
    if (b.live) t.push(['handover', tr('Handover', 'Handover')]);
    return '<div class="cc-tabs" role="tablist">' + t.map(function (x) {
      return '<button type="button" role="tab" aria-selected="' + (S.tab === x[0]) + '" data-tab="' + x[0] + '">' + esc(x[1]) + '</button>'; }).join('') + '</div>';
  }
  function picker() {
    var modes = (S.board && S.board.modes) || [];
    return '<p class="cc-lead">' + esc(tr('Turn Spatial Distribution into a command center for one situation. Look first, or turn a mode on with a reason; SMART can also suggest one.', 'Gawing command center ang Spatial Distribution para sa isang sitwasyon. Tumingin muna, o i-on ang isang mode na may dahilan; maaari ring magmungkahi ang SMART.')) + '</p>' +
      '<ul class="cc-modes">' + modes.map(function (m) {
        var w = WHAT[m.mode] || ['', ''];
        return '<li style="--cc:' + COL[m.mode] + '"><span class="cc-mode-ic">' + ico(m.mode, 22) + '</span><div><b>' + esc(nm(m)) + '</b><small>' + esc(tr(w[0], w[1])) + '</small>' +
          (S.picking === m.mode
            ? '<form class="cc-form" data-start="' + esc(m.mode) + '"><label for="cc-why">' + esc(tr('Why turn it on?', 'Bakit ito io-on?')) + '</label>' +
              '<textarea id="cc-why" name="reason" required minlength="3" maxlength="300" rows="2" placeholder="' + esc(tr('For example: heavy rain, water rising on three streets', 'Halimbawa: malakas ang ulan, tumataas ang tubig sa tatlong kalye')) + '"></textarea>' +
              '<div class="cc-row"><button class="p-btn p-btn-sm" type="submit">' + esc(tr('Turn on', 'I-on')) + ' ' + esc(nm(m)) + '</button><button type="button" class="p-btn p-btn-ghost p-btn-sm" data-cancel="1">' + esc(tr('Cancel', 'Kanselahin')) + '</button></div></form>'
            : '<div class="cc-row"><button type="button" class="p-btn p-btn-ghost p-btn-sm" data-look="' + esc(m.mode) + '">' + esc(tr('Look first', 'Tingnan muna')) + '</button>' +
              '<button type="button" class="p-btn p-btn-sm" data-pick="' + esc(m.mode) + '">' + esc(tr('Turn on…', 'I-on…')) + '</button></div>') +
          '</div></li>';
      }).join('') + '</ul>';
  }
  function tiles(b) {
    var c = b.counts || {}, t = b.tanods || {};
    return '<div class="cc-tiles">' + [[c.reports, tr('Reports', 'Ulat')], [c.open, tr('Open', 'Bukas')], [c.dispatched, tr('Tanods sent', 'Naipadalang tanod')], [t.on_duty, tr('Tanods on duty', 'Tanod na naka-duty')]]
      .map(function (x) { return '<div class="cc-tile"><b>' + (x[0] || 0) + '</b><span>' + esc(x[1]) + '</span></div>'; }).join('') + '</div>' +
      '<p class="cc-note">' + esc(tr('Reports since', 'Mga ulat mula')) + ' ' + esc(day(b.since)) + (c.residents ? ' · ' + esc(tr('from', 'mula sa')) + ' ' + c.residents + ' ' + esc(tr('residents', 'residente')) : '') +
      (c.last_at ? ' · ' + esc(tr('latest', 'pinakahuli')) + ' ' + esc(tm(c.last_at)) : '') + '</p>';
  }
  function tagList(b) {
    if (!b.tags || !b.tags.length) return '';
    return '<p class="p-eyebrow">' + esc(b.mode === 'flood' ? tr('Depth reported (MMDA flood gauge)', 'Iniulat na lalim (flood gauge ng MMDA)') : tr('What residents reported', 'Ang iniulat ng mga residente')) + '</p>' +
      '<ul class="cc-tags">' + b.tags.map(function (t) {
        return '<li data-rank="' + t.rank + '"><span class="cc-sw cc-r' + Math.min(8, t.rank) + '"></span><b>' + esc(tr('Reported', 'Iniulat:')) + ' ' + esc(tr(t.en, t.fil)) + '</b><small>' +
          t.reports + ' ' + esc(t.reports === 1 ? tr('report', 'ulat') : tr('reports', 'ulat')) + ' · ' + esc(tr('latest', 'pinakahuli')) + ' ' + esc(tm(t.last_at)) + '</small></li>'; }).join('') + '</ul>';
  }
  function cellList(b) {
    if (!b.cells || !b.cells.length) return '<p class="cc-none">' + esc(tr('No reports for this mode yet.', 'Wala pang ulat para sa mode na ito.')) + '</p>';
    return '<p class="p-eyebrow">' + esc(tr('By 100 m square, worst first', 'Bawat 100 m na parisukat, pinakamalala muna')) + '<em>' + b.cells.length + '</em></p><ol class="cc-cells">' +
      b.cells.slice(0, 12).map(function (c, i) {
        var zone = c.noah ? ' · ' + tr('NOAH flood zone', 'NOAH flood zone') + ' ' + ['', tr('low', 'mababa'), tr('medium', 'katamtaman'), tr('high', 'mataas')][c.noah] : '';
        return '<li><button type="button" class="cc-cell" data-i="' + i + '"><span class="cc-sw cc-r' + Math.min(8, c.rank || 0) + '"></span><span><b>' +
          esc(c.tag ? tr('Reported', 'Iniulat:') + ' ' + tr(c.tag_en, c.tag_fil) : tr('Reported, no depth given', 'Iniulat, walang lalim na binanggit')) + '</b><small>' +
          c.reports + ' ' + esc(c.reports === 1 ? tr('report', 'ulat') : tr('reports', 'ulat')) + ', ' + c.open + ' ' + esc(tr('open', 'bukas')) + esc(zone) + ' · ' + esc(tr('as of', 'as of')) + ' ' + esc(tm(c.last_at)) +
          '</small><i>' + esc((c.tracking_ids || []).slice(0, 3).join(', ')) + '</i></span></button></li>';
      }).join('') + '</ol>';
  }
  function siteList(b) {
    if (!b.sites || !b.sites.length) return '<p class="cc-none">' + esc(tr('No fire reported in this window.', 'Walang naiulat na sunog sa panahong ito.')) + '</p>';
    return b.sites.map(function (s, i) {
      var rings = (s.rings || []).map(function (r) {
        var named = (r.named || []).map(function (p) { return esc(p.name) + ' <i>' + p.metres + ' m</i>'; }).join(', ');
        return '<li><b>' + esc(tr('Within', 'Sa loob ng')) + ' ' + r.metres + ' m</b><small>' + r.places + ' ' + esc(tr('places of note', 'mahalagang lugar')) +
          (r.other_reports ? ' · ' + r.other_reports + ' ' + esc(tr('other reports', 'iba pang ulat')) : '') + '</small>' + (named ? '<span>' + named + '</span>' : '') + '</li>';
      }).join('');
      var tn = (s.tanods || []).map(function (t) { return esc(t.name) + ' <i>' + t.metres + ' m, ' + esc(tr('as of', 'as of')) + ' ' + esc(tm(t.as_of)) + '</i>'; }).join('<br>');
      return '<section class="cc-site"><button type="button" class="cc-cell" data-site="' + i + '"><span class="cc-sw cc-fire"></span><span><b>' +
        esc(tr('Fire reported', 'Iniulat na sunog')) + (s.tag ? ' · ' + esc(tr(s.tag_en, s.tag_fil)) : '') + '</b><small>' + s.reports + ' ' + esc(s.reports === 1 ? tr('report', 'ulat') : tr('reports', 'ulat')) +
        ' · ' + esc(tr('first', 'una')) + ' ' + esc(tm(s.first_at)) + ', ' + esc(tr('latest', 'pinakahuli')) + ' ' + esc(tm(s.last_at)) + '</small><i>' + esc((s.tracking_ids || []).join(', ')) + '</i></span></button>' +
        '<ul class="cc-rings">' + rings + '</ul>' +
        '<p class="cc-note">' + (s.fire_station ? esc(tr('Nearest fire station:', 'Pinakamalapit na istasyon ng bumbero:')) + ' ' + esc(s.fire_station.name) + ', ' + s.fire_station.metres + ' m. ' : '') +
        (tn ? '<br>' + esc(tr('Nearest tanods on duty:', 'Pinakamalapit na tanod na naka-duty:')) + '<br>' + tn : esc(tr('No tanod on duty has shared a location in the last 15 minutes.', 'Walang tanod na naka-duty ang nagbahagi ng lokasyon sa nakaraang 15 minuto.'))) + '</p></section>';
    }).join('');
  }
  function placeList(b) {
    var ps = b.places || [];
    if (!ps.length) return '<p class="cc-none">' + esc(tr('No public buildings are listed inside the barangay.', 'Walang nakalistang pampublikong gusali sa loob ng barangay.')) + '</p>';
    var done = ps.filter(function (p) { return p.status; }).length;
    var opts = [['ok', tr('OK', 'Maayos')], ['damage', tr('Damage seen', 'May pinsala')], ['closed', tr('Closed', 'Sarado')]];
    return '<p class="p-eyebrow">' + esc(tr('Places to check', 'Mga lugar na susuriin')) + '<em>' + done + ' / ' + ps.length + '</em></p>' +
      (b.live ? '' : '<p class="cc-note">' + esc(tr('Turn Quake Check on to mark places.', 'I-on ang Quake Check para markahan ang mga lugar.')) + '</p>') +
      '<ul class="cc-places">' + ps.map(function (p) {
        return '<li data-status="' + esc(p.status || '') + '"><button type="button" class="cc-pl-go" data-lat="' + p.lat + '" data-lng="' + p.lng + '"><b>' + esc(p.name) + '</b><small>' + esc(p.kind.replace(/_/g, ' ')) +
          (p.reports_near ? ' · ' + p.reports_near + ' ' + esc(tr('reports within 75 m', 'ulat sa loob ng 75 m')) : '') + (p.status ? ' · ' + esc(tm(p.at)) + (p.by ? ', ' + esc(p.by) : '') : '') + '</small></button>' +
          (b.live ? '<span class="cc-seg" role="group" aria-label="' + esc(p.name) + '">' + opts.map(function (o) {
            return '<button type="button" data-place="' + p.id + '" data-st="' + o[0] + '" aria-pressed="' + (p.status === o[0]) + '">' + esc(o[1]) + '</button>'; }).join('') + '</span>' : '') + '</li>';
      }).join('') + '</ul>';
  }
  function boardTab(b) {
    var h = tiles(b);
    if (b.mode === 'typhoon') {
      var st = b.storm || {};
      h += '<div class="cc-strip"><span><b>' + esc(S.signal ? tr('PAGASA Wind Signal No.', 'Wind Signal No.') + ' ' + S.signal : tr('No wind signal over Metro Manila', 'Walang wind signal sa Metro Manila')) + '</b><small>' +
        esc(tr('from PAGASA, as the hazard feed last read it', 'mula sa PAGASA, ayon sa huling basa ng hazard feed')) + '</small></span><span><b>' +
        esc(st.on ? tr('Storm mode on', 'Naka-on ang storm mode') : tr('Storm mode off', 'Naka-off ang storm mode')) + '</b><small>' + esc(st.on && st.until ? tr('until', 'hanggang') + ' ' + day(st.until) : tr('Settings → SMART', 'Settings → SMART')) + '</small></span></div>';
    }
    if (b.mode === 'flood') {
      h += '<div class="cc-gauge" aria-label="' + esc(tr('MMDA flood gauge', 'Flood gauge ng MMDA')) + '">' + ['gutter 8"', 'half-knee 10"', 'half-tire 13"', 'knee 19"', 'tire 26"', 'waist 37"', 'chest 45"'].map(function (g, i) {
        return '<span class="cc-r' + (i + 1) + '">' + esc(g) + '</span>'; }).join('') + '</div>';
    }
    h += tagList(b);
    if (b.mode === 'fire') h += siteList(b);
    else if (b.mode === 'quake') h += cellList(b) + placeList(b);
    else h += cellList(b);
    h += '<p class="cc-foot">' + esc(tr('What residents reported, where and when. SMART does not predict where water, fire or damage will go.', 'Ang iniulat ng mga residente, saan at kailan. Hindi hinuhulaan ng SMART kung saan pupunta ang tubig, apoy o pinsala.')) + '</p>';
    if (!b.live && !(b.active)) {
      h += '<div class="cc-cta"><button type="button" class="p-btn p-btn-sm" data-pick="' + esc(b.mode) + '" data-back="1">' + esc(tr('Turn on', 'I-on ang')) + ' ' + esc(nm(b)) + '</button></div>';
    }
    return h;
  }
  function checklistTab(b) {
    var l = b.checklist || [], done = l.filter(function (x) { return x.done; }).length;
    return '<p class="p-eyebrow">' + esc(tr('Checklist', 'Checklist')) + '<em>' + done + ' / ' + l.length + '</em></p>' +
      (b.live ? '' : '<p class="cc-note">' + esc(tr('Ticks are kept while the mode is on.', 'Naitatala ang tsek habang naka-on ang mode.')) + '</p>') +
      '<ul class="cc-check">' + l.map(function (x) {
        return '<li><label><input type="checkbox" data-item="' + esc(x.key) + '"' + (x.done ? ' checked' : '') + (b.live ? '' : ' disabled') + '><span>' + esc(tr(x.en, x.fil)) +
          (x.done ? '<small>' + esc(tm(x.at)) + (x.by ? ', ' + esc(x.by) : '') + (x.note ? ' · ' + esc(x.note) : '') + '</small>' : '') + '</span></label></li>'; }).join('') + '</ul>';
  }
  function feedLine(f) {
    var t = '<time>' + esc(tm(f.at)) + '</time>';
    switch (f.kind) {
      case 'filed': return t + '<span><b>' + esc(f.tracking_id) + '</b> ' + esc(tr('filed', 'naisampa')) + ': ' + esc(f.subject || '') + (f.place ? ' <i>' + esc(f.place) + '</i>' : '') + '</span>';
      case 'status': return t + '<span><b>' + esc(f.tracking_id) + '</b> ' + esc((C.status[f.from] || f.from) + ' → ' + (C.status[f.to] || f.to)) + (f.by ? ' <i>' + esc(f.by) + '</i>' : '') + '</span>';
      case 'dispatch': return t + '<span><b>' + esc(f.tracking_id) + '</b> ' + esc({ assigned: tr('tanod sent', 'naipadala ang tanod'), accepted: tr('tanod on the way', 'papunta na ang tanod'), resolved: tr('tanod finished', 'tapos na ang tanod') }[f.state] || f.state) + (f.tanod ? ' <i>' + esc(f.tanod) + '</i>' : '') + '</span>';
      case 'check': return t + '<span>' + esc(f.done ? '✓ ' : '○ ') + esc(tr(f.en, f.fil)) + (f.by ? ' <i>' + esc(f.by) + '</i>' : '') + '</span>';
      case 'place': return t + '<span><b>' + esc(f.name) + '</b> ' + esc({ ok: tr('checked: OK', 'nasuri: maayos'), damage: tr('checked: damage seen', 'nasuri: may pinsala'), closed: tr('checked: closed', 'nasuri: sarado') }[f.status] || f.status) + (f.by ? ' <i>' + esc(f.by) + '</i>' : '') + '</span>';
      default: return t + '<span class="cc-smart">SMART · ' + esc(f.summary || '') + '</span>';
    }
  }
  function feedTab() {
    if (!S.feed) { loadFeed(); return '<p class="cc-none">' + esc(tr('Reading the feed…', 'Binabasa ang feed…')) + '</p>'; }
    if (!S.feed.length) return '<p class="cc-none">' + esc(tr('Nothing has happened in this window yet.', 'Wala pang nangyari sa panahong ito.')) + '</p>';
    return '<ol class="cc-feed">' + S.feed.map(function (f) { return '<li data-k="' + esc(f.kind) + '">' + feedLine(f) + '</li>'; }).join('') + '</ol>';
  }
  function handoverTab(b) {
    var h = b.handover;
    return (h ? '<div class="cc-last"><p class="p-eyebrow">' + esc(tr('Last handover', 'Huling handover')) + '</p><p>' + esc(h.note) + '</p><small>' + esc(day(h.at)) + (h.by ? ' · ' + esc(h.by) : '') + '</small></div>' : '') +
      '<form class="cc-form" data-hand="1"><label for="cc-hand">' + esc(tr('Hand over to the next shift', 'I-handover sa susunod na shift')) + '</label>' +
      '<textarea id="cc-hand" name="note" required minlength="5" maxlength="1000" rows="3" placeholder="' + esc(tr('What the next shift needs to know: what is done, what is waiting, who is where', 'Ang dapat malaman ng susunod na shift: ano ang tapos, ano ang naghihintay, sino ang nasaan')) + '"></textarea>' +
      '<div class="cc-row"><button class="p-btn p-btn-sm" type="submit">' + esc(tr('Save handover', 'I-save ang handover')) + '</button></div>' +
      '<p class="cc-note">' + esc(tr('The counts and the checklist are kept with the note, and the other administrators are told.', 'Kasama ng note ang mga bilang at ang checklist, at nasasabihan ang ibang administrator.')) + '</p></form>' +
      '<form class="cc-form cc-end" data-end="1"><label for="cc-endn">' + esc(tr('Turn the mode off', 'I-off ang mode')) + '</label>' +
      '<textarea id="cc-endn" name="note" required minlength="5" maxlength="1000" rows="2" placeholder="' + esc(tr('A closing note for the record', 'Pangwakas na note para sa tala')) + '"></textarea>' +
      '<div class="cc-row"><button class="p-btn p-btn-ghost p-btn-sm" type="submit">' + esc(tr('Turn off', 'I-off ang')) + ' ' + esc(nm(b)) + '</button></div>' +
      '<p class="cc-note">' + esc(tr('SMART can switch a mode on; only a person switches it off.', 'Maaaring mag-on ng mode ang SMART; tao lamang ang nag-o-off nito.')) + '</p></form>';
  }
  function paintBody() {
    var b = S.board;
    if (!b) { body.innerHTML = '<p class="cc-none">' + esc(tr('Reading the board…', 'Binabasa ang pisara…')) + '</p>'; return; }
    if (!b.mode) { body.innerHTML = picker(); return; }
    var t = S.tab === 'handover' && !b.live ? 'board' : S.tab;
    body.innerHTML = tabs() + '<div class="cc-pane">' + (t === 'checklist' ? checklistTab(b) : t === 'feed' ? feedTab() : t === 'handover' ? handoverTab(b) : boardTab(b)) + '</div>';
  }
  function paint() { paintBar(); paintSuggest(); if (!side.hidden) { paintHead(); paintBody(); } layers(); }

  body.addEventListener('click', function (e) {
    var x;
    if ((x = e.target.closest('[data-tab]'))) { S.tab = x.dataset.tab; paintBody(); return; }
    if ((x = e.target.closest('[data-look]'))) { S.mode = x.dataset.look; S.tab = 'board'; S.board = Object.assign({}, S.board, { mode: null }); paintBody(); load(); return; }
    if ((x = e.target.closest('[data-pick]'))) {
      if (x.dataset.back) { S.mode = null; S.board = Object.assign({}, S.board, { mode: null }); }
      S.picking = x.dataset.pick; paintHead(); paintBody(); var w = document.getElementById('cc-why'); if (w) w.focus(); return;
    }
    if (e.target.closest('[data-cancel]')) { S.picking = null; paintBody(); return; }
    if ((x = e.target.closest('[data-place]'))) {
      var st = x.getAttribute('aria-pressed') === 'true' ? '' : x.dataset.st;
      act({ action: 'place', place: x.dataset.place, status: st }).then(load).catch(function (er) { say(er.message, true); }); return;
    }
    if ((x = e.target.closest('.cc-pl-go'))) { fly(+x.dataset.lng, +x.dataset.lat, 18); return; }
    if ((x = e.target.closest('[data-i]'))) { var c = S.board.cells[+x.dataset.i]; if (c) fly(c.lng, c.lat, 17.5); return; }
    if ((x = e.target.closest('[data-site]'))) { var s = S.board.sites[+x.dataset.site]; if (s) fly(s.lng, s.lat, 17); }
  });
  head.addEventListener('click', function (e) { if (e.target.closest('[data-back]')) { S.mode = null; S.picking = null; S.board = Object.assign({}, S.board, { mode: null }); paintHead(); paintBody(); layers(); load(); } });
  body.addEventListener('change', function (e) {
    var cb = e.target.closest('input[data-item]');
    if (cb) act({ action: 'check', item: cb.dataset.item, done: cb.checked ? '1' : '0' }).then(load).catch(function (er) { cb.checked = !cb.checked; say(er.message, true); });
  });
  body.addEventListener('submit', function (e) {
    var f = e.target.closest('form.cc-form'); if (!f) return;
    e.preventDefault();
    var sb = f.querySelector('button[type=submit]'); sb.disabled = true;
    var done = function (j) { say(j.message); S.picking = null; return load(); };
    var fail = function (er) { say(er.message, true); sb.disabled = false; };
    if (f.dataset.start) act({ action: 'start', mode: f.dataset.start, reason: f.reason.value }).then(function (j) { S.mode = null; S.tab = 'board'; return done(j); }).catch(fail);
    else if (f.dataset.hand) act({ action: 'handover', note: f.note.value }).then(done).catch(fail);
    else if (f.dataset.end) act({ action: 'end', note: f.note.value }).then(function (j) { S.tab = 'board'; S.mode = null; return done(j); }).catch(fail);
  });

  // ---- the map ---------------------------------------------------------------
  var RAMP = { flood: ['#CFE8FF', '#A9D4FB', '#7FBDF5', '#4FA0EC', '#2A82DD', '#1565C0', '#0D47A1', '#08306B'],
               damage: ['#FFE0B2', '#FFC680', '#FFA94D', '#FB8C00', '#F4511E', '#E53935', '#C62828', '#8E0000'] };
  function ensure() {
    if (typeof map === 'undefined' || map.getSource('cc-cells')) return typeof map !== 'undefined';
    var before = map.getLayer('clusters') ? 'clusters' : (map.getLayer('pins') ? 'pins' : undefined);
    ['cc-cells', 'cc-rings', 'cc-sites', 'cc-places'].forEach(function (s) { map.addSource(s, { type: 'geojson', data: EMPTY }); });
    map.addLayer({ id: 'cc-cells', type: 'fill', source: 'cc-cells', paint: { 'fill-color': ['get', 'c'], 'fill-opacity': 0.42 } }, before);
    map.addLayer({ id: 'cc-cells-line', type: 'line', source: 'cc-cells', paint: { 'line-color': ['get', 'c'], 'line-width': 1.5, 'line-opacity': 0.9 } }, before);
    map.addLayer({ id: 'cc-rings', type: 'line', source: 'cc-rings', paint: { 'line-color': ['get', 'c'], 'line-width': 2, 'line-dasharray': [2, 1.5] } }, before);
    map.addLayer({ id: 'cc-sites', type: 'circle', source: 'cc-sites', paint: { 'circle-radius': 9, 'circle-color': '#E5383B', 'circle-stroke-color': '#fff', 'circle-stroke-width': 2.5 } }, before);
    map.addLayer({ id: 'cc-places', type: 'circle', source: 'cc-places', paint: { 'circle-radius': 6.5, 'circle-color': ['get', 'c'], 'circle-stroke-color': '#fff', 'circle-stroke-width': 2 } }, before);
    return true;
  }
  function circle(lng, lat, m) {
    var pts = [], k = m / 6371008.8, la = lat * Math.PI / 180, lo = lng * Math.PI / 180;
    for (var i = 0; i <= 64; i++) {
      var b = i / 64 * 2 * Math.PI, la2 = Math.asin(Math.sin(la) * Math.cos(k) + Math.cos(la) * Math.sin(k) * Math.cos(b)),
          lo2 = lo + Math.atan2(Math.sin(b) * Math.sin(k) * Math.cos(la), Math.cos(k) - Math.sin(la) * Math.sin(la2));
      pts.push([lo2 * 180 / Math.PI, la2 * 180 / Math.PI]);
    }
    return { type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [pts] } };
  }
  function layers() {
    if (typeof mapReady === 'undefined') return;
    mapReady.then(function () {
      if (!ensure()) return;
      var b = S.board || {}, show = !!b.mode, ramp = RAMP[b.mode === 'flood' ? 'flood' : 'damage'];
      var cells = show ? (b.cells || []).map(function (c) { return { type: 'Feature', properties: { c: ramp[Math.max(0, Math.min(7, (c.rank || 1) - 1))] }, geometry: c.outline }; }) : [];
      var rings = [], sites = [];
      if (show && b.mode === 'fire') (b.sites || []).forEach(function (s) {
        sites.push({ type: 'Feature', properties: {}, geometry: { type: 'Point', coordinates: [s.lng, s.lat] } });
        [[50, '#E5383B'], [100, '#FB8C00'], [200, '#F9A825']].forEach(function (r) { var f = circle(s.lng, s.lat, r[0]); f.properties.c = r[1]; rings.push(f); });
      });
      var pc = { ok: '#2E7D32', damage: '#E5383B', closed: '#37474F' };
      var places = show && b.mode === 'quake' ? (b.places || []).map(function (p) { return { type: 'Feature', properties: { c: pc[p.status] || '#90A4AE' }, geometry: { type: 'Point', coordinates: [p.lng, p.lat] } }; }) : [];
      map.getSource('cc-cells').setData({ type: 'FeatureCollection', features: cells });
      map.getSource('cc-rings').setData({ type: 'FeatureCollection', features: rings });
      map.getSource('cc-sites').setData({ type: 'FeatureCollection', features: sites });
      map.getSource('cc-places').setData({ type: 'FeatureCollection', features: places });
    });
  }
  function fly(lng, lat, z) { if (typeof map !== 'undefined' && isFinite(lng) && isFinite(lat)) map.flyTo({ center: [lng, lat], zoom: z, essential: true }); }

  // ---- open, close, refresh -----------------------------------------------------
  function openSide() { if (side.hidden && typeof mapDrawer === 'function') mapDrawer('command'); side.hidden = false; btn.setAttribute('aria-expanded', 'true'); paintHead(); paintBody(); }
  function close() { side.hidden = true; btn.setAttribute('aria-expanded', 'false'); }
  btn.addEventListener('click', function () { if (side.hidden) { openSide(); load(); } else close(); });
  side.addEventListener('keydown', function (e) { if (e.key === 'Escape') { e.stopPropagation(); close(); btn.focus(); } });
  window.sdCmd = { close: close, isClosed: function () { return side.hidden; } };
  // every 30 seconds while the page is in view; the bar and the banner stay current even with the drawer shut
  function tick() { if (!document.hidden) load(); }
  S.timer = setInterval(tick, 30000);
  document.addEventListener('visibilitychange', function () { if (!document.hidden) load(); });
  load();
})();
