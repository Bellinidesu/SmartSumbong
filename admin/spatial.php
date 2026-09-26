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

layout_head(t('Spatial Distribution', 'Mapa ng mga Sumbong'), 'spatial.php');
?>

<section class="panel panel--map">
  <header class="panel-bar">
    <h2 class="panel-title"><?= e(t('Barangay 183 Map', 'Mapa ng Barangay 183')) ?></h2>
    <div class="map-toolbar">
      <label class="visually-hidden" for="f-category"><?= e(t('Filter by complaint type', 'Salain ayon sa uri ng sumbong')) ?></label>
      <select id="f-category">
        <option value=""><?= e(t('All complaint types', 'Lahat ng uri ng sumbong')) ?></option>
        <?php foreach ($categories as $c): ?>
          <option value="<?= e($c) ?>"><?= e(category_label($c)) ?></option>
        <?php endforeach; ?>
      </select>

      <label class="visually-hidden" for="f-status"><?= e(t('Filter by status', 'Salain ayon sa katayuan')) ?></label>
      <select id="f-status">
        <option value=""><?= e(t('All statuses', 'Lahat ng katayuan')) ?></option>
        <option value="under_review"><?= e(t('Under Review', 'Nirerepaso')) ?></option>
        <option value="in_progress"><?= e(t('In Progress', 'Isinasagawa')) ?></option>
        <option value="resolved"><?= e(t('Resolved/Completed', 'Nalutas/Nakumpleto')) ?></option>
        <option value="rejected"><?= e(t('Rejected', 'Tinanggihan')) ?></option>
      </select>

      <label class="visually-hidden" for="f-period"><?= e(t('Hotspot analysis month', 'Buwan ng pagsusuri ng hotspot')) ?></label>
      <input type="month" id="f-period" value="<?= e((new DateTime('now', new DateTimeZone('Asia/Manila')))->format('Y-m')) ?>">
      <label class="toggle"><input type="checkbox" id="f-period-all"> <?= e(t('All time', 'Lahat ng panahon')) ?></label>

      <label class="toggle"><input type="checkbox" id="f-heat"> <?= e(t('Heatmap', 'Heatmap')) ?></label>
      <label class="toggle"><input type="checkbox" id="f-hotspots"> <?= e(t('Hotspots', 'Mga Hotspot')) ?></label>

      <label class="toggle"><input type="checkbox" id="f-tanods"> <?= e(t('Tanods', 'Mga Tanod')) ?></label>

      <label class="toggle"><input type="checkbox" id="f-tanod-paths"> <?= e(t('Tanod Paths', 'Dinaanan ng Tanod')) ?></label>
      <label class="visually-hidden" for="f-tanod-from"><?= e(t('Tanod path range start', 'Simula ng dinaanan')) ?></label>
      <input type="date" id="f-tanod-from" disabled
             value="<?= e((new DateTime('-7 days', new DateTimeZone('Asia/Manila')))->format('Y-m-d')) ?>">
      <label class="visually-hidden" for="f-tanod-to"><?= e(t('Tanod path range end', 'Wakas ng dinaanan')) ?></label>
      <input type="date" id="f-tanod-to" disabled
             value="<?= e((new DateTime('now', new DateTimeZone('Asia/Manila')))->format('Y-m-d')) ?>">
      <label class="visually-hidden" for="f-tanod-who"><?= e(t('Filter path to one tanod', 'Isang tanod lamang')) ?></label>
      <select id="f-tanod-who" disabled>
        <option value=""><?= e(t('All tanods', 'Lahat ng tanod')) ?></option>
      </select>

      <label class="toggle"><input type="checkbox" id="f-fog" checked> <?= e(t('Dim outside 183', 'Padilimin sa labas ng 183')) ?></label>
    </div>
  </header>

  <div class="map-shell">
    <div id="map"></div>

    <!-- Barangay wifi drops. A map that has silently stopped updating
         looks exactly like a map with nothing new on it, which is the
         more dangerous of the two. -->
    <aside class="pin-detail" id="pin-detail" hidden></aside>

    <div class="conn-strip" id="conn" hidden role="status">
      <span class="conn-dot"></span><span id="conn-text"><?= e(t('Reconnecting…', 'Kumokonekta muli…')) ?></span>
    </div>

    <div class="map-dock">
      <button class="map-btn" id="fit-btn" type="button" title="<?= e(t('Frame every complaint', 'Ipakita ang lahat ng sumbong')) ?>">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M3 8V5a2 2 0 0 1 2-2h3M16 3h3a2 2 0 0 1 2 2v3M21 16v3a2 2 0 0 1-2 2h-3M8 21H5a2 2 0 0 1-2-2v-3"/>
        </svg>
      </button>

      <button class="map-btn" id="expand-btn" type="button" title="<?= e(t('Expand map to full screen', 'I-full screen ang mapa')) ?>">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"/>
        </svg>
      </button>

      <button class="incident-badge" id="incident-toggle" aria-expanded="false"
              aria-controls="map-side" title="<?= e(t('Live incidents', 'Mga kasalukuyang insidente')) ?>">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <polygon points="1 6 8 3 16 6 23 3 23 18 16 21 8 18 1 21"/>
          <line x1="8" y1="3" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="21"/>
        </svg>
        <span class="incident-count" id="pin-count">0</span>
      </button>

      <aside class="map-side" id="map-side" hidden>
        <p class="map-side-head"><?= e(t('Live incidents', 'Mga kasalukuyang insidente')) ?></p>
        <p class="map-side-note" id="map-status"><?= e(t('Connecting…', 'Kumokonekta…')) ?></p>
        <ol class="pin-list" id="pin-list"></ol>
      </aside>

      <button class="incident-badge" id="hotspot-toggle" aria-expanded="false"
              aria-controls="hotspot-side" title="<?= e(t('Hotspot clusters', 'Mga kumpol ng hotspot')) ?>">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M12 2c-1.5 3-4.5 5.5-4.5 9.5a4.5 4.5 0 0 0 9 0c0-1.5-.6-2.5-1.3-3.4.1 1.6-.7 2.4-1.4 2.4.6-2.4-.4-4.6-1.8-8.5Z"/>
        </svg>
        <span class="incident-count" id="hotspot-count">0</span>
      </button>

      <aside class="map-side" id="hotspot-side" hidden>
        <p class="map-side-head"><?= e(t('Top hotspots', 'Nangungunang hotspot')) ?></p>
        <p class="map-side-note" id="hotspot-status"><?= e(t('Turn on Hotspots to see recurring problem areas.', 'I-on ang Mga Hotspot para makita ang mga lugar na paulit-ulit ang problema.')) ?></p>
        <ol class="pin-list" id="hotspot-list"></ol>
      </aside>

      <button class="incident-badge" id="tanod-toggle" aria-expanded="false"
              aria-controls="tanod-side" title="<?= e(t('Tanod positions', 'Kinaroroonan ng mga tanod')) ?>">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <circle cx="12" cy="8" r="3.2"/>
          <path d="M5 21c0-3.6 3.1-6.5 7-6.5s7 2.9 7 6.5"/>
        </svg>
        <span class="incident-count" id="tanod-count">0</span>
      </button>

      <aside class="map-side" id="tanod-side" hidden>
        <p class="map-side-head"><?= e(t('Tanod positions', 'Kinaroroonan ng mga tanod')) ?></p>
        <p class="map-side-note" id="tanod-status"><?= e(t('Turn on Tanods to see live positions.', 'I-on ang Mga Tanod para makita ang kanilang kinaroroonan.')) ?></p>
        <ol class="pin-list" id="tanod-list"></ol>
      </aside>
    </div>
  </div>
