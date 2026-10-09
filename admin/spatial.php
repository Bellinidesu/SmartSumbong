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

// Hotspots (0042's report_hotspots clustering) are off since Rose's
// mock-defense feedback (2 Oct 2026: "remove the hotspots checkbox").
// Everything is kept; true brings the switch, panel and dock button back.
const HOTSPOTS_ENABLED = false;

$categories = [
    'street_obstruction', 'public_safety_infrastructure', 'environmental_waste_hazard',
    'animal_welfare', 'traffic_violation', 'barangay_service', 'peace_order_nuisance', 'other',
];

layout_head(t('Spatial Distribution', 'Mapa ng mga Sumbong'), 'spatial.php');
?>

<!-- The preview's map: it covers the page, everything else floats on it. -->
<section class="p-map-page" id="s-spatial">
  <div class="p-map-full" id="map"></div>

  <div class="p-map-float p-map-search" id="map-search">
    <div class="p-ttl"><h1><?= e(t('Spatial Distribution', 'Mapa ng mga Sumbong')) ?></h1>
      <span class="p-live" id="map-live"><i></i><?= e(t('Live', 'Live')) ?></span>
      <span class="p-note" id="map-status"><?= e(t('Connecting…', 'Kumokonekta…')) ?></span></div>
    <div class="p-row">
      <label class="p-pill-select"><span class="p-sr"><?= e(t('Filter by complaint type', 'Salain ayon sa uri ng sumbong')) ?></span>
        <select id="f-category">
          <option value=""><?= e(t('All complaint types', 'Lahat ng uri ng sumbong')) ?></option>
          <?php foreach ($categories as $c): ?><option value="<?= e($c) ?>"><?= e(category_label($c)) ?></option><?php endforeach; ?>
        </select></label>
      <label class="p-pill-select"><span class="p-sr"><?= e(t('Filter by status', 'Salain ayon sa katayuan')) ?></span>
        <select id="f-status">
          <option value=""><?= e(t('All statuses', 'Lahat ng katayuan')) ?></option>
          <option value="under_review"><?= e(t('Under Review', 'Nirerepaso')) ?></option>
          <option value="in_progress"><?= e(t('In Progress', 'Isinasagawa')) ?></option>
          <option value="resolved"><?= e(t('Resolved/Completed', 'Nalutas/Nakumpleto')) ?></option>
          <option value="rejected"><?= e(t('Rejected', 'Tinanggihan')) ?></option>
        </select></label>
      <label class="p-pill-select"><?= p_icon('i-cal', 16) ?><span class="p-sr"><?= e(t('Month filed', 'Buwan ng pagsampa')) ?></span>
        <input type="month" id="f-period" value="<?= e((new DateTime('now', new DateTimeZone('Asia/Manila')))->format('Y-m')) ?>" disabled></label>
      <label class="p-pill-select p-tog"><input type="checkbox" id="f-period-all" checked> <?= e(t('All time', 'Lahat ng panahon')) ?></label>
      <!-- Rose (27 Sep 2026): choices above take effect on Apply; the switches below act at once. -->
      <button type="button" class="p-btn p-btn-primary p-btn-sm p-apply" id="f-apply"><?= e(t('Apply', 'Ilapat')) ?></button>
    </div>
    <div class="p-row">
      <label class="map-sw map-sw--heat"><input type="checkbox" id="f-heat"><span class="scene" aria-hidden="true"><span></span><span></span><span></span><span></span></span><i aria-hidden="true"></i><b><?= e(t('Heatmap', 'Heatmap')) ?></b></label>
      <label class="map-sw map-sw--noah" title="<?= e(t('Project NOAH flood hazard map (UP NOAH Center)', 'Mapa ng panganib sa baha ng Project NOAH')) ?>"><input type="checkbox" id="f-flood"><svg class="wave" viewBox="0 0 400 44" preserveAspectRatio="none" aria-hidden="true"><path d="M0 6 C40 1 60 1 100 6 S160 11 200 6 S260 1 300 6 S360 11 400 6 V44 H0Z" fill="#1A73E8"/><path d="M0 6 C40 1 60 1 100 6 S160 11 200 6 S260 1 300 6 S360 11 400 6" fill="none" stroke="#fff" stroke-width="2.5"/></svg><i aria-hidden="true"></i><b><em><?= e(t('Flood zones ·', 'Bahaing lugar ·')) ?></em> Project NOAH</b></label>
      <?php if (HOTSPOTS_ENABLED): ?><label class="p-pill-select p-tog"><input type="checkbox" id="f-hotspots"> <?= e(t('Hotspots', 'Mga Hotspot')) ?></label><?php endif; ?>
      <label class="map-sw map-sw--dim"><input type="checkbox" id="f-fog" checked><span class="scene" aria-hidden="true"><svg viewBox="0 0 180 36" preserveAspectRatio="none"><path class="dim" fill-rule="evenodd" d="M0 0H180V36H0Z M54 4 L132 2 L150 14 L140 32 L84 34 L62 26 Z"/><path class="edge" d="M54 4 L132 2 L150 14 L140 32 L84 34 L62 26 Z"/></svg></span><i aria-hidden="true"></i><b><?= e(t('Dim outside 183', 'Padilimin sa labas ng 183')) ?></b></label>
    </div>
  </div>

  <p class="p-map-empty" id="map-empty" hidden><?= e(t('No spatial indices found for selected parameters', 'Walang nakitang lokasyon para sa napiling mga parameter')) ?></p>
  <p class="p-map-empty p-map-empty--error" id="map-failed" hidden><?= e(t('Map unavailable. Please reload.', 'Hindi available ang mapa. Paki-reload.')) ?></p>

  <aside class="p-map-detail" id="pin-detail" hidden></aside>
  <aside class="cs-sheet" id="case-sheet" hidden aria-label="<?= e(t('Complaint details', 'Detalye ng sumbong')) ?>"></aside>
  <aside class="cs-sheet" id="safe-sheet" hidden aria-label="<?= e(t('Safe point details', 'Detalye ng ligtas na lugar')) ?>"></aside>

  <!-- Barangay wifi drops: a map that has silently stopped updating looks
       exactly like a map with nothing new on it. -->
  <div class="p-conn" id="conn" hidden role="status"><span class="p-conn-dot"></span><span id="conn-text"><?= e(t('Reconnecting…', 'Kumokonekta muli…')) ?></span></div>

  <aside class="p-card p-card-pad p-map-stats" id="map-side" hidden>
    <p class="p-eyebrow"><?= e(t('Live incidents', 'Mga kasalukuyang insidente')) ?></p>
    <ol class="p-pin-list" id="pin-list"></ol>
  </aside>
  <?php if (HOTSPOTS_ENABLED): ?>
  <aside class="p-card p-card-pad p-map-stats" id="hotspot-side" hidden>
    <p class="p-eyebrow"><?= e(t('Top hotspots', 'Nangungunang hotspot')) ?></p>
    <p class="p-hint" id="hotspot-status" style="margin:0 0 8px"><?= e(t('Turn on Hotspots to see recurring problem areas.', 'I-on ang Mga Hotspot para makita ang mga lugar na paulit-ulit ang problema.')) ?></p>
    <ol class="p-pin-list" id="hotspot-list"></ol>
  </aside>
  <?php endif; ?>

  <div class="p-map-legend lg-card" id="map-legend" hidden>
    <h3><?= e(t('Complaint type', 'Uri ng sumbong')) ?></h3>
    <?php foreach (category_colours() as $c => $hex): ?>
      <div><span class="p-lg p-lg-circle" style="--c:<?= e($hex) ?>"></span><?= e(category_label($c)) ?></div>
    <?php endforeach; ?>
    <div id="lg-flood" hidden>
      <div class="lg-sep"></div>
      <h3><?= e(t('Flood zones · Project NOAH', 'Bahaing lugar · Project NOAH')) ?></h3>
      <div><i class="lg-sw" style="background:#dc2626"></i><?= e(t('High flood hazard', 'Mataas na panganib sa baha')) ?></div>
      <div><i class="lg-sw" style="background:#f97316"></i><?= e(t('Medium flood hazard', 'Katamtamang panganib sa baha')) ?></div>
      <div><i class="lg-sw" style="background:#facc15"></i><?= e(t('Low flood hazard', 'Mababang panganib sa baha')) ?></div>
      <div><i class="lg-sw" style="background:#8b5cf6"></i><?= e(t('Storm surge (worst case)', 'Daluyong (pinakamalala)')) ?></div>
      <div id="lg-risk" hidden><svg width="14" height="14" viewBox="-8 -8 16 16" aria-hidden="true"><circle r="6" fill="none" stroke="#0EA5E9" stroke-width="2.5"/></svg><?= e(t('Open complaint in a zone at risk now', 'Bukas na sumbong sa lugar na delikado ngayon')) ?></div>
    </div>
    <p class="p-legend-count" id="map-count"></p>
  </div>

  <!-- Flood watch (3 Oct 2026): live rain over Barangay 183 read against
       PAGASA's rainfall warnings, with Project NOAH's flood zones. -->
  <div class="fw" id="fw">
    <button type="button" class="fw-chip" id="fw-chip" aria-expanded="false" aria-controls="fw-card"><span class="fw-dot"></span><span class="fw-txt"><b><?= e(t('Flood watch', 'Bantay-baha')) ?></b><small id="fw-sum"><?= e(t('Connecting…', 'Kumokonekta…')) ?></small></span><svg class="fw-car" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg></button>
    <div class="fw-card" id="fw-card" hidden></div>
  </div>

  <div class="ss-lyr" id="ss-lyr" hidden></div>
  <div class="ss-lyr-info" id="ss-lyr-info"></div>

  <div class="p-map-dock">
    <button class="p-dock-btn" id="expand-btn" type="button" title="<?= e(t('Expand map to full screen', 'I-full screen ang mapa')) ?>" aria-label="<?= e(t('Expand map to full screen', 'I-full screen ang mapa')) ?>">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 3H5a2 2 0 0 0-2 2v3" /> <path d="M21 8V5a2 2 0 0 0-2-2h-3" /> <path d="M3 16v3a2 2 0 0 0 2 2h3" /> <path d="M16 21h3a2 2 0 0 0 2-2v-3" /></svg></button>
    <button class="p-dock-btn" id="fit-btn" type="button" title="<?= e(t('Frame every complaint', 'Ipakita ang lahat ng sumbong')) ?>" aria-label="<?= e(t('Frame every complaint', 'Ipakita ang lahat ng sumbong')) ?>">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11.5 12a.5 .5 0 1 0 1 0a.5 .5 0 1 0 -1 0" fill="currentColor" /> <path d="M5 12a7 7 0 1 0 14 0a7 7 0 1 0 -14 0" /> <path d="M12 3l0 2" /> <path d="M3 12l2 0" /> <path d="M12 19l0 2" /> <path d="M19 12l2 0" /></svg></button>
    <button class="p-dock-btn" id="layers-btn" type="button" aria-expanded="false" aria-controls="ss-lyr" title="<?= e(t('Map layers', 'Mga layer ng mapa')) ?>" aria-label="<?= e(t('Map layers', 'Mga layer ng mapa')) ?>">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z" /> <path d="M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12" /> <path d="M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17" /></svg></button>
    <button class="p-dock-btn" id="legend-toggle" type="button" aria-expanded="false" aria-controls="map-legend" title="<?= e(t('Legend', 'Alamat')) ?>" aria-label="<?= e(t('Legend', 'Alamat')) ?>">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 5h.01" /> <path d="M3 12h.01" /> <path d="M3 19h.01" /> <path d="M8 5h13" /> <path d="M8 12h13" /> <path d="M8 19h13" /></svg></button>
    <button class="p-dock-btn" id="incident-toggle" aria-expanded="false" aria-controls="map-side" title="<?= e(t('Live incidents', 'Mga kasalukuyang insidente')) ?>" aria-label="<?= e(t('Live incidents', 'Mga kasalukuyang insidente')) ?>">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20.5s5-4.4 5-8.8a5 5 0 1 0-10 0c0 4.4 5 8.8 5 8.8z"/><circle cx="12" cy="11.5" r="1.8"/><path d="M3.2 8a9.6 9.6 0 0 0 0 7M20.8 8a9.6 9.6 0 0 1 0 7"/></svg><span class="p-cnt" id="pin-count">0</span></button>
    <?php if (HOTSPOTS_ENABLED): ?>
    <button class="p-dock-btn" id="hotspot-toggle" aria-expanded="false" aria-controls="hotspot-side" title="<?= e(t('Hotspot clusters', 'Mga kumpol ng hotspot')) ?>" aria-label="<?= e(t('Hotspot clusters', 'Mga kumpol ng hotspot')) ?>">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3c1.3 3.4 5 4.8 5 9.5a5 5 0 0 1-10 0c0-2 .8-3.6 2-4.8.3 1.8 1.1 2.9 2.2 3.3C10.8 8.6 10.7 5.6 12 3z"/></svg><span class="p-cnt" id="hotspot-count">0</span></button>
    <?php endif; ?>
  </div>
</section>

<link rel="stylesheet" href="assets/vendor/maplibre/maplibre-gl.css">
<script src="assets/vendor/maplibre/maplibre-gl.js"></script>
<?php if (env('MAPILLARY_TOKEN', '') !== ''): ?>
<link rel="stylesheet" href="assets/vendor/mapillary/mapillary.css">
<script src="assets/vendor/mapillary/mapillary.js"></script>
<?php endif; ?>
<script src="assets/js/map-theme.js?v=<?= e(asset_version('../js/map-theme.js')) ?>"></script>
<script src="assets/js/sd-icons.js?v=<?= e(asset_version('../js/sd-icons.js')) ?>"></script>
<script src="assets/js/sd-pickers.js?v=<?= e(asset_version('../js/sd-pickers.js')) ?>"></script>
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
  { accessToken: window.ssAccessToken(TOKEN) }
);

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
// Rose (2 Oct 2026): pins are coloured by category, one shape for all;
// status is in the filter and the pin's detail. (The status shapes above
// stay for the legend-by-status this replaced.)
const CATEGORY_COLOUR = <?= json_encode(category_colours()) ?>;
const catColour = c => CATEGORY_COLOUR[c] || CATEGORY_COLOUR.other;
const pinName = category => 'pin-cat-' + (CATEGORY_COLOUR[category] ? category : 'other');

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

// Bellinist (9 Oct 2026): the pin is the resident app's badge: a teardrop
// in the category's colour with the category's own symbol on a white disc.
// Colour still carries the category; the symbol carries it for the one man
// in twelve who cannot separate the hues. At night it glows in its colour.
const PIN_GLYPH = {
  street_obstruction: SD_ICONS.obstruction, public_safety_infrastructure: SD_ICONS.infra, environmental_waste_hazard: SD_ICONS.waste,
  animal_welfare: SD_ICONS.animal, traffic_violation: SD_ICONS.traffic, barangay_service: SD_ICONS.service, peace_order_nuisance: SD_ICONS.noise, other: SD_ICONS.other,
};
const isDark = () => document.documentElement.getAttribute('data-theme') === 'dark';
function pinTear(cat, fill, dark) {
  const glyph = (PIN_GLYPH[cat] || PIN_GLYPH.other).replace(/__C__/g, fill);
  const filter = dark
    ? '<filter id="g" x="-60%" y="-40%" width="220%" height="180%"><feDropShadow dx="0" dy="0" stdDeviation="2.6" flood-color="' + fill + '" flood-opacity=".95"/></filter>'
    : '<filter id="g" x="-40%" y="-30%" width="180%" height="160%"><feDropShadow dx="0" dy="1.2" stdDeviation="1.3" flood-color="#000" flood-opacity=".35"/></filter>';
  return '<svg xmlns="http://www.w3.org/2000/svg" width="88" height="104" viewBox="-22 -52 44 52"><defs>' + filter + '</defs>' +
    '<g filter="url(#g)"><path d="M0 0C-4-9-15-15-15-27a15 15 0 0 1 30 0C15-15 4-9 0 0Z" fill="' + fill + '" stroke="#fff" stroke-width="1.6"/>' +
    '<circle cy="-27" r="9.5" fill="#fff"/>' +
    '<g transform="translate(-6.5 -33.5) scale(.54)" fill="none" stroke="' + fill + '" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round">' + glyph + '</g></g></svg>';
}
function addPinImages() {
  const dark = isDark();
  return Promise.all(Object.entries(CATEGORY_COLOUR).map(([c, hex]) => {
    if (map.hasImage('pin-cat-' + c)) map.removeImage('pin-cat-' + c);
    return addSvgImage('pin-cat-' + c, pinTear(c, hex, dark));
  }));
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
// Bellinist intro (9 Oct 2026): once a session the map opens wide, the
// barangay's outline draws itself, the camera settles on the residential
// area and the pins drop in. Skipped for reduced motion; ?intro=1 forces it.
const AREA_CENTRE = [(AREA[0][0] + AREA[1][0]) / 2, (AREA[0][1] + AREA[1][1]) / 2];
let introHide = false;
const INTRO = (() => {
  try {
    if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return false;
    if (/[?&]intro=1\b/.test(location.search)) return (introHide = true);
    if (sessionStorage.getItem('ss-spatial-intro')) return false;
    sessionStorage.setItem('ss-spatial-intro', '1');
    return (introHide = true);
  } catch (e) { return false; }
})();
if (INTRO) document.getElementById('map').classList.add('dm-hide');
const map = new maplibregl.Map({
  container: 'map',
  style: window.mapStyleUrl(),
  center: INTRO ? AREA_CENTRE : RESIDENTIAL_CENTRE,
  zoom: INTRO ? 15 : DEFAULT_ZOOM,
  minZoom: 15,
  maxZoom: 18,
  maxBounds: AREA,
  dragRotate: false,
  pitchWithRotate: false,
  attributionControl: false,
});
// Bottom-left, so the zoom buttons sit where Leaflet's did, under the dock.
map.addControl(new maplibregl.AttributionControl({ compact: true }), 'bottom-right');
map.touchZoomRotate.disableRotation();
// The style or its tiles could not load: say so rather than show a blank.
map.on('error', e => {
  if (!map.isStyleLoaded() || (e && e.error && /style|tile|source/i.test(String(e.error.message || '')))) {
    document.getElementById('map-failed').hidden = false;
  }
});
map.on('load', () => { document.getElementById('map-failed').hidden = true; });
map.keyboard.disableRotation();
mapFollowTheme(map);
// Bellinist: while the map is being moved the filter rows fold away and the
// controls dim, so the map has the whole screen; they return when the
// pointer does, or two seconds after the map settles.
{
  const sec = document.getElementById('s-spatial'); let t;
  sec.classList.add('ss-peek'); setTimeout(() => sec.classList.remove('ss-peek'), 3500);
  const fold = e => { if (!e.originalEvent) return; sec.classList.add('ss-dragging'); clearTimeout(t); };
  const unfold = () => { clearTimeout(t); t = setTimeout(() => sec.classList.remove('ss-dragging'), 2200); };
  ['dragstart', 'zoomstart'].forEach(ev => map.on(ev, fold));
  ['dragend', 'zoomend', 'moveend'].forEach(ev => map.on(ev, unfold));
}
map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'bottom-right');

