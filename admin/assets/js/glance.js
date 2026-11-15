/* The sign-in pages' "At a glance" panel (15 Nov 2026, Ace). The picture is drawn by signin.css from two attributes on #gl: data-phase (dawn, day, golden, dusk,
   night) and data-wx (clear, cloudy, rain, storm). This fills the words and the rows from glance.php, public information only (includes/glance.php), asks again every
   five minutes while the tab is open, and keeps the picture from the clock if the feed cannot be read. Hotlines open when pressed. No inline handlers (strict CSP). */
(function () {
  'use strict';
  var gl = document.getElementById('gl'); if (!gl) { return; }
  var T = typeof window.T === 'function' ? window.T : function (en) { return en; };
  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function safeUrl(u) { return /^https:\/\//i.test(u || '') ? u : ''; }

  var NAMES = { clear: null, cloudy: T('Cloudy', 'Maulap'), rain: T('Heavy rain', 'Malakas na ulan'), storm: T('Thunderstorm', 'Pagkulog at pagkidlat') };
  function condition(kind, phase) {
    if (kind === 'clear') { return phase === 'night' ? T('Clear night', 'Maaliwalas na gabi') : phase === 'day' ? T('Sunny', 'Maaraw') : T('Clear', 'Maaliwalas'); }
    return NAMES[kind] || '';
  }
  var LEVEL = { 1: T('Yellow', 'Dilaw'), 2: T('Orange', 'Kahel'), 3: T('Red', 'Pula') };
  function warnTitle(w) {
    if (w.kind === 'wind') { return T('Wind signal no. ', 'Wind signal blg. ') + (w.signal || ''); }
    var lv = LEVEL[w.level] || '';
    return w.kind === 'thunder' ? lv + ' ' + T('thunderstorm warning', 'babala sa pagkulog') : lv + ' ' + T('rainfall warning', 'babala sa ulan');
  }
  function untilText(w) {
    if (!w.until) { return 'PAGASA'; }
    var d = new Date(w.until); if (isNaN(d.getTime())) { return 'PAGASA'; }
    return 'PAGASA · ' + T('until ', 'hanggang ') + d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  }

  function phaseFromClock() {
    var h = new Date().getHours();
    return h < 5 ? 'night' : h < 7 ? 'dawn' : h < 15 ? 'day' : h < 17 ? 'golden' : h < 19 ? 'dusk' : 'night';
  }

  function render(d) {
    if (!d || d.ok === false) { gl.setAttribute('data-phase', phaseFromClock()); $('gl-cond').textContent = T('Weather unavailable', 'Walang datos sa panahon'); return; }
    var phase = d.phase || phaseFromClock(), kind = d.now ? d.now.kind : 'clear';
    gl.setAttribute('data-phase', phase); gl.setAttribute('data-wx', kind);
    if (d.now) {
      $('gl-temp').textContent = d.now.temp + '°';
      var cond = condition(kind, phase);
      $('gl-cond').textContent = cond;
      $('gl-when').textContent = T('NOW', 'NGAYON') + (d.when ? ' · ' + d.when : '');
      $('gl-sub').textContent = T('Feels like ', 'Pakiramdam ') + d.now.feels + '° · ' + T('wind ', 'hangin ') + d.now.wind + ' km/h';
      $('gl-scene').setAttribute('aria-label', cond + ', ' + d.now.temp + ' ' + T('degrees', 'digri') + (d.warn ? ', ' + warnTitle(d.warn) : ''));
    } else {
      $('gl-temp').textContent = ''; $('gl-cond').textContent = T('Weather unavailable', 'Walang datos sa panahon'); $('gl-sub').textContent = ''; $('gl-when').textContent = '';
    }
    var w = $('gl-warn');
    if (d.warn) { $('gl-warn-t').textContent = warnTitle(d.warn); $('gl-warn-s').textContent = untilText(d.warn); w.hidden = false; } else { w.hidden = true; }
    var f = $('gl-flood');
    if (d.flood === null || d.flood === undefined) { f.hidden = true; } else {
      $('gl-flood-t').textContent = d.flood ? T('Flood advisory in effect', 'May flood advisory') : T('No flood advisory', 'Walang flood advisory'); f.hidden = false;
    }
    var hot = d.hot || [], h = $('gl-hot');
    if (hot.length) {
      $('gl-hot-t').textContent = hot.slice(0, 3).map(function (g) { return g.name; }).join(' · ');
      var html = '';
      hot.forEach(function (g) {
        html += '<div class="g">' + esc(g.name.toUpperCase()) + '</div>';
        (g.numbers || []).forEach(function (n) {
          html += '<div class="n"><span><b>' + esc(n.label || g.name) + '</b><em>' + esc(n.number) + '</em></span>' + (n.tel ? '<a href="tel:' + esc(n.tel) + '">' + T('Call', 'Tawag') + '</a>' : '') + '</div>';
        });
      });
      $('gl-hotlist').innerHTML = html; h.hidden = false;
    } else { h.hidden = true; }
    var news = (d.news || []).filter(function (n) { return safeUrl(n.url); }), nb = $('gl-news');
    if (news.length) {
      $('gl-news-l').innerHTML = news.map(function (n) { return '<a href="' + esc(safeUrl(n.url)) + '" target="_blank" rel="noopener noreferrer">' + esc(n.t) + (n.src ? ' <em>' + esc(n.src) + '</em>' : '') + '</a>'; }).join('');
      nb.hidden = false;
    } else { nb.hidden = true; }
  }

  var btn = $('gl-hotbtn'), list = $('gl-hotlist');
  btn.addEventListener('click', function () { var open = btn.getAttribute('aria-expanded') !== 'true'; btn.setAttribute('aria-expanded', open ? 'true' : 'false'); list.hidden = !open; });

  /* When the server could not read the weather (a shared address can be turned away by the free service), the visitor's own browser asks Open-Meteo for the
     same four numbers: the portal's content-security policy already lists it, and nothing of ours goes with the request. */
  function wxKind(c) { return c >= 95 ? 'storm' : ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) ? 'rain' : (c === 0 || c === 1) ? 'clear' : 'cloudy'; }
  function browserWeather(d) {
    var q = 'latitude=14.5194&longitude=121.0122&timezone=Asia%2FManila&forecast_days=1&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m&daily=sunrise,sunset';
    return fetch('https://api.open-meteo.com/v1/forecast?' + q, { credentials: 'omit' })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (j) {
        var c = j && j.current; if (!c || typeof c.temperature_2m !== 'number') { return d; }
        var out = {}; for (var k in d) { out[k] = d[k]; }
        out.ok = true;
        out.now = { temp: Math.round(c.temperature_2m), feels: Math.round(c.apparent_temperature != null ? c.apparent_temperature : c.temperature_2m), wind: Math.round(c.wind_speed_10m || 0), kind: wxKind(c.weather_code | 0) };
        var rise = j.daily && j.daily.sunrise && Date.parse(j.daily.sunrise[0] + ':00+08:00'), set = j.daily && j.daily.sunset && Date.parse(j.daily.sunset[0] + ':00+08:00'), n = Date.now();
        if (rise && set) {
          out.phase = (n < rise - 2700000 || n > set + 3000000) ? 'night' : n < rise + 3600000 ? 'dawn' : n < set - 7200000 ? 'day' : n < set - 1200000 ? 'golden' : 'dusk';
        }
        return out;
      }).catch(function () { return d; });
  }

  function load() {
    var demo = /[?&]demo=([a-z-]{3,20})/.exec(location.search);   // only the test portal honours it
    return fetch('glance.php' + (demo ? '?demo=' + demo[1] : ''), { credentials: 'omit', headers: { 'Accept': 'application/json' } })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .catch(function () { return null; })
      .then(function (d) { return d && d.ok !== false && d.now ? d : browserWeather(d || { ok: false }); })
      .then(render).catch(function () { render(null); });
  }
  load();
  setInterval(function () { if (!document.hidden) { load(); } }, 300000);
})();