</section>

<link rel="stylesheet" href="assets/vendor/maplibre/maplibre-gl.css">
<script src="assets/vendor/maplibre/maplibre-gl.js"></script>
<script src="assets/js/map-theme.js"></script>
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
// [lng, lat] from here on: MapLibre's order, not Leaflet's.
const RESIDENTIAL_CENTRE = [121.015543, 14.526905];
const SPAN_LAT = 0.0110;
const SPAN_LNG = 0.0115;

// Google's 17z at this centre, which frames 1st Street through 31st.
// MapLibre's zoom scale is one below Leaflet's and Google's (512-pixel
// tiles), so the same framing is 16 here — and the old 16–19 range is
// 15–18.
const DEFAULT_ZOOM = 16;

// A little slack past the box so edge pins are reachable.
const PAD = 0.12;
const AREA = [
  [RESIDENTIAL_CENTRE[0] - SPAN_LNG * (1 + PAD), RESIDENTIAL_CENTRE[1] - SPAN_LAT * (1 + PAD)],
  [RESIDENTIAL_CENTRE[0] + SPAN_LNG * (1 + PAD), RESIDENTIAL_CENTRE[1] + SPAN_LAT * (1 + PAD)],
];
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
// Statuses in the portal's language; categories stay as they are, in
// English, as the apps show them.
const STATUS_LABEL = <?= json_encode(status_labels(), JSON_UNESCAPED_UNICODE) ?>;
const label = s => STATUS_LABEL[s] || s.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());

