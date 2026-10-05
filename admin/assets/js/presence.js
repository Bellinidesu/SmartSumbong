/* SmartSumbong portal — who is online and which case they have open (0087).
 *
 * Every portal page joins one Supabase Realtime presence channel and says
 * who this admin is and which case (if any) this tab has open. Pages then
 * paint what they need from the shared state:
 *   - Case Reports: faces in each row's "Open now" cell   (.ss-open[data-report])
 *   - a case page:  "Also here now"                       (#ss-also)
 *   - Activity:     "Team now"                            (#ss-team)
 * Nothing is stored; presence disappears when a tab closes.
 */
(function () {
  var cfg = window.SS_PRESENCE;
  if (!cfg) return;

  var PALETTE = ['#C2185B', '#00308F', '#2E7D32', '#6A1B9A', '#E65100', '#00838F', '#AD1457', '#283593'];

  function md5ish(id) {
    // Same colour as the PHP admin_colour(): md5 isn't in the browser, so
    // the server passes each admin's colour in; this is the fallback.
    var h = 0;
    for (var i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) >>> 0;
    return PALETTE[h % PALETTE.length];
  }

  function initials(name) {
    var p = String(name || '').replace(',', ' ').trim().split(/\s+/).filter(Boolean);
    if (!p.length) return '?';
    return ((p[0][0] || '') + (p.length > 1 ? p[p.length - 1][0] : '')).toUpperCase();
  }

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  window.ssAvatar = function (id, name, size, live) {
    size = size || 24;
    var colour = (cfg.colours && cfg.colours[id]) || md5ish(String(id));
    return '<span class="ss-av' + (live ? ' ss-live' : '') + '" style="width:' + size + 'px;height:' + size + 'px;font-size:'
      + Math.max(9, Math.floor(size / 3)) + 'px;background:' + colour + '" title="' + esc(name) + '">' + esc(initials(name)) + '</span>';
  };

  var members = [];

  function byReport() {
    var map = {};
    members.forEach(function (m) {
      if (!m.report) return;
      (map[m.report] = map[m.report] || {})[m.id] = m;
    });
    return map;
  }

  window.ssPaintOpen = function () {
    var map = byReport();
    document.querySelectorAll('.ss-open[data-report]').forEach(function (td) {
      var here = map[td.getAttribute('data-report')] || {};
      td.innerHTML = '<span class="ss-stack">' + Object.keys(here).map(function (k) {
        return window.ssAvatar(here[k].id, here[k].name, 26, true);
      }).join('') + '</span>';
    });
    var also = document.getElementById('ss-also');
    if (also && cfg.report) {
      var others = Object.values((map[cfg.report]) || {}).filter(function (m) { return m.id !== cfg.me.id; });
      also.hidden = !others.length;
      also.innerHTML = others.length
        ? '<span>' + esc(cfg.labels.alsoHere) + '</span>' + others.map(function (m) {
            return '<span class="ss-who">' + window.ssAvatar(m.id, m.name, 24, true) + esc(m.name) + '</span>';
          }).join('')
        : '';
    }
    var byAdmin = {};
    members.forEach(function (m) { var e = byAdmin[m.id] || (byAdmin[m.id] = []); if (m.tracking) e.push(m.tracking); });
    document.querySelectorAll('.ss-online[data-admin]').forEach(function (td) {
      var on = byAdmin.hasOwnProperty(td.getAttribute('data-admin'));
      var open = on ? byAdmin[td.getAttribute('data-admin')].filter(function (v, i, a) { return a.indexOf(v) === i; }) : [];
      td.classList.toggle('ss-is-on', on);
      td.innerHTML = '<span class="ss-dot"></span>' + esc(on ? (open.length ? cfg.labels.on + ' ' + open.join(', ') : cfg.labels.online) : cfg.labels.offline);
    });
    var team = document.getElementById('ss-team');
    if (team) {
      var seen = {};
      members.forEach(function (m) {
        var t = seen[m.id] || (seen[m.id] = { id: m.id, name: m.name, reports: {} });
        if (m.report) t.reports[m.report] = m.tracking || '';
      });
      var list = Object.values(seen);
      team.innerHTML = list.length ? list.map(function (t) {
        var open = Object.values(t.reports).filter(Boolean);
        return '<span class="ss-who">' + window.ssAvatar(t.id, t.name, 30, true) + '<span><b>' + esc(t.id === cfg.me.id ? cfg.labels.you : t.name)
          + '</b><br><small>' + (open.length ? esc(cfg.labels.on) + ' ' + esc(open.join(', ')) : esc(cfg.labels.online)) + '</small></span></span>';
      }).join('') : '<span class="p-hint">' + esc(cfg.labels.nobody) + '</span>';
    }
  };

  function start() {
    var sb = window.supabase.createClient(cfg.url, cfg.key, { accessToken: window.ssAccessToken(cfg.token) });
    var ch = sb.channel('portal-presence', { config: { presence: { key: cfg.me.id } } });
    ch.on('presence', { event: 'sync' }, function () {
      var st = ch.presenceState();
      members = [];
      Object.keys(st).forEach(function (k) { (st[k] || []).forEach(function (m) { members.push(m); }); });
      window.ssPaintOpen();
    });
    ch.subscribe(function (status) {
      if (status === 'SUBSCRIBED') {
        ch.track({ id: cfg.me.id, name: cfg.me.name, report: cfg.report || null, tracking: cfg.tracking || null, page: cfg.page });
      }
    });
  }

  if (window.supabase && window.supabase.createClient) {
    start();
  } else {
    var s = document.createElement('script');
    s.src = 'assets/vendor/supabase/supabase.js';
    s.onload = start;
    document.head.appendChild(s);
  }
})();
