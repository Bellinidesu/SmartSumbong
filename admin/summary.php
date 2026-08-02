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
    'week'     => ['This week',  new DateTimeImmutable('monday this week', $tzq),        new DateTimeImmutable('now', $tzq)],
    'month'    => ['This month', new DateTimeImmutable('first day of this month', $tzq), new DateTimeImmutable('now', $tzq)],
    'last'     => ['Last month', new DateTimeImmutable('first day of last month', $tzq), new DateTimeImmutable('last day of last month', $tzq)],
    'quarter'  => ['Last 90 days', new DateTimeImmutable('-90 days', $tzq),              new DateTimeImmutable('now', $tzq)],
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

if (!$isPrint) {
    $_SESSION['summary_period'] = [
        'from' => $from->format('Y-m-d'),
        'to'   => $to->format('Y-m-d'),
    ];
}

// ---------- data ----------
$error = null;
$reports = $dispatches = $logs = $attendance = [];

try {
    $reports = $db->select('reports', [
        'select'     => 'id,tracking_id,subject,category,status,is_anonymous,created_at,'
                      . 'due_at,resolved_at,closed_at,escalation_level,'
                      . 'resident:users!reports_resident_id_fkey(full_name)',
        'deleted_at' => 'is.null',
        'and'        => "(created_at.gte.{$fromISO},created_at.lte.{$toISO})",
        'order'      => 'created_at.asc',
        'limit'      => '500',
    ]);

    $dispatches = $db->select('dispatches', [
        'select'      => 'id,state,assigned_at,accepted_at,resolved_at,field_report_text,'
                       . 'tanod:users!dispatches_tanod_id_fkey(full_name),'
                       . 'report:reports!dispatches_report_id_fkey(tracking_id)',
        'and'         => "(assigned_at.gte.{$fromISO},assigned_at.lte.{$toISO})",
        'order'       => 'assigned_at.asc',
        'limit'       => '500',
    ]);

    $logs = $db->select('status_logs', [
        'select'     => 'id,old_status,new_status,remark,is_system,created_at,'
                      . 'report:reports!status_logs_report_id_fkey(tracking_id),'
                      . 'by:users!status_logs_changed_by_fkey(full_name)',
        'and'        => "(created_at.gte.{$fromISO},created_at.lte.{$toISO})",
        'order'      => 'created_at.desc',
        'limit'      => '300',
    ]);

    $attendance = $db->select('attendance', [
        'select' => 'id,tanod_id,duty_status,shift_date',
        'and'    => "(logged_at.gte.{$fromISO},logged_at.lte.{$toISO})",
        'limit'  => '1000',
    ]);
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

if (!$isPrint) { layout_head('Report Summary', 'summary.php'); }
else { print_head($periodLabel); }
?>

<?php if ($error): ?>
  <div class="alert-bar" role="alert"><?= e($error) ?></div>
<?php endif; ?>

<?php if (!$isPrint): ?>
<section class="panel">
  <header class="panel-bar">
    <h2 class="panel-title">Report Period:</h2>
    <form class="period-form" method="get">
      <label class="visually-hidden" for="from">From</label>
      <input type="date" id="from" name="from" value="<?= e($from->format('Y-m-d')) ?>">
      <span class="period-dash">to</span>
      <label class="visually-hidden" for="to">To</label>
      <input type="date" id="to" name="to" value="<?= e($to->format('Y-m-d')) ?>">
      <button class="btn-period" type="submit">Apply</button>
    </form>
    <div class="quick-ranges">
      <?php foreach ($RANGES as $key => [$lbl, $a, $b]): ?>
        <a class="chip-filter<?= $range === $key ? ' is-on' : '' ?>"
           href="?range=<?= e($key) ?>"><?= e($lbl) ?></a>
      <?php endforeach; ?>
    </div>

    <a class="btn-pdf" target="_blank" rel="noopener"
       href="summary.php?print=1&amp;from=<?= e($from->format('Y-m-d')) ?>&amp;to=<?= e($to->format('Y-m-d')) ?>">
      Download PDF Report
    </a>
  </header>

  <div class="tile-row">
    <div class="tile"><strong><?= str_pad((string) $total, 2, '0', STR_PAD_LEFT) ?></strong><span>Total Reports Logged</span></div>
    <div class="tile"><strong><?= str_pad((string) $resolved, 2, '0', STR_PAD_LEFT) ?></strong><span>Case Resolved</span></div>
    <div class="tile"><strong><?= $rate === null ? '—' : $rate . '%' ?></strong><span>Tanod Attendance Rate</span></div>
    <div class="tile"><strong><?= $avgDays === null ? '—' : $avgDays . ' days' ?></strong><span>Average Resolution Time</span></div>
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
  <h2 class="doc-h">Resident Report Ledger</h2>
  <div class="table-wrap">
    <table class="case-table doc-table">
      <thead>
        <tr>
          <th>Complaint ID</th><th>Resident</th><th>Category</th>
          <th>Status</th><th>Filed</th><th>Resolved</th>
        </tr>
      </thead>
      <tbody>
        <?php if (!$reports): ?>
          <tr class="row-empty"><td colspan="6">No complaints were filed in this period.</td></tr>
        <?php endif; ?>
        <?php foreach ($reports as $r): ?>
          <tr>
            <td class="mono"><?= e($r['tracking_id']) ?></td>
            <td><?= !empty($r['is_anonymous'])
                    ? '<em class="anon">Anonymous</em>'
                    : e($r['resident']['full_name'] ?? 'Unknown') ?></td>
            <td><?= e(category_label($r['category'])) ?></td>
            <td><?= e(status_label($r['status'])) ?><?= ($r['escalation_level'] ?? 0) > 0 ? ' (escalated)' : '' ?></td>
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
  <h2 class="doc-h">Tanod&rsquo;s Activity Timeline</h2>
  <div class="table-wrap">
    <table class="case-table doc-table">
      <thead>
        <tr><th>Tanod</th><th>Complaint</th><th>Assigned</th><th>Accepted</th><th>Outcome</th></tr>
      </thead>
      <tbody>
        <?php if (!$dispatches): ?>
          <tr class="row-empty"><td colspan="5">No dispatches were issued in this period.</td></tr>
        <?php endif; ?>
        <?php foreach ($dispatches as $d): ?>
          <tr>
            <td><?= e($d['tanod']['full_name'] ?? 'Unknown') ?></td>
            <td class="mono"><?= e($d['report']['tracking_id'] ?? '—') ?></td>
            <td><?= e(long_datetime($d['assigned_at'])) ?></td>
            <td><?= $d['accepted_at'] ? e(long_datetime($d['accepted_at'])) : 'Not accepted' ?></td>
            <td><?= e(status_label($d['state'])) ?></td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</section>

<!-- ---------- Report Case Timeline ---------- -->
<section class="panel doc-block">
  <h2 class="doc-h">Report Case Timeline</h2>
  <div class="table-wrap">
    <table class="case-table doc-table">
      <thead>
        <tr><th>When</th><th>Complaint</th><th>Change</th><th>Remark</th><th>By</th></tr>
      </thead>
      <tbody>
        <?php if (!$logs): ?>
          <tr class="row-empty"><td colspan="5">No case activity was recorded in this period.</td></tr>
        <?php endif; ?>
        <?php foreach ($logs as $l): ?>
          <tr>
            <td><?= e(long_datetime($l['created_at'])) ?></td>
            <td class="mono"><?= e($l['report']['tracking_id'] ?? '—') ?></td>
            <td><?= e(timeline_title($l)) ?></td>
            <td><?= e($l['remark'] ?? '') ?></td>
            <td><?= !empty($l['is_system']) ? 'System' : e($l['by']['full_name'] ?? 'Barangay staff') ?></td>
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
  <?php layout_foot(); ?>
<?php endif; ?>

<?php
/**
 * The printable document. Letterhead first: seal left, Bagong Pilipinas
 * right, issuing body centred; then a ruled line carrying the report
 * name and the period, the way a paper carries name and section.
 */
function print_head(string $period): void
{
    $img = fn(string $f) => is_file(__DIR__ . '/assets/img/' . $f) ? 'assets/img/' . $f : null;
    $seal = $img('brgy-183-seal.png');
    $bp   = $img('bagong-pilipinas.png');
    ?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Report Summary — <?= e($period) ?></title>
<link href="assets/css/fonts.css" rel="stylesheet">
<link href="assets/css/app.css" rel="stylesheet">
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
    <span class="doc-right"><?= e($period) ?></span>
  </div>

  <h1 class="doc-title">Smart Sumbong &mdash; Barangay Complaint Summary</h1>
<?php
}