// Every string below that reaches innerHTML passes through this. subject
// is typed by the resident who filed the complaint and full_name by the
// tanod who registered, and this page holds the admin's session token —
// a subject like <img src=x onerror=...> must render as text, not run.
function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

// Shape carries the same information as colour. Around one man in twelve
// cannot reliably separate this orange from this green, and a map read
// only by hue is a map they cannot use.
const SHAPE = {
  pending_review: 'circle', validated: 'circle',
  assigned: 'square', in_progress: 'square', offline_investigation: 'square',
  resolved: 'diamond', closed: 'diamond', archived: 'diamond',
  rejected: 'cross',
};
const pinName = status => 'pin-' + (SHAPE[status] || 'circle') + '-' + (COLOUR[status] || '#9aa1ab').slice(1);

function pinSvg(shape, fill) {
  const body = {
    circle:  '<circle cx="11" cy="11" r="8"/>',
    square:  '<rect x="3.5" y="3.5" width="15" height="15" rx="2.5"/>',
    diamond: '<path d="M11 2.5 19.5 11 11 19.5 2.5 11Z"/>',
    cross:   '<path d="M6 6l10 10M16 6L6 16" stroke-width="3.6" stroke-linecap="round" fill="none"/>',
  }[shape];
  // The cross is drawn in its colour, with a white edge under it.
  const under = shape === 'cross'
    ? '<path d="M6 6l10 10M16 6L6 16" stroke="#fff" stroke-width="6.4" stroke-linecap="round" fill="none"/>' : '';
  const top = shape === 'cross' ? body.replace('stroke-width', 'stroke="' + fill + '" stroke-width') : body;
  return '<svg xmlns="http://www.w3.org/2000/svg" width="44" height="44" viewBox="0 0 22 22" fill="' + fill +
         '" stroke="#fff" stroke-width="2">' + under + top + '</svg>';
}

function tanodSvg(fresh) {
  const fill = fresh ? '#1FA84E' : '#9aa1ab';
  return '<svg xmlns="http://www.w3.org/2000/svg" width="52" height="52" viewBox="0 0 26 26">' +
    '<circle cx="13" cy="13" r="11" fill="' + fill + '" stroke="#fff" stroke-width="2.5"/>' +
    '<circle cx="13" cy="10.5" r="3" fill="#fff"/>' +
    '<path d="M6.5 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6" fill="#fff"/>' +
  '</svg>';
}

function addSvgImage(name, svg) {
  return new Promise(resolve => {
    const img = new Image();
    img.onload = () => { if (!map.hasImage(name)) map.addImage(name, img, { pixelRatio: 2 }); resolve(); };
    img.onerror = resolve;
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
  });
}

// Branch B: MapLibre over OpenFreeMap vector tiles, in the same
// recoloured Positron the resident and tanod apps draw (their
// assets/map/style-light.json) — no API key and no billing account,
// which is what sent the CARTO attempt of 15 Sep 2026 back to plain OSM
// raster tiles.
const map = new maplibregl.Map({
  container: 'map',
  style: window.mapStyleUrl(),
  center: RESIDENTIAL_CENTRE,
  zoom: DEFAULT_ZOOM,
  minZoom: 15,
  maxZoom: 18,
  maxBounds: AREA,
  dragRotate: false,
  pitchWithRotate: false,
  attributionControl: false,
});
// Bottom-left, so the zoom buttons sit where Leaflet's did, under the dock.
map.addControl(new maplibregl.AttributionControl({ compact: true }), 'bottom-left');
map.touchZoomRotate.disableRotation();
map.keyboard.disableRotation();
mapFollowTheme(map);
map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'bottom-right');

const EMPTY = { type: 'FeatureCollection', features: [] };
const point = (lng, lat, props) => ({ type: 'Feature', properties: props || {},
                                      geometry: { type: 'Point', coordinates: [lng, lat] } });

