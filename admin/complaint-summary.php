<?php
/**
 * Barangay Complaint Summary — the barangay's own monthly form, in the
 * updated format Rose gave at the mock defense (2 Oct 2026), and what
 * Report Summary's Download PDF produces:
 *
 *   Table, one row per category plus Others and Total:
 *     Reports Received              filed in the month
 *     Resolution Efficiency         resolved of received
 *     Average Resolution Time       filing to resolution, resolved ones
 *     Number of Overdue Cases       past the admin's target date — still
 *                                   open, or resolved after it
 *   Escalated / Out of Jurisdiction the month's complaints sent to an
 *                                   outside office
 *   Diagrams                        resolution rate, and tanod attendance
 *                                   (on duty vs offline, from the duty log
 *                                   0075 started), last month vs this
 *
 * "Resolved" is resolved, closed or archived — not rejected, cancelled or
 * escalated to an outside office (those are not the barangay's to resolve).
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/doc_print.php';

$admin = require_admin();
$db    = db();
$tz    = new DateTimeZone('Asia/Manila');

$monthParam = (string) ($_GET['month'] ?? '');
if (!preg_match('/^\d{4}-\d{2}$/', $monthParam)) {
    $monthParam = (new DateTimeImmutable('now', $tz))->format('Y-m');
}
$start     = new DateTimeImmutable($monthParam . '-01 00:00:00', $tz);
$end       = $start->modify('first day of next month');
$prevStart = $start->modify('first day of last month');
$by        = trim((string) ($_GET['by'] ?? formal_name($admin['full_name'] ?? '')));

// The form's own names and order; "Others" catches anything outside the seven.
const FORM_CATEGORIES = [
    'street_obstruction'           => 'Street Obstruction',
    'public_safety_infrastructure' => 'Public Safety and Infrastructure',
    'environmental_waste_hazard'   => 'Environmental and Waste Hazards',
    'animal_welfare'               => 'Animal Welfare',
    'traffic_violation'            => 'Traffic Violation',
    'barangay_service'             => 'Barangay Service',
    'peace_order_nuisance'         => 'Peace, Order, & Nuisance',
    'other'                        => 'Others',
];

/** Per form category: received, resolved, timed, hours, overdue, escalated. */
function tally(array $rows): array
{
    $t = [];
    foreach (array_keys(FORM_CATEGORIES) as $k) {
        $t[$k] = ['received' => 0, 'resolved' => 0, 'timed' => 0, 'hours' => 0.0, 'overdue' => 0, 'escalated' => 0];
    }
    foreach ($rows as $r) {
        $k = isset(FORM_CATEGORIES[$r['category']]) ? $r['category'] : 'other';
        $t[$k]['received']++;
        if (!empty($r['referred_to'])) {
            $t[$k]['escalated']++;
            continue;   // the outside office's to resolve, not the barangay's
        }
        $done     = in_array($r['status'], ['resolved', 'closed', 'archived'], true);
        $finished = $r['resolved_at'] ?? $r['closed_at'] ?? null;
        // Overdue: still open past the target date, or resolved after it.
        if (report_is_overdue($r)
            || ($done && $finished && !empty($r['due_at']) && strtotime($finished) > strtotime($r['due_at']))) {
            $t[$k]['overdue']++;
        }
        if (!$done) {
            continue;
        }
        $t[$k]['resolved']++;
        if ($finished) {
            $t[$k]['timed']++;
            $t[$k]['hours'] += max(0, (strtotime($finished) - strtotime($r['created_at'])) / 3600);
        }
    }
    return $t;
}

/** Hours, as the form reads them: "5.2 hrs" or "3.1 days". */
function form_duration(float $h): string
{
    return $h < 48 ? number_format($h, 1) . ' hrs' : number_format($h / 24, 1) . ' days';
}

/**
 * Tanod time on duty vs offline in [from, to), summed over every tanod,
 * from the duty-status log (each row lasts until that tanod's next one).
 * Break and lunch are part of a shift, so they count as on duty.
 *
 * @return array{on: float, off: float}
 */
