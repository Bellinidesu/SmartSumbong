<?php
/**
 * Spatial Distribution — Figma node 2:1164, and the use cases
 * "View Geospatial Incident Heatmap" and "Monitoring RealTime Map".
 *
 * This is map.html brought into the portal. Three things change in the
 * move, all of them for the better:
 *
 *  1. No second login. map.html signed in on its own; here the page
 *     already knows who you are, so the browser client is handed the
 *     admin's existing access token and Realtime is authed with it.
 *     RLS still decides what comes back — the token is the admin's, not
 *     a service key.
 *  2. No hardcoded credentials. map.html carried the project URL and
 *     publishable key in the source of a public repo. Here they come
 *     from .env like everything else.
 *  3. The filters the use cases ask for: by category, by status, and a
 *     heatmap toggle for "Identify High Concentrated Zone".
 *
 * The fog layer — a world-sized polygon with the barangay cut out as a
 * hole — is what makes jurisdiction legible at a glance. Everything
 * outside 183 is dimmed rather than hidden, so an admin can still see a
 * pin that landed just over the line.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin();

$categories = [
    'street_obstruction', 'public_safety_infrastructure', 'environmental_waste_hazard',
    'animal_welfare', 'traffic_violation', 'barangay_service', 'peace_order_nuisance',
];

layout_head('Spatial Distribution', 'spatial.php');
?>

<section class="panel panel--map">
  <header class="panel-bar">
    <h2 class="panel-title">Barangay 183 Map</h2>
    <div class="map-toolbar">
      <label class="visually-hidden" for="f-category">Filter by complaint type</label>
      <select id="f-category">
        <option value="">All complaint types</option>
        <?php foreach ($categories as $c): ?>
          <option value="<?= e($c) ?>"><?= e(category_label($c)) ?></option>
        <?php endforeach; ?>
      </select>

      <label class="visually-hidden" for="f-status">Filter by status</label>
      <select id="f-status">
        <option value="">All statuses</option>
        <option value="under_review">Under Review</option>
        <option value="in_progress">In Progress</option>
        <option value="resolved">Resolved</option>
        <option value="rejected">Rejected</option>
      </select>

      <label class="visually-hidden" for="f-period">Hotspot analysis month</label>
      <input type="month" id="f-period" value="<?= e((new DateTime('now', new DateTimeZone('Asia/Manila')))->format('Y-m')) ?>">
      <label class="toggle"><input type="checkbox" id="f-period-all"> All time</label>

      <label class="toggle"><input type="checkbox" id="f-heat"> Heatmap</label>
      <label class="toggle"><input type="checkbox" id="f-hotspots"> Hotspots</label>

      <label class="toggle"><input type="checkbox" id="f-tanods"> Tanods</label>

      <label class="toggle"><input type="checkbox" id="f-tanod-paths"> Tanod Paths</label>
      <label class="visually-hidden" for="f-tanod-from">Tanod path range start</label>
      <input type="date" id="f-tanod-from" disabled
             value="<?= e((new DateTime('-7 days', new DateTimeZone('Asia/Manila')))->format('Y-m-d')) ?>">
      <label class="visually-hidden" for="f-tanod-to">Tanod path range end</label>
      <input type="date" id="f-tanod-to" disabled
             value="<?= e((new DateTime('now', new DateTimeZone('Asia/Manila')))->format('Y-m-d')) ?>">
      <label class="visually-hidden" for="f-tanod-who">Filter path to one tanod</label>
      <select id="f-tanod-who" disabled>
        <option value="">All tanods</option>
      </select>

      <label class="toggle"><input type="checkbox" id="f-fog" checked> Dim outside 183</label>
    </div>
  </header>

  <div class="map-shell">
    <div id="map"></div>

    <!-- Barangay wifi drops. A map that has silently stopped updating
         looks exactly like a map with nothing new on it, which is the
         more dangerous of the two. -->
    <aside class="pin-detail" id="pin-detail" hidden></aside>

    <div class="conn-strip" id="conn" hidden role="status">
      <span class="conn-dot"></span><span id="conn-text">Reconnecting&hellip;</span>
    </div>

    <div class="map-dock">
      <button class="map-btn" id="fit-btn" type="button" title="Frame every complaint">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M3 8V5a2 2 0 0 1 2-2h3M16 3h3a2 2 0 0 1 2 2v3M21 16v3a2 2 0 0 1-2 2h-3M8 21H5a2 2 0 0 1-2-2v-3"/>
        </svg>
      </button>

      <button class="map-btn" id="expand-btn" type="button" title="Expand map to full screen">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"/>
        </svg>
      </button>

      <button class="incident-badge" id="incident-toggle" aria-expanded="false"
              aria-controls="map-side" title="Live incidents">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <polygon points="1 6 8 3 16 6 23 3 23 18 16 21 8 18 1 21"/>
          <line x1="8" y1="3" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="21"/>
        </svg>
        <span class="incident-count" id="pin-count">0</span>
      </button>

      <aside class="map-side" id="map-side" hidden>
        <p class="map-side-head">Live incidents</p>
        <p class="map-side-note" id="map-status">Connecting&hellip;</p>
        <ol class="pin-list" id="pin-list"></ol>
      </aside>

      <button class="incident-badge" id="hotspot-toggle" aria-expanded="false"
              aria-controls="hotspot-side" title="Hotspot clusters">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M12 2c-1.5 3-4.5 5.5-4.5 9.5a4.5 4.5 0 0 0 9 0c0-1.5-.6-2.5-1.3-3.4.1 1.6-.7 2.4-1.4 2.4.6-2.4-.4-4.6-1.8-8.5Z"/>
        </svg>
        <span class="incident-count" id="hotspot-count">0</span>
      </button>

      <aside class="map-side" id="hotspot-side" hidden>
        <p class="map-side-head">Top hotspots</p>
        <p class="map-side-note" id="hotspot-status">Turn on Hotspots to see recurring problem areas.</p>
        <ol class="pin-list" id="hotspot-list"></ol>
      </aside>

      <button class="incident-badge" id="tanod-toggle" aria-expanded="false"
              aria-controls="tanod-side" title="Tanod positions">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <circle cx="12" cy="8" r="3.2"/>
          <path d="M5 21c0-3.6 3.1-6.5 7-6.5s7 2.9 7 6.5"/>
        </svg>
        <span class="incident-count" id="tanod-count">0</span>
      </button>

      <aside class="map-side" id="tanod-side" hidden>
        <p class="map-side-head">Tanod positions</p>
        <p class="map-side-note" id="tanod-status">Turn on Tanods to see live positions.</p>
        <ol class="pin-list" id="tanod-list"></ol>
      </aside>
    </div>
  </div>
</section>

<link rel="stylesheet" href="assets/vendor/leaflet/leaflet.css">
<script src="assets/vendor/leaflet/leaflet.js"></script>
<script src="assets/vendor/leaflet/leaflet-heat.js"></script>
<link rel="stylesheet" href="assets/vendor/leaflet/MarkerCluster.css">
<link rel="stylesheet" href="assets/vendor/leaflet/MarkerCluster.Default.css">
<script src="assets/vendor/leaflet/leaflet.markercluster.js"></script>
<script src="assets/vendor/supabase/supabase.js"></script>
<script>
// Self-hosted rather than imported from esm.sh. This script runs with the
// administrator's session token in scope, so third-party delivery of it
// would mean a compromised CDN could read that token and act as the
// administrator against the API. Nothing executable in this portal now
// comes from an origin we do not control.
const { createClient } = supabase;

// The token is this admin's own session. Everything below is still
// filtered by row level security; nothing here elevates anything.
const TOKEN = <?= json_encode(access_token()) ?>;
const sb = createClient(
  <?= json_encode(supabase_url()) ?>,
  <?= json_encode(supabase_key()) ?>,
  { global: { headers: { Authorization: 'Bearer ' + TOKEN } },
    auth: { persistSession: false, autoRefreshToken: false } }
);
sb.realtime.setAuth(TOKEN);

const BRGY = [14.51646, 121.01621];

// The boundary relation covers the whole barangay, most of which is the
// airport apron and Villamor Air Base — land with no residents and no
// complaints. The admin needs the residential grid, so the map is pinned
// to it: this is the only area that can be panned to, and it cannot be
// zoomed out far enough to lose it.
//
// Centre supplied by the barangay side, not derived from the relation's
// centroid, which sits over the runway. SPAN is the half-width of the
// box in degrees — raise it to take in more of the base, lower it to
// tighten onto the streets. Latitude and longitude use separate values
// because a degree of longitude is shorter than a degree of latitude at
// this latitude, and equal numbers would give a box taller than it looks.
const RESIDENTIAL_CENTRE = [14.526905, 121.015543];
const SPAN_LAT = 0.0110;
const SPAN_LNG = 0.0115;

// Google's 17z at this centre, which frames 1st Street through 31st.
// Leaflet and Google use the same zoom scale, so the number carries over.
const DEFAULT_ZOOM = 17;

const AREA = L.latLngBounds(
  [RESIDENTIAL_CENTRE[0] - SPAN_LAT, RESIDENTIAL_CENTRE[1] - SPAN_LNG],
  [RESIDENTIAL_CENTRE[0] + SPAN_LAT, RESIDENTIAL_CENTRE[1] + SPAN_LNG]
);
// Collapsed from the raw 8-value enum to the four buckets an admin
// actually scans for on a map (Rose's feedback, 15 Sep 2026) — the full
// breakdown is still one click away on Case Reports.
const STATUS_GROUPS = {
  under_review: ['pending_review', 'validated'],
  in_progress:  ['assigned', 'in_progress', 'offline_investigation'],
  resolved:     ['resolved', 'closed', 'archived'],
  rejected:     ['rejected'],
};

const COLOUR = {
  pending_review: '#f59e0b', validated: '#f59e0b',
  assigned: '#2563eb', in_progress: '#2563eb', offline_investigation: '#2563eb',
  resolved: '#22c55e', closed: '#22c55e', archived: '#22c55e',
  rejected: '#9aa1ab',
};
const label = s => s.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());

// Shape carries the same information as colour. Around one man in twelve
// cannot reliably separate this orange from this green, and a map read
// only by hue is a map they cannot use.
const SHAPE = {
  pending_review: 'circle', validated: 'circle',
  assigned: 'square', in_progress: 'square', offline_investigation: 'square',
  resolved: 'diamond', closed: 'diamond', archived: 'diamond',
  rejected: 'cross',
};

function pinFor(status) {
  const fill  = COLOUR[status] || '#9aa1ab';
  const shape = SHAPE[status]  || 'circle';
  const body = {
    circle:  '<circle cx="11" cy="11" r="8"/>',
    square:  '<rect x="3.5" y="3.5" width="15" height="15" rx="2.5"/>',
    diamond: '<path d="M11 2.5 19.5 11 11 19.5 2.5 11Z"/>',
    cross:   '<path d="M6 6l10 10M16 6L6 16" stroke-width="3.6" stroke-linecap="round" fill="none"/>',
  }[shape];

  return L.divIcon({
    className: 'pin-icon',
    iconSize: [22, 22],
    iconAnchor: [11, 11],
    popupAnchor: [0, -10],
    html: '<svg viewBox="0 0 22 22" fill="' + fill + '" stroke="#fff" stroke-width="2">'
        + body + '</svg>',
  });
}

const map = L.map('map', {
  maxBounds: AREA.pad(0.12),   // a little slack so edge pins are reachable
  maxBoundsViscosity: 0.9,     // resists dragging past it rather than snapping
  minZoom: 16,
  maxZoom: 19,
  zoomControl: false
}).setView(RESIDENTIAL_CENTRE, DEFAULT_ZOOM);
L.control.zoom({ position: 'bottomright' }).addTo(map);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
  maxZoom: 19, attribution: '&copy; OpenStreetMap contributors'
}).addTo(map);

// Below the threshold every pin stands alone; above it they would sit on
// top of each other on a barangay-sized map, so they gather into counted
// clusters that split as you zoom.
const CLUSTER_FROM = 25;
const plainPins   = L.layerGroup();
const clusterPins = L.markerClusterGroup({
  showCoverageOnHover: false,
  maxClusterRadius: 46,
  spiderfyOnMaxZoom: true,
});
let pins = plainPins.addTo(map);
let heat = null, fog = null, rings = [];
let all = [];

// ---- boundary: OSM returns the relation's ways unordered ----------
function stitch(ways) {
  const out = [];
  const pool = ways.map(w => w.map(p => [p.lat, p.lon]));
  while (pool.length) {
    let ring = pool.shift();
    let joined = true;
    while (joined) {
      joined = false;
      for (let i = 0; i < pool.length; i++) {
        const w = pool[i], a = ring[ring.length - 1], b = w[0], c = w[w.length - 1];
        const near = (p, q) => Math.abs(p[0]-q[0]) < 1e-7 && Math.abs(p[1]-q[1]) < 1e-7;
        if (near(a, b))      { ring = ring.concat(w.slice(1)); pool.splice(i,1); joined = true; break; }
        if (near(a, c))      { ring = ring.concat(w.slice().reverse().slice(1)); pool.splice(i,1); joined = true; break; }
      }
    }
    if (ring.length > 3) out.push(ring);
  }
  return out;
}

async function loadBoundary() {
  try {
    const res = await fetch('brgy183.json');
    if (!res.ok) return;
    const rel = (await res.json()).elements.find(e => e.type === 'relation');
    rings = stitch(rel.members.filter(m => m.type === 'way' && m.geometry).map(m => m.geometry));
    if (!rings.length) return;

    const outline = L.polygon(rings, {
      color: '#14181d', weight: 2, opacity: .9, fill: false, interactive: false
    }).addTo(map);

    const WORLD = [[-89.9,-179.9],[-89.9,179.9],[89.9,179.9],[89.9,-179.9]];
    fog = L.polygon([WORLD, ...rings], {
      stroke: false, fillColor: '#0d1117', fillOpacity: .55, interactive: false
    }).addTo(map);

    // The outline is drawn, but the view stays on the residential area.
    // Fitting the whole relation would zoom out to include the runway.
  } catch (e) { /* the map is still useful without the outline */ }
}

