<?php
/**
 * Dashboard — Figma node 2:628.
 *
 * Six visuals off one screen: reports filed per day, three counters, the
 * resolution-status donut, the category donut, and resolution efficiency.
 * All six come from a single dashboard_metrics() call, so every figure on
 * screen was computed at the same instant against the same definitions.
 * Six separate queries would let the counters disagree with the donut.
 *
 * ONE DELIBERATE DEPARTURE FROM THE DESIGN, flagged rather than silent:
 * the third counter in the Figma reads "Emergency Case". The panel cut
 * emergency dispatch from scope — all three panelists, complaints only —
 * so there is no emergency anything in the schema to count. Leaving the
 * tile empty would look broken; inventing an emergency table would put
 * back scope that was removed. It counts overdue complaints instead,
 * which is the number an admin most needs at a glance. Say the word and
 * it becomes something else.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin();
$db    = db();

$tz = new DateTimeZone('Asia/Manila');

// The Figma's period control is a month. Anything unparseable falls back
// to the current one rather than erroring the whole screen.
$monthParam = (string) ($_GET['month'] ?? '');
try {
    $month = $monthParam !== ''
        ? new DateTimeImmutable($monthParam . '-01 00:00:00', $tz)
        : new DateTimeImmutable('first day of this month 00:00:00', $tz);
} catch (Exception) {
    $month = new DateTimeImmutable('first day of this month 00:00:00', $tz);
}
$month = $month->setDate((int) $month->format('Y'), (int) $month->format('n'), 1)
               ->setTime(0, 0);
$next  = $month->modify('+1 month');

$error   = null;
$metrics = null;

try {
    $metrics = $db->rpc('dashboard_metrics', [
        'p_from' => $month->format(DateTimeInterface::ATOM),
        'p_to'   => $next->format(DateTimeInterface::ATOM),
    ]);
    // Same call, previous month. A number on its own says nothing —
    // "31 complaints" is either a quiet month or a crisis depending on
    // what last month was. The comparison is what a kapitan reads.
    $prev = $db->rpc('dashboard_metrics', [
        'p_from' => $month->modify('-1 month')->format(DateTimeInterface::ATOM),
        'p_to'   => $month->format(DateTimeInterface::ATOM),
    ]);
} catch (SupabaseError $ex) {
    $error = safe_error($ex);
}

// rpc() hands back the decoded body; a json-returning function gives one
// object, not a row set.
$m = is_array($metrics) ? $metrics : [];

$daily      = $m['daily'] ?? [];
$efficiency = $m['efficiency'] ?? [];
$status     = $m['resolution_status'] ?? ['done' => 0, 'overdue' => 0, 'late' => 0, 'processing' => 0, 'rejected' => 0];
$categories = $m['categories'] ?? [];
$tiles      = $m['tiles'] ?? ['resolved' => 0, 'escalated' => 0, 'overdue' => 0];
$total      = (int) ($m['total'] ?? 0);

$statusTotal = array_sum(array_map('intval', $status));

$pm        = is_array($prev ?? null) ? $prev : [];
$prevTiles = $pm['tiles'] ?? [];
$prevTotal = (int) ($pm['total'] ?? 0);

/**
 * Movement against the same figure last month. Returns null when there is
 * no previous month to compare with, rather than pretending a first month
 * is a 100% rise.
 *
 * $goodWhenDown is true for figures you want falling — overdue cases,
 * escalations — so the colour follows the meaning rather than the sign.
 */
function delta(int $now, ?int $was, bool $goodWhenDown = false): ?array
{
    if ($was === null) return null;
    if ($was === 0 && $now === 0) return ['flat', 'no change', ''];
    if ($was === 0) return ['up', 'new this month', $goodWhenDown ? 'bad' : 'good'];

    $pct = (int) round(($now - $was) / $was * 100);
    if ($pct === 0) return ['flat', 'level with last month', ''];

    $dir  = $pct > 0 ? 'up' : 'down';
    $tone = ($pct > 0) === $goodWhenDown ? 'bad' : 'good';
    return [$dir, abs($pct) . '% vs last month', $tone];
}