function duty_hours(array $logs, int $from, int $to): array
{
    $out = ['on' => 0.0, 'off' => 0.0];
    $by  = [];
    foreach ($logs as $l) {
        $by[$l['tanod_id']][] = $l;
    }
    $now = time();
    foreach ($by as $rows) {
        foreach ($rows as $i => $l) {
            $a = strtotime($l['logged_at']);
            $b = isset($rows[$i + 1]) ? strtotime($rows[$i + 1]['logged_at']) : $now;
            $a = max($a, $from); $b = min($b, $to, $now);
            if ($b <= $a) continue;
            $out[$l['duty_status'] === 'offline' ? 'off' : 'on'] += ($b - $a) / 3600;
        }
    }
    return $out;
}

function rate(array $c): ?float
{
    return $c['received'] > 0 ? $c['resolved'] / $c['received'] * 100 : null;
}

$error = null;
$now = $prev = [];
$duty = ['now' => ['on' => 0.0, 'off' => 0.0], 'prev' => ['on' => 0.0, 'off' => 0.0]];
try {
    $got  = $db->selectMany([
        'now'  => ['reports', [
            'select'     => 'category,status,created_at,resolved_at,closed_at,due_at,referred_to',
            'deleted_at' => 'is.null',
            'and'        => '(created_at.gte.' . $start->format(DateTimeInterface::ATOM)
                          . ',created_at.lt.' . $end->format(DateTimeInterface::ATOM) . ')',
            'limit'      => '10000',
        ]],
        'att' => ['attendance', [
            'select'    => 'tanod_id,duty_status,logged_at',
            'logged_at' => 'lt.' . $end->format(DateTimeInterface::ATOM),
            'order'     => 'tanod_id.asc,logged_at.asc',
            'limit'     => '20000',
        ]],
        'prev' => ['reports', [
            'select'     => 'category,status,created_at,resolved_at,closed_at,due_at,referred_to',
            'deleted_at' => 'is.null',
            'and'        => '(created_at.gte.' . $prevStart->format(DateTimeInterface::ATOM)
                          . ',created_at.lt.' . $start->format(DateTimeInterface::ATOM) . ')',
            'limit'      => '10000',
        ]],
    ]);
    $now  = tally($got['now']);
    $prev = tally($got['prev']);
    $duty = [
        'prev' => duty_hours($got['att'], $prevStart->getTimestamp(), $start->getTimestamp()),
        'now'  => duty_hours($got['att'], $start->getTimestamp(), $end->getTimestamp()),
    ];
} catch (SupabaseError $ex) {
    $error = safe_error($ex);
}

$monthName = $start->format('F');
$year      = $start->format('Y');
$prevName  = $prevStart->format('F');
$sum       = ['received' => 0, 'resolved' => 0, 'timed' => 0, 'hours' => 0.0, 'overdue' => 0, 'escalated' => 0];
foreach ($now as $c) {
    foreach ($sum as $f => $_) { $sum[$f] += $c[$f]; }
}

doc_head('Barangay Complaint Summary', true);
$pct   = fn(array $c) => $c['received'] ? (int) round($c['resolved'] / $c['received'] * 100) . '%' : '—';
$psum  = ['received' => 0, 'resolved' => 0];
foreach ($prev as $c) { $psum['received'] += $c['received']; $psum['resolved'] += $c['resolved']; }
$dutyPct = fn(array $d) => ($d['on'] + $d['off']) > 0 ? (int) round($d['on'] / ($d['on'] + $d['off']) * 100) . '%' : '—';
?>
<header class="cd-bar">
  <a class="cd-back" href="summary.php">&lsaquo; Report Summary</a>
  <span class="cd-crumb"><a href="summary.php">Report Summary</a> &rsaquo; <b>Barangay Complaint Summary</b></span>
  <span class="cd-sp"></span>
  <span class="cd-state ok" id="cd-state"><?= e($monthName . ' ' . $year) ?></span>
  <button class="cd-btn" id="cd-print" type="button">Print / Save as PDF</button>
</header>

<div class="cd-work">
  <section class="cd-desk" id="cd-desk" aria-label="Complaint summary">
    <div class="cd-stage"><div class="cd-wrap cd-flow">