// ---- rendering ---------------------------------------------------
function visible() {
  const cat = document.getElementById('f-category').value;
  const st  = document.getElementById('f-status').value;
  return all.filter(r => {
    if (cat && r.category !== cat) return false;
    if (st && !(STATUS_GROUPS[st] || []).includes(r.status)) return false;
    return true;
  });
}

function draw() {
  const rows = visible();

  const want = rows.length >= CLUSTER_FROM ? clusterPins : plainPins;
  if (want !== pins) { map.removeLayer(pins); pins = want.addTo(map); }
  plainPins.clearLayers();
  clusterPins.clearLayers();

  rows.forEach(r => {
    L.marker([r.latitude, r.longitude], { icon: pinFor(r.status) })
      .on('click', () => showDetail(r))
      .addTo(pins);
  });

  if (heat) { map.removeLayer(heat); heat = null; }
  if (document.getElementById('f-heat').checked && rows.length) {
    heat = L.heatLayer(rows.map(r => [r.latitude, r.longitude, 1]),
                       { radius: 28, blur: 20, maxZoom: 17 }).addTo(map);
  }

  const badge = document.getElementById('incident-toggle');
  document.getElementById('pin-count').textContent = rows.length;
  badge.classList.toggle('is-live', rows.length > 0);

  const list = document.getElementById('pin-list');
  list.innerHTML = '';
  rows.slice(0, 40).forEach(r => {
    const li = document.createElement('li');
    li.className = 'pin-item';
    li.innerHTML =
      '<span class="pin-dot" style="background:' + (COLOUR[r.status] || '#9aa1ab') + '"></span>' +
      '<span class="pin-body"><a href="case.php?id=' + r.id + '">' + r.tracking_id + '</a>' +
      '<small>' + label(r.category) + '</small></span>';
    li.addEventListener('mouseenter', () => map.panTo([r.latitude, r.longitude]));
    list.appendChild(li);
  });

  if (!rows.length) {
    list.innerHTML = '<li class="pin-empty">No complaint matches these filters.</li>';
  }
}