// Everything waits on the style; data that arrives first is drawn then.
const mapReady = new Promise(resolve => map.on('load', async () => {
  const shapes = [['circle', '#f59e0b'], ['square', '#2563eb'], ['diamond', '#22c55e'],
                  ['cross', '#9aa1ab'], ['circle', '#9aa1ab']];
  await Promise.all([
    ...shapes.map(([s, c]) => addSvgImage('pin-' + s + '-' + c.slice(1), pinSvg(s, c))),
    addSvgImage('tanod-fresh', tanodSvg(true)),
    addSvgImage('tanod-stale', tanodSvg(false)),
  ]);

  // Bottom to top: fog, outline, complaint heat, tanod path heat,
  // hotspots, complaints, tanods.
  map.addSource('fog', { type: 'geojson', data: EMPTY });
  map.addLayer({ id: 'fog', type: 'fill', source: 'fog',
                 paint: { 'fill-color': '#0d1117', 'fill-opacity': .55 } });
  map.addLayer({ id: 'outline', type: 'line', source: 'fog', filter: ['==', ['get', 'role'], 'outline'],
                 paint: { 'line-color': '#14181d', 'line-width': 2, 'line-opacity': .9 } });
  map.setFilter('fog', ['==', ['get', 'role'], 'fog']);

  // Leaflet.heat's own default ramp (blue, lime, red), so the heat reads
  // the way it always has.
  map.addSource('heat', { type: 'geojson', data: EMPTY });
  map.addLayer({ id: 'heat', type: 'heatmap', source: 'heat', layout: { visibility: 'none' },
    // Leaflet.heat scaled each view to its own peak; MapLibre's density
    // is absolute, so a barangay's worth of points needs more intensity
    // and a radius that grows with the zoom to read the same way.
    paint: {
      'heatmap-radius': ['interpolate', ['linear'], ['zoom'], 15, 22, 18, 60],
      'heatmap-intensity': ['interpolate', ['linear'], ['zoom'], 15, 2, 18, 4],
      'heatmap-color': ['interpolate', ['linear'], ['heatmap-density'],
        0, 'rgba(0,0,255,0)', 0.2, 'rgba(0,0,255,.6)', 0.4, 'blue', 0.65, 'lime', 1, 'red'],
      'heatmap-opacity': .8,
    } });

  // A distinct blue-to-pink ramp, so a path trail never reads as more
  // complaint heat when both layers happen to be on at once.
  map.addSource('tanod-paths', { type: 'geojson', data: EMPTY });
  map.addLayer({ id: 'tanod-paths', type: 'heatmap', source: 'tanod-paths', layout: { visibility: 'none' },
    paint: {
      'heatmap-radius': ['interpolate', ['linear'], ['zoom'], 15, 14, 18, 40],
      'heatmap-weight': 0.6,
      'heatmap-intensity': ['interpolate', ['linear'], ['zoom'], 15, 1.5, 18, 3],
      'heatmap-color': ['interpolate', ['linear'], ['heatmap-density'],
        0, 'rgba(29,78,216,0)', 0.3, '#1d4ed8', 0.6, '#7c3aed', 1, '#db2777'],
      'heatmap-opacity': .85,
    } });

  map.addSource('hotspots', { type: 'geojson', data: EMPTY });
  map.addLayer({ id: 'hotspots', type: 'circle', source: 'hotspots', layout: { visibility: 'none' },
    paint: {
      'circle-radius': ['get', 'radius'],
      'circle-color': ['get', 'colour'],
      'circle-opacity': .55,
      'circle-stroke-color': '#fff',
      'circle-stroke-width': 2,
    } });

  map.addSource('tanods', { type: 'geojson', data: EMPTY });
  map.addLayer({ id: 'tanods', type: 'symbol', source: 'tanods', layout: {
    visibility: 'none',
    'icon-image': ['case', ['get', 'fresh'], 'tanod-fresh', 'tanod-stale'],
    'icon-allow-overlap': true, 'icon-ignore-placement': true,
  } });

  setPinsSource(false);

  ['pins', 'clusters', 'hotspots', 'tanods'].forEach(id => {
    map.on('mouseenter', id, () => { map.getCanvas().style.cursor = 'pointer'; });
    map.on('mouseleave', id, () => { map.getCanvas().style.cursor = ''; });
  });
  map.on('click', 'pins', e => { const r = byId.get(e.features[0].properties.id); if (r) showDetail(r); });
  map.on('click', 'clusters', async e => {
    const f = e.features[0];
    const zoom = await map.getSource('reports').getClusterExpansionZoom(f.properties.cluster_id);
    map.easeTo({ center: f.geometry.coordinates, zoom });
  });
  map.on('click', 'hotspots', e => { const h = hotspots[e.features[0].properties.i]; if (h) showHotspotDetail(h); });
  map.on('click', 'tanods', e => { const t = tanodRows[e.features[0].properties.i]; if (t) tanodDetail(t); });

  resolve();
}));