const EMPTY = { type: 'FeatureCollection', features: [] };
let hazards = null;
const point = (lng, lat, props) => ({ type: 'Feature', properties: props || {},
                                      geometry: { type: 'Point', coordinates: [lng, lat] } });

// Everything waits on the style; data that arrives first is drawn then.
const mapReady = new Promise(resolve => map.on('load', async () => {
  await addPinImages();
  window.addEventListener('themechange', () => { addPinImages(); outlineLook(); bigLabelLook(); });

  // Bottom to top: fog, outline, complaint heat, hotspots, complaints.
  // (Live tanod positions and path heat were removed on branch B, 26 Sep
  // 2026: the tanod app no longer streams a location — see 0067.)
  map.addSource('fog', { type: 'geojson', data: EMPTY, lineMetrics: true });
  map.addLayer({ id: 'fog', type: 'fill', source: 'fog',
                 paint: { 'fill-color': '#0d1117', 'fill-opacity': .55 } });
  map.addLayer({ id: 'outline', type: 'line', source: 'fog', filter: ['==', ['get', 'role'], 'outline'],
                 paint: { 'line-color': '#14181d', 'line-width': 2, 'line-opacity': .9 } });
  map.setFilter('fog', ['==', ['get', 'role'], 'fog']);
  // A soft glow under the outline, for the night map only.
  map.addLayer({ id: 'outline-glow', type: 'line', source: 'fog', filter: ['==', ['get', 'role'], 'outline'], layout: { visibility: 'none' },
                 paint: { 'line-color': '#FF9D3C', 'line-width': 9, 'line-blur': 7, 'line-opacity': .6 } }, 'outline');
  // "BARANGAY 183", large and faint, under everything; it fades as you zoom in.
  // The names of the places round the barangay, in large faint type under the
  // pins: the barangay itself, then Villamor, the airport terminal, Newport
  // and the neighbouring barangays. Places are placed in priority order and
  // one that would run into a bigger one stays out of its way.
  // (k: size tier, o: how faint; coordinates from OpenStreetMap.)
  map.addSource('biglab', { type: 'geojson', data: { type: 'FeatureCollection', features: [
    point(RESIDENTIAL_CENTRE[0], RESIDENTIAL_CENTRE[1] + 0.0004, { name: 'BARANGAY 183', sub: 'PASAY CITY · ZONE 20', k: 1, o: .11, p: 0 }),
    point(121.02433, 14.51713, { name: 'VILLAMOR AIR BASE', sub: 'PHILIPPINE AIR FORCE', k: .8, o: .12, p: 1 }),
    point(121.01375, 14.51922, { name: 'NAIA TERMINAL 3', sub: 'NINOY AQUINO INTERNATIONAL AIRPORT', k: .75, o: .12, p: 1 }),
    point(121.01768, 14.51954, { name: 'NEWPORT CITY', sub: 'RESORTS WORLD MANILA', k: .6, o: .105, p: 2 }),
    point(121.0209, 14.5249, { name: 'VILLAMOR GOLF COURSE', sub: 'VILLAMOR AIR BASE', k: .55, o: .1, p: 2 }),
    point(121.02057, 14.53049, { name: 'HUMABON PLACE', sub: 'MAGALLANES', k: .55, o: .1, p: 2 }),
    point(121.00790, 14.53148, { name: 'MARICABAN', sub: 'PASAY CITY', k: .55, o: .1, p: 2 }),
    point(121.00774, 14.52843, { name: 'BARANGAY 184', k: .4, o: .09, p: 3 }),
    point(121.01100, 14.52751, { name: 'BARANGAY 185', k: .4, o: .09, p: 3 }),
    point(121.01029, 14.53044, { name: 'BARANGAY 182', k: .4, o: .09, p: 3 }),
    point(121.01130, 14.53002, { name: 'BARANGAY 181', k: .33, o: .08, p: 4 }),
    point(121.01170, 14.53019, { name: 'BARANGAY 180', k: .33, o: .08, p: 4 }),
    point(121.00489, 14.53177, { name: 'BARANGAY 186', k: .4, o: .09, p: 3 }),
    point(121.00811, 14.53198, { name: 'BARANGAY 168', k: .33, o: .08, p: 4 }),
  ] } });
  map.addLayer({ id: 'biglab', type: 'symbol', source: 'biglab',
    layout: { 'text-field': ['format', ['get', 'name'], {}, ['case', ['has', 'sub'], '\n', ''], {}, ['coalesce', ['get', 'sub'], ''], { 'font-scale': .3 }],
              'text-font': ['Noto Sans Bold'], 'text-letter-spacing': .16, 'text-allow-overlap': false, 'text-ignore-placement': false, 'text-padding': 12,
              'symbol-sort-key': ['get', 'p'], 'text-max-width': 40,
              'text-size': ['interpolate', ['exponential', 2], ['zoom'], 15, ['*', ['get', 'k'], 30], 18, ['*', ['get', 'k'], 240]] },
    paint: { 'text-color': '#141B34', 'text-opacity': 0 } });
  outlineLook(); bigLabelLook();

  // Project NOAH's flood and storm-surge zones (map-theme.js), off until
  // the switch or a rain warning turns them on; and a ring for each open
  // complaint inside a zone at risk under the current warning.
  hazards = window.mapHazards ? window.mapHazards(map, { hidden: true }) : null;
  map.addSource('risk', { type: 'geojson', data: EMPTY });
  map.addLayer({ id: 'risk', type: 'circle', source: 'risk',
    paint: { 'circle-radius': 20, 'circle-color': 'rgba(14,165,233,0)', 'circle-stroke-color': '#0EA5E9', 'circle-stroke-width': 3 } });

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

  map.addSource('hotspots', { type: 'geojson', data: EMPTY });
  map.addLayer({ id: 'hotspots', type: 'circle', source: 'hotspots', layout: { visibility: 'none' },
    paint: {
      'circle-radius': ['get', 'radius'],
      'circle-color': ['get', 'colour'],
      'circle-opacity': .55,
      'circle-stroke-color': '#fff',
      'circle-stroke-width': 2,
    } });

  setPinsSource(false);

  ['pins', 'hotspots'].forEach(id => {
    map.on('mouseenter', id, () => { map.getCanvas().style.cursor = 'pointer'; });
    map.on('mouseleave', id, () => { map.getCanvas().style.cursor = ''; });
  });
  map.on('click', 'pins', e => { const r = byId.get(e.features[0].properties.id); if (r) showDetail(r); });
  map.on('click', 'hotspots', e => { const h = hotspots[e.features[0].properties.i]; if (h) showHotspotDetail(h); });
  // If the complaints are slow or fail, the intro still settles the camera.
  setTimeout(() => runIntro(), 4500);

  resolve();
}));

// Donut pins (Bellinist): a cluster is the complaint pin, bigger, with a ring of
// the categories inside it and the count on its white disc. They are drawn as
// markers from the cluster's own category counts; they spring in as you zoom
// out and burst when you open one.
const DM = new Map();
let dmKey = '';
const dmCats = () => Object.keys(CATEGORY_COLOUR);
function donutSvg(props, n) {
  const cats = dmCats(), parts = cats.map((c, i) => [c, Number(props['c' + i] || 0)]).filter(x => x[1] > 0), tot = parts.reduce((a, x) => a + x[1], 0) || 1;
  let a0 = -90, ring = '';
  parts.forEach(([c, v]) => {
    const a1 = a0 + 360 * v / tot, whole = parts.length === 1, r = 21, f = a => [(r * Math.cos(a * Math.PI / 180)).toFixed(2), (r * Math.sin(a * Math.PI / 180)).toFixed(2)];
    if (whole) ring += '<circle r="' + r + '" fill="none" stroke="' + catColour(c) + '" stroke-width="5"/>';
    else { const p0 = f(a0), p1 = f(a1 - 4); ring += '<path d="M' + p0 + ' A' + r + ' ' + r + ' 0 ' + (a1 - a0 > 180 ? 1 : 0) + ' 1 ' + p1 + '" fill="none" stroke="' + catColour(c) + '" stroke-width="5" stroke-linecap="round"/>'; }
    a0 = a1;
  });
  return '<svg viewBox="-34 -78 68 82" aria-hidden="true"><path class="dm-body" d="M0 0C-7-14-27-24-27-43a27 27 0 0 1 54 0C27-24 7-14 0 0Z" stroke="#fff" stroke-width="2.4"/>' +
    '<g transform="translate(0 -43)">' + ring + '<circle r="15.5" fill="#fff"/><text y="' + (String(n).length > 3 ? 5 : 6) + '" text-anchor="middle" font-family="Urbanist,sans-serif" font-weight="800" font-size="' + (String(n).length > 3 ? 12 : 17) + '" fill="#141B34">' + esc(n) + '</text></g></svg>';
}
function clusterMarkers() {
  if (map._dmBound) return; map._dmBound = true;
  const update = () => {
    if (!map.getLayer('clusters')) return;
    const feats = clustered ? map.queryRenderedFeatures({ layers: ['clusters'] }) : [], seen = new Map();
    feats.forEach(f => { if (f.properties.cluster_id != null && !seen.has(f.properties.cluster_id)) seen.set(f.properties.cluster_id, f); });
    const key = [...seen.keys()].sort().join(',') + '|' + (isDark() ? 1 : 0);
    if (key === dmKey) return; dmKey = key;
    DM.forEach((m, id) => { if (!seen.has(id)) { m.el.classList.remove('in'); m.el.classList.add('out'); setTimeout(() => m.marker.remove(), 260); DM.delete(id); } });
    seen.forEach((f, id) => {
      if (DM.has(id)) return;
      const n = f.properties.point_count, w = n < 10 ? 46 : n < 50 ? 58 : 70, el = document.createElement('button');
      el.type = 'button'; el.className = 'dm in'; el.style.width = w + 'px'; el.style.height = (w * 82 / 68) + 'px';
      el.setAttribute('aria-label', n + T(' complaints, open to see them', ' sumbong, buksan para makita'));
      el.innerHTML = donutSvg(f.properties, f.properties.point_count_abbreviated || n);
      const marker = new maplibregl.Marker({ element: el, anchor: 'bottom' }).setLngLat(f.geometry.coordinates).addTo(map);
      el.addEventListener('click', async ev => {
        ev.stopPropagation(); el.classList.add('burst');
        const zoom = await map.getSource('reports').getClusterExpansionZoom(f.properties.cluster_id);
        map.easeTo({ center: f.geometry.coordinates, zoom, duration: 700 });
      });
      DM.set(id, { marker, el });
    });
  };
  map.on('render', update);
  window.addEventListener('themechange', () => { dmKey = ''; DM.forEach(m => m.marker.remove()); DM.clear(); update(); });
}

// Below the threshold every pin stands alone; above it they would sit on
// top of each other on a barangay-sized map, so they gather into counted
// clusters that split as you zoom. A GeoJSON source is clustered or not
// from creation, so it is rebuilt when the count crosses the line.
const CLUSTER_FROM = 25;
let clustered = null;
function setPinsSource(want) {
  if (clustered === want) return;
  ['pins', 'clusters'].forEach(id => { if (map.getLayer(id)) map.removeLayer(id); });
  if (map.getSource('reports')) map.removeSource('reports');
  clustered = want;
  // A cluster counts its members per category, so its ring can show the mix.
  const clusterProperties = {};
  Object.keys(CATEGORY_COLOUR).forEach((c, i) => { clusterProperties['c' + i] = ['+', ['case', ['==', ['get', 'cat'], c], 1, 0]]; });
  map.addSource('reports', { type: 'geojson', data: EMPTY,
                             cluster: want, clusterRadius: 46, clusterMaxZoom: 17, clusterProperties });
  const h = introHide ? 0 : 1;
  map.addLayer({ id: 'clusters', type: 'circle', source: 'reports', filter: ['has', 'point_count'],
    paint: { 'circle-opacity': 0, 'circle-stroke-opacity': 0, 'circle-radius': 20 } });
  clusterMarkers();
  map.addLayer({ id: 'pins', type: 'symbol', source: 'reports', filter: ['!', ['has', 'point_count']],
    layout: { 'icon-image': ['get', 'icon'], 'icon-allow-overlap': true, 'icon-ignore-placement': true,
              'icon-anchor': 'bottom', 'icon-size': ['interpolate', ['linear'], ['zoom'], 15, .62, 16, .74, 18, .95] },
    paint: { 'icon-opacity': h } });
  // The flood-risk rings go round pins and clusters alike, so they sit on top.
  if (map.getLayer('risk')) {
    map.moveLayer('risk');
    // A pin's head is above the point it marks, so its ring is lifted to match.
    map.setPaintProperty('risk', 'circle-translate', want ? [0, 0] : [0, -20]);
  }
}

// The outline and the big type follow the theme.
function outlineLook() {
  if (!map.getLayer('outline')) return;
  const dark = isDark();
  map.setPaintProperty('outline', 'line-color', dark ? '#FF9D3C' : '#14181d');
  map.setLayoutProperty('outline-glow', 'visibility', dark ? 'visible' : 'none');
}
function bigLabelLook() {
  if (!map.getLayer('biglab')) return;
  const dark = isDark(), m = dark ? 1.45 : 1;
  map.setPaintProperty('biglab', 'text-color', dark ? '#FF9D3C' : '#141B34');
  map.setPaintProperty('biglab', 'text-opacity', ['interpolate', ['linear'], ['zoom'],
    15, ['*', m, ['get', 'o']], 16.4, ['*', m * .45, ['get', 'o']], 17.2, 0]);
}

// The intro: the outline draws itself, the camera settles, the pins drop.
let introRan = false;
function runIntro() {
  if (!INTRO || introRan) return; introRan = true;
  const ease = t => 1 - Math.pow(1 - t, 3), back = t => { const c = 1.9; return 1 + (c + 1) * Math.pow(t - 1, 3) + c * Math.pow(t - 1, 2); };
  const frame = (ms, fn, done) => { const t0 = performance.now(); (function f(now) { const u = Math.min(1, (now - t0) / ms); fn(u); if (u < 1) requestAnimationFrame(f); else if (done) done(); })(t0); };
  const dark = isDark();
  map.setPaintProperty('outline', 'line-width', 5);
  frame(1900, u => map.setPaintProperty('outline', 'line-gradient', ['step', ['line-progress'], '#FF9800', Math.max(.001, ease(u)), 'rgba(255,152,0,0)']),
    () => { map.setPaintProperty('outline', 'line-gradient', null); map.setPaintProperty('outline', 'line-width', 2); });
  setTimeout(() => map.easeTo({ center: RESIDENTIAL_CENTRE, zoom: DEFAULT_ZOOM, duration: 1900, easing: ease }), 1000);
  setTimeout(() => {
    introHide = false;
    frame(850, u => {
      const o = Math.min(1, u * 2);
      if (map.getLayer('pins')) { map.setPaintProperty('pins', 'icon-opacity', o); map.setPaintProperty('pins', 'icon-translate', [0, -120 * (1 - back(u))]); }
      document.getElementById('map').classList.toggle('dm-hide', false);
    }, () => { if (map.getLayer('pins')) map.setPaintProperty('pins', 'icon-translate', [0, 0]); });
  }, 2700);
}

let all = [], rings = [];
let loaded = false;   // the complaints have arrived at least once
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
// What the map shows is what was last applied, not what the dropdowns
// say right now (Rose, 27 Sep 2026: choose, then Apply).
const applied = { cat: '', st: '', period: '', allTime: true };

function readFilters() {
  return {
    cat: document.getElementById('f-category').value,
    st: document.getElementById('f-status').value,
    period: document.getElementById('f-period').value,
    allTime: document.getElementById('f-period-all').checked,
  };
}

function markDirty() {
  const f = readFilters();
  const dirty = f.cat !== applied.cat || f.st !== applied.st || f.allTime !== applied.allTime
             || (!f.allTime && f.period !== applied.period);
  document.getElementById('f-apply').classList.toggle('p-dirty', dirty);
}

function visible() {
  const { cat, st } = applied;
  const { from, to } = periodRange();
  const fromMs = new Date(from).getTime(), toMs = new Date(to).getTime();
  return all.filter(r => {
    if (cat && r.category !== cat) return false;
    if (st && !(STATUS_GROUPS[st] || []).includes(r.status)) return false;
    const t = new Date(r.created_at).getTime();
    if (t < fromMs || t >= toMs) return false;
    return true;
  });
}