// ---- data + realtime ---------------------------------------------
async function load() {
  const { data, error } = await sb.from('reports')
    .select('id,tracking_id,subject,category,status,latitude,longitude,created_at,due_at')
    .is('deleted_at', null)
    .order('created_at', { ascending: false });

  const note = document.getElementById('map-status');
  if (error) { note.textContent = 'Could not load complaints: ' + error.message; return; }

  all = data || [];
  note.textContent = all.length
    ? 'Live — new complaints appear without refreshing.'
    : 'No complaints have been filed yet.';
  draw();
}

sb.channel('reports-spatial')
  .on('postgres_changes', { event: '*', schema: 'public', table: 'reports' }, payload => {
    const row = payload.new || payload.old;
    if (!row) return;
    all = all.filter(r => r.id !== row.id);
    if (payload.eventType !== 'DELETE' && !row.deleted_at) all.unshift(row);
    draw();
  })
  .subscribe(status => {
    const strip = document.getElementById('conn'),
          text  = document.getElementById('conn-text');
    if (status === 'SUBSCRIBED') {
      strip.setAttribute('hidden', '');
    } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
      text.textContent = 'Connection lost — this map is not updating. Reconnecting…';
      strip.removeAttribute('hidden');
    }
  });

// A popup covers the map and closes the moment you look away. A drawer
// keeps the complaint on screen while the map stays exactly where the
// admin left it.
function fmtDate(iso) {
  if (!iso) return null;
  return new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Manila', month: 'short', day: 'numeric', year: 'numeric',
    hour: 'numeric', minute: '2-digit', hour12: true,
  }).format(new Date(iso));
}

