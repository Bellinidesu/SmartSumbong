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

// The command center (0143) can be switched off (feature_switches, 0144): then none of its parts are drawn.
$ccOn = feature_on('command_center');

$categories = category_keys();   // the catalogue (0146), in the barangay's order

// What the engine sees (0123, 0124, 0127): the SMART drawer lists it and the map can show it. Each call is optional.
$patterns = []; $smartSum = []; $smartLate = []; $smartSpikes = []; $smartLevels = []; $smartBusy = [];
// 0145: the drawer reads the barangay-wide analytics, which are for super admins and captains
$smartOn = sees_everything();
if ($smartOn) try {
    $sg = db()->selectMany([
        'patterns' => ['rpc/smart_patterns', ['p_days' => null], true],
        'risk'     => ['rpc/smart_deadline_risk', [], true],
        'spikes'   => ['rpc/smart_spikes', [], true],
        'sum'      => ['rpc/smart_summary', [], true],
        'lv'       => ['report_triage', ['select' => 'report_id,effective_level', 'limit' => '5000'], true],
        'dp'       => ['dispatches', ['select' => 'report_id', 'state' => 'in.(assigned,accepted)', 'limit' => '5000'], true],
    ]);
    $ok = fn(string $k): array => (isset($sg[$k]) && !($sg[$k] instanceof SupabaseError) && is_array($sg[$k])) ? $sg[$k] : [];
    $patterns    = array_slice($ok('patterns'), 0, 12);
    $smartLate   = array_values(array_filter($ok('risk'), fn($r) => ($r['risk'] ?? '') === 'high'));
    $smartSpikes = $ok('spikes');
    $smartSum    = $ok('sum');
    foreach ($ok('lv') as $row) { $smartLevels[$row['report_id']] = $row['effective_level']; }
    foreach ($ok('dp') as $row) { $smartBusy[] = $row['report_id']; }
} catch (SupabaseError) { /* the drawer just stays empty */ }
layout_head(t('Spatial Distribution', 'Mapa ng mga Sumbong'), 'spatial.php');
?>