function delta_html(?array $d): string
{
    if ($d === null) return '';
    [$dir, $text, $tone] = $d;
    $arrow = $dir === 'up' ? '▲' : ($dir === 'down' ? '▼' : '•');
    return '<span class="delta delta--' . $tone . '">' . $arrow . ' ' . e($text) . '</span>';
}

layout_head('Dashboard', 'dashboard.php');
?>

<?php if ($error): ?>
  <div class="alert-bar" role="alert"><?= e($error) ?></div>
<?php endif; ?>

<div class="dash-top">
  <form class="month-picker" method="get">
    <label class="visually-hidden" for="month">Reporting month</label>
    <input type="month" id="month" name="month"
           value="<?= e($month->format('Y-m')) ?>" onchange="this.form.submit()">
  </form>
  <button class="btn-pdf" type="button" onclick="window.print()">Download PDF</button>
  <!-- The kapitan reads these figures over someone's shoulder and asks how
       current they are. Better on the screen than in the answer. -->
  <p class="as-of">Data as of <?= e((new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')))->format('g:i A, j M Y')) ?></p>
</div>

<!-- ---------- reports received ---------- -->
<section class="card chart-card">
  <header class="chart-head">
    <h2 class="chart-title">Total reports received</h2>
    <span class="chart-period"><?= e($month->format('F Y')) ?>
      <?= delta_html(delta($total, $prevTotal ?: null)) ?></span>
  </header>

  <?php if ($total === 0): ?>
    <p class="empty"><strong>No complaints were filed in <?= e($month->format('F Y')) ?>.</strong>
       Pick another month above.</p>
  <?php else: ?>
    <div class="chart-box"><canvas id="chart-received"></canvas></div>
  <?php endif; ?>
</section>

<!-- ---------- counters and donuts ---------- -->
<div class="dash-mid">

  <div class="tile-stack">
    <div class="tile">
      <p class="tile-label">Reports Resolved</p>
      <p class="tile-value"><?= (int) $tiles['resolved'] ?></p>
      <p class="tile-foot"><?= e($month->format('F Y')) ?>
        <?= delta_html(delta((int) $tiles['resolved'], isset($prevTiles['resolved']) ? (int) $prevTiles['resolved'] : null)) ?></p>
    </div>
    <div class="tile">
      <p class="tile-label">Escalated Reports</p>
      <p class="tile-value"><?= (int) $tiles['escalated'] ?></p>
      <p class="tile-foot"><?= e($month->format('F Y')) ?>
        <?= delta_html(delta((int) $tiles['escalated'], isset($prevTiles['escalated']) ? (int) $prevTiles['escalated'] : null, true)) ?></p>
    </div>
    <div class="tile tile--warn">
      <p class="tile-label">Overdue Cases</p>
      <p class="tile-value"><?= (int) $tiles['overdue'] ?></p>
      <p class="tile-foot">Past their resolution target
        <?= delta_html(delta((int) $tiles['overdue'], isset($prevTiles['overdue']) ? (int) $prevTiles['overdue'] : null, true)) ?></p>
    </div>
  </div>

  <section class="card donut-card">
    <h2 class="chart-title">Resolution status report</h2>
    <?php if ($statusTotal === 0): ?>
      <p class="empty">Nothing to chart for this month.</p>
    <?php else: ?>
      <div class="donut-box">
        <canvas id="chart-status"></canvas>
        <div class="donut-centre">
          <strong><?= $statusTotal ?></strong>
          <span>Report<?= $statusTotal === 1 ? '' : 's' ?></span>
        </div>
      </div>
      <ul class="legend">
        <li><span class="sw" style="background:var(--done)"></span>Done (<?= (int) $status['done'] ?>)</li>
        <li><span class="sw" style="background:var(--overdue)"></span>Overdue work (<?= (int) $status['overdue'] ?>)</li>
        <li><span class="sw" style="background:var(--late)"></span>Work finished late (<?= (int) $status['late'] ?>)</li>
        <li><span class="sw" style="background:var(--processing)"></span>Processing (<?= (int) $status['processing'] ?>)</li>
        <?php if ((int) ($status['rejected'] ?? 0) > 0): ?>
          <li><span class="sw" style="background:#9ca3af"></span>Denied (<?= (int) $status['rejected'] ?>)</li>
        <?php endif; ?>
      </ul>
      <p class="chart-hint">Click a segment to open those complaints.</p>
    <?php endif; ?>
  </section>

  <section class="card donut-card">
    <h2 class="chart-title">Category Distribution</h2>
    <?php if (!$categories): ?>
      <p class="empty">Nothing to chart for this month.</p>
    <?php else: ?>
      <div class="donut-box">
        <canvas id="chart-category"></canvas>
        <div class="donut-centre">
          <strong><?= $total ?></strong>
          <span>Report<?= $total === 1 ? '' : 's' ?></span>
        </div>
      </div>
      <ul class="legend" id="legend-category"></ul>
      <p class="chart-hint">Click a segment to open those complaints.</p>
    <?php endif; ?>
  </section>
</div>

<!-- ---------- resolution efficiency ---------- -->
<section class="card chart-card">
  <header class="chart-head">
    <h2 class="chart-title">Resolution efficiency</h2>
    <span class="chart-period"><?= e($month->format('F Y')) ?></span>
  </header>
  <p class="chart-note">
    Average hours taken to finish a complaint, against the hours its
    category was allowed. Below the dashed line is inside the SLA.
  </p>
  <div class="chart-box"><canvas id="chart-efficiency"></canvas></div>
</section>

<script src="assets/vendor/chart/chart.umd.min.js"></script>
<script>
(function () {
  if (!window.Chart) { return; }

  var daily      = <?= json_encode($daily, JSON_UNESCAPED_UNICODE) ?>;
  var efficiency = <?= json_encode($efficiency, JSON_UNESCAPED_UNICODE) ?>;
  var status     = <?= json_encode($status) ?>;
  var categories = <?= json_encode($categories, JSON_UNESCAPED_UNICODE) ?>;

  var css = getComputedStyle(document.documentElement);
  function token(name) { return css.getPropertyValue(name).trim(); }

  Chart.defaults.font.family = "'Roboto', system-ui, sans-serif";
  Chart.defaults.color = token('--ink-soft');
  Chart.defaults.plugins.legend.display = false;

  function title(s) {
    return s.replace(/_/g, ' ').replace(/\b\w/g, function (c) { return c.toUpperCase(); });
  }

  // ---- reports received ----
  var received = document.getElementById('chart-received');
  if (received) {
    new Chart(received, {
      type: 'line',
      data: {
        labels: daily.map(function (d) { return d.label; }),
        datasets: [{
          data: daily.map(function (d) { return d.filed; }),
          borderColor: token('--navy'),
          backgroundColor: 'rgba(0, 48, 143, .10)',
          fill: true, tension: .35, borderWidth: 2,
          pointRadius: 0, pointHoverRadius: 5,
          pointHoverBackgroundColor: token('--navy')
        }]
      },
      options: {
        responsive: true, maintainAspectRatio: false, resizeDelay: 120,
        animation: { duration: 300 },
        interaction: { mode: 'index', intersect: false },
        plugins: {
          tooltip: {
            callbacks: {
              title: function (i) { return 'Day ' + i[0].label; },
              label: function (c) { return c.parsed.y + (c.parsed.y === 1 ? ' report' : ' reports'); }
            }
          }
        },
        scales: {
          y: { beginAtZero: true, ticks: { precision: 0 }, grid: { color: token('--rule') } },
          x: { grid: { display: false } }
        }
      }
    });
  }

  // ---- resolution status ----
  var st = document.getElementById('chart-status');
  if (st) {
    new Chart(st, {
      type: 'doughnut',
      data: {
        labels: ['Done', 'Overdue work', 'Work finished late', 'Processing', 'Denied'],
        datasets: [{
          data: [status.done, status.overdue, status.late, status.processing, status.rejected || 0],
          backgroundColor: [token('--done'), token('--overdue'), token('--late'),
                            token('--processing'), '#9ca3af'],
          borderWidth: 0
        }]
      },
      options: {
        responsive: true, maintainAspectRatio: false, resizeDelay: 120,
        animation: { duration: 300 }, cutout: '68%',
        // A chart that shows a problem should also be the way to reach it.
        onClick: function (_, hit) {
          if (!hit.length) return;
          var to = ['resolved', '', '', 'in_progress', 'rejected'][hit[0].index];
          location.href = to ? 'cases.php?status=' + to : 'cases.php?view=attention';
        },
        onHover: function (ev, hit) { ev.native.target.style.cursor = hit.length ? 'pointer' : 'default'; }
      }
    });
  }

  // ---- category distribution ----
  var cat = document.getElementById('chart-category');
  if (cat) {
    var palette = ['#00308f', '#ff9800', '#2563eb', '#22c55e', '#a855f7', '#ef4444', '#0891b2'];
    var colours = categories.map(function (_, i) { return palette[i % palette.length]; });

    new Chart(cat, {
      type: 'doughnut',
      data: {
        labels: categories.map(function (c) { return title(c.category); }),
        datasets: [{ data: categories.map(function (c) { return c.n; }),
                     backgroundColor: colours, borderWidth: 0 }]
      },
      options: {
        responsive: true, maintainAspectRatio: false, resizeDelay: 120,
        animation: { duration: 300 }, cutout: '68%',
        onClick: function (_, hit) {
          if (!hit.length) return;
          location.href = 'cases.php?q=' + encodeURIComponent(categories[hit[0].index].category);
        },
        onHover: function (ev, hit) { ev.native.target.style.cursor = hit.length ? 'pointer' : 'default'; }
      }
    });

    var list = document.getElementById('legend-category');
    categories.forEach(function (c, i) {
      var li = document.createElement('li');
      var sw = document.createElement('span');
      sw.className = 'sw';
      sw.style.background = colours[i];
      li.appendChild(sw);
      li.appendChild(document.createTextNode(title(c.category) + ' (' + c.n + ')'));
      list.appendChild(li);
    });
  }

  // ---- resolution efficiency ----
  var eff = document.getElementById('chart-efficiency');
  if (eff) {
    new Chart(eff, {
      type: 'line',
      data: {
        labels: efficiency.map(function (d) { return d.label; }),
        datasets: [
          {
            label: 'Hours taken',
            data: efficiency.map(function (d) { return d.actual; }),
            borderColor: token('--orange'),
            backgroundColor: 'rgba(255, 152, 0, .12)',
            fill: true, tension: .35, borderWidth: 2,
            spanGaps: true, pointRadius: 3
          },
          {
            label: 'Hours allowed',
            data: efficiency.map(function (d) { return d.allowed; }),
            borderColor: token('--ink-soft'),
            borderDash: [5, 4], borderWidth: 1.5,
            fill: false, spanGaps: true, pointRadius: 0
          }
        ]
      },
      options: {
        responsive: true, maintainAspectRatio: false, resizeDelay: 120,
        animation: { duration: 300 },
        interaction: { mode: 'index', intersect: false },
        plugins: {
          legend: { display: true, position: 'bottom', labels: { boxWidth: 12, usePointStyle: true } },
          tooltip: {
            callbacks: {
              title: function (i) { return 'Day ' + i[0].label; },
              label: function (c) {
                return c.dataset.label + ': ' + (c.parsed.y === null ? '—' : c.parsed.y + ' h');
              }
            }
          }
        },
        scales: {
          y: { beginAtZero: true, title: { display: true, text: 'Hours' },
               grid: { color: token('--rule') } },
          x: { grid: { display: false } }
        }
      }
    });
  }
})();
</script>

<?php layout_foot(); ?>