function showDetail(r) {
  const box = document.getElementById('pin-detail');
  const submitted = fmtDate(r.created_at) || '—';
  const deadline  = fmtDate(r.due_at);
  box.innerHTML =
    '<button class="detail-x" type="button" aria-label="Close">&times;</button>' +
    '<p class="detail-id">' + r.tracking_id + '</p>' +
    '<p class="detail-cat">' + label(r.category) + '</p>' +
    '<p class="detail-sub">' + (r.subject || '') + '</p>' +
    '<p class="detail-status"><span class="pin-dot" style="background:' +
      (COLOUR[r.status] || '#9aa1ab') + '"></span>' + label(r.status) + '</p>' +
    '<dl class="detail-dates">' +
      '<dt>Submitted</dt><dd>' + submitted + '</dd>' +
      '<dt>Deadline</dt><dd>' + (deadline || 'No deadline set') + '</dd>' +
    '</dl>' +
    '<a class="detail-open" href="case.php?id=' + r.id + '">Open this case</a>';
  box.removeAttribute('hidden');
  box.querySelector('.detail-x').addEventListener('click',
    () => box.setAttribute('hidden', ''));
}

// Frame everything currently shown, without losing the residential pin.
document.getElementById('fit-btn').addEventListener('click', () => {
  const rows = visible();
  if (!rows.length) { map.setView(RESIDENTIAL_CENTRE, DEFAULT_ZOOM); return; }
  map.fitBounds(L.latLngBounds(rows.map(r => [r.latitude, r.longitude])),
                { padding: [60, 60], maxZoom: 18 });
});

