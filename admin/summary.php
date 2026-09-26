<?php
/**
 * Report Summary — Figma "Report Tab" (282:1631), and the use cases
 * View Report Summary / Filter View Report Summary Period /
 * Download PDF Report.
 *
 * Usero's panel comment was that reproducing the dashboard charts is not
 * a barangay report. So this screen is tabular throughout, and the export
 * is a real document with a letterhead, a stated period and a signature
 * block — laid out the way an academic or barangay paper is: seals left
 * and right, the issuing body centred between them, a ruled name/section
 * line under it, and the date bottom right.
 *
 * The export is print-to-PDF rather than a server-side PDF library. That
 * is a deliberate choice: it adds no composer dependency to a barangay
 * server that has to be maintained after turnover, it renders the same
 * letterhead the screen already has, and "Save as PDF" is one step in
 * every browser's print dialog. If the barangay later wants a generated
 * file attached to an email, that is an Edge Function, not this page.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin();
$db    = db();
$tz    = new DateTimeZone('Asia/Manila');

session_start_once();

// The admin who checks this every Monday should not retype the dates.
if ($_SERVER['QUERY_STRING'] === '' && !empty($_SESSION['summary_period'])) {
    $_GET = $_SESSION['summary_period'];
}

// Quick ranges, because "last month" is the request and typing two dates
// is the tax on it.
$tzq = new DateTimeZone('Asia/Manila');
$RANGES = [
    'week'     => [t('This week', 'Ngayong linggo'),  new DateTimeImmutable('monday this week', $tzq),        new DateTimeImmutable('now', $tzq)],
    'month'    => [t('This month', 'Ngayong buwan'), new DateTimeImmutable('first day of this month', $tzq), new DateTimeImmutable('now', $tzq)],
    'last'     => [t('Last month', 'Nakaraang buwan'), new DateTimeImmutable('first day of last month', $tzq), new DateTimeImmutable('last day of last month', $tzq)],
    'quarter'  => [t('Last 90 days', 'Huling 90 araw'), new DateTimeImmutable('-90 days', $tzq),              new DateTimeImmutable('now', $tzq)],
];
$range = (string) ($_GET['range'] ?? '');
if (isset($RANGES[$range])) {
    $_GET['from'] = $RANGES[$range][1]->format('Y-m-d');
    $_GET['to']   = $RANGES[$range][2]->format('Y-m-d');
}

// ---------- period ----------
try {
    $from = new DateTimeImmutable(($_GET['from'] ?? '') !== ''
        ? $_GET['from'] . ' 00:00:00' : 'first day of this month 00:00:00', $tz);
} catch (Exception) {
    $from = new DateTimeImmutable('first day of this month 00:00:00', $tz);
}
try {
    $to = new DateTimeImmutable(($_GET['to'] ?? '') !== ''
        ? $_GET['to'] . ' 23:59:59' : 'now', $tz);
} catch (Exception) {
    $to = new DateTimeImmutable('now', $tz);
}
if ($to < $from) { [$from, $to] = [$to, $from]; }

$fromISO = $from->format(DateTimeInterface::ATOM);
$toISO   = $to->format(DateTimeInterface::ATOM);
$isPrint = isset($_GET['print']);
// The signed PDF is the barangay's official record: English, whatever
// language the screen is set to (branch B).
if ($isPrint) { force_lang('en'); }

// The seven categories are fixed per the Scope and Limitations — same list
// cases.php's category dropdown draws from.
const CATEGORIES = [
    'street_obstruction', 'public_safety_infrastructure', 'environmental_waste_hazard',
    'animal_welfare', 'traffic_violation', 'barangay_service', 'peace_order_nuisance',
];
$category = (string) ($_GET['category'] ?? '');
if (!in_array($category, CATEGORIES, true)) { $category = ''; }

if (!$isPrint) {
    $_SESSION['summary_period'] = [
        'from'     => $from->format('Y-m-d'),
        'to'       => $to->format('Y-m-d'),
        'category' => $category,
    ];
}

// ---------- data ----------
$error = null;
$reports = $dispatches = $logs = $attendance = [];

/**
 * Every row in the period. A single select with limit=500 (300 for the
 * timeline) used to be the whole story: a busy quarter printed a signed
 * report computed from the first 500 complaints only. So every page is
 * fetched; the hard ceiling only guards against a runaway range, and when
 * it is reached the page says so ($truncated) rather than presenting a
 * partial count as the total. Queries order by something unique (…,id)
 * so offset paging cannot skip or repeat rows.
 *
 * Fetched in two parallel rounds (branch B) — the four tables' row
 * counts, then every page of every table at once — instead of one page
 * after another: with the database in Mumbai, ~25 back-to-back round
 * trips made this page take about nine seconds.
 */
