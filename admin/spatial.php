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
        <option value="open">Open only</option>
        <option value="pending_review">Pending Review</option>
        <option value="validated">Validated</option>
        <option value="assigned">Assigned</option>
        <option value="in_progress">In Progress</option>
        <option value="resolved">Resolved</option>
        <option value="closed">Closed</option>
      </select>

      <label class="toggle"><input type="checkbox" id="f-heat"> Heatmap</label>
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
const OPEN = ['pending_review','validated','assigned','in_progress','offline_investigation'];

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
    if (st === 'open')  return OPEN.includes(r.status);
    if (st && r.status !== st) return false;
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
    .select('id,tracking_id,subject,category,status,latitude,longitude,created_at')
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
function showDetail(r) {
  const box = document.getElementById('pin-detail');
  box.innerHTML =
    '<button class="detail-x" type="button" aria-label="Close">&times;</button>' +
    '<p class="detail-id">' + r.tracking_id + '</p>' +
    '<p class="detail-cat">' + label(r.category) + '</p>' +
    '<p class="detail-sub">' + (r.subject || '') + '</p>' +
    '<p class="detail-status"><span class="pin-dot" style="background:' +
      (COLOUR[r.status] || '#9aa1ab') + '"></span>' + label(r.status) + '</p>' +
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

loadBoundary().then(load);
</script>

<?php layout_foot(); ?>