// Full-screen the map itself (the Fullscreen API target has to be the
// .map-shell wrapper, not #map, or Leaflet's own absolutely-positioned
// dock and detail panel would be left behind outside the fullscreen
// element). Leaflet caches its container size, so it needs an explicit
// nudge once the browser has actually finished resizing the element.
const expandBtn = document.getElementById('expand-btn');
const mapShell  = document.querySelector('.map-shell');
expandBtn.addEventListener('click', () => {
  if (!document.fullscreenElement) {
    (mapShell.requestFullscreen || mapShell.webkitRequestFullscreen || function(){}).call(mapShell)
      .catch(() => {});
  } else {
    (document.exitFullscreen || document.webkitExitFullscreen || function(){}).call(document);
  }
});
document.addEventListener('fullscreenchange', () => {
  const active = document.fullscreenElement === mapShell;
  expandBtn.classList.toggle('is-active', active);
  expandBtn.title = active ? 'Exit full screen' : 'Expand map to full screen';
  setTimeout(() => map.invalidateSize(), 120);
});

// Collapsed by default: the map is the screen, the list is a drawer.
const toggle = document.getElementById('incident-toggle');
const side   = document.getElementById('map-side');
toggle.addEventListener('click', () => {
  const open = side.hasAttribute('hidden');
  open ? side.removeAttribute('hidden') : side.setAttribute('hidden', '');
  toggle.setAttribute('aria-expanded', String(open));
});

// Tuning aid, off unless asked for: load spatial.php?bounds=1 and the
// console prints the framing on every pan, ready to paste above.
if (new URLSearchParams(location.search).has('bounds')) {
  map.on('moveend', () => {
    const b = map.getBounds(), c = map.getCenter();
    console.log('centre [%s, %s]  span %s / %s  zoom %s',
      c.lat.toFixed(6), c.lng.toFixed(6),
      ((b.getNorth() - b.getSouth()) / 2).toFixed(4),
      ((b.getEast()  - b.getWest())  / 2).toFixed(4), map.getZoom());
  });
}

['f-category','f-status','f-heat'].forEach(id =>
  document.getElementById(id).addEventListener('change', draw));

document.getElementById('f-fog').addEventListener('change', e => {
  if (!fog) return;
  e.target.checked ? fog.addTo(map) : map.removeLayer(fog);
});

// ---- hotspots: real spatial clustering, not just a visual blur -------
// The Heatmap toggle above is a rendering aid over whatever the current
// filters show. This is analysis: report_hotspots() (0042) runs an
// actual density-based clustering pass in the database over a chosen
// time window and hands back ranked, counted groups — "8 reports within
// a block of each other this quarter" instead of a blur an admin has to
// eyeball themselves.
const hotspotLayer = L.layerGroup();
let hotspots = [];

function periodRange() {
  const to = new Date();
  if (document.getElementById('f-period-all').checked) {
    return { from: '2000-01-01T00:00:00Z', to: to.toISOString() };
  }
  const val = document.getElementById('f-period').value; // 'YYYY-MM'
  if (!val) { return { from: '2000-01-01T00:00:00Z', to: to.toISOString() }; }
  const [y, m] = val.split('-').map(Number);
  return {
    from: new Date(Date.UTC(y, m - 1, 1)).toISOString(),
    to:   new Date(Date.UTC(y, m, 1)).toISOString(),
  };
}

// More reports, hotter colour — same principle as the pin/status legend
// above: colour is a hint, never the only channel, so the popup and the
// ranked list both spell the count out in text too.
function hotspotColour(n) {
  if (n >= 10) return '#dc2626';
  if (n >= 6)  return '#f97316';
  return '#f59e0b';
}

// Distance in metres between two lat/lng points — plain haversine, no
// PostGIS needed client-side. Used only to approximate which loaded
// reports fall inside a given hotspot circle, matching report_hotspots()'s
// own eps=45m clustering radius (0042) closely enough for display purposes.
function haversineMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const toRad = d => d * Math.PI / 180;
  const dLat = toRad(lat2 - lat1), dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
          + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// Rose's feedback (15 Sep 2026): clicking a hotspot should show a submitted
