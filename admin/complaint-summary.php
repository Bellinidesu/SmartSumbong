<?php
/**
 * Barangay Complaint Summary — the barangay's own monthly form (Rose,
 * 30 Sep 2026), and what Report Summary's Download PDF now produces: the
 * dashboard's figures for one month, per category, with this month's
 * resolution rate against last month's.
 *
 *   Total Reports Received          filed in the month, per category
 *   Resolution Efficiency           resolved of received, average time to
 *                                   resolve, and how many met the admin's
 *                                   target date
 *   Diagram                         resolution rate, last month vs this
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
$by        = trim((string) ($_GET['by'] ?? ($admin['full_name'] ?? '')));

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

/** Per form category: received, resolved, on time, average hours. */
function tally(array $rows): array
{
    $t = [];
    foreach (array_keys(FORM_CATEGORIES) as $k) {
        $t[$k] = ['received' => 0, 'resolved' => 0, 'on_time' => 0, 'dated' => 0, 'hours' => 0.0];
    }
    foreach ($rows as $r) {
        $k = isset(FORM_CATEGORIES[$r['category']]) ? $r['category'] : 'other';
        $t[$k]['received']++;
        $done = in_array($r['status'], ['resolved', 'closed', 'archived'], true) && empty($r['referred_to']);
        if (!$done) {
            continue;
        }
        $t[$k]['resolved']++;
        $finished = $r['resolved_at'] ?? $r['closed_at'] ?? null;
        if ($finished) {
            $t[$k]['hours'] += max(0, (strtotime($finished) - strtotime($r['created_at'])) / 3600);
            if (!empty($r['due_at'])) {
                $t[$k]['dated']++;
                if (strtotime($finished) <= strtotime($r['due_at'])) {
                    $t[$k]['on_time']++;
                }
            }
        }
    }
    return $t;
}

function rate(array $c): ?float
{
    return $c['received'] > 0 ? $c['resolved'] / $c['received'] * 100 : null;
}

$error = null;
$now = $prev = [];
try {
    $got  = $db->selectMany([
        'now'  => ['reports', [
            'select'     => 'category,status,created_at,resolved_at,closed_at,due_at,referred_to',
            'deleted_at' => 'is.null',
            'and'        => '(created_at.gte.' . $start->format(DateTimeInterface::ATOM)
                          . ',created_at.lt.' . $end->format(DateTimeInterface::ATOM) . ')',
            'limit'      => '10000',
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
} catch (SupabaseError $ex) {
    $error = safe_error($ex);
}

$monthName = $start->format('F');
$year      = $start->format('Y');
$prevName  = $prevStart->format('F');
$total     = $now ? array_sum(array_column($now, 'received')) : 0;

doc_head('Barangay Complaint Summary');
?>
<form class="doc-toolbar" method="get">
  <a href="summary.php">&larr; Report Summary</a>
  <label>Month <input type="month" name="month" value="<?= e($monthParam) ?>"></label>
  <label>Requested by <input type="text" name="by" value="<?= e($by) ?>" size="24"></label>
  <button type="submit" formaction="complaint-summary.php" style="background:#fff;color:#00308f">Update</button>
  <span class="spacer"></span>
  <button type="button" onclick="window.print()">Print / Save as PDF</button>
</form>

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
    .form-table td:first-child { width: 38%; }
    .form-table .head td { font-weight: 700; }
    .form-table .cat td:first-child { padding-left: 0.65in; }
    .form-table td.num { font-variant-numeric: tabular-nums; }
    .chart-title { text-align: center; font-weight: 700; margin: 0.1in 0 6px; }
    .chart-legend { display: flex; justify-content: center; gap: 22px; font-size: 10.5pt; margin-top: 4px; }
    .chart-legend span::before { content: ""; display: inline-block; width: 12px; height: 12px; margin-right: 6px; vertical-align: -1px; background: var(--c); }
  </style>

  <table class="form-table">
    <tr class="head"><td>Total Reports Received</td><td class="num"><?= $total ?></td></tr>
    <?php foreach (FORM_CATEGORIES as $k => $label): ?>
      <tr class="cat"><td><?= e($label) ?></td><td class="num"><?= $now[$k]['received'] ?></td></tr>
    <?php endforeach; ?>
  </table>

  <table class="form-table">
    <tr class="head"><td colspan="2">Resolution Efficiency per Category</td></tr>
    <?php foreach (FORM_CATEGORIES as $k => $label): $c = $now[$k]; $r = rate($c); ?>
      <tr class="cat">
        <td><?= e($label) ?></td>
        <td class="num">
          <?php if ($c['received'] === 0): ?>
            No reports
          <?php else: ?>
            <?php
            $parts = [$c['resolved'] . ' of ' . $c['received'] . ' resolved (' . (int) round($r) . '%)'];
            if ($c['resolved'] > 0) { $parts[] = 'average ' . number_format($c['hours'] / $c['resolved'], 1) . ' h'; }
            if ($c['dated'] > 0)    { $parts[] = $c['on_time'] . ' of ' . $c['dated'] . ' on time'; }
            echo e(implode(' · ', $parts));
            ?>
          <?php endif; ?>
        </td>
      </tr>
    <?php endforeach; ?>
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
  <?php endif; ?>

  <?php doc_requested_by($by); ?>
</div>
</body>
</html>
