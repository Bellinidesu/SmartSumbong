/* Weather and flood watch on the dashboard (17 Oct 2026): layout C of the aesthetics page's Widgets section.
   The rain now, the next twelve hours as bars coloured by PAGASA's thresholds, PAGASA's own words for Metro Manila when it has a warning,
   and a cyclone line when one is near. Reads Open-Meteo for the rain falling now and the portal's hazards.php (PAGASA, GDACS) for the rest. */
(function () {
  var root = document.getElementById('hzw'); if (!root) return;
  var L = JSON.parse(root.getAttribute('data-l') || '{}');
  var LV = [['#22c55e', L.none], ['#eab308', L.yellow], ['#f97316', L.orange], ['#dc2626', L.red]];
  var esc = function (v) { return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  var level = function (mm) { return mm >= 30 ? 3 : mm >= 15 ? 2 : mm >= 7.5 ? 1 : 0; };
  var bar = function (mm) { return mm >= 30 ? '#dc2626' : mm >= 15 ? '#f97316' : mm >= 7.5 ? '#eab308' : '#7DB3E8'; };
  var clock = function (d) { return d ? new Date(d.replace(' ', 'T') + '+08:00').toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }) : ''; };
  var state = { mm: null, hz: null, at: null };

  function render() {
    var hz = state.hz, mm = state.mm, rain = mm == null ? 0 : level(mm);
    var off = hz ? Math.max.apply(null, [0].concat(hz.warnings.filter(function (w) { return w.metro && /rain/i.test(w.type); }).map(function (w) { return w.level; }))) : 0;
    var lvl = Math.max(rain, off), col = LV[lvl][0];
    var fc = hz && hz.forecast && hz.forecast.length ? hz.forecast : null, peak = fc ? Math.max.apply(null, fc.map(function (f) { return f.mm; })) : 0;
    var metro = hz ? hz.warnings.filter(function (w) { return w.metro; }) : [];
    var h = '<div class="hzw-top"><span class="hzw-pill' + (lvl ? ' pulse' : '') + '" style="--c:' + col + '"><i></i>' + esc(LV[lvl][1]) + '</span>' +
      '<div class="hzw-big">' + (mm == null ? '—' : mm.toFixed(1)) + '<small>mm/h</small></div>' +
      '<span class="hzw-note">' + esc(metro.length ? metro[0].text : (hz && hz.sources.pagasa_warnings ? L.clear : L.waiting)) + '</span></div>';
    if (fc) {
      h += '<div class="hzw-bars">' + fc.map(function (f, i) { return '<span class="' + (i === 0 ? 'now' : '') + '" style="height:' + Math.max(8, Math.round(f.mm / Math.max(30, peak) * 100)) + '%;--bc:' + bar(f.mm) + '" title="' + esc(f.h) + ' · ' + f.mm.toFixed(1) + ' mm/h"></span>'; }).join('') + '</div>' +
        '<div class="hzw-ax"><span>' + esc(L.now) + '</span><span>' + esc(fc[Math.floor(fc.length / 2)].h) + '</span><span>' + esc(fc[fc.length - 1].h) + '</span></div>' +
        '<p class="hzw-sm">' + esc(L.next.replace('{n}', fc.length)) + ' ' + esc(peak < 0.5 ? L.dry : L.peak.replace('{mm}', peak.toFixed(1))) + '</p>';
    }
    var cy = hz && hz.cyclone;
    if (cy) {
      h += '<div class="hzw-cy"><b>' + esc(L.typhoon) + ' · ' + esc(cy.name) + '</b><span>' + cy.km + ' km ' + esc(cy.dir) + (cy.gdacs && cy.gdacs.wind ? ' · ' + cy.gdacs.wind + ' km/h' : '') + (cy.signal ? ' · Signal ' + cy.signal : '') + '</span></div>';
    }
    h += '<div class="hzw-src"><i' + (mm == null ? ' class="off"' : '') + '>Open-Meteo</i><i' + (hz && hz.sources.pagasa_warnings ? '' : ' class="off"') + '>PAGASA</i><i' + (hz && hz.sources.gdacs ? '' : ' class="off"') + '>GDACS</i><span>' + esc(L.asof) + ' ' + (state.at ? state.at.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }) : '—') + '</span>' +
      (hz && hz.stale ? '<em>' + esc(L.old) + '</em>' : '') + '<a href="spatial.php">' + esc(L.map) + ' &rarr;</a></div>';
    root.style.setProperty('--c', col);
    root.querySelector('.hzw-body').innerHTML = h;
    var m = metro[0]; var link = root.querySelector('.hzw-pg');
    if (link) link.textContent = m ? 'PAGASA · ' + m.type + (m.severity ? ' (' + m.severity + ')' : '') + (m.expires ? ' · ' + L.until + ' ' + clock(m.expires) : '') : '';
  }

  function read() {
    fetch('https://api.open-meteo.com/v1/forecast?latitude=14.5194&longitude=121.0122&minutely_15=precipitation&past_minutely_15=4&forecast_minutely_15=0&timezone=Asia%2FManila', { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw 0; return r.json(); })
      .then(function (d) { var q = d.minutely_15.precipitation.filter(function (v) { return v != null; }); state.mm = q.length ? q.reduce(function (a, v) { return a + v; }, 0) : null; })
      .catch(function () { state.mm = null; })
      .then(function () { return fetch('hazards.php', { cache: 'no-store', credentials: 'same-origin' }).then(function (r) { if (!r.ok) throw 0; return r.json(); }).then(function (d) { state.hz = d && d.ok ? d : null; }).catch(function () { state.hz = null; }); })
      .then(function () { state.at = new Date(); render(); });
  }
  render(); read(); setInterval(read, 10 * 60 * 1000);
})();