const SUMMARY_PAGE = 1000;
const SUMMARY_MAX  = 25000;
$truncated = [];

/**
 * @param array<string, array{0:string, 1:array<string,string>}> $tables
 * @return array<string, list<array>>
 */
function select_all_many(Supabase $db, array $tables, array &$truncated): array
{
    $counts = $db->selectMany($tables, true);
    $pages = [];
    foreach ($tables as $key => [$table, $query]) {
        $n = min((int) ($counts[$key] ?? 0), SUMMARY_MAX);
        if ((int) ($counts[$key] ?? 0) > SUMMARY_MAX) { $truncated[$table] = true; }
        // At least one page, so an empty count still asks (and a count
        // that failed to parse cannot hide rows).
        for ($offset = 0; $offset < max($n, 1); $offset += SUMMARY_PAGE) {
            $q = $query;
            $q['limit']  = (string) SUMMARY_PAGE;
            $q['offset'] = (string) $offset;
            $pages["{$key}#{$offset}"] = [$table, $q];
        }
    }
    $got = $db->selectMany($pages);
    $out = [];
    foreach ($tables as $key => $_) {
        $rows = [];
        foreach ($pages as $pk => $_p) {
            if (str_starts_with($pk, "{$key}#")) { array_push($rows, ...($got[$pk] ?? [])); }
        }
        $out[$key] = array_slice($rows, 0, SUMMARY_MAX);
    }
    return $out;
}

try {
    $reportsQuery = [
        'select'     => 'id,tracking_id,subject,category,status,is_anonymous,created_at,'
                      . 'due_at,resolved_at,closed_at,escalation_level,'
                      . 'resident:users!reports_resident_id_fkey(full_name)',
        'deleted_at' => 'is.null',
        'and'        => "(created_at.gte.{$fromISO},created_at.lte.{$toISO})",
        'order'      => 'created_at.asc,id.asc',
    ];
    // Category narrows the Resident Report Ledger only — the Tanod
    // Activity Timeline and Report Case Timeline stay period-only, since
    // they describe the barangay's overall effort for the period, not one
    // category's slice of it.
    if ($category !== '') {
        $reportsQuery['category'] = 'eq.' . $category;
    }

    $all = select_all_many($db, [
        'reports'    => ['reports', $reportsQuery],
        'dispatches' => ['dispatches', [
            'select'      => 'id,state,assigned_at,accepted_at,resolved_at,field_report_text,'
                           . 'tanod:users!dispatches_tanod_id_fkey(full_name),'
                           . 'report:reports!dispatches_report_id_fkey(tracking_id)',
            'and'         => "(assigned_at.gte.{$fromISO},assigned_at.lte.{$toISO})",
            'order'       => 'assigned_at.asc,id.asc',
        ]],
        'logs'       => ['status_logs', [
            'select'     => 'id,old_status,new_status,remark,is_system,created_at,'
                          . 'report:reports!status_logs_report_id_fkey(tracking_id),'
                          . 'by:users!status_logs_changed_by_fkey(full_name)',
            'and'        => "(created_at.gte.{$fromISO},created_at.lte.{$toISO})",
            'order'      => 'created_at.desc,id.desc',
        ]],
        'attendance' => ['attendance', [
            'select' => 'id,tanod_id,duty_status,shift_date',
            'and'    => "(logged_at.gte.{$fromISO},logged_at.lte.{$toISO})",
            'order'  => 'id.asc',
        ]],
    ], $truncated);
    $reports    = $all['reports'];
    $dispatches = $all['dispatches'];
    $attendance = $all['attendance'];

    // The same entry repeated on one complaint (the dispatch retries that
    // 0064 stopped writing, still in older periods) is shown once with
    // its count, as the resident app's timeline does — thousands of
    // identical rows were the bulk of this table and of the page's weight.
    $logs = [];
    $lastByReport = [];
    foreach ($all['logs'] as $l) {
        $rid = $l['report']['tracking_id'] ?? '';
        $sig = ($l['old_status'] ?? '') . '|' . ($l['new_status'] ?? '') . '|' . ($l['remark'] ?? '');
        if (isset($lastByReport[$rid]) && $lastByReport[$rid]['sig'] === $sig) {
            $logs[$lastByReport[$rid]['i']]['repeat'] = ($logs[$lastByReport[$rid]['i']]['repeat'] ?? 1) + 1;
            continue;
        }
        $logs[] = $l;
        $lastByReport[$rid] = ['sig' => $sig, 'i' => array_key_last($logs)];
    }
} catch (SupabaseError $ex) {
    $error = safe_error($ex);
}