<!-- The preview's map: it covers the page, everything else floats on it. -->
<section class="p-map-page" id="s-spatial">
  <div class="p-map-full" id="map"></div>

  <div class="p-map-float p-map-search" id="map-search">
    <div class="p-ttl"><h1><?= e(t('Spatial Distribution', 'Mapa ng mga Sumbong')) ?></h1>
      <span class="p-live" id="map-live"><i></i><?= e(t('Live', 'Live')) ?></span>
      <span class="p-note" id="map-status"><?= e(t('Connecting…', 'Kumokonekta…')) ?></span>
      <button type="button" class="ss-pin" id="map-pin" aria-pressed="false" title="<?= e(t('Keep this open', 'Panatilihing bukas ito')) ?>" aria-label="<?= e(t('Keep this open', 'Panatilihing bukas ito')) ?>"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 4h6l-1 6 3 3H7l3-3z"/><path d="M12 13v7"/></svg><span class="ss-pin-l"><?= e(t('Lock open', 'I-lock')) ?></span></button></div>
    <?php // 15 Nov 2026 (Rose): staff see only their committee's kinds, so they have no complaint type filter ?>
    <div class="p-row">
      <label class="p-pill-select"<?= my_tier() === 'moderator' ? ' hidden' : '' ?>><span class="p-sr"><?= e(t('Filter by complaint type', 'Salain ayon sa uri ng sumbong')) ?></span>
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
        <input type="hidden" id="f-from"><input type="hidden" id="f-to"><input type="month" id="f-period" value="<?= e((new DateTime('now', new DateTimeZone('Asia/Manila')))->format('Y-m')) ?>" disabled></label>
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

  <?php if (is_super()): // 15 Nov 2026 (Ace): the barangay's places moved here from Settings, for now: a button on the side that opens them in a panel (places.php) ?>
  <dialog class="pl-dlg" id="pl-dlg" aria-labelledby="pl-ttl">
    <div class="pl-head"><h2 id="pl-ttl"><?= e(t('The barangay’s places', 'Mga lugar ng barangay')) ?></h2><button type="button" class="p-btn p-btn-ghost p-btn-sm" data-pl-close><?= e(t('Close', 'Isara')) ?></button></div>
    <div class="pl-body" id="pl-body"></div>
  </dialog>
  <script nonce="<?= csp_nonce() ?>" src="assets/js/places-panel.js?v=<?= e(asset_version('../js/places-panel.js')) ?>" defer></script>
  <?php endif; ?>
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
  <?php if ($smartOn): ?>
  <aside class="p-card p-card-pad p-map-stats ss-drawer" id="smart-side" hidden aria-label="SMART engine">
    <div class="ss-drawer-head"><?= smart_logo(34) ?>
      <span class="ss-thinkline"><?= e(t('Reading the map…', 'Binabasa ang mapa…')) ?></span>
      <span class="ss-think" aria-hidden="true"><i></i><i></i><i></i></span>
    </div>
    <div class="ss-drawer-body" hidden>
      <div class="ss-say" id="ss-say"><b id="ss-say-t"><?= e(t('Reading the engine…', 'Binabasa ang engine…')) ?></b><small id="ss-say-s"></small></div>

      <p class="p-eyebrow"><?= e(t('Needs you, most urgent first', 'Kailangan ka, pinakamadalian muna')) ?><em id="ss-q-n">0</em></p>
      <div class="ss-queue" id="ss-queue"></div>
      <button type="button" class="ss-more" id="ss-more" hidden></button>

      <p class="p-eyebrow ss-also"><?= e(t('Also noticed', 'Napansin din')) ?></p>
      <p class="p-eyebrow"><?= e(t('Recurring problems', 'Paulit-ulit na problema')) ?><em><?= count($patterns) ?></em></p>
      <?php if (!$patterns): ?>
        <p class="p-hint"><?= e(t('Nothing has come up more than once in the same place lately.', 'Walang problemang umulit sa iisang lugar nitong mga nakaraan.')) ?></p>
      <?php else: ?>
      <ol class="p-pin-list">
        <?php foreach ($patterns as $pt): ?>
          <li><button type="button" class="p-pin-row ss-recur" data-lat="<?= e((string) $pt['lat']) ?>" data-lng="<?= e((string) $pt['lng']) ?>" data-c="<?= e(category_colours()[(string) $pt['category']] ?? '#FF9800') ?>" aria-pressed="false">
            <b><?= e(category_label((string) $pt['category'])) ?></b>
            <small><?= (int) $pt['reports'] ?> <?= e(t('reports from', 'ulat mula sa')) ?> <?= (int) $pt['residents'] ?> <?= e(t('residents over', 'residente sa loob ng')) ?> <?= (int) $pt['weeks'] ?> <?= e(t('weeks', 'linggo')) ?>
              · <?= (int) $pt['still_open'] ?> <?= e(t('still open', 'bukas pa')) ?><?= !empty($pt['hazard']) ? ' · ' . e((string) $pt['hazard']) : '' ?></small>
            <span class="ss-chips"><?php foreach (array_slice((array) ($pt['tracking_ids'] ?? []), 0, 3) as $tid): ?><i><?= e((string) $tid) ?></i><?php endforeach; ?></span>
          </button></li>
        <?php endforeach; ?>
      </ol>
      <?php endif; ?>

      <?php if ($smartSpikes): ?>
      <p class="p-eyebrow"><?= e(t('Spikes this week', 'Pagtaas ngayong linggo')) ?><em><?= count($smartSpikes) ?></em></p>
      <ul class="ss-spikes">
        <?php foreach (array_slice($smartSpikes, 0, 4) as $sp): $usual = (float) $sp['usual']; $ratio = $usual > 0 ? (int) $sp['this_week'] / $usual : 0; ?>
          <li><span class="sk-t"><b><?= e(category_label((string) $sp['category'])) ?></b><?= !empty($sp['place']) ? '<small>' . e((string) $sp['place']) . '</small>' : '' ?></span>
            <span class="sk-n"><b><?= (int) $sp['this_week'] ?></b><small><?= e(t('this week', 'ngayong linggo')) ?></small></span>
            <span class="sk-u"><?= e(t('usually', 'karaniwan')) ?> <b><?= e(rtrim(rtrim(number_format($usual, 1), '0'), '.')) ?></b><?= $ratio >= 2 ? '<em>×' . e(rtrim(rtrim(number_format($ratio, 1), '0'), '.')) . '</em>' : '' ?></span></li>
        <?php endforeach; ?>
      </ul>
      <?php endif; ?>
    </div>
  </aside>
  <?php endif; ?>
  <?php if ($ccOn): ?>
  <!-- The command center (SMART Iteration 4, 0143): assets/js/sd-command.js fills these. -->
  <aside class="p-card p-map-stats cc-side" id="cc-side" hidden aria-label="<?= e(t('Command center', 'Sentro ng Pamamahala')) ?>">
    <div class="cc-head"></div>
    <div class="cc-body"></div>
  </aside>
  <div class="cc-bar" id="cc-bar" hidden role="status"></div>
  <div class="cc-suggest" id="cc-suggest" hidden role="status" aria-live="polite"></div>
  <div class="cc-toast" id="cc-toast" hidden role="status" aria-live="polite"></div>
  <?php endif; ?>
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
      <div class="lg-cat" data-cat="<?= e($c) ?>" style="--c:<?= e($hex) ?>"><span class="lg-ic" data-glyph="<?= e($c) ?>"></span><span class="lg-t"><?= e(category_label($c)) ?></span><b class="lg-n">0</b></div>
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
    <div class="fw-card" id="fw-card" hidden role="region" aria-live="polite" aria-label="<?= e(t('Flood and typhoon watch', 'Bantay-baha at bantay-bagyo')) ?>"></div>
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
    <?php if ($smartOn): ?>
    <button class="p-dock-btn ss-dock ss-dock-logo" id="smart-toggle" type="button" aria-expanded="false" aria-controls="smart-side" title="SMART engine" aria-label="SMART engine">
      <?= smart_brain(24) ?><span class="p-cnt"><?= (int) ($smartSum['urgent_waiting'] ?? 0) + (int) ($smartSum['high_waiting'] ?? 0) ?></span></button>
    <?php endif; ?>
    <?php if ($ccOn): ?>
    <button class="p-dock-btn cc-dock" id="cc-toggle" type="button" aria-expanded="false" aria-controls="cc-side" title="<?= e(t('Command center', 'Sentro ng Pamamahala')) ?>" aria-label="<?= e(t('Command center', 'Sentro ng Pamamahala')) ?>">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l8 4v5c0 4.4-3.4 8.3-8 9-4.6-.7-8-4.6-8-9V7z"/><path d="M12 8v4"/><path d="M12 16h.01"/></svg></button>
    <?php endif; ?>
    <?php if (HOTSPOTS_ENABLED): ?>
    <button class="p-dock-btn" id="hotspot-toggle" aria-expanded="false" aria-controls="hotspot-side" title="<?= e(t('Hotspot clusters', 'Mga kumpol ng hotspot')) ?>" aria-label="<?= e(t('Hotspot clusters', 'Mga kumpol ng hotspot')) ?>">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3c1.3 3.4 5 4.8 5 9.5a5 5 0 0 1-10 0c0-2 .8-3.6 2-4.8.3 1.8 1.1 2.9 2.2 3.3C10.8 8.6 10.7 5.6 12 3z"/></svg><span class="p-cnt" id="hotspot-count">0</span></button>
    <?php endif; ?>
    <?php if (is_super()): ?>
    <button class="p-dock-btn" id="pl-open" type="button" aria-haspopup="dialog" aria-expanded="false" aria-controls="pl-dlg" title="<?= e(t('The barangay’s places', 'Mga lugar ng barangay')) ?>" aria-label="<?= e(t('The barangay’s places', 'Mga lugar ng barangay')) ?>">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 21s-6-5.2-6-10a6 6 0 0 1 12 0c0 4.8-6 10-6 10z"/><path d="M9.5 11l1.7 1.7 3.3-3.4"/></svg></button>
    <?php endif; ?>
  </div>
