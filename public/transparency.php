<?php
/**
 * Public Transparency Dashboard — no login.
 *
 * Everything else under admin/ sits behind require_admin() for good
 * reason: most of it is one specific resident's ID photo, phone number,
 * or complaint text. This page is deliberately the opposite — a second,
 * narrower surface for the numbers that are already aggregate-safe, with
 * no session and no admin chrome at all.
 *
 * Two RPCs back it, both from migration 0043 and both SECURITY DEFINER,
 * granted to anon:
 *
 *   public_transparency_stats() — counts, category breakdown, resolution
 *   time vs. SLA target. Same shape dashboard_metrics() already computes
 *   for the admin dashboard, duplicated as its own function rather than
 *   shared so an admin-only field added there can never leak here by
 *   forgetting this second consumer exists.
 *
 *   public_report_heat() — never a real report's coordinates. Every point
 *   is a fixed ~44m grid cell, and any cell with fewer than 3 reports is
 *   dropped entirely before it ever reaches this page. Decided with the
 *   user (29 Aug 2026): aggregated heat only, no individual pins, so a
 *   single complaint — often filed near the complainant's own home — can
 *   never be the thing this public map is pointing at.
 *
 * Uses `new Supabase()` with no access token, which falls back to the
 * publishable key for both the apikey and Authorization headers (see
 * Supabase::request() in includes/supabase.php) — i.e. this page talks to
 * PostgREST as the anon role, exactly the role those two functions are
 * granted to. There is no admin session anywhere on this page.
 *
 * require_once on admin/includes/layout.php below is for category_label()
 * only — a plain string-formatting helper with no auth dependency. This
 * page never calls layout_head()/layout_foot(), so current_admin() (which
 * *does* require a session) is never invoked.
 */
declare(strict_types=1);

require_once __DIR__ . '/../admin/includes/config.php';
require_once __DIR__ . '/../admin/includes/supabase.php';
require_once __DIR__ . '/../admin/includes/layout.php';

$db = new Supabase();

$tz     = new DateTimeZone('Asia/Manila');
$period = ($_GET['period'] ?? 'month') === 'all' ? 'all' : 'month';
$from   = $period === 'all'
    ? new DateTimeImmutable('2000-01-01 00:00:00', $tz)
    : new DateTimeImmutable('first day of this month 00:00:00', $tz);
$to     = new DateTimeImmutable('now', $tz);

$error = null;
$stats = [];
$heat  = [];

try {
    $stats = $db->rpc('public_transparency_stats', [
        'p_from' => $from->format(DateTimeInterface::ATOM),
        'p_to'   => $to->format(DateTimeInterface::ATOM),
    ]);
    $heat = $db->rpc('public_report_heat', [
        'p_from'     => $from->format(DateTimeInterface::ATOM),
        'p_to'       => $to->format(DateTimeInterface::ATOM),
        'p_category' => null,
    ]);
} catch (SupabaseError) {
    $error = 'Statistics are temporarily unavailable. Please check back shortly.';
}

$m          = is_array($stats) ? $stats : [];
$total      = (int) ($m['total'] ?? 0);
$tiles      = $m['tiles'] ?? ['resolved' => 0, 'overdue' => 0];
$status     = $m['resolution_status'] ?? ['done' => 0, 'overdue' => 0, 'late' => 0, 'processing' => 0, 'rejected' => 0];
$categories = $m['categories'] ?? [];
$eff        = $m['efficiency'] ?? null;