// Below the threshold every pin stands alone; above it they would sit on
// top of each other on a barangay-sized map, so they gather into counted
// clusters that split as you zoom. A GeoJSON source is clustered or not
// from creation, so it is rebuilt when the count crosses the line.
const CLUSTER_FROM = 25;
let clustered = null;
function setPinsSource(want) {
  if (clustered === want) return;
  ['pins', 'cluster-count', 'clusters'].forEach(id => { if (map.getLayer(id)) map.removeLayer(id); });
  if (map.getSource('reports')) map.removeSource('reports');
  clustered = want;
  map.addSource('reports', { type: 'geojson', data: EMPTY,
                             cluster: want, clusterRadius: 46, clusterMaxZoom: 17 });
  map.addLayer({ id: 'clusters', type: 'circle', source: 'reports', filter: ['has', 'point_count'],
    paint: {
      'circle-color': ['step', ['get', 'point_count'], '#ffb74d', 10, '#ff9800', 50, '#e65100'],
      'circle-radius': ['step', ['get', 'point_count'], 16, 10, 20, 50, 25],
      'circle-stroke-color': 'rgba(255,255,255,.85)',
      'circle-stroke-width': 4,
    } }, 'tanods');
  map.addLayer({ id: 'cluster-count', type: 'symbol', source: 'reports', filter: ['has', 'point_count'],
    layout: { 'text-field': ['get', 'point_count_abbreviated'], 'text-font': ['Noto Sans Bold'], 'text-size': 13 },
    paint: { 'text-color': '#14181d' } }, 'tanods');
  map.addLayer({ id: 'pins', type: 'symbol', source: 'reports', filter: ['!', ['has', 'point_count']],
    layout: { 'icon-image': ['get', 'icon'], 'icon-allow-overlap': true, 'icon-ignore-placement': true } },
    'tanods');
}

let all = [], rings = [];
const byId = new Map();

// ---- boundary: OSM returns the relation's ways unordered ----------
function stitch(ways) {
  const out = [];
  const pool = ways.map(w => w.map(p => [p.lon, p.lat]));
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

// Signed area (shoelace): MapLibre takes a ring wound the same way as
// the outer one for a new polygon, not a hole, so each barangay ring is
// wound against the world ring before it is cut out of it.
const area = r => r.reduce((s, p, i) => { const q = r[(i + 1) % r.length]; return s + p[0] * q[1] - q[0] * p[1]; }, 0);
const closed = r => (r[0][0] === r[r.length-1][0] && r[0][1] === r[r.length-1][1]) ? r : r.concat([r[0]]);

async function loadBoundary() {
  try {
    const res = await fetch('brgy183.json');
    if (!res.ok) return;
    const rel = (await res.json()).elements.find(e => e.type === 'relation');
    rings = stitch(rel.members.filter(m => m.type === 'way' && m.geometry).map(m => m.geometry)).map(closed);
    if (!rings.length) return;

    const WORLD = [[-179.9, -85], [179.9, -85], [179.9, 85], [-179.9, 85], [-179.9, -85]];
    const worldSign = Math.sign(area(WORLD));
    const holes = rings.map(r => Math.sign(area(r)) === worldSign ? r.slice().reverse() : r);
    await mapReady;
    map.getSource('fog').setData({ type: 'FeatureCollection', features: [
      { type: 'Feature', properties: { role: 'fog' }, geometry: { type: 'Polygon', coordinates: [WORLD, ...holes] } },
      { type: 'Feature', properties: { role: 'outline' }, geometry: { type: 'MultiLineString', coordinates: rings } },
    ] });
    map.setLayoutProperty('fog', 'visibility', document.getElementById('f-fog').checked ? 'visible' : 'none');

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

async function draw() {
  const rows = visible();
  byId.clear();
  all.forEach(r => byId.set(r.id, r));

  await mapReady;
  setPinsSource(rows.length >= CLUSTER_FROM);
  map.getSource('reports').setData({ type: 'FeatureCollection',
    features: rows.map(r => point(r.longitude, r.latitude, { id: r.id, icon: pinName(r.status) })) });

  const heatOn = document.getElementById('f-heat').checked && rows.length;
  map.getSource('heat').setData(heatOn
    ? { type: 'FeatureCollection', features: rows.map(r => point(r.longitude, r.latitude)) } : EMPTY);
  map.setLayoutProperty('heat', 'visibility', heatOn ? 'visible' : 'none');

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
      '<span class="pin-body"><a href="case.php?id=' + encodeURIComponent(r.id) + '">' + esc(r.tracking_id) + '</a>' +
      '<small>' + esc(label(r.category)) + '</small></span>';
    li.addEventListener('mouseenter', () => map.panTo([r.longitude, r.latitude]));
    list.appendChild(li);
  });

  if (!rows.length) {
    list.innerHTML = '<li class="pin-empty">' + T('No complaint matches these filters.', 'Walang sumbong na tugma sa mga salang ito.') + '</li>';
  }
}

// ---- data + realtime ---------------------------------------------
async function load() {
  const { data, error } = await sb.from('reports')
    .select('id,tracking_id,subject,category,status,latitude,longitude,created_at,due_at')
    .is('deleted_at', null)
    .order('created_at', { ascending: false });

  const note = document.getElementById('map-status');
  if (error) { note.textContent = T('Could not load complaints: ', 'Hindi ma-load ang mga sumbong: ') + error.message; return; }

  all = data || [];
  note.textContent = all.length
    ? T('Live — new complaints appear without refreshing.', 'Live — lumalabas ang bagong sumbong nang hindi nire-refresh.')
    : T('No complaints have been filed yet.', 'Wala pang naisampang sumbong.');
  draw();
}

let connLost = false;
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
      // Changes made while the socket was down were never delivered, so
      // hiding the strip alone would present a map that is missing them
      // as current. Reload the rows once the channel is back.
      if (connLost) { connLost = false; load(); }
    } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
      connLost = true;
      text.textContent = T('Connection lost — this map is not updating. Reconnecting…', 'Nawala ang koneksyon — hindi nag-a-update ang mapa. Kumokonekta muli…');
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
    '<button class="detail-x" type="button" aria-label="' + T('Close', 'Isara') + '">&times;</button>' +
    '<p class="detail-id">' + esc(r.tracking_id) + '</p>' +
    '<p class="detail-cat">' + esc(label(r.category)) + '</p>' +
    '<p class="detail-sub">' + esc(r.subject) + '</p>' +
    '<p class="detail-status"><span class="pin-dot" style="background:' +
      (COLOUR[r.status] || '#9aa1ab') + '"></span>' + esc(label(r.status)) + '</p>' +
    '<dl class="detail-dates">' +
      '<dt>' + T('Submitted', 'Isinumite') + '</dt><dd>' + submitted + '</dd>' +
      '<dt>' + T('Deadline', 'Takdang oras') + '</dt><dd>' + (deadline || T('No deadline set', 'Walang takdang oras')) + '</dd>' +
    '</dl>' +
    '<a class="detail-open" href="case.php?id=' + encodeURIComponent(r.id) + '">' + T('Open this case', 'Buksan ang kasong ito') + '</a>';
  box.removeAttribute('hidden');
  box.querySelector('.detail-x').addEventListener('click',
    () => box.setAttribute('hidden', ''));
}