<div class="doc-page">
  <?php doc_letterhead(); ?>
  <p class="doc-title">Barangay Complaint Summary</p>

  <?php if ($error): ?>
    <p style="color:#a01818"><?= e($error) ?></p>
  <?php else: ?>
  <p style="margin:0 0 14px 0.6in">In the month of <span class="fill"><?= e($monthName) ?></span> of <span class="fill"><?= e($year) ?></span>,</p>

  <style>
    .form-table { width: 100%; border-collapse: collapse; margin-bottom: 0.3in; font-size: 12pt; }
    .form-table td { border: 1px solid var(--line); padding: 2px 8px; vertical-align: top; }
    .form-table.grid { font-size: 10.5pt; }
    .form-table.grid td { padding: 4px 7px; vertical-align: middle; }
    .form-table.grid td:first-child { width: 30%; }
    .form-table .head td { font-weight: 700; text-align: center; background: #eef1f7; }
    .form-table .total td { font-weight: 700; background: #f6f7fa; }
    .form-table td.num { font-variant-numeric: tabular-nums; text-align: center; }
    .form-table small { font-size: 85%; color: var(--muted); font-weight: 400; }
    .form-table.esc td { padding: 8px 10px; vertical-align: middle; }
    .form-table.esc td.big { width: 1.1in; font-size: 16pt; font-weight: 700; }
    .pies { display: grid; grid-template-columns: 1fr 1fr; gap: 0.3in; margin-top: 4px; text-align: center; font-size: 10.5pt; }
    .pies b { display: block; margin-bottom: 4px; }
    .pies .none { color: var(--muted); font-style: italic; margin: 4px 0 0; }
    .chart-block { break-inside: avoid; margin-top: 0.2in; }
    .chart-title { text-align: center; font-weight: 700; margin: 0.1in 0 6px; }
    .chart-legend { display: flex; justify-content: center; gap: 22px; font-size: 10.5pt; margin-top: 4px; }
    .chart-legend span::before { content: ""; display: inline-block; width: 12px; height: 12px; margin-right: 6px; vertical-align: -1px; background: var(--c); }
  </style>

  <table class="form-table grid">
    <tr class="head">
      <td>Category</td><td>Reports Received</td><td>Resolution Efficiency</td>
      <td>Average Resolution Time</td><td>Number of Overdue Cases</td>
    </tr>
    <?php foreach (FORM_CATEGORIES + ['__total' => 'Total'] as $k => $label):
      $c = $k === '__total' ? $sum : $now[$k]; $r = rate($c); ?>
      <tr<?= $k === '__total' ? ' class="total"' : '' ?>>
        <td><?= e($label) ?></td>
        <td class="num"><?= $c['received'] ?></td>
        <td class="num"><?= $r === null ? '—' : (int) round($r) . '% <small>(' . $c['resolved'] . ' of ' . $c['received'] . ')</small>' ?></td>
        <td class="num"><?= $c['timed'] ? e(form_duration($c['hours'] / $c['timed'])) : '—' ?></td>
        <td class="num"><?= $c['overdue'] ?></td>
      </tr>
    <?php endforeach; ?>
  </table>

  <table class="form-table esc">
    <tr>
      <td>Total Number of Escalated/Out of Jurisdiction Cases <small>(under Katarungang Pambarangay,
        Criminal Offense, VAWC-Related, Public Officer Grievances, Outside the boundary of Barangay 183)</small></td>
      <td class="num big"><?= $sum['escalated'] ?></td>
    </tr>
  </table>

  <?php
  // Resolution rate, last month vs this month, per category (the form's
  // "diagram"). Inline SVG so it prints exactly as it shows.
  $W = 640; $H = 230; $left = 34; $bottom = 60; $top = 16;
  $plotW = $W - $left - 8; $plotH = $H - $bottom - $top;
  $cats  = array_keys(FORM_CATEGORIES);
  $slot  = $plotW / count($cats);
  $barW  = min(22, $slot / 3);
  $y     = fn(float $pct) => $top + $plotH * (1 - $pct / 100);
  ?>
  <p class="chart-title">Resolution rate: <?= e($prevName) ?> vs <?= e($monthName) ?></p>
  <svg viewBox="0 0 <?= $W ?> <?= $H ?>" width="100%" role="img"
       aria-label="Resolution rate per category, <?= e($prevName) ?> compared with <?= e($monthName) ?>">
    <?php foreach ([0, 25, 50, 75, 100] as $g): ?>
      <line x1="<?= $left ?>" x2="<?= $W - 8 ?>" y1="<?= $y($g) ?>" y2="<?= $y($g) ?>" stroke="#ccc" stroke-width="0.6"/>
      <text x="<?= $left - 4 ?>" y="<?= $y($g) + 3 ?>" font-size="9" text-anchor="end" fill="#555"><?= $g ?>%</text>
    <?php endforeach; ?>
    <?php foreach ($cats as $i => $k):
      $cx = $left + $slot * $i + $slot / 2;
      foreach ([[$prev[$k], -1, '#9fb4dd'], [$now[$k], 1, '#00308f']] as [$c, $side, $fill]):
        $r = rate($c);
        $x = $side < 0 ? $cx - $barW - 1 : $cx + 1;
        if ($r === null): ?>
          <text x="<?= $x + $barW / 2 ?>" y="<?= $y(0) - 3 ?>" font-size="8" text-anchor="middle" fill="#888">–</text>
        <?php else: ?>
          <rect x="<?= $x ?>" y="<?= $y($r) ?>" width="<?= $barW ?>" height="<?= max(0.5, $y(0) - $y($r)) ?>" fill="<?= $fill ?>"/>
          <text x="<?= $x + $barW / 2 ?>" y="<?= $y($r) - 3 ?>" font-size="8" text-anchor="middle" fill="#222"><?= (int) round($r) ?></text>
        <?php endif;
      endforeach;
      $words = explode(' ', str_replace(', &', ',&', FORM_CATEGORIES[$k]));
      $lines = []; $line = '';
      foreach ($words as $w) {
          if (strlen($line . ' ' . $w) > 13 && $line !== '') { $lines[] = $line; $line = $w; }
          else { $line = trim($line . ' ' . $w); }
      }
      $lines[] = $line;
      foreach ($lines as $li => $txt): ?>
        <text x="<?= $cx ?>" y="<?= $y(0) + 12 + $li * 10 ?>" font-size="8.5" text-anchor="middle" fill="#222"><?= e(str_replace(',&', ', &', $txt)) ?></text>
      <?php endforeach;
    endforeach; ?>
    <line x1="<?= $left ?>" x2="<?= $W - 8 ?>" y1="<?= $y(0) ?>" y2="<?= $y(0) ?>" stroke="#222" stroke-width="0.8"/>
  </svg>
  <div class="chart-legend">
    <span style="--c:#9fb4dd"><?= e($prevName) ?></span>
    <span style="--c:#00308f"><?= e($monthName) ?></span>
  </div>

  <div class="chart-block">
  <p class="chart-title">Tanod attendance rate: <?= e($prevName) ?> vs <?= e($monthName) ?></p>
  <div class="pies">
    <?php foreach ([[$prevName, $duty['prev']], [$monthName, $duty['now']]] as [$label, $d]):
      $tot = $d['on'] + $d['off']; ?>
      <div>
        <b><?= e($label) ?></b>
        <?php if ($tot <= 0): ?>
          <svg viewBox="0 0 120 120" width="150"><circle cx="60" cy="60" r="54" fill="#eee" stroke="#ccc"/></svg>
          <p class="none">No duty logged in <?= e($label) ?></p>
        <?php else:
          $pOn = $d['on'] / $tot;
          if ($pOn >= 0.9999 || $pOn <= 0.0001): ?>
            <svg viewBox="0 0 120 120" width="150"><circle cx="60" cy="60" r="54" fill="<?= $pOn > 0.5 ? '#00308f' : '#bdbdbd' ?>"/></svg>
          <?php else:
            $ang = $pOn * 2 * M_PI;
            $x = 60 + 54 * sin($ang); $y = 60 - 54 * cos($ang); $big = $pOn > 0.5 ? 1 : 0; ?>
            <svg viewBox="0 0 120 120" width="150">
              <circle cx="60" cy="60" r="54" fill="#bdbdbd"/>
              <path d="M60 60 L60 6 A54 54 0 <?= $big ?> 1 <?= round($x, 2) ?> <?= round($y, 2) ?> Z" fill="#00308f"/>
            </svg>
          <?php endif; ?>
          <div class="chart-legend">
            <span style="--c:#00308f">On duty <?= (int) round($pOn * 100) ?>%</span>
            <span style="--c:#bdbdbd">Offline <?= 100 - (int) round($pOn * 100) ?>%</span>
          </div>
        <?php endif; ?>
      </div>
    <?php endforeach; ?>
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

  <aside class="cd-insp" aria-label="Summary details">
    <div class="cd-sec"><h2>Ready to print <span class="cd-count wait" id="cd-cnt"></span></h2><div class="cd-chk" id="cd-chk"></div></div>
    <form class="cd-sec" method="get" id="cd-form"><h2>Report</h2>
      <div class="cd-field"><label for="f-month">Month</label><input id="f-month" name="month" type="month" value="<?= e($monthParam) ?>" max="<?= e((new DateTimeImmutable('now', $tz))->format('Y-m')) ?>"></div>
      <div class="cd-field"><label for="f-by">Requested by</label><input id="f-by" name="by" value="<?= e($by) ?>" autocomplete="off"></div>
    </form>
    <?php if (!$error): ?>
    <div class="cd-sec"><h2><?= e($monthName) ?> at a glance</h2>
      <div class="cd-tiles">
        <div class="cd-tile"><b><?= $sum['received'] ?></b><span>Received</span></div>
        <div class="cd-tile"><b><?= e($pct($sum)) ?></b><span>Resolved (<?= $sum['resolved'] ?>)</span></div>
        <div class="cd-tile"><b><?= $sum['overdue'] ?></b><span>Overdue</span></div>
        <div class="cd-tile"><b><?= $sum['escalated'] ?></b><span>Escalated</span></div>
      </div>
    </div>
    <div class="cd-sec"><h2>Compared with <?= e($prevName) ?></h2>
      <div class="cd-row"><span>Received</span><b class="prev"><?= $psum['received'] ?></b><span class="cd-arrow">&rarr;</span><b><?= $sum['received'] ?></b></div>
      <div class="cd-row"><span>Resolution rate</span><b class="prev"><?= e($pct($psum)) ?></b><span class="cd-arrow">&rarr;</span><b><?= e($pct($sum)) ?></b></div>
      <div class="cd-row"><span>Tanod on duty</span><b class="prev"><?= e($dutyPct($duty['prev'])) ?></b><span class="cd-arrow">&rarr;</span><b><?= e($dutyPct($duty['now'])) ?></b></div>
    </div>
    <?php endif; ?>
  </aside>
</div>

<script>
(function () {
  var $ = function (id) { return document.getElementById(id); };
  // Month reloads the figures; Requested by fills in live.
  $('f-month').addEventListener('change', function () { if ($('f-month').value) $('cd-form').submit(); });
  function render() {
    var by = $('f-by').value.trim();
    document.querySelectorAll('.req .fill').forEach(function (el) { el.textContent = by || 'Name of Requestor'; el.classList.toggle('cd-empty', !by); });
    var checks = [['Report month', !!$('f-month').value], ['Requested by', !!by]];
    var done = checks.filter(function (c) { return c[1]; }).length, ready = done === checks.length;
    $('cd-chk').innerHTML = checks.map(function (c) { return '<div class="' + (c[1] ? 'y' : 'n') + '"><i>' + (c[1] ? '&#10003;' : '') + '</i>' + c[0] + '</div>'; }).join('');
    $('cd-cnt').textContent = done + ' of ' + checks.length; $('cd-cnt').className = 'cd-count ' + (ready ? 'ok' : 'wait');
    $('cd-print').disabled = !ready;
  }
  $('f-by').addEventListener('input', render);
  $('cd-print').onclick = function () { window.print(); };

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