async function draw() {
  const rows = visible();
  document.getElementById('map-empty').hidden = rows.length > 0 || !loaded;
  byId.clear();
  all.forEach(r => byId.set(r.id, r));

  await mapReady;
  setPinsSource(rows.length >= CLUSTER_FROM);
  // Complaints filed from the very same spot would sit exactly on top of
  // each other and read as one pin (Rose, 2 Oct 2026: "recheck the
  // number of complaints"). Each repeat is set a few metres round the
  // spot, so every complaint counted is a pin you can see and click.
  const seen = new Map();
  const features = rows.map(r => {
    const key = (+r.latitude).toFixed(5) + ',' + (+r.longitude).toFixed(5);
    const n = seen.get(key) || 0;
    seen.set(key, n + 1);
    let lng = +r.longitude, lat = +r.latitude;
    if (n > 0) {
      const ang = n * 2.4, d = 0.00004 * Math.ceil(n / 6);   // about 4 m per ring
      lng += d * Math.cos(ang) / Math.cos(lat * Math.PI / 180);
      lat += d * Math.sin(ang);
    }
    return point(lng, lat, { id: r.id, icon: pinName(r.category), cat: r.category });
  });
  map.getSource('reports').setData({ type: 'FeatureCollection', features });

  // Complaints pinned outside the area the map can show (old test
  // reports, or a resident filing from elsewhere) are counted, and said
  // to be, rather than silently missing from the count you can see.
  const [[w, s], [e, n]] = AREA;
  const outside = rows.filter(r => r.longitude < w || r.longitude > e || r.latitude < s || r.latitude > n).length;
  document.getElementById('map-count').textContent =
    rows.length + T(rows.length === 1 ? ' complaint' : ' complaints', ' sumbong') +
    (outside ? T(' · ' + outside + ' outside this map', ' · ' + outside + ' nasa labas ng mapang ito') : '');

  const heatOn = document.getElementById('f-heat').checked && rows.length;
  map.getSource('heat').setData(heatOn
    ? { type: 'FeatureCollection', features: rows.map(r => point(r.longitude, r.latitude)) } : EMPTY);
  map.setLayoutProperty('heat', 'visibility', heatOn ? 'visible' : 'none');

  fwRisk();

  const badge = document.getElementById('incident-toggle');
  document.getElementById('pin-count').textContent = rows.length;
  badge.classList.toggle('p-live-n', rows.length > 0);

  const list = document.getElementById('pin-list');
  list.innerHTML = '';
  rows.slice(0, 40).forEach(r => {
    const li = document.createElement('li');
    li.className = 'p-pin-row';
    li.innerHTML =
      '<span class="p-dot-s" style="background:' + catColour(r.category) + '"></span>' +
      '<span class="p-pin-body"><a href="case.php?id=' + encodeURIComponent(r.id) + '">' + esc(r.tracking_id) + '</a>' +
      '<small>' + esc(label(r.category)) + '</small></span>';
    // Clicking a row (not hovering) moves the map, and opens the case panel.
    li.style.cursor = 'pointer';
    li.addEventListener('click', e => { if (e.target.closest('a')) return; showDetail(r); });
    list.appendChild(li);
  });

  if (!rows.length) {
    list.innerHTML = '<li class="p-pin-empty">' + T('No complaint matches these filters.', 'Walang sumbong na tugma sa mga salang ito.') + '</li>';
  }
  if (loaded) runIntro();
}