// ---------- the four tiles ----------
$total    = count($reports);
$resolved = count(array_filter($reports, fn($r) => in_array($r['status'], ['resolved','closed','archived'], true)));

$hours = [];
foreach ($reports as $r) {
    $end = $r['resolved_at'] ?? $r['closed_at'] ?? null;
    if ($end) {
        $hours[] = (strtotime($end) - strtotime($r['created_at'])) / 3600;
    }
}
$avgDays = $hours ? round(array_sum($hours) / count($hours) / 24, 1) : null;

// Attendance rate: distinct tanod-days with an on_duty log, over the
// number of tanod-days that were possible in the period. A rough measure
// and labelled as one — the barangay has no roster of expected shifts.
$onDuty = [];
foreach ($attendance as $a) {
    if ($a['duty_status'] === 'on_duty') { $onDuty[$a['tanod_id'] . '|' . $a['shift_date']] = true; }
}
$days     = max(1, (int) $from->diff($to)->days + 1);
$tanodIds = array_unique(array_column($attendance, 'tanod_id'));
$possible = max(1, count($tanodIds) * $days);
$rate     = $tanodIds ? round(count($onDuty) / $possible * 100) : null;

$periodLabel = $from->format('M j, Y') . ' — ' . $to->format('M j, Y');

// This report's period can include today (the quick ranges above all do,
// except "Last month"), in which case the figures below can still move
// while it's on screen. A closed, past period is a fixed report and
// should read as one — no live badge, nothing to watch.
$isOngoing = !$isPrint && $to >= new DateTimeImmutable('today', $tz);

$categoryLabel = $category !== '' ? category_label($category) : t('All Categories', 'Lahat ng Kategorya');

if (!$isPrint) { layout_head(t('Report Summary', 'Buod ng mga Ulat'), 'summary.php'); }
else { print_head($periodLabel, $categoryLabel); }
?>

<?php if ($error): ?>
  <div class="alert-bar" role="alert"><?= e($error) ?></div>
<?php endif; ?>

<?php if ($truncated): ?>
  <!-- Printed too: a signed report must not pass off a partial count. -->
  <div class="alert-bar" role="alert">
    <?= e(t('This period has more than ', 'Mahigit ')) ?><?= number_format(SUMMARY_MAX) ?><?= e(t(' rows in ', ' na hanay sa ')) ?>
    <?= e(implode(', ', array_map(fn($t) => str_replace('_', ' ', $t), array_keys($truncated)))) ?>;
    <?= e(t('only the first ', 'ang unang ')) ?><?= number_format(SUMMARY_MAX) ?><?= e(t(' are included. Choose a shorter period.', ' lamang ang kasama. Pumili ng mas maikling panahon.')) ?>
  </div>
<?php endif; ?>

<?php if (!$isPrint): ?>
<?php if ($isOngoing): ?>
  <!-- A signed, printable document should never move under an admin's
       feet — figures here only ever change on an explicit refresh, never
       in place, and only shown at all when the period is still open. -->
  <div class="update-banner" id="update-banner" role="status">
    <span><?= e(t('New activity has been recorded for this period.', 'May bagong aktibidad na naitala sa panahong ito.')) ?></span>
    <a href="summary.php"><?= e(t('Refresh to include it', 'I-refresh para maisama')) ?></a>
  </div>