// date and a deadline, the same way clicking an individual pin already
// does (showDetail() above). A hotspot is an aggregate of several reports
// though, not one, so there is no single submitted date/deadline to read
// off the row the way showDetail() can — report_hotspots() (0042) only
// ever returns the cluster's centroid, count, top category, and first/last
// report timestamps, never the member reports themselves. Rather than add
// a new RPC just to list cluster membership, this reconstructs it
// client-side: `all` already holds every report visible on the map, so
// filtering to whichever of those sit within report_hotspots()'s own 45m
// clustering radius of this hotspot's centroid (and inside the same
// period/category the hotspot analysis is currently scoped to) recovers
// the same group of reports well enough to show real dates from, not just
// the cluster's own summary numbers.
function showHotspotDetail(h) {
  const { from, to } = periodRange();
  const cat = document.getElementById('f-category').value || null;
  const fromMs = new Date(from).getTime(), toMs = new Date(to).getTime();

  const members = all.filter(r => {
    if (cat && r.category !== cat) return false;
    const t = new Date(r.created_at).getTime();
    if (t < fromMs || t >= toMs) return false;
    return haversineMeters(r.latitude, r.longitude, h.centroid_lat, h.centroid_lng) <= 45;
  });

  const open = members.filter(r =>
    !['resolved', 'closed', 'archived', 'rejected'].includes(r.status) && r.due_at);
  let nearestDeadline = null;
  open.forEach(r => {
    if (!nearestDeadline || new Date(r.due_at) < new Date(nearestDeadline)) nearestDeadline = r.due_at;
  });

  const submitted = fmtDate(h.first_at) || '—';
  const submittedRange = (h.last_at && h.last_at !== h.first_at)
    ? submitted + ' – ' + (fmtDate(h.last_at) || '—') : submitted;
  const deadlineText = nearestDeadline
    ? fmtDate(nearestDeadline) + ' (nearest of ' + open.length + ' still open)'
    : 'No open deadlines in this cluster';

  const box = document.getElementById('pin-detail');
  box.innerHTML =
    '<button class="detail-x" type="button" aria-label="Close">&times;</button>' +
    '<p class="detail-id">Hotspot &mdash; ' + h.report_count + ' report' + (h.report_count === 1 ? '' : 's') + '</p>' +
    '<p class="detail-cat">Mostly ' + label(h.top_category) + '</p>' +
    '<dl class="detail-dates">' +
      '<dt>Submitted</dt><dd>' + submittedRange + '</dd>' +
      '<dt>Deadline</dt><dd>' + deadlineText + '</dd>' +
    '</dl>' +
    (members.length
      ? '<p class="detail-sub">Reports in this cluster:</p>' +
        '<ol class="pin-list" style="margin:0">' +
        members.slice(0, 8).map(r =>
          '<li class="pin-item">' +
            '<span class="pin-dot" style="background:' + (COLOUR[r.status] || '#9aa1ab') + '"></span>' +
            '<span class="pin-body"><a href="case.php?id=' + r.id + '">' + r.tracking_id + '</a>' +
            '<small>' + label(r.category) + '</small></span>' +
          '</li>').join('') +
        '</ol>'
      : '');
  box.removeAttribute('hidden');
  box.querySelector('.detail-x').addEventListener('click',
    () => box.setAttribute('hidden', ''));
}

async function loadHotspots() {
  const status = document.getElementById('hotspot-status');
  const badge  = document.getElementById('hotspot-toggle');
  const count  = document.getElementById('hotspot-count');
  const list   = document.getElementById('hotspot-list');

  if (!document.getElementById('f-hotspots').checked) {
    hotspotLayer.clearLayers();
    if (map.hasLayer(hotspotLayer)) map.removeLayer(hotspotLayer);
    return;
  }

  const { from, to } = periodRange();
  const cat = document.getElementById('f-category').value || null;

  status.textContent = 'Analysing…';
  const { data, error } = await sb.rpc('report_hotspots', { p_from: from, p_to: to, p_category: cat });
  if (error) { status.textContent = 'Could not load hotspots: ' + error.message; return; }

  hotspots = data || [];
  hotspotLayer.clearLayers();

  hotspots.forEach(h => {
    const radius = 10 + Math.min(h.report_count, 20) * 1.4;
    L.circleMarker([h.centroid_lat, h.centroid_lng], {
      radius, color: '#fff', weight: 2,
      fillColor: hotspotColour(h.report_count), fillOpacity: 0.55,
    }).on('click', () => showHotspotDetail(h)).addTo(hotspotLayer);
  });

  if (!map.hasLayer(hotspotLayer)) hotspotLayer.addTo(map);

  count.textContent = hotspots.length;
  badge.classList.toggle('is-live', hotspots.length > 0);
  status.textContent = hotspots.length
    ? hotspots.length + ' recurring area' + (hotspots.length === 1 ? '' : 's') + ' found in this period.'
    : 'No recurring hotspots in this period — complaints are spread out, or too few to cluster.';

  list.innerHTML = '';
  hotspots.slice(0, 15).forEach((h, i) => {
    const li = document.createElement('li');
    li.className = 'pin-item';
    li.innerHTML =
      '<span class="pin-dot" style="background:' + hotspotColour(h.report_count) + '"></span>' +
      '<span class="pin-body">#' + (i + 1) + ' — ' + h.report_count + ' reports' +
      '<small>' + label(h.top_category) + '</small></span>';
    li.addEventListener('click', () => map.setView([h.centroid_lat, h.centroid_lng], 18));
    list.appendChild(li);
  });
  if (!hotspots.length) {
    list.innerHTML = '<li class="pin-empty">Nothing recurring enough to call a hotspot yet.</li>';
  }
}

