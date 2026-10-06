<?php
/**
 * Barangay Complaint — one case, on the barangay's letterhead (Rose,
 * 7 Oct 2026, from her "Barangay Complaint" template): the complaint
 * number, category and concern, the complainant, the description, the
 * address with the pinned spot on a map, the photos, and who requested it.
 *
 * Same document desk as the Certification of Lack of Jurisdiction: the
 * page on a desk with zoom, an inspector beside it to adjust what prints,
 * and printing logged on the case's own trail.
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/doc_print.php';

$admin = require_admin();
$db    = db();
$id    = (string) ($_GET['id'] ?? '');

const COMPLAINT_PRINT_REMARK = 'Barangay Complaint printed';

$report = null;
$media  = [];
$error  = null;
try {
    $got = $db->selectMany([
        'report' => ['reports', [
            'select'     => 'id,tracking_id,status,category,subject,description,is_anonymous,location_label,latitude,longitude,created_at,'
                          . 'resident:users!reports_resident_id_fkey(full_name)',
            'id'         => 'eq.' . $id,
            'deleted_at' => 'is.null',
            'limit'      => '1',
        ]],
        'media' => ['report_media', [
            'select'    => 'media_url,mime_type',
            'report_id' => 'eq.' . $id,
            'order'     => 'created_at.asc',
        ], true],
    ]);
    $report = $got['report'][0] ?? null;
    $media  = is_array($got['media']) ? array_values(array_filter($got['media'], fn($m) => str_starts_with((string) $m['mime_type'], 'image/'))) : [];
    if (!$report) $error = 'That complaint could not be found.';
} catch (SupabaseError $ex) {
    $error = safe_error($ex);
}

// Print, logged on the case's trail (same status in and out, with a remark).
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['do'] ?? '') === 'printed') {
    header('Content-Type: application/json');
    if (!$report || !csrf_check($_POST['csrf'] ?? null)) { http_response_code(400); echo '{"ok":false}'; exit; }
    try {
        $db->insert('status_logs', [
            'report_id'  => $report['id'],
            'changed_by' => $admin['id'],
            'old_status' => $report['status'],
            'new_status' => $report['status'],
            'remark'     => COMPLAINT_PRINT_REMARK,
        ]);
        echo '{"ok":true}';
    } catch (Throwable) {
        http_response_code(500); echo '{"ok":false}';
    }
    exit;
}

$number      = $report ? preg_replace('/^BRG-/', '', (string) $report['tracking_id']) : '';
$catLabel    = $report ? category_label((string) $report['category']) : '';
$complainant = !$report ? '' : (!empty($report['is_anonymous']) ? 'Anonymous' : formal_name($report['resident']['full_name'] ?? ''));
$by          = trim((string) ($_GET['by'] ?? formal_name($admin['full_name'] ?? '')));
$lat         = (float) ($report['latitude'] ?? 0);
$lng         = (float) ($report['longitude'] ?? 0);

doc_head('Barangay Complaint ' . ($report['tracking_id'] ?? ''), true);
?>
<link href="assets/vendor/maplibre/maplibre-gl.css" rel="stylesheet">
<style>
  .cp p { margin: 0 0 10px; line-height: 1.45; }
  .cp .cp-cat { text-align: center; font-weight: 700; margin: -0.15in 0 4px; }
  .cp .cp-sub { text-align: center; font-style: italic; margin: 0 0 0.35in; }
  .cp .cp-row { display: grid; grid-template-columns: 1.15in 1fr; gap: 8px; margin: 0 0 12px; }
  .cp .cp-row b { font-weight: 700; }
  .cp .cp-map { width: 100%; height: 2.3in; border: 1px solid #222; margin: 6px 0 4px; position: relative; overflow: hidden; }
  .cp .cp-map img, .cp .cp-map > div { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
  .cp .cp-coords { font-size: 10pt; color: #555; margin-top: 2px; }
  .cp .cp-media { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-top: 6px; }
  .cp .cp-media img { width: 100%; aspect-ratio: 4 / 3; object-fit: cover; border: 1px solid #222; }
  .cp .cp-none { font-style: italic; color: #555; }
  .cp [hidden] { display: none !important; }
  @media print { .maplibregl-ctrl { display: none !important; } }
</style>

<header class="cd-bar">
  <a class="cd-back" href="case.php?id=<?= e($id) ?>">&lsaquo; <?= e($report['tracking_id'] ?? 'Case') ?></a>
  <span class="cd-crumb"><a href="cases.php">Case Reports</a> &rsaquo; <a href="case.php?id=<?= e($id) ?>"><?= e($report['tracking_id'] ?? '') ?></a> &rsaquo; <b>Barangay Complaint</b></span>
  <span class="cd-sp"></span>
  <span class="cd-state wait" id="cd-state">Checking…</span>
  <button class="cd-btn" id="cd-print" type="button" disabled>Print / Save as PDF</button>
</header>

<div class="cd-work">
  <section class="cd-desk" id="cd-desk" aria-label="Barangay Complaint">
    <div class="cd-stage"><div class="cd-wrap cd-flow">
<div class="doc-page">
  <?php doc_letterhead(); ?>
  <?php if ($error): ?>
    <p style="color:#a01818"><?= e($error) ?></p>
  <?php else: ?>
  <p class="doc-title">Barangay Complaint # <?= e($number) ?></p>
  <div class="cp">
    <p class="cp-cat"><?= e(mb_strtoupper($catLabel)) ?></p>
    <p class="cp-sub">(<?= e($catLabel) ?> – <?= e($report['subject']) ?>)</p>

    <div class="cp-row"><b>Complainant:</b><span><?= e($complainant) ?></span></div>
    <div class="cp-row"><b>Date filed:</b><span><?= e(long_datetime($report['created_at'])) ?></span></div>
    <div class="cp-row"><b>Description:</b><span><?= e($report['description']) ?></span></div>
    <div class="cp-row"><b>Address:</b>
      <div><?= e($report['location_label'] ?: 'Barangay 183, Zone 20, Villamor, Pasay City') ?>
        <div class="cp-coords"><?= e(coord_label($lat, $lng)) ?></div>
        <div class="cp-map" id="cp-map-wrap"><div id="cp-map"></div></div>
      </div>
    </div>
    <div class="cp-row" id="cp-media-row"><b>Media:</b>
      <div>
        <?php if (!$media): ?>
          <span class="cp-none">No photos were attached.</span>
        <?php else: ?>
          <div class="cp-media">
            <?php foreach (array_slice($media, 0, 6) as $m): ?>
              <img src="<?= e(cld_thumb($m['media_url'], 600)) ?>" alt="Photo attached to the complaint" crossorigin="anonymous">
            <?php endforeach; ?>
          </div>
        <?php endif; ?>
      </div>
    </div>
  </div>
  <?php endif; ?>

  <?php doc_requested_by($by); ?>
</div>
    </div></div>
    <div class="cd-tools" role="toolbar" aria-label="Zoom">
      <button type="button" id="cd-zo" aria-label="Zoom out">&minus;</button><span class="cd-z" id="cd-zl">100%</span><button type="button" id="cd-zi" aria-label="Zoom in">+</button>
      <span class="cd-sep"></span><button type="button" id="cd-zf">Fit page</button><button type="button" id="cd-zw">Fit width</button><span class="cd-sep"></span><span>Letter</span>
    </div>
  </section>

  <aside class="cd-insp" aria-label="Complaint details">
    <div class="cd-sec"><h2>Ready to print <span class="cd-count wait" id="cd-cnt"></span></h2><div class="cd-chk" id="cd-chk"></div></div>
    <div class="cd-sec"><h2>On the page</h2>
      <div class="cd-field"><label for="f-by">Requested by</label><input id="f-by" value="<?= e($by) ?>" autocomplete="off"></div>
      <label class="cd-tick"><input type="checkbox" id="f-map" checked> Map of the pinned location</label>
      <label class="cd-tick"><input type="checkbox" id="f-media" <?= $media ? 'checked' : '' ?> <?= $media ? '' : 'disabled' ?>> Photos (<?= count($media) ?>)</label>
    </div>
    <div class="cd-sec"><h2>The complaint</h2>
      <div class="cd-chk">
        <div class="y"><i>&#10003;</i><?= e($report['tracking_id'] ?? '') ?> · <?= e(status_label((string) ($report['status'] ?? ''))) ?></div>
        <div class="y"><i>&#10003;</i><?= e($catLabel) ?></div>
      </div>
    </div>
  </aside>
</div>
<div class="cd-toast" id="cd-toast" role="status"></div>

<script src="assets/vendor/maplibre/maplibre-gl.js"></script>
<script src="assets/js/map-theme.js?v=<?= e(asset_version('../js/map-theme.js')) ?>"></script>
<script>
(function () {
  var $ = function (id) { return document.getElementById(id); };
  var CSRF = <?= json_encode(csrf_token()) ?>, LAT = <?= json_encode($lat) ?>, LNG = <?= json_encode($lng) ?>;
  var mapReady = false;

  // The pinned spot, drawn once and kept as a picture so it prints exactly.
  if (window.maplibregl && LAT && LNG) {
    var map = new maplibregl.Map({
      container: 'cp-map', style: 'assets/map/style-light.json', center: [LNG, LAT], zoom: 17,
      interactive: false, attributionControl: false, preserveDrawingBuffer: true
    });
    new maplibregl.Marker({ color: '#c62828' }).setLngLat([LNG, LAT]).addTo(map);
    map.once('idle', function () {
      try {
        var img = new Image();
        img.alt = 'Map of the pinned location';
        img.src = map.getCanvas().toDataURL('image/png');
        // the marker is HTML on top of the canvas: draw a pin onto the picture
        img.onload = function () {
          var c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
          var g = c.getContext('2d'); g.drawImage(img, 0, 0);
          var x = c.width / 2, y = c.height / 2, r = Math.max(8, c.width / 60);
          g.fillStyle = '#c62828'; g.beginPath(); g.arc(x, y - r * 1.6, r, 0, Math.PI * 2); g.fill();
          g.beginPath(); g.moveTo(x - r * .8, y - r * 1.2); g.lineTo(x + r * .8, y - r * 1.2); g.lineTo(x, y); g.closePath(); g.fill();
          g.fillStyle = '#fff'; g.beginPath(); g.arc(x, y - r * 1.6, r * .4, 0, Math.PI * 2); g.fill();
          var shot = new Image(); shot.alt = img.alt; shot.src = c.toDataURL('image/png');
          var wrap = $('cp-map-wrap'); wrap.innerHTML = ''; wrap.appendChild(shot);
          map.remove(); mapReady = true; render();
        };
      } catch (e) { mapReady = true; render(); }
    });
  } else { mapReady = true; }

  function render() {
    var by = $('f-by').value.trim();
    document.querySelectorAll('.req .fill').forEach(function (el) { el.textContent = by || 'Name of Requestor'; el.classList.toggle('cd-empty', !by); });
    $('cp-map-wrap').hidden = !$('f-map').checked;
    var mediaRow = $('cp-media-row'); if (mediaRow) mediaRow.hidden = !$('f-media').checked && !$('f-media').disabled;
    var checks = [['Requested by', !!by], ['Map ready', !$('f-map').checked || mapReady]];
    var done = checks.filter(function (c) { return c[1]; }).length, ready = done === checks.length;
    $('cd-chk').innerHTML = checks.map(function (c) { return '<div class="' + (c[1] ? 'y' : 'n') + '"><i>' + (c[1] ? '&#10003;' : '') + '</i>' + c[0] + '</div>'; }).join('');
    $('cd-cnt').textContent = done + ' of ' + checks.length; $('cd-cnt').className = 'cd-count ' + (ready ? 'ok' : 'wait');
    $('cd-state').textContent = ready ? 'Ready to print' : 'Preparing…'; $('cd-state').className = 'cd-state ' + (ready ? 'ok' : 'wait');
    $('cd-print').disabled = !ready;
  }
  ['f-by', 'f-map', 'f-media'].forEach(function (k) { $(k).addEventListener('input', render); $(k).addEventListener('change', render); });

  function toast(t) { $('cd-toast').textContent = t; $('cd-toast').classList.add('on'); clearTimeout(toast._t); toast._t = setTimeout(function () { $('cd-toast').classList.remove('on'); }, 2600); }
  $('cd-print').onclick = function () {
    fetch(location.href, { method: 'POST', body: new URLSearchParams({ do: 'printed', csrf: CSRF }), credentials: 'same-origin' })
      .catch(function () { toast('Printed, but it could not be logged on the case.'); });
    window.print();
  };

  var z = 1, inch = 96;
  function setZ(v) { z = Math.max(.4, Math.min(1.6, Math.round(v * 100) / 100)); document.documentElement.style.setProperty('--z', z); $('cd-zl').textContent = Math.round(z * 100) + '%'; }
  $('cd-zi').onclick = function () { setZ(z + .1); }; $('cd-zo').onclick = function () { setZ(z - .1); };
  $('cd-zf').onclick = function () { var d = $('cd-desk'); setZ(Math.min((d.clientWidth - 48) / (8.5 * inch), (d.clientHeight - 64) / (11 * inch))); };
  $('cd-zw').onclick = function () { setZ(Math.min(1, ($('cd-desk').clientWidth - 48) / (8.5 * inch))); };
  render();
  requestAnimationFrame(function () { $('cd-zw').click(); });
})();
</script>
</body>
</html>
