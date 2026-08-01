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

<section class="panel">
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

    <aside class="map-side">
      <p class="map-side-head">
        Live incidents <span id="pin-count" class="pin-count">0</span>
      </p>
      <p class="map-side-note" id="map-status">Connecting&hellip;</p>
      <ol class="pin-list" id="pin-list"></ol>
    </aside>
  </div>
</section>

<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script src="https://unpkg.com/leaflet.heat@0.2.0/dist/leaflet-heat.js"></script>
<script type="module">
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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
const OPEN = ['pending_review','validated','assigned','in_progress','offline_investigation'];

const COLOUR = {
  pending_review: '#f59e0b', validated: '#f59e0b',
  assigned: '#2563eb', in_progress: '#2563eb', offline_investigation: '#2563eb',
  resolved: '#22c55e', closed: '#22c55e', archived: '#22c55e',
  rejected: '#9aa1ab',
};
const label = s => s.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());

const map = L.map('map').setView(BRGY, 15);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
  maxZoom: 19, attribution: '&copy; OpenStreetMap contributors'
}).addTo(map);

const pins = L.layerGroup().addTo(map);
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

    map.fitBounds(outline.getBounds(), { padding: [20, 20] });
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
  pins.clearLayers();

  rows.forEach(r => {
    L.circleMarker([r.latitude, r.longitude], {
      radius: 8, weight: 2, color: '#fff',
      fillColor: COLOUR[r.status] || '#9aa1ab', fillOpacity: .92
    }).bindPopup(
      '<strong>' + r.tracking_id + '</strong><br>' +
      label(r.category) + ' &middot; ' + label(r.status) + '<br>' +
      '<a href="case.php?id=' + r.id + '">Open this case</a>'
    ).addTo(pins);
  });

  if (heat) { map.removeLayer(heat); heat = null; }
  if (document.getElementById('f-heat').checked && rows.length) {
    heat = L.heatLayer(rows.map(r => [r.latitude, r.longitude, 1]),
                       { radius: 28, blur: 20, maxZoom: 17 }).addTo(map);
  }

  document.getElementById('pin-count').textContent = rows.length;

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
  .subscribe();

['f-category','f-status','f-heat'].forEach(id =>
  document.getElementById(id).addEventListener('change', draw));

document.getElementById('f-fog').addEventListener('change', e => {
  if (!fog) return;
  e.target.checked ? fog.addTo(map) : map.removeLayer(fog);
});

loadBoundary().then(load);
</script>

<?php layout_foot(); ?>