<?php endif; ?>
<section class="panel">
  <header class="panel-bar">
    <h2 class="panel-title"><?= e(t('Report Period:', 'Panahon ng Ulat:')) ?>
      <?php if ($isOngoing): ?>
        <span class="live-badge" id="live-badge" title="<?= e(t('This period is still open — watching for new activity', 'Bukas pa ang panahong ito — binabantayan ang bagong aktibidad')) ?>">
          <span class="live-dot" aria-hidden="true"></span><span id="live-badge-text"><?= e(t('Watching', 'Nagbabantay')) ?></span>
        </span>
      <?php endif; ?>
    </h2>
    <form class="period-form" method="get">
      <label class="visually-hidden" for="from"><?= e(t('From', 'Mula')) ?></label>
      <input type="date" id="from" name="from" value="<?= e($from->format('Y-m-d')) ?>">
      <span class="period-dash"><?= e(t('to', 'hanggang')) ?></span>
      <label class="visually-hidden" for="to"><?= e(t('To', 'Hanggang')) ?></label>
      <input type="date" id="to" name="to" value="<?= e($to->format('Y-m-d')) ?>">
      <label class="visually-hidden" for="category"><?= e(t('Category', 'Kategorya')) ?></label>
      <select id="category" name="category">
        <option value=""><?= e(t('All Categories', 'Lahat ng Kategorya')) ?></option>
        <?php foreach (CATEGORIES as $c): ?>
          <option value="<?= e($c) ?>" <?= $category === $c ? 'selected' : '' ?>>
            <?= e(category_label($c)) ?>
          </option>
        <?php endforeach; ?>
      </select>
      <button class="btn-period" type="submit"><?= e(t('Apply', 'Ilapat')) ?></button>
    </form>
    <div class="quick-ranges">
      <?php foreach ($RANGES as $key => [$lbl, $a, $b]): ?>
        <a class="chip-filter<?= $range === $key ? ' is-on' : '' ?>"
           href="?range=<?= e($key) ?>&amp;category=<?= e($category) ?>"><?= e($lbl) ?></a>
      <?php endforeach; ?>
    </div>

    <a class="btn-pdf" target="_blank" rel="noopener"
       href="summary.php?print=1&amp;from=<?= e($from->format('Y-m-d')) ?>&amp;to=<?= e($to->format('Y-m-d')) ?>&amp;category=<?= e($category) ?>">
      <?= e(t('Download PDF Report', 'I-download ang PDF na Ulat')) ?>
    </a>
  </header>

  <div class="tile-row">
    <div class="tile"><strong><?= str_pad((string) $total, 2, '0', STR_PAD_LEFT) ?></strong><span><?= e(t('Total Reports Logged', 'Kabuuang Naitalang Ulat')) ?></span></div>
    <div class="tile"><strong><?= str_pad((string) $resolved, 2, '0', STR_PAD_LEFT) ?></strong><span><?= e(t('Case Resolved', 'Nalutas na Kaso')) ?></span></div>
    <div class="tile"><strong><?= $rate === null ? '—' : $rate . '%' ?></strong><span><?= e(t('Tanod Attendance Rate', 'Antas ng Pagdalo ng Tanod')) ?></span></div>
    <div class="tile"><strong><?= $avgDays === null ? '—' : $avgDays . t(' days', ' araw') ?></strong><span><?= e(t('Average Resolution Time', 'Karaniwang Tagal ng Paglutas')) ?></span></div>
  </div>
</section>
<?php else: ?>
  <div class="doc-tiles">
    <span><strong><?= $total ?></strong> reports logged</span>
    <span><strong><?= $resolved ?></strong> resolved</span>
    <span><strong><?= $rate === null ? 'n/a' : $rate . '%' ?></strong> tanod attendance</span>
    <span><strong><?= $avgDays === null ? 'n/a' : $avgDays . ' days' ?></strong> average resolution</span>
  </div>
<?php endif; ?>