// Frame everything currently shown, without losing the residential pin.
document.getElementById('fit-btn').addEventListener('click', () => {
  const rows = visible();
  if (!rows.length) { map.easeTo({ center: RESIDENTIAL_CENTRE, zoom: DEFAULT_ZOOM }); return; }
  const b = new maplibregl.LngLatBounds();
  rows.forEach(r => b.extend([r.longitude, r.latitude]));
  map.fitBounds(b, { padding: 60, maxZoom: 17 });
});

// Full-screen the map itself (the Fullscreen API target has to be the
// .map-shell wrapper, not #map, or the dock and detail panel would be
// left behind outside the fullscreen element). The map caches its
// container size, so it needs an explicit nudge once the browser has
// actually finished resizing the element.
const expandBtn = document.getElementById('expand-btn');
const mapShell  = document.querySelector('.map-shell');
// iPhone Safari has no element fullscreen at all; a button that does
// nothing when tapped reads as broken, so it is not offered there.
if (!document.fullscreenEnabled && !document.webkitFullscreenEnabled) {
  expandBtn.hidden = true;
}
expandBtn.addEventListener('click', () => {
  if (!document.fullscreenElement) {
    // The prefixed call returns nothing rather than a promise.
    const p = (mapShell.requestFullscreen || mapShell.webkitRequestFullscreen || function(){}).call(mapShell);
    if (p && p.catch) p.catch(() => {});
  } else {
    (document.exitFullscreen || document.webkitExitFullscreen || function(){}).call(document);
  }
});
document.addEventListener('fullscreenchange', () => {
  const active = document.fullscreenElement === mapShell;
  expandBtn.classList.toggle('is-active', active);
  expandBtn.title = active ? T('Exit full screen', 'Lumabas sa full screen') : T('Expand map to full screen', 'I-full screen ang mapa');
  setTimeout(() => map.resize(), 120);
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
      c.lng.toFixed(6), c.lat.toFixed(6),
      ((b.getNorth() - b.getSouth()) / 2).toFixed(4),
      ((b.getEast()  - b.getWest())  / 2).toFixed(4), map.getZoom().toFixed(2));
  });
}