$maxCat = 1;
foreach ($categories as $c) {
    $maxCat = max($maxCat, (int) ($c['n'] ?? 0));
}
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Transparency Report — SmartSumbong | Barangay 183</title>
<link rel="icon" type="image/png" href="../admin/assets/img/brgy-183-seal.png">
<meta name="theme-color" content="#0B2B6B">
<link href="../admin/assets/css/fonts.css" rel="stylesheet">
<style>
  :root {
    --navy: #0B2B6B; --navy-deep: #081F4D; --orange: #FF9800;
    --ink: #1B2536; --muted: #5C6B85; --line: #E3E7F0; --bg: #F5F7FC;
    --ok: #22c55e; --warn: #f59e0b; --bad: #dc2626;
  }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: 'Inter', system-ui, sans-serif; background: var(--bg); color: var(--ink); }

  .pub-header {
    background: linear-gradient(135deg, var(--navy), var(--navy-deep));
    color: #fff; padding: 28px 20px 68px;
  }
  .pub-header-inner { max-width: 960px; margin: 0 auto; display: flex; align-items: center; gap: 14px; }
  .pub-header img { width: 48px; height: 48px; border-radius: 50%; background: #fff; }
  .pub-header h1 { font-size: 19px; margin: 0; }
  .pub-header p { margin: 2px 0 0; font-size: 13px; color: #C7D3F2; }

  .pub-wrap { max-width: 960px; margin: -46px auto 40px; padding: 0 20px; }

  .pub-period { display: flex; gap: 8px; margin-bottom: 18px; }
  .pub-period a {
    padding: 7px 14px; border-radius: 999px; font-size: 13px; font-weight: 600;
    text-decoration: none; background: #fff; color: var(--navy); border: 1px solid var(--line);
  }
  .pub-period a.is-on { background: var(--navy); color: #fff; border-color: var(--navy); }

  .pub-tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 14px; margin-bottom: 18px; }
  .pub-tile { background: #fff; border-radius: 14px; padding: 16px 18px; box-shadow: 0 6px 20px rgba(11,43,107,.08); }
  .pub-tile .n { font-size: 26px; font-weight: 800; color: var(--navy); }
  .pub-tile .l { font-size: 12.5px; color: var(--muted); margin-top: 2px; }

  .pub-card { background: #fff; border-radius: 14px; padding: 18px 20px; margin-bottom: 18px; box-shadow: 0 6px 20px rgba(11,43,107,.06); }
  .pub-card h2 { font-size: 14px; margin: 0 0 14px; color: var(--navy); }

  .pub-bar-row { display: flex; align-items: center; gap: 10px; margin-bottom: 9px; font-size: 12.5px; }
  .pub-bar-label { width: 170px; flex: none; color: var(--ink); }
  .pub-bar-track { flex: 1; background: var(--bg); border-radius: 6px; height: 10px; overflow: hidden; }
  .pub-bar-fill { height: 100%; background: var(--orange); border-radius: 6px; }
  .pub-bar-n { width: 30px; flex: none; text-align: right; color: var(--muted); font-variant-numeric: tabular-nums; }

  .pub-status-row { display: flex; flex-wrap: wrap; gap: 10px; }
  .pub-status-chip { flex: 1; min-width: 110px; text-align: center; padding: 10px; border-radius: 10px; background: var(--bg); }
  .pub-status-chip .n { font-size: 18px; font-weight: 700; }
  .pub-status-chip .l { font-size: 11.5px; color: var(--muted); }

  #pub-map { height: 340px; border-radius: 12px; }
  .pub-map-note { font-size: 12px; color: var(--muted); margin: 10px 0 0; line-height: 1.5; }

  .pub-footer { max-width: 960px; margin: 0 auto 30px; padding: 0 20px; font-size: 11.5px; color: var(--muted); text-align: center; }
  .pub-error { background: #FDECEC; color: #9B1C1C; border-radius: 10px; padding: 12px 16px; font-size: 13px; margin-bottom: 18px; }
</style>
</head>
<body>

<header class="pub-header">
  <div class="pub-header-inner">
    <img src="../admin/assets/img/brgy-183-seal.png" alt="Barangay 183 seal">
    <div>
      <h1>Barangay 183 &middot; Pasay City</h1>
      <p>SmartSumbong Transparency Report</p>
    </div>
  </div>
</header>

<main class="pub-wrap">
  <?php if ($error): ?>
    <div class="pub-error"><?= e($error) ?></div>
  <?php endif; ?>

  <nav class="pub-period">
    <a href="?period=month" class="<?= $period === 'month' ? 'is-on' : '' ?>">This month</a>
    <a href="?period=all" class="<?= $period === 'all' ? 'is-on' : '' ?>">All time</a>
  </nav>

  <section class="pub-tiles">
    <div class="pub-tile"><div class="n"><?= $total ?></div><div class="l">Complaints filed</div></div>
    <div class="pub-tile"><div class="n"><?= (int) ($tiles['resolved'] ?? 0) ?></div><div class="l">Resolved</div></div>
    <div class="pub-tile"><div class="n"><?= (int) ($tiles['overdue'] ?? 0) ?></div><div class="l">Currently overdue</div></div>
    <div class="pub-tile">
      <div class="n"><?= $eff && $eff['avg_hours'] !== null ? round((float) $eff['avg_hours']) . 'h' : '—' ?></div>
      <div class="l">Avg. time to resolve<?= $eff && $eff['avg_target'] !== null ? ' (target ' . round((float) $eff['avg_target']) . 'h)' : '' ?></div>
    </div>
  </section>

  <section class="pub-card">
    <h2>Complaints by category</h2>
    <?php if (!$categories): ?>
      <p class="pub-map-note">No complaints filed in this period yet.</p>
    <?php endif; ?>
    <?php foreach ($categories as $c): $n = (int) ($c['n'] ?? 0); ?>
      <div class="pub-bar-row">
        <span class="pub-bar-label"><?= e(category_label((string) $c['category'])) ?></span>
        <span class="pub-bar-track"><span class="pub-bar-fill" style="width:<?= max(4, round($n / $maxCat * 100)) ?>%"></span></span>
        <span class="pub-bar-n"><?= $n ?></span>
      </div>
    <?php endforeach; ?>
  </section>

  <section class="pub-card">
    <h2>Where things stand</h2>
    <div class="pub-status-row">
      <div class="pub-status-chip"><div class="n" style="color:var(--ok)"><?= (int) $status['done'] ?></div><div class="l">Done on time</div></div>
      <div class="pub-status-chip"><div class="n" style="color:var(--warn)"><?= (int) $status['late'] ?></div><div class="l">Done, past target</div></div>
      <div class="pub-status-chip"><div class="n" style="color:var(--navy)"><?= (int) $status['processing'] ?></div><div class="l">Still being worked</div></div>
      <div class="pub-status-chip"><div class="n" style="color:var(--bad)"><?= (int) $status['overdue'] ?></div><div class="l">Past target, open</div></div>
      <div class="pub-status-chip"><div class="n" style="color:var(--muted)"><?= (int) $status['rejected'] ?></div><div class="l">Not accepted</div></div>
    </div>
  </section>

  <section class="pub-card">
    <h2>Where complaints recur</h2>
    <div id="pub-map"></div>
    <p class="pub-map-note">
      Shaded areas show where complaints have recurred nearby &mdash; not exact
      locations. To protect residents' privacy, no single complaint is ever
      shown on its own: an area only appears here once at least three
      complaints have occurred within a short distance of each other.
    </p>
  </section>
</main>

<p class="pub-footer">
  Barangay 183, Pasay City &mdash; figures update automatically as complaints
  are filed and resolved. This page does not require an account and shows
  no personal information.
</p>

<link rel="stylesheet" href="../admin/assets/vendor/leaflet/leaflet.css">
<script src="../admin/assets/vendor/leaflet/leaflet.js"></script>
<script src="../admin/assets/vendor/leaflet/leaflet-heat.js"></script>
<script>
  // Same residential-area framing spatial.php uses, so this map opens
  // already looking at the barangay instead of the runway/apron that
  // dominates the rest of the official boundary.
  const CENTRE = [14.526905, 121.015543];
  const map = L.map('pub-map', { minZoom: 15, maxZoom: 18, zoomControl: true })
    .setView(CENTRE, 16);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19, attribution: '&copy; OpenStreetMap contributors'
  }).addTo(map);

  // Every point here is already a suppressed grid cell from
  // public_report_heat() — never a real report coordinate. See 0043.
  const CELLS = <?= json_encode(array_map(
      fn(array $c) => [(float) $c['cell_lat'], (float) $c['cell_lng'], (int) $c['n']],
      $heat
  ), JSON_UNESCAPED_UNICODE) ?>;

  if (CELLS.length) {
    L.heatLayer(CELLS, { radius: 30, blur: 24, maxZoom: 17, max: Math.max(...CELLS.map(c => c[2])) })
      .addTo(map);
    map.fitBounds(L.latLngBounds(CELLS.map(c => [c[0], c[1]])).pad(0.3), { maxZoom: 17 });
  }
</script>
</body>
</html>