// ---- data + realtime ---------------------------------------------
async function load() {
  const { data, error } = await sb.from('reports')
    .select('id,tracking_id,subject,category,status,latitude,longitude,location_label,created_at,due_at')
    .is('deleted_at', null)
    .order('created_at', { ascending: false });

  const note = document.getElementById('map-status');
  if (error) { note.textContent = T('Could not load complaints: ', 'Hindi ma-load ang mga sumbong: ') + error.message; return; }

  all = data || [];
  loaded = true;
  note.textContent = all.length
    ? T('Live — new complaints appear without refreshing.', 'Live — lumalabas ang bagong sumbong nang hindi nire-refresh.')
    : T('No complaints have been filed yet.', 'Wala pang naisampang sumbong.');
  // Still down: keep saying so; the line above was just rewritten with the good news.
  if (connLost && window.__showLive) { delete note.dataset.live; window.__showLive(true); }
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
    // The title card carries it: the Live pill goes red and says Reconnecting, and the line beside it says why.
    const pill = document.getElementById('map-live'), note = document.getElementById('map-status');
    const showLive = down => {
      pill.classList.toggle('p-down', down); pill.lastChild.textContent = down ? T('Reconnecting…', 'Kumokonekta…') : T('Live', 'Live');
      if (down) { if (!note.dataset.live) note.dataset.live = note.textContent; note.textContent = T('Connection lost — new complaints are not appearing.', 'Nawala ang koneksyon — hindi lumalabas ang mga bagong sumbong.'); }
      else if (note.dataset.live) { note.textContent = note.dataset.live; delete note.dataset.live; }
    };
    window.__showLive = showLive;
    if (status === 'SUBSCRIBED') {
      strip.setAttribute('hidden', ''); showLive(false);
      // Changes made while the socket was down were never delivered, so
      // hiding the strip alone would present a map that is missing them
      // as current. Reload the rows once the channel is back.
      if (connLost) { connLost = false; load(); }
    } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
      connLost = true;
      text.textContent = T('Connection lost — this map is not updating. Reconnecting…', 'Nawala ang koneksyon — hindi nag-a-update ang mapa. Kumokonekta muli…');
      strip.removeAttribute('hidden'); showLive(true);
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

// ---- case panel ------------------------------------------------------
// A pin opens a Google Maps-style panel over the left of the map (3 Oct
// 2026, replacing the small detail box): the complaint, where it is, who
// has it, whether it sits in a Project NOAH flood zone, what else is
// nearby, and how far along it is. "Open this case" is at the bottom.
const CS_OPEN = ['pending_review', 'validated'], CS_DISPATCHED = ['assigned', 'in_progress', 'offline_investigation'], CS_DONE = ['resolved', 'closed', 'archived'];
let csFor = null;
function csIcon(d) { return '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + d + '</svg>'; }
function csPad() { return { left: innerWidth > 980 ? 420 : 0, top: 0, right: 0, bottom: 0 }; }
// Photos open in the page: hover to see the cue, press to view, arrows or the sides to go on, Esc to close.
let lbx = null;
function lbClose() { if (!lbx) return; const e = lbx.el; lbx = null; e.classList.remove('in'); setTimeout(() => e.remove(), 200); }
function lbShow(urls, i) {
  lbClose(); if (!urls.length) return;
  const el = document.createElement('div'); el.className = 'ss-lbx'; el.setAttribute('role', 'dialog'); el.setAttribute('aria-label', T('Photo', 'Larawan'));
  el.innerHTML = '<button type="button" class="lb-x" aria-label="' + T('Close', 'Isara') + '">&times;</button>' + (urls.length > 1 ? '<button type="button" class="lb-n p" aria-label="' + T('Previous', 'Nakaraan') + '">&#8249;</button><button type="button" class="lb-n n" aria-label="' + T('Next', 'Susunod') + '">&#8250;</button>' : '') +
    '<img alt=""><span class="lb-c"></span>';
  document.getElementById('s-spatial').appendChild(el); lbx = { el, urls, i };
  const go = d => { lbx.i = (lbx.i + d + urls.length) % urls.length; const im = el.querySelector('img'); im.classList.remove('sw'); void im.offsetWidth; im.referrerPolicy = 'no-referrer'; im.src = urls[lbx.i]; im.classList.add('sw'); el.querySelector('.lb-c').textContent = urls.length > 1 ? (lbx.i + 1) + ' / ' + urls.length : ''; };
  go(0); lbx.go = go; void el.offsetWidth; el.classList.add('in');
  el.addEventListener('click', e => { if (e.target.closest('.lb-n.p')) go(-1); else if (e.target.closest('.lb-n.n')) go(1); else if (!e.target.closest('img')) lbClose(); });
}
document.addEventListener('click', e => {
  const a = e.target.closest && e.target.closest('.qv-media a, .cs-photos a'); if (!a) return;
  e.preventDefault(); const box = a.parentNode, list = [...box.querySelectorAll('a')], urls = list.map(x => x.dataset.u || x.getAttribute('href'));
  lbShow(urls, 0); lbx.go(list.indexOf(a));
});
document.addEventListener('keydown', e => { if (!lbx) return; if (e.key === 'Escape') { e.stopPropagation(); lbClose(); } else if (e.key === 'ArrowRight' && lbx.urls.length > 1) lbx.go(1); else if (e.key === 'ArrowLeft' && lbx.urls.length > 1) lbx.go(-1); }, true);

// Pictures for the action tiles: each is a small world in the case's colour.
const ACT_SCENE = {
  send: '<svg class="bgx" viewBox="0 0 54 54" aria-hidden="true"><g class="st"><path d="M-2 16H56M-2 36H56M16 -2V56M38 -2V56"/></g><g class="bl"><rect x="20" y="20" width="14" height="12" rx="2"/><rect x="42" y="20" width="10" height="12" rx="2"/><rect x="2" y="40" width="12" height="12" rx="2"/><rect x="20" y="40" width="14" height="12" rx="2"/></g><path class="rt" d="M5 50C14 44 14 30 26 28S42 16 48 8"/><circle class="en" cx="48" cy="8" r="3.4"/><circle class="en o" cx="5" cy="50" r="2.4"/></svg>',
  zoom: '<svg class="bgx" viewBox="0 0 54 54" aria-hidden="true"><g class="st w"><path d="M-2 14H56M-2 40H56M14 -2V56M40 -2V56"/></g><g class="bl"><rect x="18" y="18" width="18" height="18" rx="3"/><rect x="2" y="2" width="8" height="8" rx="2"/><rect x="44" y="44" width="8" height="8" rx="2"/></g><circle class="lens" cx="27" cy="27" r="15"/><circle class="lens b" cx="27" cy="27" r="9"/></svg>',
  look: '<svg class="bgx" viewBox="0 0 54 54" aria-hidden="true"><defs><linearGradient id="lksk" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0A1230"/><stop offset="1" stop-color="#2A3F86"/></linearGradient></defs><rect width="54" height="54" fill="url(#lksk)"/><g class="sk"><circle cx="12" cy="9" r=".9"/><circle cx="40" cy="7" r=".8"/><circle cx="46" cy="18" r=".7"/><circle cx="24" cy="14" r=".6"/></g><path class="bd" d="M0 34L10 26V18L18 22V34Z"/><path class="bd" d="M54 34L44 26V16L36 22V34Z"/><path class="rd" d="M27 30L2 54H52Z"/><path class="ln" d="M27 32V54"/><ellipse class="gl" cx="27" cy="31" rx="18" ry="6"/></svg>',
  copy: '<svg class="bgx" viewBox="0 0 54 54" aria-hidden="true"><g class="sh2"><rect x="16" y="11" width="24" height="30" rx="3"/></g><g class="sh1"><rect x="12" y="15" width="24" height="30" rx="3"/><path d="M17 24H31M17 29H31M17 34H26"/></g></svg>',
};
// How far through its time a complaint is: elapsed against the deadline, red once past it.
function slaHtml(r) {
  if (!r.due_at || CS_DONE.includes(r.status) || r.status === 'rejected' || r.status === 'cancelled') return '';
  const t0 = new Date(r.created_at).getTime(), t1 = new Date(r.due_at).getTime(), now = Date.now(), f = Math.max(0, Math.min(1, (now - t0) / Math.max(1, t1 - t0))), late = now > t1;
  const ms = Math.abs(t1 - now), h = Math.round(ms / 36e5), when = h < 48 ? h + T(' h', ' oras') : Math.round(h / 24) + T(' days', ' araw');
  return '<div class="cs-sla' + (late ? ' late' : f > .75 ? ' soon' : '') + '"><div class="sl-t"><small>' + T('Time to deadline', 'Oras bago ang deadline') + '</small><b>' + (late ? T('Overdue by ', 'Lampas ng ') : T('Due in ', 'Sa loob ng ')) + when + '</b></div><div class="sl-bar"><i style="width:' + (f * 100).toFixed(0) + '%"></i></div></div>';
}
// One colour code for progress on every case, whatever its category: the portal's status family.
const STAGE_COL = ['#9AA3B2', '#F9AB00', '#2F6BFF', '#1E9E56'], STAGE_ICON = ['photo', 'handler', 'send', 'safepoints'];
function stageOf(i, rejected, status) {
  if (rejected && i === 1) return { c: status === 'cancelled' ? '#9AA3B2' : '#E5383B', i: 'close' };
  return { c: STAGE_COL[i], i: STAGE_ICON[i] };
}
function showDetail(r) {
  qvClose(true); spClose();
  const el = document.getElementById('case-sheet');
  csFor = r.id;
  const col = catColour(r.category);
  const lng = +r.longitude, lat = +r.latitude;
  const nearby = all.filter(q => q.id !== r.id && Math.hypot((q.longitude - lng) * 107500, (q.latitude - lat) * 110600) < 150).length;
  const rejected = r.status === 'rejected' || r.status === 'cancelled';
  const steps = rejected ? [[T('Filed', 'Naisampa'), 1], [label(r.status), 1]]
    : [[T('Filed', 'Naisampa'), 1], [T('Validated', 'Napatunayan'), r.status !== 'pending_review'],
       [T('Tanod dispatched', 'Na-dispatch ang tanod'), CS_DISPATCHED.includes(r.status) || CS_DONE.includes(r.status)], [T('Resolved', 'Nalutas'), CS_DONE.includes(r.status)]];
  el.style.setProperty('--cs', col);
  // The step the complaint is at now: bold, in the category's colour, with a ring.
  const cur = steps.reduce((m, [, on], i) => on ? i : m, 0);
  const glyph = (PIN_GLYPH[r.category] || PIN_GLYPH.other).replace(/__C__/g, '#fff');
  el.innerHTML =
    '<div class="cs-hero" id="cs-hero" title="' + T('Drag to move', 'I-drag para ilipat') + '"><span class="cs-grip" aria-hidden="true"></span><button class="cs-x" type="button" aria-label="' + T('Close', 'Isara') + '">&times;</button>' +
      '<span class="cs-cat">' + esc(label(r.category)) + '</span>' +
      '<svg class="cs-mark cs-glyph" viewBox="0 0 24 24" aria-hidden="true">' + glyph + '</svg></div>' +
    '<div class="cs-body">' +
      '<h2 class="cs-title">' + esc(r.subject || label(r.category)) + '</h2>' +
      '<p class="cs-meta"><span class="cs-id">' + esc(r.tracking_id) + '</span> · <span class="cs-st" style="--st:' + (COLOUR[r.status] || '#9aa1ab') + '">' + esc(label(r.status)) + '</span></p>' +
      '<div class="cs-acts' + (MLY ? ' four' : '') + '">' +
        '<a class="ac-send" data-act="dispatch" href="case.php?id=' + encodeURIComponent(r.id) + '#dispatch"><span>' + ACT_SCENE.send + csIcon(SD_ICONS.send) + '</span>' + T('Dispatch', 'I-dispatch') + '</a>' +
        '<button type="button" class="ac-zoom" data-act="zoom"><span>' + ACT_SCENE.zoom + csIcon(SD_ICONS.zoom) + '</span>' + T('Zoom here', 'Lapitan') + '</button>' +
        (MLY ? '<button type="button" class="ac-look" data-act="look"><span>' + ACT_SCENE.look + csIcon(SD_ICONS.view360) + '</span>' + T('Look around', 'Luminga') + '</button>' : '') +
        '<button type="button" class="ac-copy" data-act="copy"><span>' + ACT_SCENE.copy + csIcon(SD_ICONS.copy) + '</span>' + T('Copy ID', 'Kopyahin') + '</button>' +
      '</div>' +
      '<ul class="cs-rows">' +
        '<li>' + csIcon(SD_ICONS.pin) + '<span>' + esc(r.location_label ? T('Near ', 'Malapit sa ') + r.location_label : T('Pinned location', 'Naka-pin na lokasyon')) + '<small>Barangay 183, Zone 20, Villamor, Pasay City</small></span></li>' +
        '<li>' + csIcon(SD_ICONS.calendar) + '<span>' + T('Submitted ', 'Isinumite ') + esc(fmtDate(r.created_at) || '—') + '<small>' + esc(r.due_at ? T('Deadline ', 'Takdang oras ') + fmtDate(r.due_at) : T('No deadline set', 'Walang takdang oras')) + '</small></span></li>' +
        '<li>' + csIcon(SD_ICONS.handler) + '<span id="cs-tanod">' + T('Checking who has it…', 'Tinitingnan kung sino ang may hawak…') + '<small>&nbsp;</small></span></li>' +
        '<li>' + csIcon(SD_ICONS.flood) + '<span id="cs-flood">' + T('Checking the flood map…', 'Tinitingnan ang mapa ng baha…') + '<small>Project NOAH 100-year flood map</small></span></li>' +
        '<li>' + csIcon(SD_ICONS.radar) + '<span>' + nearby + T(nearby === 1 ? ' other complaint within 150 m' : ' other complaints within 150 m', ' iba pang sumbong sa loob ng 150 m') + '<small>' + T('Same block or the next', 'Parehong bloke o katabi') + '</small></span></li>' +
      '</ul>' +
      '<h3 class="cs-h">' + T('Progress', 'Takbo') + '</h3>' +
      '<ol class="cs-stg">' + steps.map(([t, on], i) => {
        const g = stageOf(i, rejected, r.status), nx = steps[i + 1] ? stageOf(i + 1, rejected, r.status) : null;
        return '<li class="' + (on ? 'on' : '') + (i === cur ? ' cur' : '') + '" style="--c:' + g.c + '">' + (nx ? '<i class="sg' + (i < cur ? ' lit' : '') + '" style="--a:' + g.c + ';--b:' + nx.c + '"></i>' : '') +
          '<span class="bub">' + (on && i < cur ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l5 5 9-10"/></svg>' : sdIcon(g.i)) + '</span><b>' + esc(t) + '</b></li>';
      }).join('') + '</ol>' + slaHtml(r) +
      '<div id="cs-extra"></div>' +
    '</div>' +
    '<div class="cs-foot"><a class="p-btn p-btn-primary cs-open" href="case.php?id=' + encodeURIComponent(r.id) + '"><span>' + T('Open this case', 'Buksan ang kasong ito') + '</span><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"/></svg></a></div>';
  el.hidden = false; el.querySelector('.cs-body').scrollTop = 0;
  document.getElementById('s-spatial').classList.add('sheet-open');
  if (typeof mapDrawer === 'function') mapDrawer('sheet');
  map.easeTo({ center: [lng, lat], zoom: Math.max(map.getZoom(), 17), padding: csPad(), duration: 800 });
  el.querySelector('.cs-x').addEventListener('click', closeCaseSheet);
  csDraggable(el);
  // Each action answers its press, then goes where it says: the plane flies off, then the dispatch page;
  // the magnifier magnifies, then the zoomed card; the 360 turns once, then the street; the copy ticks.
  const ACT = (btn, cls, ms, then) => btn && btn.addEventListener('click', ev => {
    ev.preventDefault(); if (btn.classList.contains(cls)) return; btn.classList.add(cls);
    const reduced = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    setTimeout(() => { btn.classList.remove(cls); }, ms + 120); setTimeout(then, reduced ? 0 : ms);
  });
  const dp = el.querySelector('[data-act=dispatch]'); ACT(dp, 'go', 520, () => { location.href = dp.getAttribute('href'); });
  ACT(el.querySelector('[data-act=zoom]'), 'go', 420, () => qvOpen(r));
  ACT(el.querySelector('[data-act=look]'), 'go', 650, () => lkOpen(r));
  const cp = el.querySelector('[data-act=copy]'); ACT(cp, 'go', 0, () => {
    const done = () => (window.pToast ? pToast(T('Copied ', 'Nakopya ') + r.tracking_id) : null);
    try { navigator.clipboard.writeText(r.tracking_id).then(done, done); } catch (e) { done(); }
    const sp = cp.querySelector('span'), lb = cp.lastChild, was = [sp.innerHTML, lb.textContent];
    sp.innerHTML = csIcon('<path d="M5 12.5l5 5 9-10"/>'); lb.textContent = T('Copied', 'Nakopya'); cp.classList.add('done');
    setTimeout(() => { sp.innerHTML = was[0]; lb.textContent = was[1]; cp.classList.remove('done'); }, 1500);
  });
  // Who has it, the first photo, and the flood level, filled in as they arrive.
  sb.from('dispatches').select('state,assigned_at,tanod:users!dispatches_tanod_id_fkey(full_name)').eq('report_id', r.id).order('assigned_at', { ascending: false }).limit(1)
    .then(({ data }) => { if (csFor !== r.id) return; const d = data && data[0], box = document.getElementById('cs-tanod'); if (!box) return;
      box.innerHTML = d && d.tanod ? esc(String(d.tanod.full_name || '').trim()) + '<small>' + esc(label(d.state)) + ' · ' + esc(fmtDate(d.assigned_at) || '') + '</small>'
        : esc(T('No tanod assigned yet', 'Wala pang naka-assign na tanod')) + '<small>' + esc(T('Dispatch from the case', 'I-dispatch mula sa kaso')) + '</small>'; });
  // The resident's words and photos fill the card under the progress.
  Promise.all([sb.from('reports').select('description').eq('id', r.id).limit(1), sb.from('report_media').select('media_url').eq('report_id', r.id).limit(3),
    sb.from('status_logs').select('new_status,remark,created_at,by:users!status_logs_changed_by_fkey(full_name)').eq('report_id', r.id).order('created_at', { ascending: false }).limit(1)]).then(([d, m, lg]) => {
    if (csFor !== r.id) return; const box = document.getElementById('cs-extra'); if (!box) return;
    const q = d.data && d.data[0] && d.data[0].description, ph = (m.data || []).map(x => x.media_url);
    const L = lg && lg.data && lg.data[0], ms = L ? Date.now() - new Date(L.created_at).getTime() : 0, h = Math.round(ms / 36e5), ago = h < 1 ? T('just now', 'ngayon lang') : h < 48 ? h + T(' h ago', ' oras ang nakalipas') : Math.round(h / 24) + T(' days ago', ' araw ang nakalipas');
    const last = L ? '<div class="cs-last"><i></i><div><small>' + T('Last update', 'Huling update') + ' · ' + esc(ago) + '</small><b>' + esc(label(L.new_status)) + (L.by && L.by.full_name ? ' · ' + esc(String(L.by.full_name).trim()) : T(' · by the system', ' · ng sistema')) + '</b>' + (L.remark ? '<span>' + esc(String(L.remark).slice(0, 140)) + '</span>' : '') + '</div></div>' : '';
    box.innerHTML = last + (q ? '<div class="cs-quote"><small>' + T('In the resident’s words', 'Sa salita ng residente') + '</small>“' + esc(String(q).slice(0, 200)) + (String(q).length > 200 ? '…' : '') + '”</div>' : '') +
      '';
  });
  sb.from('report_media').select('media_url').eq('report_id', r.id).limit(3)
    .then(({ data }) => { if (csFor !== r.id || !data || !data[0]) return; const h = document.getElementById('cs-hero'); if (!h) return;
      // The banner is the photo: hover shows View, press opens it large (with the others, if there are more).
      h.dataset.urls = JSON.stringify(data.map(d => d.media_url));
      const img = new Image(); img.alt = ''; img.className = 'cs-photo'; img.referrerPolicy = 'no-referrer';
      img.onload = () => { h.classList.add('has-photo'); if (!h.querySelector('.cs-view')) h.insertAdjacentHTML('beforeend', '<span class="cs-view"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + SD_ICONS.zoom + '</svg>' + T('View', 'Tingnan') + (data.length > 1 ? ' · ' + data.length : '') + '</span>'); };
      // A photo that will not load is skipped for the next one.
      let k = 0; img.onerror = () => { k++; if (k < data.length) img.src = data[k].media_url; };
      img.src = data[0].media_url; h.prepend(img); });
  (window.hazardAt ? window.hazardAt(lng, lat) : Promise.resolve({ flood: 0 })).then(h => {
    if (csFor !== r.id) return; const box = document.getElementById('cs-flood'); if (!box) return;
    const lv = h.flood || 0;
    box.firstChild.textContent = lv ? [T('Low', 'Mababa'), T('Medium', 'Katamtaman'), T('High', 'Mataas')][lv - 1] + T(' flood hazard', ' na panganib sa baha') : T('Outside the flood zones', 'Labas sa bahaing lugar');
  }).catch(() => {});
}
// ---- Look around: street imagery with the resident's photo in it ---------
// (Bellinist phase 5, 9 Oct 2026.) Mapillary's street-level imagery, found
// nearest to the complaint and newest first; the resident's photo stands in
// the scene where the complaint was filed, and a slider sets it beside the
// street as it was. Needs MAPILLARY_TOKEN; without one the buttons are not
// drawn.
const MLY = <?= json_encode(env('MAPILLARY_TOKEN', '')) ?>;
let LK = null;
const lkRad = d => d * Math.PI / 180;
const lkBearing = (a, b) => (Math.atan2((b.lng - a.lng) * Math.cos(lkRad(a.lat)), b.lat - a.lat) * 180 / Math.PI + 360) % 360;
const lkMetres = (a, b) => Math.hypot((b.lng - a.lng) * 107500, (b.lat - a.lat) * 110600);
const LK_DIRS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
const lkDir = b => LK_DIRS[Math.round(((b % 360) + 360) % 360 / 45) % 8];

async function lkFind(lng, lat) {
  const dl = 0.0013, db = 0.0011;
  const r = await fetch('https://graph.mapillary.com/images?' + new URLSearchParams({
    access_token: MLY, bbox: [lng - dl, lat - db, lng + dl, lat + db].join(','), limit: '2000',
    fields: 'id,captured_at,compass_angle,is_pano,computed_geometry' }));
  if (!r.ok) throw new Error('mapillary ' + r.status);
  let best = null;
  ((await r.json()).data || []).forEach(i => {
    const g = i.computed_geometry && i.computed_geometry.coordinates; if (!g) return;
    const d = lkMetres({ lng, lat }, { lng: g[0], lat: g[1] }), age = (Date.now() - i.captured_at) / 3.156e10;
    // Near beats far, new beats old, a panorama beats a flat photo.
    const score = d + age * 8 - (i.is_pano ? 12 : 0);
    if (d < 120 && (!best || score < best.score)) best = { id: i.id, score };
  });
  return best;
}
function lkClose(silent) {
  const el = document.getElementById('ss-lk'); if (!el) { LK = null; return; }
  const v = LK && LK.viewer; LK = null;
  try { if (v) v.remove(); } catch (e) { /* already gone */ }
  if (silent) { el.remove(); return; }
  el.classList.remove('open'); el.classList.add('out'); setTimeout(() => el.remove(), 520);
}
function lkOpen(r) {
  lkClose(true);
  if (!window.mapillary || !MLY) return;
  const sec = document.getElementById('s-spatial'), lng = +r.longitude, lat = +r.latitude, col = catColour(r.category);
  const here = { lng, lat }, glyph = (PIN_GLYPH[r.category] || PIN_GLYPH.other).replace(/__C__/g, '#fff');
  const el = document.createElement('div'); el.id = 'ss-lk'; el.className = 'ss-lk'; el.style.setProperty('--cs', col);
  const pt = map.project([lng, lat]), cb = map.getContainer().getBoundingClientRect(), sb0 = sec.getBoundingClientRect();
  el.style.setProperty('--ox', (pt.x + cb.left - sb0.left) + 'px'); el.style.setProperty('--oy', (pt.y + cb.top - sb0.top - 40) + 'px');
  el.innerHTML =
    '<div class="lk-view" id="lk-view"></div>' +
    '<div class="lk-cmp" id="lk-cmp" hidden><div class="lk-cmp-img" id="lk-cmp-img"><svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + glyph + '</svg></div>' +
      '<span class="lk-tag l">' + T('NOW · the resident’s photo', 'NGAYON · larawan ng residente') + '</span><div class="lk-grip" id="lk-grip"><span><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l-6 6 6 6M15 6l6 6-6 6"/></svg></span></div></div>' +
    '<span class="lk-tag r" id="lk-then" hidden></span>' +
    '<div class="lk-card" id="lk-card" hidden><div class="lk-ph" id="lk-ph"><span class="lk-gl"><svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + glyph + '</svg></span><em id="lk-phn"></em></div>' +
      '<div class="lk-cap"><b>' + esc(r.tracking_id) + '</b><small>' + T('Resident photo · ', 'Larawan ng residente · ') + esc(fmtDate(r.created_at) || '') + '</small></div><i class="lk-stem"></i><i class="lk-spot"></i></div>' +
    '<div class="lk-edge" id="lk-edge" hidden></div>' +
    '<div class="lk-top"><button type="button" class="lk-back" data-lkclose aria-label="' + T('Back to the map', 'Bumalik sa mapa') + '">' + sdIcon('back') + '</button>' +
      '<div class="lk-ti"><b>' + T('Look around', 'Luminga-linga') + '</b><span>' + esc(r.location_label ? T('Near ', 'Malapit sa ') + r.location_label : r.tracking_id) + ' · ' + esc(r.tracking_id) + '</span></div>' +
      '<div class="lk-hd" id="lk-hd"><svg class="lk-needle" id="lk-needle" viewBox="0 0 24 24"><path d="M12 3l5 16-5-4-5 4z" fill="currentColor"/></svg><b id="lk-hdt">N 0°</b></div></div>' +
    '<div class="lk-state" id="lk-state"><span class="lk-spin"></span><b>' + T('Finding street imagery…', 'Hinahanap ang street imagery…') + '</b></div>' +
    '<aside class="lk-send" id="lk-send" aria-label="' + T('Send to tanod', 'Ipadala sa tanod') + '"></aside>' +
    '<div class="lk-bar"><div class="lk-steps"><button type="button" data-lkstep="prev">' + T('◀ Step back', '◀ Umatras') + '</button><button type="button" data-lkstep="next">' + T('Step ahead ▶', 'Sumulong ▶') + '</button></div>' +
      '<div class="lk-fact" id="lk-fact"><span class="lk-cdot"></span>' + esc(label(r.category)) + '</div>' +
      '<div class="lk-acts"><button type="button" class="p-btn" id="lk-cmp-btn" data-lkcmp>' + T('Then / Now', 'Dati / Ngayon') + '</button><a class="p-btn" href="case.php?id=' + encodeURIComponent(r.id) + '">' + T('Open case', 'Buksan ang kaso') + '</a><button type="button" class="p-btn p-btn-primary" id="lk-send-btn" data-lksend disabled>' + T('Send to tanod', 'Ipadala sa tanod') + '</button></div>' +
      '<small class="lk-credit">' + T('Imagery © Mapillary contributors, CC BY-SA 4.0', 'Imagery © Mapillary contributors, CC BY-SA 4.0') + '</small></div>';
  sec.appendChild(el);
  LK = { el, r, here, viewer: null, ready: false, photos: [], pn: 0, raf: 0, bearing: 0, sx: 40 };
  void el.offsetWidth; el.classList.add('open');

  // The resident's photos, as they arrive.
  sb.from('report_media').select('media_url').eq('report_id', r.id).limit(3).then(({ data }) => {
    if (!LK || LK.r.id !== r.id || !data || !data.length) return;
    LK.photos = data.map(d => d.media_url); lkPhoto();
  });

  lkFind(lng, lat).then(best => {
    if (!LK || LK.r.id !== r.id) return;
    const st = document.getElementById('lk-state');
    if (!best) { st.innerHTML = '<b>' + T('No street imagery within 120 m of this spot.', 'Walang street imagery sa loob ng 120 m ng lugar na ito.') + '</b><small>' + T('Mapillary has nothing recent here.', 'Walang kuha ang Mapillary dito.') + '</small>'; st.classList.add('none'); return; }
    const v = new mapillary.Viewer({ accessToken: MLY, container: 'lk-view', imageId: best.id, component: { cover: false, zoom: false, bearing: false } });
    LK.viewer = v;
    v.on('image', e => lkImage(e.image));
    v.on('bearing', e => { LK.bearing = e.bearing; lkHeading(); lkPlace(); });
    ['pov', 'fov', 'position'].forEach(ev => v.on(ev, lkPlace));
  }).catch(err => { console.error('Look around', err); const st = document.getElementById('lk-state'); if (st) { st.innerHTML = '<b>' + T('Street imagery could not be reached.', 'Hindi maabot ang street imagery.') + '</b>'; st.classList.add('none'); } });
}
function lkImage(im) {
  if (!LK) return;
  const first = !LK.ready; LK.ready = true;
  LK.img = { id: im.id, lng: im.lngLat.lng, lat: im.lngLat.lat, comp: im.compassAngle, pano: im.cameraType === 'spherical', at: im.capturedAt };
  const st = document.getElementById('lk-state'); if (st) st.hidden = true;
  const sbn = document.getElementById('lk-send-btn'); if (sbn) sbn.disabled = false;
  const when = new Intl.DateTimeFormat('en-US', { month: 'short', year: 'numeric' }).format(new Date(im.capturedAt));
  const then = document.getElementById('lk-then'); then.hidden = false; then.textContent = T('THEN · street imagery, ', 'DATI · street imagery, ') + when + ' · Mapillary';
  const m = Math.round(lkMetres(LK.here, LK.img));
  document.getElementById('lk-fact').innerHTML = '<span class="lk-cdot"></span>' + esc(label(LK.r.category)) + ' · <b>' + (m < 3 ? T('you are at the spot', 'nandito ka na') : m + ' m ' + T('away', 'ang layo')) + '</b>';
  if (first && LK.img.pano) {
    // Turn to face the complaint.
    const b = lkBearing(LK.img, LK.here), delta = ((b - LK.img.comp + 540) % 360) - 180;
    LK.viewer.setCenter([(0.5 + delta / 360 + 1) % 1, 0.5]);
  }
  lkPlace();
}
function lkHeading() {
  const b = ((LK.bearing % 360) + 360) % 360;
  document.getElementById('lk-hdt').textContent = lkDir(b) + ' ' + Math.round(b) + '°';
  document.getElementById('lk-needle').style.transform = 'rotate(' + b.toFixed(0) + 'deg)';
}
function lkPhoto() {
  if (!LK) return;
  const url = LK.photos[LK.pn % (LK.photos.length || 1)], ph = document.getElementById('lk-ph'), ci = document.getElementById('lk-cmp-img');
  if (!url) return;
  ph.style.backgroundImage = 'url("' + url.replace(/"/g, '%22') + '")'; ph.classList.add('has');
  ci.style.backgroundImage = 'url("' + url.replace(/"/g, '%22') + '")'; ci.classList.add('has');
  document.getElementById('lk-phn').textContent = T('Photo ', 'Larawan ') + (LK.pn % LK.photos.length + 1) + '/' + LK.photos.length;
}
// The resident's photo stands where the complaint was filed.
function lkPlace() {
  if (!LK || !LK.viewer || !LK.ready || LK.busy) return;
  LK.busy = true;
  LK.viewer.project({ lng: LK.here.lng, lat: LK.here.lat }).then(p => {
    LK.busy = false; if (!LK) return;
    const card = document.getElementById('lk-card'), edge = document.getElementById('lk-edge'), W = LK.el.clientWidth, H = LK.el.clientHeight;
    if (p && p[0] != null && p[0] > -40 && p[0] < W + 40) {
      const u = Math.max(-1.2, Math.min(1.2, (p[0] - W / 2) / (W / 2)));
      card.hidden = false; edge.hidden = true;
      card.style.left = p[0] + 'px'; card.style.top = Math.max(96, p[1] - 232) + 'px';
      card.style.setProperty('--ry', (-u * 24).toFixed(1) + 'deg'); card.style.setProperty('--stem', Math.max(14, p[1] - Math.max(96, p[1] - 232) - 205) + 'px');
    } else {
      card.hidden = true;
      const rel = ((lkBearing(LK.img, LK.here) - LK.bearing + 540) % 360) - 180;
      edge.hidden = false; edge.className = 'lk-edge ' + (rel < 0 ? 'l' : 'r');
      edge.innerHTML = (rel < 0 ? '◀ ' : '') + T('The complaint is this way', 'Nandito ang sumbong') + (rel < 0 ? '' : ' ▶');
    }
  }).catch(() => { LK.busy = false; });
}
(function lkEvents() {
  document.addEventListener('click', e => {
    if (!LK || !e.target.closest) return; const t = e.target;
    if (t.closest('[data-lkclose]')) { lkClose(false); return; }
    const st = t.closest('[data-lkstep]');
    if (st && LK.viewer) { LK.viewer.moveDir(st.dataset.lkstep === 'next' ? mapillary.NavigationDirection.Next : mapillary.NavigationDirection.Prev).catch(() => {}); return; }
    if (t.closest('[data-lkcmp]')) {
      const c = document.getElementById('lk-cmp'), on = c.hidden; c.hidden = !on; t.closest('button').classList.toggle('on', on);
      LK.el.style.setProperty('--sx', LK.sx + '%'); return;
    }
    if (t.closest('[data-lksend]')) { lkSendOpen(); return; }
    if (t.closest('[data-lksendx]')) { document.getElementById('lk-send').classList.remove('open'); return; }
    const go = t.closest('[data-lksendgo]'); if (go) { lkSendGo(go); return; }
    if (t.closest('#lk-ph') && LK.photos.length > 1) { LK.pn++; lkPhoto(); }
  });
  document.addEventListener('pointerdown', e => {
    if (!LK || !e.target.closest || !e.target.closest('#lk-grip')) return; LK.drag = true; e.preventDefault();
  });
  window.addEventListener('pointermove', e => {
    if (!LK || !LK.drag) return; const r = LK.el.getBoundingClientRect();
    LK.sx = Math.max(8, Math.min(92, (e.clientX - r.left) / r.width * 100)); LK.el.style.setProperty('--sx', LK.sx + '%');
  });
  window.addEventListener('pointerup', () => { if (LK) LK.drag = false; });
  window.addEventListener('resize', () => { if (LK && LK.viewer) { try { LK.viewer.resize(); } catch (e) { /* closing */ } lkPlace(); } });
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && LK) { e.stopPropagation(); lkClose(false); } }, true);
})();

// ---- Send to tanod (Bellinist phase 5b): the street view goes with the one who is going ----
const ME = <?= json_encode($admin['id'] ?? null) ?>;
const DUTY_ORDER = { on_duty: 0, break: 1, lunch: 1, offline: 2 };
const dutyLabel = d => ({ on_duty: T('On duty', 'Naka-duty'), break: T('On break', 'Nagpapahinga'), lunch: T('At lunch', 'Kumakain'), offline: T('Offline', 'Offline') }[d] || d);
function lkSpot() {
  if (!LK || !LK.img) return null;
  return { m: Math.round(lkMetres(LK.img, LK.here)), dir: lkDir(lkBearing(LK.img, LK.here)) };
}
async function lkSendOpen() {
  const el = document.getElementById('lk-send'); if (!el || !LK) return;
  el.classList.add('open');
  el.innerHTML = '<div class="sd-h"><b>' + T('Send to tanod', 'Ipadala sa tanod') + '</b><button type="button" class="sd-x" data-lksendx aria-label="' + T('Close', 'Isara') + '">&times;</button></div><p class="sd-l">' + T('Loading the tanod…', 'Kinukuha ang mga tanod…') + '</p>';
  const { data, error } = await sb.from('users').select('id,full_name,duty_status').eq('role', 'tanod').not('duty_status', 'is', null);
  if (!LK) return;
  if (error || !data) { el.innerHTML = '<div class="sd-h"><b>' + T('Send to tanod', 'Ipadala sa tanod') + '</b><button type="button" class="sd-x" data-lksendx>&times;</button></div><p class="sd-l">' + T('The tanod could not be loaded.', 'Hindi ma-load ang mga tanod.') + '</p>'; return; }
  const list = data.slice().sort((a, b) => (DUTY_ORDER[a.duty_status] ?? 3) - (DUTY_ORDER[b.duty_status] ?? 3) || String(a.full_name).localeCompare(String(b.full_name)));
  const r = LK.r, sp = lkSpot(), street = r.location_label || T('the spot', 'lugar');
  const where = !sp ? '' : sp.m < 3 ? T(' The street view was taken right at the spot.', ' Kinuha ang street view mismo sa lugar.') : T(' From where the street view was taken, the spot is about ' + sp.m + ' m ' + sp.dir + '.', ' Mula sa kinuhanan ng street view, ang lugar ay mga ' + sp.m + ' m sa ' + sp.dir + '.');
  const first = list.findIndex(t => t.duty_status === 'on_duty');
  el.innerHTML = '<div class="sd-h"><b>' + T('Send to tanod', 'Ipadala sa tanod') + '</b><button type="button" class="sd-x" data-lksendx aria-label="' + T('Close', 'Isara') + '">&times;</button></div>' +
    '<p class="sd-l">' + T('Who is going', 'Sino ang pupunta') + '</p><div class="sd-list">' + (list.length ? list.map((t, i) =>
      '<label class="sd-t d-' + esc(t.duty_status) + '"><input type="radio" name="lkt" value="' + esc(t.id) + '"' + (i === Math.max(0, first) ? ' checked' : '') + '><span class="av">' + esc(String(t.full_name || '?').split(/[ ,]+/).filter(Boolean).slice(0, 2).map(w => w[0]).join('').toUpperCase()) + '</span>' +
      '<span><b>' + esc(String(t.full_name || '').trim()) + '</b><small>' + esc(dutyLabel(t.duty_status)) + '</small></span></label>').join('') : '<p class="sd-l">' + T('No tanod accounts yet.', 'Wala pang tanod.') + '</p>') + '</div>' +
    '<p class="sd-l">' + T('Include', 'Isama') + '</p>' +
    '<label class="sd-c"><input type="checkbox" id="sd-street" checked><span>' + T('The street view of the spot', 'Ang street view ng lugar') + '</span></label>' +
    '<label class="sd-c"><input type="checkbox" id="sd-photos" checked' + (LK.photos.length ? '' : ' disabled') + '><span>' + (LK.photos.length ? T('The resident’s photos (' + LK.photos.length + ')', 'Ang mga larawan ng residente (' + LK.photos.length + ')') : T('No resident photos to include', 'Walang larawan ng residente')) + '</span></label>' +
    '<textarea id="sd-msg" rows="4" maxlength="600">' + esc(T('Please check ' + r.tracking_id + ' near ' + street + '.' + where, 'Pakisuri ang ' + r.tracking_id + ' malapit sa ' + street + '.' + where)) + '</textarea>' +
    '<button type="button" class="p-btn p-btn-primary sd-go" data-lksendgo' + (list.length ? '' : ' disabled') + '>' + T('Send', 'Ipadala') + '</button>';
}
async function lkSendGo(btn) {
  const el = document.getElementById('lk-send'), pick = el.querySelector('input[name=lkt]:checked'), msg = el.querySelector('#sd-msg').value.trim();
  if (!pick || !msg || !LK) return;
  btn.disabled = true; btn.textContent = T('Sending…', 'Ipinapadala…');
  const street = el.querySelector('#sd-street').checked && LK.img, sp = lkSpot(), name = pick.closest('label').querySelector('b').textContent, r = LK.r;
  const { error } = await sb.from('look_shares').insert({
    report_id: r.id, tanod_id: pick.value, sent_by: ME, message: msg,
    mapillary_image_id: street ? LK.img.id : null, image_captured_at: street ? new Date(LK.img.at).toISOString() : null,
    spot_dir: street && sp ? sp.dir : null, spot_metres: street && sp ? Math.min(1000, sp.m) : null,
    include_photos: !!(el.querySelector('#sd-photos').checked && LK.photos.length),
  });
  if (error) { btn.disabled = false; btn.textContent = T('Send', 'Ipadala'); if (window.pToast) pToast(T('Could not send: ', 'Hindi naipadala: ') + error.message); return; }
  // The tanod's notifications list is what their phone shows first.
  await sb.from('notifications').insert({ user_id: pick.value, report_id: r.id, kind: 'look_around', message: T('From the barangay: ', 'Mula sa barangay: ') + msg }).then(() => {}, () => {});
  el.innerHTML = '<div class="sd-h"><b>' + T('Sent', 'Naipadala') + '</b><button type="button" class="sd-x" data-lksendx aria-label="' + T('Close', 'Isara') + '">&times;</button></div>' +
    '<p class="sd-ok"><span class="tick"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5 9-10"/></svg></span>' + T('Sent to ', 'Naipadala kay ') + '<b>' + esc(name) + '</b></p>' +
    '<p class="sd-l">' + T('They will see it in their notifications and on the case.', 'Makikita nila ito sa notifications at sa kaso.') + '</p>';
  if (window.pToast) pToast(T('Sent to ', 'Naipadala kay ') + name);
}

// ---- Zoom here: the camera flies in and a box unfolds out of the pin ----
// (Bellinist, 9 Oct 2026.) The case card tucks away, the box shows the
// resident's photos and the quick facts, and its button carries the admin on
// to the case in Case Reports.
let qvFor = null, qvPlace = null;
function qvClose(silent) {
  const box = document.getElementById('ss-qv');
  qvFor = null;
  if (qvPlace) { map.off('move', qvPlace); qvPlace = null; }
  document.getElementById('case-sheet').classList.remove('cs-tuck');
  if (!box) return;
  if (silent) { box.remove(); return; }
  box.classList.remove('in'); box.classList.add('out');
  setTimeout(() => box.remove(), 280);
}
function qvOpen(r) {
  qvClose(true);
  const sec = document.getElementById('s-spatial'), sheet = document.getElementById('case-sheet');
  const lng = +r.longitude, lat = +r.latitude, col = catColour(r.category);
  qvFor = r.id; sheet.classList.add('cs-tuck');
  map.easeTo({ center: [lng, lat], zoom: 18, padding: { left: 0, top: 0, right: 0, bottom: 0 }, offset: [-190, 40], duration: 950,
               easing: t => 1 - Math.pow(1 - t, 3) });
  const nearby = all.filter(q => q.id !== r.id && Math.hypot((q.longitude - lng) * 107500, (q.latitude - lat) * 110600) < 150).length;
  const rejected = r.status === 'rejected' || r.status === 'cancelled';
  const late = r.due_at && new Date(r.due_at).getTime() < Date.now() && !rejected && !CS_DONE.includes(r.status);
  const glyph = (PIN_GLYPH[r.category] || PIN_GLYPH.other).replace(/__C__/g, '#fff');
  const box = document.createElement('div');
  box.id = 'ss-qv'; box.className = 'ss-qv'; box.setAttribute('role', 'dialog'); box.setAttribute('aria-label', esc(r.subject || ''));
  box.style.setProperty('--cs', col);
  box.innerHTML = '<span class="qv-tail"></span>' +
    '<div class="qv-h"><span class="qv-ic"><svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + glyph + '</svg></span>' +
      '<div class="qv-t"><b>' + esc(r.subject || label(r.category)) + '</b><span>' + esc(r.tracking_id) + ' · ' + esc(label(r.category)) + '</span></div>' +
      '<button type="button" class="qv-x" data-qvx aria-label="' + T('Close', 'Isara') + '">&times;</button></div>' +
    '<div class="qv-body">' +
      '<div class="qv-st"><span class="cs-st" style="--st:' + (COLOUR[r.status] || '#9aa1ab') + '">' + esc(label(r.status)) + '</span>' + (late ? '<span class="qv-late">' + T('Overdue', 'Lampas na') + '</span>' : '') + '</div>' +
      '<div class="qv-media" id="qv-media"><i class="qv-ph none"><svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + glyph + '</svg></i></div>' +
      '<div class="qv-cap" id="qv-cap">' + T('Looking for the resident’s photos…', 'Hinahanap ang mga larawan ng residente…') + '</div>' +
      '<div class="qv-q" id="qv-q" hidden></div>' +
      '<div class="qv-facts"><div><small>' + T('Filed', 'Naisampa') + '</small><b>' + esc(fmtDate(r.created_at) || '—') + '</b></div>' +
        '<div><small>' + T('Tanod', 'Tanod') + '</small><b id="qv-tanod">…</b></div>' +
        '<div><small>' + T('Where', 'Saan') + '</small><b>' + esc(r.location_label || T('Pinned location', 'Naka-pin')) + '</b></div>' +
        '<div><small>' + T('Nearby', 'Malapit') + '</small><b>' + nearby + T(' within 150 m', ' sa loob ng 150 m') + '</b></div></div>' +
      '<div class="qv-act"><button type="button" class="p-btn p-btn-primary" data-qvgo>' + T('Open in Case Reports', 'Buksan sa Case Reports') +
        ' <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" width="16" height="16" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"/></svg></button>' +
        (MLY ? '<button type="button" class="qv-look" data-qvlook title="' + T('Look around', 'Luminga-linga') + '"><span class="ql-in"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + SD_ICONS.view360 + '</svg><b>360°</b><small>' + T('Look around', 'Luminga') + '</small></span></button>' : '') +
        '<button type="button" class="p-btn" data-qvback>' + T('Back', 'Bumalik') + '</button></div></div>';
  sec.appendChild(box);
  const place = () => {
    if (qvFor !== r.id) return;
    const p = map.project([lng, lat]), c = map.getContainer().getBoundingClientRect(), s = sec.getBoundingClientRect();
    const ax = p.x + (c.left - s.left), ay = p.y + (c.top - s.top) - 40, bw = box.offsetWidth, bh = box.offsetHeight;
    const right = ax + 44 + bw < s.width - 16, left = right ? ax + 44 : ax - 44 - bw, top = Math.max(14, Math.min(s.height - bh - 24, ay - 120));
    box.style.left = left + 'px'; box.style.top = top + 'px'; box.classList.toggle('flip', !right);
    box.style.setProperty('--ox', (ax - left) + 'px'); box.style.setProperty('--oy', (ay - top) + 'px');
    box.style.setProperty('--ty', Math.max(24, Math.min(bh - 24, ay - top)) + 'px');
  };
  qvPlace = place; map.on('move', place);
  setTimeout(() => { if (qvFor !== r.id) return; place(); void box.offsetWidth; box.classList.add('in'); }, 900);
  box.querySelector('[data-qvx]').addEventListener('click', () => qvBack(r));
  box.querySelector('[data-qvback]').addEventListener('click', () => qvBack(r));
  const qvl = box.querySelector('[data-qvlook]'); if (qvl) qvl.addEventListener('click', () => lkOpen(r));
  box.querySelector('[data-qvgo]').addEventListener('click', () => {
    const nav = document.querySelector('.p-nav a[href="cases.php"]');
    if (nav) { nav.classList.remove('ss-navglow'); void nav.offsetWidth; nav.classList.add('ss-navglow'); }
    box.classList.add('go');
    setTimeout(() => { location.href = 'case.php?id=' + encodeURIComponent(r.id); }, 650);
  });
  // The photos, the resident's own words and the tanod, as they arrive.
  sb.from('report_media').select('media_url').eq('report_id', r.id).limit(3).then(({ data }) => {
    if (qvFor !== r.id) return; const m = document.getElementById('qv-media'), cap = document.getElementById('qv-cap'); if (!m) return;
    if (!data || !data.length) { cap.textContent = T('No photos attached', 'Walang kalakip na larawan'); return; }
    m.innerHTML = '';
    data.forEach(d => { const a = document.createElement('a'), img = new Image(); a.className = 'qv-ph'; a.href = d.media_url; a.target = '_blank'; a.rel = 'noopener';
      img.alt = ''; img.referrerPolicy = 'no-referrer'; img.src = d.media_url; a.appendChild(img); m.appendChild(a); });
    m.dataset.n = data.length; cap.textContent = T('Photos from the resident · ', 'Mga larawan mula sa residente · ') + data.length;
  });
  sb.from('reports').select('description').eq('id', r.id).limit(1).then(({ data }) => {
    if (qvFor !== r.id || !data || !data[0] || !data[0].description) return; const q = document.getElementById('qv-q'); if (!q) return;
    q.textContent = '“' + String(data[0].description).slice(0, 220) + (data[0].description.length > 220 ? '…' : '') + '”'; q.hidden = false;
  });
  sb.from('dispatches').select('tanod:users!dispatches_tanod_id_fkey(full_name)').eq('report_id', r.id).order('assigned_at', { ascending: false }).limit(1).then(({ data }) => {
    if (qvFor !== r.id) return; const b = document.getElementById('qv-tanod'); if (!b) return;
    b.textContent = data && data[0] && data[0].tanod ? String(data[0].tanod.full_name || '').trim() : T('Not yet', 'Wala pa');
  });
}
function qvBack(r) {
  qvClose(false);
  map.easeTo({ center: [+r.longitude, +r.latitude], zoom: 17, padding: csPad(), duration: 600 });
}
document.addEventListener('keydown', e => { if (e.key === 'Escape' && qvFor) { const r = byId.get(qvFor); if (r) qvBack(r); else qvClose(true); } });

// Drag the panel by its header; it stays inside the map and remembers where
// it was put for the rest of the visit.
let csPos = null;
function csDraggable(el) {
  if (csPos) { el.style.left = csPos[0] + 'px'; el.style.top = csPos[1] + 'px'; el.style.bottom = 'auto'; el.style.height = csPos[2] + 'px'; }
  const hero = el.querySelector('.cs-hero');
  let down = null;
  hero.addEventListener('pointerdown', e => { down = [e.clientX, e.clientY]; }, true);
  hero.addEventListener('click', e => {
    if (e.target.closest('button') || !hero.classList.contains('has-photo')) return;
    if (down && Math.hypot(e.clientX - down[0], e.clientY - down[1]) > 5) return;   // that was a drag
    let urls = []; try { urls = JSON.parse(hero.dataset.urls || '[]'); } catch (x) { /* none */ }
    lbShow(urls, 0);
  });
  hero.addEventListener('pointerdown', e => {
    if (e.target.closest('button')) return;
    const box = document.getElementById('s-spatial').getBoundingClientRect(), r = el.getBoundingClientRect();
    const dx = e.clientX - r.left, dy = e.clientY - r.top, h = r.height;
    el.classList.add('cs-dragging'); hero.setPointerCapture(e.pointerId);
    const move = ev => {
      const x = Math.max(8, Math.min(box.width - r.width - 8, ev.clientX - box.left - dx));
      const y = Math.max(8, Math.min(box.height - h - 8, ev.clientY - box.top - dy));
      el.style.left = x + 'px'; el.style.top = y + 'px'; el.style.bottom = 'auto'; el.style.height = h + 'px';
      csPos = [x, y, h];
    };
    const up = () => { el.classList.remove('cs-dragging'); hero.removeEventListener('pointermove', move); hero.removeEventListener('pointerup', up); };
    hero.addEventListener('pointermove', move); hero.addEventListener('pointerup', up);
  });
}
function closeCaseSheet() {
  csFor = null; qvClose(true); lkClose(true);
  document.getElementById('case-sheet').hidden = true;
  document.getElementById('s-spatial').classList.remove('sheet-open');
  map.easeTo({ padding: { left: 0, top: 0, right: 0, bottom: 0 }, duration: 500 });
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
const mapShell  = document.getElementById('s-spatial');
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
  expandBtn.classList.toggle('p-on', active);
  expandBtn.title = active ? T('Exit full screen', 'Lumabas sa full screen') : T('Expand map to full screen', 'I-full screen ang mapa');
  setTimeout(() => map.resize(), 120);
});

// Collapsed by default: the map is the screen, the list is a drawer.
const toggle = document.getElementById('incident-toggle');
const side   = document.getElementById('map-side');
toggle.addEventListener('click', () => {
  const open = side.hasAttribute('hidden');
  if (open) mapDrawer('incidents');
  open ? side.removeAttribute('hidden') : side.setAttribute('hidden', '');
  if (open) placeSide();
  toggle.setAttribute('aria-expanded', String(open));
});

// The incidents list opens below the filter box wherever the two would
// overlap (narrower windows), never on top of it.
function placeSide() {
  if (innerWidth <= 980) { side.style.top = ''; side.style.maxHeight = ''; return; }
  const shell = document.getElementById('s-spatial').getBoundingClientRect();
  const sr = document.getElementById('map-search').getBoundingClientRect(), lr = side.getBoundingClientRect();
  const top = lr.left < sr.right + 8 ? Math.max(84, sr.bottom - shell.top + 12) : 84;
  side.style.top = top + 'px'; side.style.maxHeight = 'calc(100% - ' + (top + 16) + 'px)';
}
addEventListener('resize', () => { if (!side.hasAttribute('hidden')) placeSide(); });

// The legend, the incidents list and the flood watch card share the right
// side of the map, so opening one closes the others.
function mapDrawer(which) {
  if (which !== 'sheet' && csFor) closeCaseSheet();
  if (which !== 'layers') { const lc = document.getElementById('ss-lyr'); if (lc && !lc.hidden) { lc.hidden = true; document.getElementById('layers-btn').setAttribute('aria-expanded', 'false'); } }
  if (which !== 'incidents') { side.setAttribute('hidden', ''); toggle.setAttribute('aria-expanded', 'false'); }
  if (which !== 'legend') { document.getElementById('map-legend').hidden = true; document.getElementById('legend-toggle').setAttribute('aria-expanded', 'false'); }
  if (which !== 'flood') { document.getElementById('fw-card').hidden = true; document.getElementById('fw-chip').setAttribute('aria-expanded', 'false'); }
}
document.getElementById('legend-toggle').addEventListener('click', () => {
  const lg = document.getElementById('map-legend'), open = lg.hidden;
  if (open) mapDrawer('legend');
  lg.hidden = !open;
  document.getElementById('legend-toggle').setAttribute('aria-expanded', String(open));
});
document.getElementById('fw-chip').addEventListener('click', () => {
  const c = document.getElementById('fw-card'), open = c.hidden;
  if (open) mapDrawer('flood');
  c.hidden = !open;
  document.getElementById('fw-chip').setAttribute('aria-expanded', String(open));
});

// ---- Map layers (Bellinist phase 4, 9 Oct 2026) -------------------------
// Air quality (Open-Meteo), safe points and public transport (OpenStreetMap,
// through layers.php, cached). Each is its own tile in the Layers card; what
// is on says what it is saying in a small card under the filter card.
const LAYER = { aq: false, transit: false, safe: false };
const LAYER_DATA = { aq: null, transit: null, safe: null }, LAYER_ERR = {};
let layerQ = Promise.resolve();
const ROUTE_COLOURS = ['#FF8A3D', '#2F6BFF', '#1E9E56', '#E0609A', '#8E3FD6', '#0F9D9A', '#E5383B', '#F9AB00'];
const SAFE_KINDS = {
  evac:      { c: '#1E9E56', en: 'Evacuation or shelter', fil: 'Evacuation o silungan', g: SD_ICONS.evac },
  hydrant:   { c: '#E5383B', en: 'Fire hydrant',          fil: 'Fire hydrant',          g: '<path d="M12 3c2 3 5 5.5 5 9a5 5 0 0 1-10 0c0-3.5 3-6 5-9z"/>' },
  health:    { c: '#2F6BFF', en: 'Health facility',       fil: 'Pasilidad pangkalusugan', g: '<path d="M12 5v14M5 12h14"/>' },
  responder: { c: '#FF8A3D', en: 'Fire or police',        fil: 'Bumbero o pulis',       g: '<path d="M12 3l2.6 5.6 6 .8-4.4 4.2 1.1 6-5.3-2.9-5.3 2.9 1.1-6L3.4 9.4l6-.8z"/>' },
  hall:      { c: '#00308F', en: 'Barangay or city hall', fil: 'Barangay o city hall',  g: '<path d="M12 3L5 6v6c0 4.5 3 7.5 7 9 4-1.5 7-4.5 7-9V6z"/>' },
};
const AQ_BANDS = [[50, 'Good', 'Mabuti', '#34C759'], [100, 'Moderate', 'Katamtaman', '#F9C74F'], [150, 'Unhealthy for sensitive groups', 'Hindi mabuti sa sensitibo', '#FF8A3D'],
                  [200, 'Unhealthy', 'Hindi mabuti', '#E5383B'], [300, 'Very unhealthy', 'Napakasama', '#8E3FD6'], [1e9, 'Hazardous', 'Mapanganib', '#7E0023']];
const aqBand = v => AQ_BANDS.find(b => v <= b[0]);

function layerSafeImages() {
  return Promise.all(Object.entries(SAFE_KINDS).map(([k, d]) => {
    if (map.hasImage('safe-' + k)) return null;
    return addSvgImage('safe-' + k, '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="-17 -17 34 34"><rect x="-14" y="-14" width="28" height="28" rx="9" fill="' + d.c + '" stroke="#fff" stroke-width="2.6"/>' +
      '<g transform="translate(-9 -9) scale(.75)" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">' + d.g + '</g></svg>');
  }));
}
function layerBox() { const [[w, s], [e, n]] = AREA; return [w, s, e, n].map(v => v.toFixed(3)).join(','); }
async function layerLoad(k) {
  if (LAYER_DATA[k]) return LAYER_DATA[k];
  delete LAYER_ERR[k];
  try {
    if (k === 'aq') {
      const r = await fetch('https://air-quality-api.open-meteo.com/v1/air-quality?latitude=' + RESIDENTIAL_CENTRE[1] + '&longitude=' + RESIDENTIAL_CENTRE[0] +
        '&current=us_aqi,pm2_5,pm10,nitrogen_dioxide,ozone&timezone=Asia%2FManila');
      if (!r.ok) throw new Error(r.status);
      const c = (await r.json()).current; if (!c || c.us_aqi == null) throw new Error('empty');
      return (LAYER_DATA.aq = { v: Math.round(c.us_aqi), pm25: c.pm2_5, pm10: c.pm10, no2: c.nitrogen_dioxide, o3: c.ozone, time: c.time });
    }
    // One at a time: the public OpenStreetMap servers do not like two at once.
    const run = layerQ.then(async () => { const r = await fetch('layers.php?k=' + k + '&b=' + layerBox(), { credentials: 'same-origin' });
      if (!r.ok) throw new Error(r.status); return r.json(); });
    layerQ = run.catch(() => {});
    return (LAYER_DATA[k] = await run);
  } catch (e) { LAYER_ERR[k] = true; return null; }
}
function layerShape() {
  // The barangay's own outline when it has loaded; otherwise the map's area.
  const polys = rings && rings.length ? rings.map(r => [r]) : [[[[AREA[0][0], AREA[0][1]], [AREA[1][0], AREA[0][1]], [AREA[1][0], AREA[1][1]], [AREA[0][0], AREA[1][1]], [AREA[0][0], AREA[0][1]]]]];
  return { type: 'Feature', properties: {}, geometry: { type: 'MultiPolygon', coordinates: polys } };
}
function layerBefore() { return map.getLayer('clusters') ? 'clusters' : undefined; }
async function layerDraw(k) {
  await mapReady;
  const vis = LAYER[k] ? 'visible' : 'none', dark = isDark();
  if (k === 'aq') {
    if (LAYER.aq && !map.getSource('aq')) {
      const d = await layerLoad('aq'); if (!d) return;
      map.addSource('aq', { type: 'geojson', data: layerShape() });
      map.addLayer({ id: 'aq-fill', type: 'fill', source: 'aq', paint: { 'fill-color': aqBand(d.v)[3], 'fill-opacity': dark ? .2 : .26 } }, 'outline');
    }
    if (map.getLayer('aq-fill')) { map.setLayoutProperty('aq-fill', 'visibility', vis); if (LAYER_DATA.aq) map.setPaintProperty('aq-fill', 'fill-color', aqBand(LAYER_DATA.aq.v)[3]); map.setPaintProperty('aq-fill', 'fill-opacity', dark ? .2 : .26); }
  } else if (k === 'transit') {
    if (LAYER.transit && !map.getSource('transit')) {
      const d = await layerLoad('transit'); if (!d) return;
      const refs = [...new Set(d.features.filter(f => f.properties.k === 'route').map(f => f.properties.ref || f.properties.name))];
      d.features.forEach(f => { if (f.properties.k === 'route') f.properties.c = ROUTE_COLOURS[refs.indexOf(f.properties.ref || f.properties.name) % ROUTE_COLOURS.length]; });
      map.addSource('transit', { type: 'geojson', data: d });
      map.addLayer({ id: 'transit-glow', type: 'line', source: 'transit', filter: ['==', ['get', 'k'], 'route'], layout: { 'line-cap': 'round' },
                     paint: { 'line-color': ['get', 'c'], 'line-width': 12, 'line-blur': 8, 'line-opacity': 0 } }, layerBefore());
      map.addLayer({ id: 'transit-case', type: 'line', source: 'transit', filter: ['==', ['get', 'k'], 'route'], layout: { 'line-cap': 'round', 'line-join': 'round' },
                     paint: { 'line-color': '#fff', 'line-width': ['interpolate', ['linear'], ['zoom'], 15, 6, 18, 11], 'line-opacity': .9 } }, layerBefore());
      map.addLayer({ id: 'transit-line', type: 'line', source: 'transit', filter: ['==', ['get', 'k'], 'route'], layout: { 'line-cap': 'round', 'line-join': 'round' },
                     paint: { 'line-color': ['get', 'c'], 'line-width': ['interpolate', ['linear'], ['zoom'], 15, 3.4, 18, 7] } }, layerBefore());
      map.addLayer({ id: 'transit-stops', type: 'circle', source: 'transit', filter: ['==', ['get', 'k'], 'stop'],
                     paint: { 'circle-radius': ['interpolate', ['linear'], ['zoom'], 15, 3.5, 18, 6.5], 'circle-color': '#fff', 'circle-stroke-color': '#00308F', 'circle-stroke-width': 2.4 } }, layerBefore());
    }
    ['transit-glow', 'transit-case', 'transit-line', 'transit-stops'].forEach(id => { if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', vis); });
    if (map.getLayer('transit-glow')) map.setPaintProperty('transit-glow', 'line-opacity', dark ? .75 : 0);
  } else if (k === 'safe') {
    if (LAYER.safe && !map.getSource('safe')) {
      const d = await layerLoad('safe'); if (!d) return;
      await layerSafeImages();
      d.features.forEach(f => { f.properties.icon = 'safe-' + f.properties.k; });
      map.addSource('safe', { type: 'geojson', data: d });
      map.addLayer({ id: 'safe', type: 'symbol', source: 'safe', layout: { 'icon-image': ['get', 'icon'], 'icon-allow-overlap': true, 'icon-ignore-placement': true,
        'icon-size': ['interpolate', ['linear'], ['zoom'], 15, .5, 18, .8] } }, layerBefore());
      map.on('mouseenter', 'safe', () => { map.getCanvas().style.cursor = 'pointer'; });
      map.on('mouseleave', 'safe', () => { map.getCanvas().style.cursor = ''; });
      map.on('click', 'safe', e => safeSheet(e.features[0]));
    }
    if (map.getLayer('safe')) map.setLayoutProperty('safe', 'visibility', vis);
  }
}
// A safe point, opened in the same left panel the complaints use: its
// service's colour, photos of the exact place (found on the net: the
// photo OpenStreetMap links, Wikimedia Commons files taken within 120 m,
// then Mapillary street imagery), address, coordinates, and what
// OpenStreetMap or the barangay's own settings know of it.
const HALL = <?= json_encode(['phone' => env('BARANGAY_HALL_PHONE', ''), 'hours' => env('BARANGAY_HALL_HOURS', '')]) ?>;
let spFor = null;
function spClose() {
  spFor = null;
  const el = document.getElementById('safe-sheet');
  if (el && !el.hidden) { el.hidden = true; document.getElementById('s-spatial').classList.remove('sheet-open'); map.easeTo({ padding: { left: 0, top: 0, right: 0, bottom: 0 }, duration: 500 }); }
}
const spStrip = h => String(h || '').replace(/<[^>]*>/g, '').slice(0, 40);
async function spPhotos(p, lng, lat) {
  const out = [], seen = new Set(), add = (url, credit, page) => { if (url && !seen.has(url) && out.length < 6) { seen.add(url); out.push({ url, credit, page }); } };
  const commons = (j, limitJpeg) => Object.values((j.query || {}).pages || {}).forEach(pg => {
    const ii = (pg.imageinfo || [])[0]; if (!ii || (limitJpeg && !/^image\/jpe?g$/.test(ii.mime || ''))) return;
    const m = ii.extmetadata || {};
    add(ii.thumburl, (m.Artist ? spStrip(m.Artist.value) + ' · ' : '') + ((m.LicenseShortName || {}).value || 'Wikimedia Commons'), ii.descriptionurl);
  });
  // 1. The photo the place's own OpenStreetMap entry points at.
  if (/^File:/i.test(p.commons || '')) {
    try { commons(await (await fetch('https://commons.wikimedia.org/w/api.php?' + new URLSearchParams({ action: 'query', titles: p.commons, prop: 'imageinfo', iiprop: 'url|extmetadata|mime', iiurlwidth: '720', format: 'json', origin: '*' }))).json(), false); } catch (e) { /* the next source */ }
  }
  // 2. Wikimedia Commons: files geotagged within 120 m of the place.
  try {
    commons(await (await fetch('https://commons.wikimedia.org/w/api.php?' + new URLSearchParams({ action: 'query', generator: 'geosearch', ggscoord: lat + '|' + lng, ggsradius: '120', ggsnamespace: '6', ggslimit: '8',
      prop: 'imageinfo', iiprop: 'url|extmetadata|mime', iiurlwidth: '720', format: 'json', origin: '*' }))).json(), true);
  } catch (e) { /* the next source */ }
  // 3. Mapillary: the nearest street imagery of the place.
  if (typeof MLY !== 'undefined' && MLY) {
    try {
      const j = await (await fetch('https://graph.mapillary.com/images?' + new URLSearchParams({ access_token: MLY, limit: '300',
        bbox: [lng - 0.0004, lat - 0.00035, lng + 0.0004, lat + 0.00035].join(','), fields: 'id,thumb_1024_url,computed_geometry,captured_at,is_pano' }))).json();
      ((j && j.data) || []).map(i => { const c = i.computed_geometry && i.computed_geometry.coordinates; return c && i.thumb_1024_url ? { i, d: lkMetres({ lng, lat }, { lng: c[0], lat: c[1] }) - (Date.now() - i.captured_at) / 3.156e10 * 3 + (i.is_pano ? 40 : 0) } : null; })
        .filter(Boolean).sort((a, b) => a.d - b.d).slice(0, 3).forEach(x => add(x.i.thumb_1024_url, 'Mapillary contributors · CC BY-SA', 'https://www.mapillary.com/app/?pKey=' + x.i.id));
    } catch (e) { /* none */ }
  }
  return out;
}
function safeSheet(f) {
  const p = f.properties, kd = SAFE_KINDS[p.k]; if (!kd) return;
  const [lng, lat] = f.geometry.coordinates, coord = lat.toFixed(5) + ', ' + lng.toFixed(5), key = coord;
  if (p.k === 'hall' && /183/.test(p.name || '')) { p.phone = p.phone || HALL.phone; p.hours = p.hours || HALL.hours; }
  closeCaseSheet(); spFor = key;
  const el = document.getElementById('safe-sheet'), g = kd.g || '';
  const row = (ic, v) => v ? '<li>' + csIcon(ic) + '<span>' + v + '</span></li>' : '';
  const dir = 'https://www.google.com/maps/dir/?api=1&destination=' + lat + ',' + lng + '&travelmode=walking';
  el.style.setProperty('--cs', kd.c);
  el.innerHTML =
    '<div class="cs-hero sp-hero" id="sp-hero"><button class="cs-x" type="button" aria-label="' + T('Close', 'Isara') + '">&times;</button><span class="cs-cat">' + esc(T(kd.en, kd.fil)) + '</span>' +
      '<svg class="cs-mark cs-glyph" viewBox="0 0 24 24" aria-hidden="true">' + g + '</svg><span class="sp-credit" id="sp-credit" hidden></span></div>' +
    '<div class="cs-body"><h2 class="cs-title">' + esc(p.name || T(kd.en, kd.fil)) + '</h2>' +
      '<p class="cs-meta"><span class="cs-st" style="--st:' + kd.c + '">' + esc(T(kd.en, kd.fil)) + '</span></p>' +
      '<div class="cs-acts"><a class="ac-send" target="_blank" rel="noopener" href="' + dir + '"><span>' + ACT_SCENE.send + csIcon(SD_ICONS.directions) + '</span>' + T('Directions', 'Direksyon') + '</a>' +
        '<button type="button" class="ac-zoom" data-spzoom><span>' + ACT_SCENE.zoom + csIcon(SD_ICONS.zoom) + '</span>' + T('Zoom here', 'Lapitan') + '</button>' +
        '<button type="button" class="ac-copy" data-spcopy><span>' + ACT_SCENE.copy + csIcon(SD_ICONS.copy) + '</span>' + T('Copy coords', 'Kopyahin') + '</button></div>' +
      '<ul class="cs-rows">' +
        row(SD_ICONS.pin, esc(p.addr || 'Barangay 183, Pasay City') + '<small>' + coord + '</small>') +
        row(SD_ICONS.phone, esc(p.phone)) +
        row(SD_ICONS.clock, esc(p.hours)) +
        row(SD_ICONS.users, p.cap ? esc(p.cap) + T(' people', ' tao') + '<small>' + T('Capacity', 'Kapasidad') + '</small>' : '') +
        row(SD_ICONS.hall, p.op ? esc(p.op) + '<small>' + T('Operator', 'Nangangasiwa') + '</small>' : '') +
        row(SD_ICONS.link, p.web ? '<a href="' + esc(p.web) + '" target="_blank" rel="noopener">' + esc(p.web.replace(/^https?:\/\/(www\.)?/, '').slice(0, 38)) + '</a>' : '') +
      '</ul>' +
      '<h3 class="cs-h">' + T('Photos', 'Mga larawan') + '</h3><div class="sp-strip" id="sp-strip"><span class="sp-load">' + T('Looking for photos of this place…', 'Naghahanap ng larawan ng lugar…') + '</span></div>' +
      '<small class="sp-src">' + T('From OpenStreetMap, Wikimedia Commons and Mapillary. Photos found near the place, not always of the building itself.', 'Mula sa OpenStreetMap, Wikimedia Commons at Mapillary. Mga larawang malapit sa lugar, hindi laging ng mismong gusali.') + '</small></div>' +
    '<div class="cs-foot"><a class="p-btn p-btn-primary" style="background:' + kd.c + ';border-color:' + kd.c + '" target="_blank" rel="noopener" href="' + dir + '">' + T('Directions', 'Direksyon') + '</a></div>';
  el.hidden = false; el.querySelector('.cs-body').scrollTop = 0;
  document.getElementById('s-spatial').classList.add('sheet-open');
  if (typeof mapDrawer === 'function') mapDrawer('sheet');
  map.easeTo({ center: [lng, lat], zoom: Math.max(map.getZoom(), 17.4), padding: csPad(), duration: 800 });
  el.querySelector('.cs-x').addEventListener('click', spClose);
  const press = (btn, ms, then) => btn.addEventListener('click', () => { if (btn.classList.contains('go')) return; btn.classList.add('go'); setTimeout(() => btn.classList.remove('go'), ms + 120); setTimeout(then, (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) ? 0 : ms); });
  press(el.querySelector('[data-spzoom]'), 420, () => map.easeTo({ center: [lng, lat], zoom: 18, padding: csPad() }));
  const spc = el.querySelector('[data-spcopy]'); press(spc, 0, () => {
    try { navigator.clipboard.writeText(coord); } catch (x) { /* blocked */ } if (window.pToast) pToast(T('Copied ', 'Nakopya ') + coord);
    const sp = spc.querySelector('span'), lb = spc.lastChild, was = [sp.innerHTML, lb.textContent];
    sp.innerHTML = csIcon('<path d="M5 12.5l5 5 9-10"/>'); lb.textContent = T('Copied', 'Nakopya'); spc.classList.add('done');
    setTimeout(() => { sp.innerHTML = was[0]; lb.textContent = was[1]; spc.classList.remove('done'); }, 1500);
  });
  spPhotos(p, lng, lat).then(list => {
    if (spFor !== key) return; const strip = document.getElementById('sp-strip'), hero = document.getElementById('sp-hero'); if (!strip) return;
    if (!list.length) { strip.innerHTML = '<span class="sp-load">' + T('No photos of this place found yet.', 'Wala pang nakitang larawan ng lugar.') + '</span>'; return; }
    const show = i => {
      const l = list[i], img = new Image(); img.referrerPolicy = 'no-referrer';
      img.onload = () => { hero.style.backgroundImage = 'linear-gradient(180deg, transparent 50%, rgba(0,0,0,.5)), url("' + l.url.replace(/"/g, '%22') + '")'; hero.classList.add('has-bg'); };
      img.src = l.url; const c = document.getElementById('sp-credit'); c.hidden = false; c.textContent = l.credit;
      strip.querySelectorAll('a').forEach((a, k) => a.classList.toggle('on', k === i));
    };
    strip.innerHTML = list.map((l, i) => '<a href="' + esc(l.page) + '" target="_blank" rel="noopener" data-i="' + i + '" style="background-image:url(\'' + l.url.replace(/'/g, '%27') + '\')"></a>').join('');
    strip.querySelectorAll('a').forEach(a => a.addEventListener('click', ev => { ev.preventDefault(); show(Number(a.dataset.i)); }));
    show(0);
  });
}
function layerInfo() {
  const box = document.getElementById('ss-lyr-info'); if (!box) return; let h = '';
  if (LAYER.aq) {
    const d = LAYER_DATA.aq;
    h += !d ? '<div class="lyc">' + (LAYER_ERR.aq ? T('Air quality could not be read right now.', 'Hindi mabasa ang kalidad ng hangin ngayon.') : T('Reading the air…', 'Binabasa ang hangin…')) + '</div>' : (() => {
      const b = aqBand(d.v), bar = Math.min(100, d.v / 300 * 100);
      const row = (n, v, max) => '<div class="aq-r"><span>' + n + '</span><div><i style="width:' + Math.min(100, (v || 0) / max * 100).toFixed(0) + '%"></i></div><b>' + (v == null ? '–' : Math.round(v * 10) / 10) + '</b></div>';
      return '<div class="lyc aq" style="--c:' + b[3] + '"><div class="aq-h"><b>' + d.v + '</b><span><em>' + T('Air quality', 'Kalidad ng hangin') + '</em><strong>' + esc(T(b[1], b[2])) + '</strong></span></div>' +
        '<div class="aq-bar"><i style="left:' + bar + '%"></i></div>' + row('PM2.5', d.pm25, 35) + row('PM10', d.pm10, 100) + row('NO₂', d.no2, 100) + row('O₃', d.o3, 120) +
        '<small>Open-Meteo · CAMS · ' + esc(String(d.time || '').replace('T', ' ')) + '</small></div>';
    })();
  }
  if (LAYER.transit) {
    const d = LAYER_DATA.transit;
    h += !d ? '<div class="lyc">' + (LAYER_ERR.transit ? T('Transit could not be loaded from OpenStreetMap.', 'Hindi ma-load ang transit mula sa OpenStreetMap.') : T('Loading routes…', 'Nilo-load ang mga ruta…')) + '</div>' : (() => {
      const seen = new Map(); d.features.filter(f => f.properties.k === 'route').forEach(f => { const key = f.properties.ref || f.properties.name; if (!seen.has(key)) seen.set(key, f.properties); });
      const stops = d.features.filter(f => f.properties.k === 'stop').length, list = [...seen.values()];
      return '<div class="lyc tr"><b>' + T('Public transport', 'Pampublikong sasakyan') + '</b>' + (list.length ? list.slice(0, 6).map(p => '<div class="tr-r"><i style="background:' + ROUTE_COLOURS[[...seen.keys()].indexOf(p.ref || p.name) % ROUTE_COLOURS.length] + '"></i><span>' + esc(p.ref || p.name) + '</span><small>' + esc(p.mode) + '</small></div>').join('') + (list.length > 6 ? '<small>+ ' + (list.length - 6) + T(' more routes', ' pang ruta') + '</small>' : '')
        : '<small>' + T('OpenStreetMap has no routes mapped here yet.', 'Wala pang naka-map na ruta dito sa OpenStreetMap.') + '</small>') + '<small>' + stops + T(' stops · OpenStreetMap', ' hintuan · OpenStreetMap') + '</small></div>';
    })();
  }
  if (LAYER.safe) {
    const d = LAYER_DATA.safe;
    h += !d ? '<div class="lyc">' + (LAYER_ERR.safe ? T('Safe points could not be loaded from OpenStreetMap.', 'Hindi ma-load ang mga ligtas na lugar.') : T('Finding safe points…', 'Hinahanap ang mga ligtas na lugar…')) + '</div>' : (() => {
      const n = {}; d.features.forEach(f => { n[f.properties.k] = (n[f.properties.k] || 0) + 1; });
      return '<div class="lyc sf"><b>' + T('Safe points', 'Mga ligtas na lugar') + '</b>' + Object.entries(SAFE_KINDS).map(([k, kd]) => '<div class="tr-r"><i class="sq" style="background:' + kd.c + '"></i><span>' + esc(T(kd.en, kd.fil)) + '</span><small>' + (n[k] || 0) + '</small></div>').join('') + '<small>OpenStreetMap</small></div>';
    })();
  }
  box.innerHTML = h;
}
function layerSync() {
  Object.keys(LAYER).forEach(k => { const c = document.getElementById('lyr-' + k); if (c) c.checked = !!LAYER[k]; });
  const on = Object.values(LAYER).some(Boolean) || ['f-heat', 'f-flood'].some(id => { const c = document.getElementById(id); return c && c.checked; });
  document.getElementById('layers-btn').classList.toggle('on', on);
  const cnt = [...document.querySelectorAll('#lyr-list input')].filter(c => c.checked).length, nEl = document.getElementById('lyr-n'), offB = document.getElementById('lyr-off');
  if (nEl) { nEl.hidden = !cnt; nEl.textContent = cnt + T(' on', ' bukas'); } if (offB) offB.hidden = !cnt;
  layerInfo();
}
(function layerInit() {
  const sec = document.getElementById('s-spatial'), btn = document.getElementById('layers-btn'), card = document.getElementById('ss-lyr');
  // Heatmap, Flood zones and Dim outside were switches in the title card; they are layers, so
  // they live here now, with their own pictures. The other layers get pictures too.
  card.innerHTML = '<div class="lyr-list" id="lyr-list"></div>';
  const list = document.getElementById('lyr-list');
  // Like the Maps chooser: a picture tile at the map's bottom-left, and the layers open in a row beside it.
  btn.classList.add('lyr-tile'); btn.classList.remove('p-dock-btn');
  btn.innerHTML = '<span class="lt-pic" aria-hidden="true"></span><span class="lt-lbl"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + SD_ICONS.layers + '</svg>' + T('Layers', 'Layers') + '</span>';
  sec.appendChild(btn); sec.appendChild(card);
  document.querySelectorAll('.p-map-search .map-sw').forEach(l => list.appendChild(l));
  document.querySelectorAll('.p-map-search .p-row').forEach(r => { if (!r.children.length) r.remove(); });
  // Each switch's box carries its own mark: it fills in when the layer is on. Project NOAH's is an N.
  // Project NOAH is credited at the foot of the card with the other sources, not on the tile.
  list.querySelectorAll('.map-sw--noah b').forEach(b => { const em = b.querySelector('em'); if (em) b.textContent = em.textContent.replace(/\s*[·•]\s*$/, '').trim(); });
  list.querySelectorAll('.map-sw--dim b').forEach(b => { b.textContent = T('Dim outside', 'I-dim sa labas'); });
  // Flood zones draws its wave straight in the chip; the tile wants it inside its picture.
  list.querySelectorAll('.map-sw').forEach(l => { if (l.querySelector('.scene')) return; const sc = document.createElement('span'); sc.className = 'scene'; sc.setAttribute('aria-hidden', 'true'); l.querySelectorAll(':scope > svg').forEach(v => sc.appendChild(v)); l.insertBefore(sc, l.querySelector(':scope > i')); });
  const MARK = { heat: 'heat', noah: 'noah', dim: 'dim', transit: 'jeepney', air: 'wind', safe: 'safepoints' };
  list.querySelectorAll('.map-sw').forEach(l => { const m = /map-sw--(\w+)/.exec(l.className), box = l.querySelector(':scope > i'); if (!m || !box || !MARK[m[1]]) return;
    l.classList.add('has-ic'); l.querySelector('.scene').insertAdjacentHTML('beforeend', '<svg class="mk-ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + SD_ICONS[MARK[m[1]]] + '</svg>'); });
  const sw = (k, cls, label, scene) => '<label class="map-sw map-sw--' + cls + '"><input type="checkbox" id="lyr-' + k + '"><span class="scene" aria-hidden="true">' + scene + '</span><i aria-hidden="true"></i><b>' + label + '</b></label>';
  list.insertAdjacentHTML('beforeend',
    sw('transit', 'transit', T('Transit', 'Transit') + '',
      '<svg viewBox="0 0 180 36" preserveAspectRatio="none"><path class="r1" d="M-4 26 C30 8 60 30 96 16 S150 6 186 18"/><path class="r2" d="M-4 10 C34 28 70 4 110 22 S160 28 186 8"/><path class="r3" d="M20 40 C44 24 78 18 100 4"/><circle cx="52" cy="17" r="2.4"/><circle cx="108" cy="19" r="2.4"/><circle cx="150" cy="13" r="2.4"/></svg>') +
    sw('aq', 'air', T('Air quality', 'Kalidad ng hangin'), '<span></span><span></span><span></span><span></span><i></i><i></i><i></i><i></i><i></i>') +
    sw('safe', 'safe', T('Safe points', 'Ligtas na lugar'), '<span></span><span></span><span></span><svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + SD_ICONS.safepoints + '</svg>'));
  list.querySelectorAll('.map-sw:not(.has-ic)').forEach(l => { const m = /map-sw--(\w+)/.exec(l.className), box = l.querySelector(':scope > i'); if (!m || !box || !MARK[m[1]]) return;
    l.classList.add('has-ic'); l.querySelector('.scene').insertAdjacentHTML('beforeend', '<svg class="mk-ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + SD_ICONS[MARK[m[1]]] + '</svg>'); });
  // Each layer is a small square: its picture, its icon centred with no frame. The icons move
  // and fill in when the layer is on.
  const TI = (cls, body) => '<svg class="ti ' + cls + '" viewBox="0 0 24 24" aria-hidden="true">' + body + '</svg>';
  const TILE = {
    heat: TI('heat', '<g class="fl">' + SD_ICONS.heat + '</g>'),
    noah: '<span class="nw"></span><span class="nl"></span><span class="np"><i></i><i></i><i></i></span>',
    dim: TI('dim', '<circle cx="12" cy="12" r="9"/><path class="half" d="M12 3a9 9 0 0 0 0 18z"/>'),
    transit: TI('transit', '<g class="car"><path d="M3 16V9a2 2 0 0 1 2-2h9.5a2 2 0 0 1 1.6.8L19 11h1.2A1.8 1.8 0 0 1 22 12.8V16a1 1 0 0 1-1 1h-1M3 16a1 1 0 0 0 1 1h1M10 17h4"/><path d="M3 12h13M7 7v5M11.5 7v5"/>' +
      '<g class="wh"><circle cx="7.5" cy="17.5" r="2"/><path d="M7.5 16v3"/></g><g class="wh"><circle cx="17.5" cy="17.5" r="2"/><path d="M17.5 16v3"/></g></g><path class="road" d="M1 21.8H23"/>'),
    aq: TI('air', '<path class="a1" d="M3 8h9a3 3 0 1 0-3-3"/><path class="a2" d="M3 12.5h15a3 3 0 1 1-3 3"/><path class="a3" d="M3 17h6a2.5 2.5 0 1 1-2.5 2.5"/>'),
    safe: TI('safe', '<mask id="sf-m"><rect width="24" height="24" fill="#fff"/><path d="M12 8.6v6.8M8.6 12h6.8" stroke="#000" stroke-width="2.4" stroke-linecap="round"/></mask>' +
      '<path class="sh" mask="url(#sf-m)" d="M12 3 5 6v5.5c0 4.3 2.9 7.7 7 9.5 4.1-1.8 7-5.2 7-9.5V6z"/><path class="pl" d="M12 8.6v6.8M8.6 12h6.8"/>'),
  };
  // The pictures stay as they were. Dim's and Transit's are redrawn square, so they stay crisp at this size.
  const DIMPIC = '<svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><path class="dim" fill-rule="evenodd" d="M0 0H100V100H0Z M24 20L72 14 88 42 72 80 36 84 14 56Z"/><path class="edge" d="M24 20L72 14 88 42 72 80 36 84 14 56Z"/></svg>';
  const ROUTEPIC = '<svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><path class="r1" d="M-4 70C20 40 46 84 70 52S96 30 104 40"/><path class="r2" d="M-4 30C24 56 50 12 78 44S100 70 104 62"/><path class="r3" d="M30 104C40 80 62 70 80 46"/><circle cx="28" cy="58" r="3"/><circle cx="66" cy="47" r="3"/><circle cx="88" cy="34" r="3"/></svg>';
  list.querySelectorAll('.map-sw').forEach(l => { const m = /map-sw--(\w+)/.exec(l.className), sc = l.querySelector('.scene'); const k = m && (m[1] === 'air' ? 'aq' : m[1]);
    if (!sc || !TILE[k]) return; l.classList.add('tile');
    if (k === 'noah') { sc.innerHTML = TILE.noah; return; }
    if (k === 'dim') sc.innerHTML = DIMPIC; if (k === 'transit') sc.innerHTML = ROUTEPIC;
    sc.querySelectorAll('svg.mk-ic').forEach(v => v.remove()); sc.insertAdjacentHTML('beforeend', TILE[k]); });
  btn.addEventListener('click', e => { e.stopPropagation(); const open = card.hidden; if (open) mapDrawer('layers'); card.hidden = !open; btn.setAttribute('aria-expanded', String(open)); });
  card.addEventListener('click', e => { if (!e.target.closest('#lyr-off')) return; document.querySelectorAll('#lyr-list input:checked').forEach(c => c.click()); });
  card.addEventListener('change', e => {
    const m = /^lyr-(.+)$/.exec(e.target.id || ''); if (!m) { layerSync(); return; } const k = m[1];
    LAYER[k] = e.target.checked; layerSync();
    layerDraw(k).then(() => { if (LAYER[k] && !LAYER_DATA[k]) LAYER[k] = false; layerSync(); });
  });
  document.addEventListener('click', e => { if (!card.hidden && !e.target.closest('#ss-lyr, #layers-btn')) { card.hidden = true; btn.setAttribute('aria-expanded', 'false'); } });
  window.addEventListener('themechange', () => ['aq', 'transit'].forEach(k => { if (map.getLayer(k === 'aq' ? 'aq-fill' : 'transit-glow')) layerDraw(k); }));
  // The outline arrives after the page does; the air-quality tint follows it.
  const wait = setInterval(() => { if (rings.length) { clearInterval(wait); if (map.getSource('aq')) map.getSource('aq').setData(layerShape()); } }, 600); setTimeout(() => clearInterval(wait), 20000);
})();

// The filter dropdowns and the month picker, in the portal's own look.
const STATUS_DOT = { under_review: '#F9AB00', in_progress: '#2F6BFF', resolved: '#1E9E56', rejected: '#9AA3B2' };
sdPickers.select(document.getElementById('f-category'), { dot: v => catColour(v) });
sdPickers.select(document.getElementById('f-status'), { dot: v => STATUS_DOT[v] });
sdPickers.month(document.getElementById('f-period'), { allTime: document.getElementById('f-period-all') });

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

document.getElementById('f-heat').addEventListener('change', draw);
['f-category', 'f-status', 'f-period'].forEach(id =>
  document.getElementById(id).addEventListener('change', () => {
    // Picking a month means that month, not all time.
    if (id === 'f-period') document.getElementById('f-period-all').checked = false;
    document.getElementById('f-period').disabled = document.getElementById('f-period-all').checked;
    markDirty();
  }));
document.getElementById('f-apply').addEventListener('click', () => {
  Object.assign(applied, readFilters());
  markDirty();
  draw();
  loadHotspots();
});

document.getElementById('f-flood').addEventListener('change', e => { FW.auto = false; floodLayer(); fwRender(); });

// ---- flood watch -----------------------------------------------------
// Project NOAH publishes hazard maps, not live readings, so the live part
// is the rain: every 10 minutes the browser asks Open-Meteo (free, no key)
// how much fell on Barangay 183 in the last hour, and reads it against
// PAGASA's rainfall warnings — Yellow 7.5–15 mm/h, Orange 15–30, Red over
// 30. When a warning is up the NOAH zones turn on by themselves, the zones
// that flood at that rain are brought forward, and each open complaint
// inside them is ringed. If the rain source can't be reached the chip says
// so and the zones stay as the admin set them.
const FWL = [
  { en: 'No rain warning', fil: 'Walang babala sa ulan', col: '#22c55e', short: '',
    note: ['Flood zones stay as you set them.', 'Nananatili ang mga bahaing lugar ayon sa setting mo.'] },
  { en: 'Yellow rainfall warning', fil: 'Dilaw na babala sa ulan', col: '#eab308', short: 'Yellow',
    note: ['Flooding possible in high-hazard areas.', 'Posibleng bumaha sa mga lugar na mataas ang panganib.'] },
  { en: 'Orange rainfall warning', fil: 'Kahel na babala sa ulan', col: '#f97316', short: 'Orange',
    note: ['Flooding threatening in high and medium-hazard areas.', 'Banta ng baha sa mataas at katamtamang panganib.'] },
  { en: 'Red rainfall warning', fil: 'Pulang babala sa ulan', col: '#dc2626', short: 'Red',
    note: ['Serious flooding expected in every flood zone.', 'Inaasahan ang malubhang baha sa lahat ng bahaing lugar.'] },
];
const FW = { online: null, mm: null, level: 0, at: null, auto: false, risk: [] };
const OPEN_STATUSES = ['pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation'];
const fwLevel = mm => mm >= 30 ? 3 : mm >= 15 ? 2 : mm >= 7.5 ? 1 : 0;

async function fwRead() {
  const [lng, lat] = RESIDENTIAL_CENTRE;
  try {
    const res = await fetch('https://api.open-meteo.com/v1/forecast?latitude=' + lat + '&longitude=' + lng +
      '&minutely_15=precipitation&past_minutely_15=4&forecast_minutely_15=0&timezone=Asia%2FManila', { cache: 'no-store' });
    if (!res.ok) throw new Error(res.status);
    const q = (await res.json()).minutely_15.precipitation.filter(v => v != null);
    if (!q.length) throw new Error('no readings');
    FW.mm = q.reduce((a, v) => a + v, 0);   // the last four quarter-hours: mm in the past hour
    FW.online = true;
  } catch (e) {
    FW.online = false; FW.mm = null;
  }
  FW.at = new Date();
  const was = FW.level;
  FW.level = FW.online ? fwLevel(FW.mm) : 0;
  const flood = document.getElementById('f-flood');
  if (FW.level > 0 && !flood.checked) { flood.checked = true; FW.auto = true; }
  if (FW.level === 0 && FW.auto) { flood.checked = false; FW.auto = false; }
  floodLayer();
  await fwRisk();
  if (FW.level > was) fwAlert();
  fwRender();
}

// The NOAH layer as the switch and the warning have it.
async function floodLayer() {
  await mapReady;
  const on = document.getElementById('f-flood').checked;
  if (hazards) hazards.show(on);
  document.getElementById('lg-flood').hidden = !on;
  if (map.getLayer('hazard-fill')) {
    const min = 4 - FW.level;   // Yellow brings forward level 3, Orange 2+, Red all
    map.setPaintProperty('hazard-fill', 'fill-opacity', FW.level > 0
      ? ['case', ['all', ['==', ['get', 'hazard'], 'flood'], ['>=', ['get', 'level'], min]], 0.55, 0.2] : 0.38);
  }
}

let riskSeq = 0;
async function fwRisk() {
  const seq = ++riskSeq;
  const showRing = FW.level > 0 && document.getElementById('f-flood').checked;
  document.getElementById('lg-risk').hidden = !showRing;
  if (!FW.level || !window.hazardAt) { FW.risk = []; }
  else {
    const min = 4 - FW.level;
    const open = visible().filter(r => OPEN_STATUSES.includes(r.status));
    const levels = await Promise.all(open.map(r => window.hazardAt(+r.longitude, +r.latitude).catch(() => ({ flood: 0 }))));
    if (seq !== riskSeq) return;
    FW.risk = open.filter((r, i) => levels[i].flood >= min);
  }
  await mapReady;
  map.getSource('risk').setData(showRing
    ? { type: 'FeatureCollection', features: FW.risk.map(r => point(+r.longitude, +r.latitude)) } : EMPTY);
  if (!document.getElementById('fw-card').hidden) fwRender();
}

function fwAlert() {
  const L = FWL[FW.level], old = document.querySelector('#s-spatial .fw-alert');
  if (old) old.remove();
  const el = document.createElement('div');
  el.className = 'fw-alert'; el.setAttribute('role', 'status'); el.style.setProperty('--fw', L.col);
  el.textContent = T(L.en, L.fil) + ': ' + T('flood zones turned on', 'binuksan ang mga bahaing lugar') + ' · ' +
    FW.risk.length + T(FW.risk.length === 1 ? ' open complaint in a zone at risk' : ' open complaints in zones at risk', ' bukas na sumbong sa delikadong lugar');
  document.getElementById('s-spatial').appendChild(el);
  setTimeout(() => el.remove(), 6000);
}

function fwRender() {
  const box = document.getElementById('fw'), L = FWL[FW.level];
  box.style.setProperty('--fw', FW.online ? L.col : '#9AA1AB');
  box.dataset.live = FW.online ? '1' : '0';
  const t = FW.at ? FW.at.toLocaleTimeString(window.LANG === 'fil' ? 'fil-PH' : 'en-US', { hour: 'numeric', minute: '2-digit' }) : '—';
  document.getElementById('fw-sum').textContent = FW.online === null ? T('Connecting…', 'Kumokonekta…')
    : FW.online ? 'Live · ' + FW.mm.toFixed(1) + ' mm/h' + (FW.level ? ' · ' + L.short : '')
    : T('Offline · retrying', 'Offline · sinusubukang muli');
  const flood = document.getElementById('f-flood').checked;
  document.getElementById('fw-card').innerHTML = (FW.online
    ? '<div class="fw-level"><span class="fw-dot"></span><span><b>' + esc(T(L.en, L.fil)) + '</b><small>' + esc(T(L.note[0], L.note[1])) + '</small></span>' +
      '<span class="fw-rain">' + FW.mm.toFixed(1) + '<small>mm/h</small></span></div>' +
      '<div class="fw-row"><span>' + esc(T('Open complaints in zones at risk', 'Bukas na sumbong sa delikadong lugar')) + '</span><b>' + (FW.level ? FW.risk.length : '—') + '</b></div>' +
      '<div class="fw-row"><span>' + esc(T('Flood zones on the map', 'Bahaing lugar sa mapa')) + '</span><b>' +
        esc(flood ? (FW.auto ? T('On (turned on by the warning)', 'Bukas (dahil sa babala)') : T('On', 'Bukas')) : T('Off', 'Sarado')) + '</b></div>' +
      '<div class="fw-row"><span>' + esc(T('Last checked', 'Huling tingin')) + '</span><b>' + esc(t) + '</b></div>'
    : '<div class="fw-level"><span class="fw-dot"></span><span><b>' + esc(T('Flood data offline', 'Offline ang datos ng baha')) + '</b><small>' +
      esc(T('The rain source can\u2019t be reached. Trying again in 10 minutes; flood zones stay as you set them.',
            'Hindi maabot ang pinagkukunan ng ulan. Susubukan muli sa loob ng 10 minuto.')) + '</small></span></div>') +
    '<p class="fw-src">' + esc(T('Rain: Open-Meteo, checked every 10 minutes, read against PAGASA rainfall warnings. Flood zones: Project NOAH 100-year flood map (UP NOAH Center).',
                                 'Ulan: Open-Meteo, bawat 10 minuto, ayon sa babala ng PAGASA. Bahaing lugar: Project NOAH (UP NOAH Center).')) + '</p>';
}

fwRender();
fwRead();
setInterval(fwRead, 10 * 60 * 1000);

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
  const to = new Date(Date.now() + 60 * 1000);
  if (applied.allTime) {
    return { from: '2000-01-01T00:00:00Z', to: to.toISOString() };
  }
  const val = applied.period; // 'YYYY-MM'
  if (!val) { return { from: '2000-01-01T00:00:00Z', to: to.toISOString() }; }
  // A month in Manila (UTC+8): midnight on the 1st there is 16:00 the
  // day before in UTC. Taking the UTC month moved eight hours of reports
  // across each month boundary.
  const [y, m] = val.split('-').map(Number);
  const MANILA = 8 * 3600 * 1000;
  return {
    from: new Date(Date.UTC(y, m - 1, 1) - MANILA).toISOString(),
    to:   new Date(Date.UTC(y, m, 1) - MANILA).toISOString(),
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
  const cat = applied.cat || null;
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
    '<button class="p-x" type="button" aria-label="' + T('Close', 'Isara') + '">&times;</button>' +
    '<p class="p-id">Hotspot &mdash; ' + h.report_count + T(h.report_count === 1 ? ' report' : ' reports', ' ulat') + '</p>' +
    '<p class="p-cat">' + T('Mostly ', 'Karamihan ay ') + esc(label(h.top_category)) + '</p>' +
    '<dl class="p-dates">' +
      '<dt>' + T('Submitted', 'Isinumite') + '</dt><dd>' + submittedRange + '</dd>' +
      '<dt>' + T('Deadline', 'Takdang oras') + '</dt><dd>' + deadlineText + '</dd>' +
    '</dl>' +
    (members.length
      ? '<p class="p-sub">' + T('Reports in this cluster:', 'Mga ulat sa kumpol na ito:') + '</p>' +
        '<ol class="p-pin-list" style="margin:0">' +
        members.slice(0, 8).map(r =>
          '<li class="p-pin-row">' +
            '<span class="p-dot-s" style="background:' + (COLOUR[r.status] || '#9aa1ab') + '"></span>' +
            '<span class="p-pin-body"><a href="case.php?id=' + encodeURIComponent(r.id) + '">' + esc(r.tracking_id) + '</a>' +
            '<small>' + esc(label(r.category)) + '</small></span>' +
          '</li>').join('') +
        '</ol>'
      : '');
  box.removeAttribute('hidden');
  box.querySelector('.p-x').addEventListener('click',
    () => box.setAttribute('hidden', ''));
}

async function loadHotspots() {
  if (!HOTSPOTS) return;
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
  const cat = applied.cat || null;

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
  badge.classList.toggle('p-live-n', hotspots.length > 0);
  status.textContent = hotspots.length
    ? hotspots.length + T(hotspots.length === 1 ? ' recurring area found in this period.' : ' recurring areas found in this period.',
                          ' lugar na paulit-ulit ang nakita sa panahong ito.')
    : T('No recurring hotspots in this period — complaints are spread out, or too few to cluster.',
        'Walang paulit-ulit na hotspot sa panahong ito — kalat ang mga sumbong, o kakaunti para ipangkat.');

  list.innerHTML = '';
  hotspots.slice(0, 15).forEach((h, i) => {
    const li = document.createElement('li');
    li.className = 'p-pin-row';
    li.innerHTML =
      '<span class="p-dot-s" style="background:' + hotspotColour(h.report_count) + '"></span>' +
      '<span class="p-pin-body">#' + (i + 1) + ' — ' + h.report_count + T(' reports', ' ulat') +
      '<small>' + esc(label(h.top_category)) + '</small></span>';
    li.addEventListener('click', () => map.easeTo({ center: [h.centroid_lng, h.centroid_lat], zoom: 17 }));
    list.appendChild(li);
  });
  if (!hotspots.length) {
    list.innerHTML = '<li class="p-pin-empty">' + T('Nothing recurring enough to call a hotspot yet.', 'Wala pang sapat na paulit-ulit para tawaging hotspot.') + '</li>';
  }
}

const HOTSPOTS = <?= json_encode(HOTSPOTS_ENABLED) ?>;
if (HOTSPOTS) document.getElementById('f-hotspots').addEventListener('change', loadHotspots);
document.getElementById('f-period-all').addEventListener('change', e => {
  document.getElementById('f-period').disabled = e.target.checked;
  markDirty();
});

const hotspotToggleBtn = document.getElementById('hotspot-toggle');
const hotspotSide      = document.getElementById('hotspot-side');
if (HOTSPOTS) hotspotToggleBtn.addEventListener('click', () => {
  const open = hotspotSide.hasAttribute('hidden');
  open ? hotspotSide.removeAttribute('hidden') : hotspotSide.setAttribute('hidden', '');
  hotspotToggleBtn.setAttribute('aria-expanded', String(open));
});

// The complaints and the boundary are fetched side by side with the
// style and tiles; each is drawn as soon as the map can take it.
loadBoundary();
load();
</script>

<?php layout_foot(); ?>