document.getElementById('f-hotspots').addEventListener('change', loadHotspots);
document.getElementById('f-period').addEventListener('change', loadHotspots);
document.getElementById('f-category').addEventListener('change', loadHotspots);
document.getElementById('f-period-all').addEventListener('change', e => {
  document.getElementById('f-period').disabled = e.target.checked;
  loadHotspots();
});

const hotspotToggleBtn = document.getElementById('hotspot-toggle');
const hotspotSide      = document.getElementById('hotspot-side');
hotspotToggleBtn.addEventListener('click', () => {
  const open = hotspotSide.hasAttribute('hidden');
  open ? hotspotSide.removeAttribute('hidden') : hotspotSide.setAttribute('hidden', '');
  hotspotToggleBtn.setAttribute('aria-expanded', String(open));
});

// ---- tanods: live position + pathing heatmap (0059) -----------------
// Two independent things, each behind its own checkbox so an admin who
// only wants complaints sees neither: (1) tanod_live_positions() — each
// tanod's current fix (users.last_geom, already used for auto-dispatch
// since 0005), refreshed on a poll matching the mobile app's own 30-second
// update cadence, since there is no narrow realtime table worth opening a
// channel on for this that reports-spatial doesn't already cover; (2)
// tanod_path_heatmap() over an admin-picked date range — the "pathing
// heatmap of all tanods", or one tanod at a time via the select below.
// Neither is grid-suppressed or count-gated the way the now-removed
// public transparency heat was (0058) — this is admin-only and the point
// is precise, individual movement, not anonymised aggregate.

const tanodLayer = L.layerGroup();
let tanodPathHeat = null;
let tanodRows = [];

function tanodIcon(t) {
  const fill = t.is_fresh ? '#1FA84E' : '#9aa1ab';
  return L.divIcon({
    className: 'tanod-icon',
    iconSize: [26, 26],
    iconAnchor: [13, 13],
    popupAnchor: [0, -12],
    html: '<svg viewBox="0 0 26 26">' +
      '<circle cx="13" cy="13" r="11" fill="' + fill + '" stroke="#fff" stroke-width="2.5"/>' +
      '<circle cx="13" cy="10.5" r="3" fill="#fff"/>' +
      '<path d="M6.5 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6" fill="#fff"/>' +
    '</svg>',
  });
}

function tanodDetail(t) {
  const box = document.getElementById('pin-detail');
  box.innerHTML =
    '<button class="detail-x" type="button" aria-label="Close">&times;</button>' +
    '<p class="detail-id">' + t.full_name + '</p>' +
    '<p class="detail-cat">' + label(t.duty_status || 'offline') + (t.is_fresh ? '' : ' — stale fix') + '</p>' +
    '<dl class="detail-dates">' +
      '<dt>Last update</dt><dd>' + (fmtDate(t.last_location_at) || 'Never') + '</dd>' +
    '</dl>';
  box.removeAttribute('hidden');
  box.querySelector('.detail-x').addEventListener('click',
    () => box.setAttribute('hidden', ''));
}