<!-- ---------- Resident Report Ledger ---------- -->
<section class="panel doc-block">
  <h2 class="doc-h"><?= e(t('Resident Report Ledger', 'Talaan ng mga Ulat ng Residente')) ?></h2>
  <div class="table-wrap">
    <table class="case-table doc-table doc-table--orange">
      <thead>
        <tr>
          <th><?= e(t('Complaint ID', 'ID ng Sumbong')) ?></th><th><?= e(t('Resident', 'Residente')) ?></th><th><?= e(t('Category', 'Kategorya')) ?></th>
          <th><?= e(t('Status', 'Katayuan')) ?></th><th><?= e(t('Filed', 'Naisampa')) ?></th><th><?= e(t('Resolved', 'Nalutas')) ?></th>
        </tr>
      </thead>
      <tbody>
        <?php if (!$reports): ?>
          <tr class="row-empty"><td colspan="6"><?= e(t('No complaints were filed in this period.', 'Walang naisampang sumbong sa panahong ito.')) ?></td></tr>
        <?php endif; ?>
        <?php foreach ($reports as $r): ?>
          <tr>
            <td class="mono"><?= e($r['tracking_id']) ?></td>
            <td><?= !empty($r['is_anonymous'])
                    ? '<em class="anon">' . e(t('Anonymous', 'Hindi nagpakilala')) . '</em>'
                    : e($r['resident']['full_name'] ?? t('Unknown', 'Hindi kilala')) ?></td>
            <td><?= e(category_label($r['category'])) ?></td>
            <td><?= e(status_label($r['status'])) ?><?= ($r['escalation_level'] ?? 0) > 0 ? e(t(' (escalated)', ' (na-escalate)')) : '' ?></td>
            <td><?= e(short_date($r['created_at'])) ?></td>
            <td><?= e(short_date($r['resolved_at'] ?? $r['closed_at'] ?? null)) ?: '—' ?></td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</section>

<!-- ---------- Tanod's Activity Timeline ---------- -->
<section class="panel doc-block">
  <h2 class="doc-h"><?= t('Tanod&rsquo;s Activity Timeline', 'Takbo ng Gawain ng mga Tanod') ?></h2>
  <div class="table-wrap">
    <table class="case-table doc-table doc-table--navy">
      <thead>
        <tr><th>Tanod</th><th><?= e(t('Complaint', 'Sumbong')) ?></th><th><?= e(t('Assigned', 'Na-assign')) ?></th><th><?= e(t('Accepted', 'Tinanggap')) ?></th><th><?= e(t('Outcome', 'Kinalabasan')) ?></th></tr>
      </thead>
      <tbody>
        <?php if (!$dispatches): ?>
          <tr class="row-empty"><td colspan="5"><?= e(t('No dispatches were issued in this period.', 'Walang dispatch na inilabas sa panahong ito.')) ?></td></tr>
        <?php endif; ?>
        <?php foreach ($dispatches as $d): ?>
          <tr>
            <td><?= e($d['tanod']['full_name'] ?? t('Unknown', 'Hindi kilala')) ?></td>
            <td class="mono"><?= e($d['report']['tracking_id'] ?? '—') ?></td>
            <td><?= e(long_datetime($d['assigned_at'])) ?></td>
            <td><?= $d['accepted_at'] ? e(long_datetime($d['accepted_at'])) : e(t('Not accepted', 'Hindi tinanggap')) ?></td>
            <td><?= e(status_label($d['state'])) ?></td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</section>

<!-- ---------- Report Case Timeline ---------- -->
<section class="panel doc-block">
  <h2 class="doc-h"><?= e(t('Report Case Timeline', 'Takbo ng mga Kaso')) ?></h2>
  <div class="table-wrap">
    <table class="case-table doc-table doc-table--orange">
      <thead>
        <tr><th><?= e(t('When', 'Kailan')) ?></th><th><?= e(t('Complaint', 'Sumbong')) ?></th><th><?= e(t('Change', 'Pagbabago')) ?></th><th><?= e(t('Remark', 'Puna')) ?></th><th><?= e(t('By', 'Ni')) ?></th></tr>
      </thead>
      <tbody>
        <?php if (!$logs): ?>
          <tr class="row-empty"><td colspan="5"><?= e(t('No case activity was recorded in this period.', 'Walang naitalang aktibidad sa kaso sa panahong ito.')) ?></td></tr>
        <?php endif; ?>
        <?php foreach ($logs as $l): ?>
          <tr>
            <td><?= e(long_datetime($l['created_at'])) ?></td>
            <td class="mono"><?= e($l['report']['tracking_id'] ?? '—') ?></td>
            <td><?= e(timeline_title($l)) ?></td>
            <td><?= e($l['remark'] ?? '') ?><?php if (($l['repeat'] ?? 1) > 1): ?> <span class="muted">× <?= (int) $l['repeat'] ?></span><?php endif; ?></td>
            <td><?= !empty($l['is_system']) ? e(t('System', 'System')) : e($l['by']['full_name'] ?? t('Barangay staff', 'Kawani ng barangay')) ?></td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</section>