</section>

<link rel="stylesheet" href="assets/vendor/maplibre/maplibre-gl.css?v=<?= e(vendor_version('maplibre-gl')) ?>">
<link rel="stylesheet" href="assets/css/sd-widgets.css?v=<?= e(asset_version('sd-widgets.css')) ?>">
<link rel="stylesheet" href="assets/css/sd-look.css?v=<?= e(asset_version('sd-look.css')) ?>">
<link rel="stylesheet" href="assets/css/sd-light.css?v=<?= e(asset_version('sd-light.css')) ?>">
<link rel="stylesheet" href="assets/css/sd-dark.css?v=<?= e(asset_version('sd-dark.css')) ?>">
<?php if ($ccOn): ?>
<link rel="stylesheet" href="assets/css/sd-command.css?v=<?= e(asset_version('sd-command.css')) ?>">
<?php endif; ?>
<script nonce="<?= csp_nonce() ?>" src="assets/vendor/maplibre/maplibre-gl.js?v=<?= e(vendor_version('maplibre-gl')) ?>"></script>
<?php // Mapillary (1 MB) loads the first time StreetLook opens, not with the page (speed sweep, 16 Nov 2026); see mlyLoad() ?>
<script nonce="<?= csp_nonce() ?>" src="assets/js/map-theme.js?v=<?= e(asset_version('../js/map-theme.js')) ?>"></script>
<script nonce="<?= csp_nonce() ?>" src="assets/js/sd-icons.js?v=<?= e(asset_version('../js/sd-icons.js')) ?>"></script>
<script nonce="<?= csp_nonce() ?>" src="assets/js/sd-pickers.js?v=<?= e(asset_version('../js/sd-pickers.js')) ?>"></script>
<script nonce="<?= csp_nonce() ?>" src="assets/vendor/supabase/supabase.js?v=<?= e(vendor_version('supabase-js')) ?>"></script>
<?php $sdCfg = [
    'token' => access_token(), 'sbUrl' => supabase_url(), 'sbKey' => supabase_key(),
    'statusLabel' => status_labels(), 'categoryColour' => category_colours(), 'sensitiveBadge' => sensitive_badge(['is_sensitive' => true]),
    'categoryIcon' => array_map(fn (array $c): string => $c['icon'], categories_all()),
    'mapV' => (string) max(array_map('filemtime', glob(__DIR__ . '/assets/map/*') ?: [0])),
    'mly' => env('MAPILLARY_TOKEN', ''), 'mlyV' => vendor_version('mapillary-js'), 'me' => $admin['id'] ?? null,
    'hall' => ['phone' => env('BARANGAY_HALL_PHONE', ''), 'hours' => env('BARANGAY_HALL_HOURS', '')], 'brgyLine' => brgy_line(), 'hotspots' => HOTSPOTS_ENABLED,
]; ?>
<script nonce="<?= csp_nonce() ?>" type="application/json" id="sd-cfg"><?= json_encode($sdCfg, JSON_HEX_TAG | JSON_HEX_AMP | JSON_UNESCAPED_UNICODE) ?></script>
<script nonce="<?= csp_nonce() ?>" src="assets/js/spatial.js?v=<?= e(asset_version('../js/spatial.js')) ?>"></script>
<script nonce="<?= csp_nonce() ?>" src="assets/js/sd-tools.js?v=<?= e(asset_version('../js/sd-tools.js')) ?>"></script>
<script nonce="<?= csp_nonce() ?>" src="assets/js/sd-dock.js?v=<?= e(asset_version('../js/sd-dock.js')) ?>"></script>
<?php if ($smartOn): ?>
<script nonce="<?= csp_nonce() ?>">window.SS_SMART = <?= json_encode(['levels' => (object) $smartLevels, 'late' => array_column($smartLate, 'report_id'),
    'recur' => array_map(fn($p) => ['lat' => (float) $p['lat'], 'lng' => (float) $p['lng']], $patterns),
    'recurIds' => array_values(array_unique(array_merge(...array_map(fn($p) => array_map('strval', (array) ($p['tracking_ids'] ?? [])), $patterns ?: [[]])))),
    'busy' => $smartBusy,
    'lateInfo' => (object) array_column(array_map(fn($r) => ['id' => $r['report_id'], 'left' => (float) $r['hours_left'], 'typical' => (float) $r['typical_hours']], $smartLate), null, 'id'),
    'spikes' => count($smartSpikes), 'recurring' => count($patterns)], JSON_UNESCAPED_UNICODE) ?>;</script>
<script nonce="<?= csp_nonce() ?>" src="assets/js/sd-smart.js?v=<?= e(asset_version('../js/sd-smart.js')) ?>"></script>
<?php endif; ?>
<?php if ($ccOn): ?>
<script nonce="<?= csp_nonce() ?>">window.SS_CMD = <?= json_encode(['csrf' => csrf_token(), 'status' => status_labels()], JSON_UNESCAPED_UNICODE) ?>;</script>
<script nonce="<?= csp_nonce() ?>" src="assets/js/sd-command.js?v=<?= e(asset_version('../js/sd-command.js')) ?>"></script>
<?php endif; ?>

<?php layout_foot(); ?>