async function loadTanodPositions() {
  const status = document.getElementById('tanod-status');
  const badge  = document.getElementById('tanod-toggle');
  const count  = document.getElementById('tanod-count');
  const list   = document.getElementById('tanod-list');
  const select = document.getElementById('f-tanod-who');

  if (!document.getElementById('f-tanods').checked) {
    tanodLayer.clearLayers();
    if (map.hasLayer(tanodLayer)) map.removeLayer(tanodLayer);
    return;
  }

  const { data, error } = await sb.rpc('tanod_live_positions');
  if (error) { status.textContent = 'Could not load tanod positions: ' + error.message; return; }

  tanodRows = data || [];
  tanodLayer.clearLayers();

  tanodRows.forEach(t => {
    if (t.lat == null || t.lng == null) return;
    L.marker([t.lat, t.lng], { icon: tanodIcon(t) })
      .on('click', () => tanodDetail(t))
      .addTo(tanodLayer);
  });
  if (!map.hasLayer(tanodLayer)) tanodLayer.addTo(map);

  const live = tanodRows.filter(t => t.is_fresh);
  count.textContent = live.length;
  badge.classList.toggle('is-live', live.length > 0);
  status.textContent = tanodRows.length
    ? live.length + ' of ' + tanodRows.length + ' tanod' + (tanodRows.length === 1 ? '' : 's') + ' reporting live.'
    : 'No tanod has ever reported a position yet.';

  list.innerHTML = '';
  tanodRows.forEach(t => {
    const li = document.createElement('li');
    li.className = 'pin-item';
    li.innerHTML =
      '<span class="pin-dot" style="background:' + (t.is_fresh ? '#1FA84E' : '#9aa1ab') + '"></span>' +
      '<span class="pin-body">' + t.full_name +
      '<small>' + label(t.duty_status || 'offline') + (t.is_fresh ? '' : ' — stale') + '</small></span>';
    if (t.lat != null && t.lng != null) {
      li.addEventListener('click', () => map.panTo([t.lat, t.lng]));
    }
    list.appendChild(li);
  });
  if (!tanodRows.length) {
    list.innerHTML = '<li class="pin-empty">No tanod has ever reported a position yet.</li>';
  }

  // Keep "narrow to one tanod" in sync without clobbering whatever the
  // admin currently has picked, so an open path-heatmap selection survives
  // a routine 30-second refresh.
  const current = select.value;
  select.innerHTML = '<option value="">All tanods</option>' +
    tanodRows.map(t => '<option value="' + t.tanod_id + '">' + t.full_name + '</option>').join('');
  select.value = tanodRows.some(t => t.tanod_id === current) ? current : '';
}

async function loadTanodPaths() {
  const enabled = document.getElementById('f-tanod-paths').checked;
  if (tanodPathHeat) { map.removeLayer(tanodPathHeat); tanodPathHeat = null; }
  if (!enabled) return;

  const from = document.getElementById('f-tanod-from').value;
  const to   = document.getElementById('f-tanod-to').value;
  if (!from || !to) return;

  const who = document.getElementById('f-tanod-who').value || null;
  // Bare dates from the picker, read as Asia/Manila midnight. The "to"
  // date is inclusive on screen but tanod_path_heatmap()'s p_to is an
  // exclusive upper bound, so it is pushed one day forward here.
  const fromIso = new Date(from + 'T00:00:00+08:00').toISOString();
  const toIso   = new Date(new Date(to + 'T00:00:00+08:00').getTime() + 24 * 60 * 60 * 1000).toISOString();

  const { data, error } = await sb.rpc('tanod_path_heatmap',
    { p_from: fromIso, p_to: toIso, p_tanod: who });
  if (error) {
    document.getElementById('tanod-status').textContent = 'Could not load tanod paths: ' + error.message;
    return;
  }

  const points = (data || []).map(p => [p.lat, p.lng, 0.6]);
  if (points.length) {
    // A distinct blue-to-pink gradient, so a path trail never reads as
    // more complaint-heat when both layers happen to be on at once.
    tanodPathHeat = L.heatLayer(points, {
      radius: 18, blur: 14, maxZoom: 18,
      gradient: { 0.3: '#1d4ed8', 0.6: '#7c3aed', 1: '#db2777' },
    }).addTo(map);
  }
}

document.getElementById('f-tanods').addEventListener('change', loadTanodPositions);
document.getElementById('f-tanod-paths').addEventListener('change', e => {
  const on = e.target.checked;
  document.getElementById('f-tanod-from').disabled = !on;
  document.getElementById('f-tanod-to').disabled = !on;
  document.getElementById('f-tanod-who').disabled = !on;
  loadTanodPaths();
});
['f-tanod-from', 'f-tanod-to', 'f-tanod-who'].forEach(id =>
  document.getElementById(id).addEventListener('change', loadTanodPaths));

const tanodToggleBtn = document.getElementById('tanod-toggle');
const tanodSide      = document.getElementById('tanod-side');
tanodToggleBtn.addEventListener('click', () => {
  const open = tanodSide.hasAttribute('hidden');
  open ? tanodSide.removeAttribute('hidden') : tanodSide.setAttribute('hidden', '');
  tanodToggleBtn.setAttribute('aria-expanded', String(open));
});

// New pings land every 30 seconds per on-duty tanod (0059's mobile-side
// change) — re-poll on that cadence while the layer is on. loadTanodPositions()
// itself no-ops instantly whenever the checkbox is off, so this timer costs
// nothing while the feature is unused.
setInterval(loadTanodPositions, 30000);

loadBoundary().then(load);
</script>

<?php layout_foot(); ?>