<?php if ($isPrint): ?>
  <div class="doc-sign">
    <div class="sign-slot">
      <span class="sign-rule"></span>
      <span class="sign-name">Prepared by: <?= e($admin['full_name']) ?></span>
      <span class="sign-role">Barangay Administrator</span>
    </div>
    <div class="sign-slot">
      <span class="sign-rule"></span>
      <span class="sign-name">Noted by</span>
      <span class="sign-role">Punong Barangay</span>
    </div>
  </div>
  <p class="doc-date"><?= e((new DateTimeImmutable('now', $tz))->format('n.j.Y')) ?></p>
  </div><!-- /doc -->
  <script>window.addEventListener('load', () => setTimeout(() => window.print(), 400));</script>
  </body></html>
<?php else: ?>
  <?php if ($isOngoing): ?>
  <script src="assets/vendor/supabase/supabase.js"></script>
  <script>
  // Realtime, 6 Sep 2026 — only wired up for an open period (see
  // $isOngoing above). This report is meant to be printed and signed, so
  // unlike cases.php/dashboard.php it never rewrites its own figures —
  // it only tells the admin new activity exists and lets them choose to
  // reload with it included, the same non-destructive idiom case.php and
  // accounts.php use. attendance is not in the supabase_realtime
  // publication, so the Tanod Attendance Rate tile isn't watched here —
  // only reports/dispatches/status_logs are.
  (function () {
    if (!window.supabase) { return; }
    const { createClient } = supabase;
    const TOKEN = <?= json_encode(access_token()) ?>;
    const sb = createClient(
      <?= json_encode(supabase_url()) ?>,
      <?= json_encode(supabase_key()) ?>,
      { global: { headers: { Authorization: 'Bearer ' + TOKEN } },
        auth: { persistSession: false, autoRefreshToken: false } }
    );
    sb.realtime.setAuth(TOKEN);

    sb.channel('summary-period')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'reports' },
        function () { document.getElementById('update-banner').classList.add('is-shown'); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'dispatches' },
        function () { document.getElementById('update-banner').classList.add('is-shown'); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'status_logs' },
        function () { document.getElementById('update-banner').classList.add('is-shown'); })
      .subscribe(function (status) {
        var badge = document.getElementById('live-badge'),
            text  = document.getElementById('live-badge-text');
        if (!badge) return;
        if (status === 'SUBSCRIBED') { badge.classList.remove('is-down'); text.textContent = T('Watching', 'Nagbabantay'); }
        else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
          badge.classList.add('is-down'); text.textContent = T('Reconnecting…', 'Kumokonekta muli…');
        }
      });
  })();
  </script>
  <?php endif; ?>
  <?php layout_foot(); ?>
<?php endif; ?>

<?php
/**
 * The printable document. Letterhead first: seal left, Bagong Pilipinas
 * right, issuing body centred; then a ruled line carrying the report
 * name and the period, the way a paper carries name and section.
 */
function print_head(string $period, string $categoryLabel = 'All Categories'): void
{
    $img = fn(string $f) => is_file(__DIR__ . '/assets/img/' . $f) ? 'assets/img/' . $f : null;
    $seal = $img('brgy-183-seal.png');
    $bp   = $img('bagong-pilipinas.png');
    ?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Report Summary — <?= e($period) ?></title>
<link href="assets/css/fonts.css?v=<?= e(asset_version('fonts.css')) ?>" rel="stylesheet">
<link href="assets/css/app.css?v=<?= e(asset_version('app.css')) ?>" rel="stylesheet">
</head>
<body class="doc-body">
<div class="doc">

  <header class="doc-head">
    <?php if ($seal): ?><img class="doc-seal" src="<?= e($seal) ?>" alt=""><?php endif; ?>
    <div class="doc-org">
      <p>Republic of the Philippines</p>
      <p class="doc-org-main">CITY OF PASAY</p>
      <p>Barangay 183, Zone 20</p>
      <p>Villamor, Pasay City</p>
    </div>
    <?php if ($bp): ?><img class="doc-seal" src="<?= e($bp) ?>" alt=""><?php endif; ?>
  </header>

  <div class="doc-rule">
    <span class="doc-left">COMPLAINT REPORT SUMMARY</span>
    <span class="doc-right"><?= e($period) ?> &middot; <?= e($categoryLabel) ?></span>
  </div>

  <h1 class="doc-title">Smart Sumbong &mdash; Barangay Complaint Summary</h1>
<?php
}