['f-category','f-status','f-heat'].forEach(id =>
  document.getElementById(id).addEventListener('change', draw));

document.getElementById('f-fog').addEventListener('change', async e => {
  await mapReady;
  map.setLayoutProperty('fog', 'visibility', e.target.checked ? 'visible' : 'none');
});

// ---- hotspots: real spatial clustering, not just a visual blur -------
// The Heatmap toggle above is a rendering aid over whatever the current
// filters show. This is analysis: report_hotspots() (0042) runs an
// actual density-based clustering pass in the database over a chosen
// time window and hands back ranked, counted groups — "8 reports within
// a block of each other this quarter" instead of a blur an admin has to
// eyeball themselves.
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
    ? fmtDate(nearestDeadline) + T(' (nearest of ' + open.length + ' still open)', ' (pinakamalapit sa ' + open.length + ' na bukas pa)')
    : T('No open deadlines in this cluster', 'Walang bukas na takdang oras sa kumpol na ito');

  const box = document.getElementById('pin-detail');
  box.innerHTML =
    '<button class="detail-x" type="button" aria-label="' + T('Close', 'Isara') + '">&times;</button>' +
    '<p class="detail-id">Hotspot &mdash; ' + h.report_count + T(h.report_count === 1 ? ' report' : ' reports', ' ulat') + '</p>' +
    '<p class="detail-cat">' + T('Mostly ', 'Karamihan ay ') + esc(label(h.top_category)) + '</p>' +
    '<dl class="detail-dates">' +
      '<dt>' + T('Submitted', 'Isinumite') + '</dt><dd>' + submittedRange + '</dd>' +
      '<dt>' + T('Deadline', 'Takdang oras') + '</dt><dd>' + deadlineText + '</dd>' +
    '</dl>' +
    (members.length
      ? '<p class="detail-sub">' + T('Reports in this cluster:', 'Mga ulat sa kumpol na ito:') + '</p>' +
        '<ol class="pin-list" style="margin:0">' +
        members.slice(0, 8).map(r =>
          '<li class="pin-item">' +
            '<span class="pin-dot" style="background:' + (COLOUR[r.status] || '#9aa1ab') + '"></span>' +
            '<span class="pin-body"><a href="case.php?id=' + encodeURIComponent(r.id) + '">' + esc(r.tracking_id) + '</a>' +
            '<small>' + esc(label(r.category)) + '</small></span>' +
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
    await mapReady;
    map.getSource('hotspots').setData(EMPTY);
    map.setLayoutProperty('hotspots', 'visibility', 'none');
    return;
  }

  const { from, to } = periodRange();
  const cat = document.getElementById('f-category').value || null;

  status.textContent = T('Analysing…', 'Sinusuri…');
  const { data, error } = await sb.rpc('report_hotspots', { p_from: from, p_to: to, p_category: cat });
  if (error) { status.textContent = T('Could not load hotspots: ', 'Hindi ma-load ang mga hotspot: ') + error.message; return; }

  hotspots = data || [];
  await mapReady;
  map.getSource('hotspots').setData({ type: 'FeatureCollection', features: hotspots.map((h, i) =>
    point(h.centroid_lng, h.centroid_lat, {
      i, radius: 10 + Math.min(h.report_count, 20) * 1.4, colour: hotspotColour(h.report_count),
    })) });
  map.setLayoutProperty('hotspots', 'visibility', 'visible');

  count.textContent = hotspots.length;
  badge.classList.toggle('is-live', hotspots.length > 0);
  status.textContent = hotspots.length
    ? hotspots.length + T(hotspots.length === 1 ? ' recurring area found in this period.' : ' recurring areas found in this period.',
                          ' lugar na paulit-ulit ang nakita sa panahong ito.')
    : T('No recurring hotspots in this period — complaints are spread out, or too few to cluster.',
        'Walang paulit-ulit na hotspot sa panahong ito — kalat ang mga sumbong, o kakaunti para ipangkat.');

  list.innerHTML = '';
  hotspots.slice(0, 15).forEach((h, i) => {
    const li = document.createElement('li');
    li.className = 'pin-item';
    li.innerHTML =
      '<span class="pin-dot" style="background:' + hotspotColour(h.report_count) + '"></span>' +
      '<span class="pin-body">#' + (i + 1) + ' — ' + h.report_count + T(' reports', ' ulat') +
      '<small>' + esc(label(h.top_category)) + '</small></span>';
    li.addEventListener('click', () => map.easeTo({ center: [h.centroid_lng, h.centroid_lat], zoom: 17 }));
    list.appendChild(li);
  });
  if (!hotspots.length) {
    list.innerHTML = '<li class="pin-empty">' + T('Nothing recurring enough to call a hotspot yet.', 'Wala pang sapat na paulit-ulit para tawaging hotspot.') + '</li>';
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

let tanodRows = [];

function tanodDetail(t) {
  const box = document.getElementById('pin-detail');
  box.innerHTML =
    '<button class="detail-x" type="button" aria-label="' + T('Close', 'Isara') + '">&times;</button>' +
    '<p class="detail-id">' + esc(t.full_name) + '</p>' +
    '<p class="detail-cat">' + esc(label(t.duty_status || 'offline')) + (t.is_fresh ? '' : T(' — stale fix', ' — lumang lokasyon')) + '</p>' +
    '<dl class="detail-dates">' +
      '<dt>' + T('Last update', 'Huling update') + '</dt><dd>' + (fmtDate(t.last_location_at) || T('Never', 'Hindi pa')) + '</dd>' +
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
    await mapReady;
    map.getSource('tanods').setData(EMPTY);
    map.setLayoutProperty('tanods', 'visibility', 'none');
    return;
  }

  const { data, error } = await sb.rpc('tanod_live_positions');
  if (error) { status.textContent = T('Could not load tanod positions: ', 'Hindi ma-load ang kinaroroonan ng mga tanod: ') + error.message; return; }

  tanodRows = data || [];
  await mapReady;
  map.getSource('tanods').setData({ type: 'FeatureCollection', features: tanodRows
    .map((t, i) => (t.lat == null || t.lng == null) ? null : point(t.lng, t.lat, { i, fresh: !!t.is_fresh }))
    .filter(Boolean) });
  map.setLayoutProperty('tanods', 'visibility', 'visible');

  const live = tanodRows.filter(t => t.is_fresh);
  count.textContent = live.length;
  badge.classList.toggle('is-live', live.length > 0);
  status.textContent = tanodRows.length
    ? T(live.length + ' of ' + tanodRows.length + (tanodRows.length === 1 ? ' tanod' : ' tanods') + ' reporting live.',
        live.length + ' sa ' + tanodRows.length + ' tanod ang nag-uulat ng lokasyon ngayon.')
    : T('No tanod has ever reported a position yet.', 'Wala pang tanod na nag-ulat ng lokasyon.');

  list.innerHTML = '';
  tanodRows.forEach(t => {
    const li = document.createElement('li');
    li.className = 'pin-item';
    li.innerHTML =
      '<span class="pin-dot" style="background:' + (t.is_fresh ? '#1FA84E' : '#9aa1ab') + '"></span>' +
      '<span class="pin-body">' + esc(t.full_name) +
      '<small>' + esc(label(t.duty_status || 'offline')) + (t.is_fresh ? '' : T(' — stale', ' — luma')) + '</small></span>';
    if (t.lat != null && t.lng != null) {
      li.addEventListener('click', () => map.panTo([t.lng, t.lat]));
    }
    list.appendChild(li);
  });
  if (!tanodRows.length) {
    list.innerHTML = '<li class="pin-empty">' + T('No tanod has ever reported a position yet.', 'Wala pang tanod na nag-ulat ng lokasyon.') + '</li>';
  }

  // Keep "narrow to one tanod" in sync without clobbering whatever the
  // admin currently has picked, so an open path-heatmap selection survives
  // a routine 30-second refresh.
  const current = select.value;
  select.innerHTML = '<option value="">' + T('All tanods', 'Lahat ng tanod') + '</option>' +
    tanodRows.map(t => '<option value="' + esc(t.tanod_id) + '">' + esc(t.full_name) + '</option>').join('');
  select.value = tanodRows.some(t => t.tanod_id === current) ? current : '';
}

async function loadTanodPaths() {
  const enabled = document.getElementById('f-tanod-paths').checked;
  await mapReady;
  map.getSource('tanod-paths').setData(EMPTY);
  map.setLayoutProperty('tanod-paths', 'visibility', 'none');
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
    document.getElementById('tanod-status').textContent = T('Could not load tanod paths: ', 'Hindi ma-load ang dinaanan ng mga tanod: ') + error.message;
    return;
  }

  const points = (data || []).map(p => point(p.lng, p.lat));
  if (points.length) {
    map.getSource('tanod-paths').setData({ type: 'FeatureCollection', features: points });
    map.setLayoutProperty('tanod-paths', 'visibility', 'visible');
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

// The complaints and the boundary are fetched side by side with the
// style and tiles; each is drawn as soon as the map can take it.
loadBoundary();
load();
</script>

<?php layout_foot(); ?>
