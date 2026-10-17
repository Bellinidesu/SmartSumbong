// The briefing on Notifications: a live clock with the sky and the weather for Pasay, and the morning, afternoon and night tabs.
// A tab makes the engine "think" for a moment (the glow the dashboard has), then the numbers swap in.
(function () {
  var root = document.getElementById('ss-brief');
  if (!root) return;
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches, busy = false;

  // ---- tabs
  function show(period) {
    root.querySelectorAll('[data-pane]').forEach(function (p) { p.hidden = p.dataset.pane !== period; });
    root.querySelectorAll('[data-period]').forEach(function (b) {
      var on = b.dataset.period === period;
      b.classList.toggle('p-on', on); b.setAttribute('aria-selected', String(on));
    });
    root.classList.remove('is-thinking'); root.classList.add('is-rise');
    setTimeout(function () { root.classList.remove('is-rise'); }, 700);
    busy = false;
  }
  root.querySelector('.ss-brief-tabs').addEventListener('click', function (e) {
    var b = e.target.closest('[data-period]');
    if (!b || busy || b.classList.contains('p-on')) return;
    if (reduce) { show(b.dataset.period); return; }
    busy = true; root.classList.add('is-thinking');
    setTimeout(function () { show(b.dataset.period); }, 650);
  });

  // the arrow folds and unfolds the widgets below (widgets-core.js listens for it)

  // ---- the clock (Manila time) and the sky behind it
  var clock = document.getElementById('ss-clock');
  if (!clock) return;
  var bar = document.getElementById('ss-bar');
  var tEl = document.getElementById('ss-clock-time'), apEl = document.getElementById('ss-clock-ampm');
  var lang = window.LANG === 'fil' ? 'fil-PH' : 'en-PH';
  var fmtT = new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Manila', hour: 'numeric', minute: '2-digit', hour12: true });
  var fmtH = new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Manila', hour: 'numeric', hour12: false });
  var fmtM = new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Manila', minute: 'numeric' });
  var fmtD = new Intl.DateTimeFormat(lang, { timeZone: 'Asia/Manila', weekday: 'long', month: 'long', day: 'numeric' });
  function sky(h) { return h >= 5 && h < 9 ? 'dawn' : h >= 9 && h < 16 ? 'day' : h >= 16 && h < 19 ? 'dusk' : 'night'; }
  var lastSky = '';
  function tick() {
    var now = new Date(), parts = fmtT.format(now).split(/\s+/), h = parseInt(fmtH.format(now), 10) % 24, m = parseInt(fmtM.format(now), 10);
    tEl.textContent = parts[0]; apEl.textContent = parts[1] || '';
    var de = document.getElementById('ss-date'); if (de) de.textContent = fmtD.format(now);
    var s = sky(h);
    if (s !== lastSky) { bar.dataset.sky = s; lastSky = s; }
    // the sun crosses the sky from 6 AM to 6 PM, the moon through the night
    var hh = h + m / 60, day = hh >= 6 && hh < 18, f = day ? (hh - 6) / 12 : ((hh + 6) % 24) / 12;
    f = Math.min(1, Math.max(0, f));
    clock.style.setProperty('--gx', Math.round(12 + 70 * f) + '%');
    clock.style.setProperty('--gy', Math.round(68 - 46 * Math.sin(Math.PI * f)) + '%');
    bar.dataset.orb = day ? 'sun' : 'moon';
  }
  tick(); setInterval(tick, 1000);

  // ---- the weather (Open-Meteo, the same source as the map's rain gauge) on a tile that wears the engine's glow:
  // the symbol follows the sky, the temperature rides on it, and the details wait in a tooltip.
  var W = window.SS_WX || {}, L = W.labels || {}, tile = document.getElementById('ss-wxt');
  var G = {
    sun: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><g class="ss-wg-spin"><circle cx="12" cy="12" r="4" fill="currentColor" fill-opacity=".3"/><path d="M12 2.5v2.2M12 19.3v2.2M2.5 12h2.2M19.3 12h2.2M5.3 5.3l1.6 1.6M17.1 17.1l1.6 1.6M18.7 5.3l-1.6 1.6M6.9 17.1l-1.6 1.6"/></g></svg>',
    moon: '<svg viewBox="0 0 24 24" fill="currentColor" fill-opacity=".3" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" aria-hidden="true"><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/></svg>',
    cloud: '<svg viewBox="0 0 24 24" fill="currentColor" fill-opacity=".25" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" aria-hidden="true"><path class="ss-wg-drift" d="M7 18a4.5 4.5 0 0 1-.4-9A6 6 0 0 1 18 10.5a3.7 3.7 0 0 1-.3 7.5z"/></svg>',
    rain: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7 14.5a4.5 4.5 0 0 1-.4-9A6 6 0 0 1 18 7a3.7 3.7 0 0 1-.3 7.5" fill="currentColor" fill-opacity=".25"/><path class="ss-wg-d1" d="M8 17.5l-1 2.5"/><path class="ss-wg-d2" d="M12 17.5l-1 2.5"/><path class="ss-wg-d3" d="M16 17.5l-1 2.5"/></svg>',
    storm: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7 14a4.5 4.5 0 0 1-.4-9A6 6 0 0 1 18 6.5a3.7 3.7 0 0 1-.3 7.5" fill="currentColor" fill-opacity=".25"/><path class="ss-wg-bolt" d="M12.5 11l-2.5 4h3l-2 4.5"/></svg>',
    fog: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M5 9h14M3 13h18M6 17h12"/></svg>'
  };
  function describe(code, isDay) {
    if (code === 0) return [isDay ? 'sun' : 'moon', L.clear];
    if (code === 1) return [isDay ? 'sun' : 'moon', L.mostly];
    if (code === 2) return ['cloud', L.partly];
    if (code === 3) return ['cloud', L.cloudy];
    if (code === 45 || code === 48) return ['fog', L.fog];
    if (code >= 51 && code <= 57) return ['rain', L.drizzle];
    if (code >= 61 && code <= 67) return ['rain', L.rain];
    if (code >= 80 && code <= 82) return ['rain', L.shower];
    if (code >= 95) return ['storm', L.storm];
    return ['cloud', L.cloudy];
  }
  var KEY = 'ss-wx-v2';
  function paint(d) {
    var c = d.current, info = describe(c.weather_code, c.is_day === 1);
    document.getElementById('ss-wxt-g').innerHTML = G[info[0]] || G.cloud;
    document.getElementById('ss-wxt-t').textContent = Math.round(c.temperature_2m) + '°';
    document.getElementById('ss-wxt-tip').innerHTML = '<b></b><span></span>';
    var tip = document.getElementById('ss-wxt-tip');
    tip.firstChild.textContent = info[1] || '';
    tip.lastChild.textContent = (L.feels || 'Feels like') + ' ' + Math.round(c.apparent_temperature) + '° · ' + (L.wind || 'Wind') + ' ' + Math.round(c.wind_speed_10m) + ' km/h · ' + (L.humidity || 'Humidity') + ' ' + Math.round(c.relative_humidity_2m) + '% · ' + (L.rainnow || 'Rain now') + ' ' + (+c.precipitation).toFixed(1) + ' mm';
    tile.dataset.state = 'ok'; tile.dataset.kind = info[0]; tile.setAttribute('aria-label', (info[1] || '') + ', ' + Math.round(c.temperature_2m) + '°');
    clock.dataset.rain = (info[0] === 'rain' || info[0] === 'storm') ? '1' : '0';
  }
  function fail() {
    tile.dataset.state = 'off';
    document.getElementById('ss-wxt-g').innerHTML = G.cloud; document.getElementById('ss-wxt-t').textContent = '';
    document.getElementById('ss-wxt-tip').textContent = L.off || 'Weather unavailable';
  }
  var cached = null;
  try { cached = JSON.parse(sessionStorage.getItem(KEY) || 'null'); } catch (e) {}
  if (cached && Date.now() - cached.at < 10 * 60 * 1000) { paint(cached.d); return; }
  var url = 'https://api.open-meteo.com/v1/forecast?latitude=' + (W.lat || 14.5194) + '&longitude=' + (W.lng || 121.0122) +
    '&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,precipitation,wind_speed_10m,is_day&timezone=Asia%2FManila';
  fetch(url, { cache: 'no-store' }).then(function (r) { if (!r.ok) throw 0; return r.json(); }).then(function (d) {
    if (!d || !d.current) throw 0;
    try { sessionStorage.setItem(KEY, JSON.stringify({ at: Date.now(), d: d })); } catch (e) {}
    paint(d);
  }).catch(fail);
})();
