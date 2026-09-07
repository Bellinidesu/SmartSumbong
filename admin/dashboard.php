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
  <!-- No-login version of a handful of these same figures, for residents
       and anyone else. Opens in its own tab rather than navigating the
       admin away from the session they're in. -->
  <a class="btn-pdf" href="../public/transparency.php" target="_blank" rel="noopener">Public Transparency Page</a>
  <!-- The kapitan reads these figures over someone's shoulder and asks how
       current they are. Better on the screen than in the answer. -->
  <p class="as-of">Data as of <span id="as-of-time"><?= e((new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')))->format('g:i A, j M Y')) ?></span>
    <?php if ($month->format('Y-m') === (new DateTimeImmutable('now', $tz))->format('Y-m')): ?>
      <span class="live-badge" id="live-badge" title="This month's figures update as reports come in — no reload needed">
        <span class="live-dot" aria-hidden="true"></span><span id="live-badge-text">Live</span>
      </span>
    <?php endif; ?>
  </p>
</div>

<!-- ---------- reports received ---------- -->
<section class="card chart-card">
  <header class="chart-head">
    <h2 class="chart-title">Total reports received</h2>
    <span class="chart-period"><?= e($month->format('F Y')) ?>
      <span id="received-delta"><?= delta_html(delta($total, $prevTotal ?: null)) ?></span></span>
  </header>

  <?php if ($total === 0): ?>
    <p class="empty" id="received-empty"><strong>No complaints were filed in <?= e($month->format('F Y')) ?>.</strong>
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
      <p class="tile-value" id="tile-resolved-value"><?= (int) $tiles['resolved'] ?></p>
      <p class="tile-foot"><?= e($month->format('F Y')) ?>
        <span id="tile-resolved-delta"><?= delta_html(delta((int) $tiles['resolved'], isset($prevTiles['resolved']) ? (int) $prevTiles['resolved'] : null)) ?></span></p>
    </div>
    <div class="tile">
      <p class="tile-label">Escalated Reports</p>
      <p class="tile-value" id="tile-escalated-value"><?= (int) $tiles['escalated'] ?></p>
      <p class="tile-foot"><?= e($month->format('F Y')) ?>
        <span id="tile-escalated-delta"><?= delta_html(delta((int) $tiles['escalated'], isset($prevTiles['escalated']) ? (int) $prevTiles['escalated'] : null, true)) ?></span></p>
    </div>
    <div class="tile tile--warn">
      <p class="tile-label">Overdue Cases</p>
      <p class="tile-value" id="tile-overdue-value"><?= (int) $tiles['overdue'] ?></p>
      <p class="tile-foot">Past their resolution target
        <span id="tile-overdue-delta"><?= delta_html(delta((int) $tiles['overdue'], isset($prevTiles['overdue']) ? (int) $prevTiles['overdue'] : null, true)) ?></span></p>
    </div>
  </div>

  <section class="card donut-card">
    <h2 class="chart-title">Resolution status report</h2>
    <?php if ($statusTotal === 0): ?>
      <p class="empty" id="status-empty">Nothing to chart for this month.</p>
    <?php else: ?>
      <div class="donut-box">
        <canvas id="chart-status"></canvas>
        <div class="donut-centre">
          <strong id="status-donut-total"><?= $statusTotal ?></strong>
          <span id="status-donut-label">Report<?= $statusTotal === 1 ? '' : 's' ?></span>
        </div>
      </div>
      <ul class="legend" id="legend-status">
        <li><span class="sw" style="background:var(--done)"></span>Done (<span id="legend-done"><?= (int) $status['done'] ?></span>)</li>
        <li><span class="sw" style="background:var(--overdue)"></span>Overdue work (<span id="legend-overdue"><?= (int) $status['overdue'] ?></span>)</li>
        <li><span class="sw" style="background:var(--late)"></span>Work finished late (<span id="legend-late"><?= (int) $status['late'] ?></span>)</li>
        <li><span class="sw" style="background:var(--processing)"></span>Processing (<span id="legend-processing"><?= (int) $status['processing'] ?></span>)</li>
        <?php if ((int) ($status['rejected'] ?? 0) > 0): ?>
          <li id="legend-rejected-row"><span class="sw" style="background:#9ca3af"></span>Denied (<span id="legend-rejected"><?= (int) $status['rejected'] ?></span>)</li>
        <?php endif; ?>
      </ul>
      <p class="chart-hint">Click a segment to open those complaints.</p>
    <?php endif; ?>
  </section>

  <section class="card donut-card">
    <h2 class="chart-title">Category Distribution</h2>
    <?php if (!$categories): ?>
      <p class="empty" id="category-empty">Nothing to chart for this month.</p>
    <?php else: ?>
      <div class="donut-box">
        <canvas id="chart-category"></canvas>
        <div class="donut-centre">
          <strong id="category-donut-total"><?= $total ?></strong>
          <span id="category-donut-label">Report<?= $total === 1 ? '' : 's' ?></span>
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
<script src="assets/vendor/supabase/supabase.js"></script>
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

  // Kept so the realtime block below (added 6 Sep 2026, "the entire system
  // needs to work realtime") can push fresh data into the same instances
  // instead of tearing them down and rebuilding on every change.
  var receivedChart = null, statusChart = null, categoryChart = null, efficiencyChart = null;
  var categoryPalette = ['#00308f', '#ff9800', '#2563eb', '#22c55e', '#a855f7', '#ef4444', '#0891b2'];

  function renderCategoryLegend(cats, colours) {
    var list = document.getElementById('legend-category');
    if (!list) return;
    list.innerHTML = '';
    cats.forEach(function (c, i) {
      var li = document.createElement('li');
      var sw = document.createElement('span');
      sw.className = 'sw';
      sw.style.background = colours[i % colours.length];
      li.appendChild(sw);
      li.appendChild(document.createTextNode(title(c.category) + ' (' + c.n + ')'));
      list.appendChild(li);
    });
  }

  // ---- reports received ----
  var received = document.getElementById('chart-received');
  if (received) {
    receivedChart = new Chart(received, {
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
    statusChart = new Chart(st, {
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
    var colours = categories.map(function (_, i) { return categoryPalette[i % categoryPalette.length]; });

    categoryChart = new Chart(cat, {
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
          if (!hit.length || !categories[hit[0].index]) return;
          location.href = 'cases.php?q=' + encodeURIComponent(categories[hit[0].index].category);
        },
        onHover: function (ev, hit) { ev.native.target.style.cursor = hit.length ? 'pointer' : 'default'; }
      }
    });

    renderCategoryLegend(categories, colours);
  }

  // ---- resolution efficiency ----
  var eff = document.getElementById('chart-efficiency');
  if (eff) {
    efficiencyChart = new Chart(eff, {
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

  // ================= Realtime, added 6 Sep 2026 =================
  // Explicit ask: "the entire system needs to work realtime." dashboard_metrics()
  // (0012) only ever reads from public.reports, so a change there is the
  // whole live-update signal this page needs — no need to also watch
  // dispatches or status_logs separately. Only wired up when viewing the
  // current month; a past month's figures do not move as new reports
  // come in, so there is nothing to subscribe to.
  var IS_CURRENT_MONTH = <?= json_encode($month->format('Y-m') === (new DateTimeImmutable('now', $tz))->format('Y-m')) ?>;
  if (!IS_CURRENT_MONTH || !window.supabase) { return; }

  // These four flags describe which sections the server template actually
  // built at load. If a realtime figure would flip one of them (a month
  // that opened empty gets its first report, or vice versa), that is a
  // change in page *structure*, not just numbers — simplest and safest
  // is to let the server re-render its own template rather than grow
  // ad-hoc DOM-morphing logic for what should be a rare edge.
  var HAS_RECEIVED = <?= json_encode($total !== 0) ?>;
  var HAS_STATUS   = <?= json_encode($statusTotal !== 0) ?>;
  var HAS_CATEGORY = <?= json_encode((bool) $categories) ?>;
  var HAS_REJECTED = <?= json_encode(((int) ($status['rejected'] ?? 0)) > 0) ?>;
  var PREV_TOTAL   = <?= json_encode($prevTotal ?: null) ?>;
  var PREV_TILES   = <?= json_encode($prevTiles ?: null) ?>;
  var MONTH_FROM   = <?= json_encode($month->format(DateTimeInterface::ATOM)) ?>;
  var MONTH_TO     = <?= json_encode($next->format(DateTimeInterface::ATOM)) ?>;

  function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  // Mirrors delta()/delta_html() in dashboard.php exactly, so a live
  // update reads the same as a reload would.
  function computeDelta(now, was, goodWhenDown) {
    if (was === null || was === undefined) return null;
    if (was === 0 && now === 0) return ['flat', 'no change', ''];
    if (was === 0) return ['up', 'new this month', goodWhenDown ? 'bad' : 'good'];
    var pct = Math.round((now - was) / was * 100);
    if (pct === 0) return ['flat', 'level with last month', ''];
    var dir  = pct > 0 ? 'up' : 'down';
    var tone = (pct > 0) === !!goodWhenDown ? 'bad' : 'good';
    return [dir, Math.abs(pct) + '% vs last month', tone];
  }
  function deltaHtml(d) {
    if (!d) return '';
    var arrow = d[0] === 'up' ? '▲' : (d[0] === 'down' ? '▼' : '•');
    return '<span class="delta delta--' + d[2] + '">' + arrow + ' ' + escapeHtml(d[1]) + '</span>';
  }
  function setText(id, v) { var el = document.getElementById(id); if (el) el.textContent = v; }
  function setHtml(id, v) { var el = document.getElementById(id); if (el) el.innerHTML = v; }

  var { createClient } = supabase;
  var TOKEN = <?= json_encode(access_token()) ?>;
  var sb = createClient(
    <?= json_encode(supabase_url()) ?>,
    <?= json_encode(supabase_key()) ?>,
    { global: { headers: { Authorization: 'Bearer ' + TOKEN } },
      auth: { persistSession: false, autoRefreshToken: false } }
  );
  sb.realtime.setAuth(TOKEN);

  function applyMetrics(m) {
    var d2          = m.daily || [];
    var eff2        = m.efficiency || [];
    var st2         = m.resolution_status || { done: 0, overdue: 0, late: 0, processing: 0, rejected: 0 };
    var cats2       = m.categories || [];
    var tiles2      = m.tiles || { resolved: 0, escalated: 0, overdue: 0 };
    var total2      = m.total || 0;
    var statusTotal2 = (st2.done || 0) + (st2.overdue || 0) + (st2.late || 0)
                     + (st2.processing || 0) + (st2.rejected || 0);

    var needsReceived = total2 !== 0;
    var needsStatus   = statusTotal2 !== 0;
    var needsCategory = cats2.length > 0;
    var needsRejected = (st2.rejected || 0) > 0;
    if (needsReceived !== HAS_RECEIVED || needsStatus !== HAS_STATUS ||
        needsCategory !== HAS_CATEGORY || needsRejected !== HAS_REJECTED) {
      location.reload();
      return;
    }

    if (receivedChart) {
      receivedChart.data.labels = d2.map(function (x) { return x.label; });
      receivedChart.data.datasets[0].data = d2.map(function (x) { return x.filed; });
      receivedChart.update();
    }
    setHtml('received-delta', deltaHtml(computeDelta(total2, PREV_TOTAL)));

    if (statusChart) {
      statusChart.data.datasets[0].data = [st2.done, st2.overdue, st2.late, st2.processing, st2.rejected || 0];
      statusChart.update();
    }
    setText('status-donut-total', statusTotal2);
    setText('status-donut-label', 'Report' + (statusTotal2 === 1 ? '' : 's'));
    setText('legend-done', st2.done || 0);
    setText('legend-overdue', st2.overdue || 0);
    setText('legend-late', st2.late || 0);
    setText('legend-processing', st2.processing || 0);
    if (HAS_REJECTED) setText('legend-rejected', st2.rejected || 0);

    categories = cats2; // keep the donut's own onClick (defined above) current
    if (categoryChart) {
      var colours = cats2.map(function (_, i) { return categoryPalette[i % categoryPalette.length]; });
      categoryChart.data.labels = cats2.map(function (c) { return title(c.category); });
      categoryChart.data.datasets[0].data = cats2.map(function (c) { return c.n; });
      categoryChart.data.datasets[0].backgroundColor = colours;
      categoryChart.update();
      renderCategoryLegend(cats2, colours);
    }
    setText('category-donut-total', total2);
    setText('category-donut-label', 'Report' + (total2 === 1 ? '' : 's'));

    if (efficiencyChart) {
      efficiencyChart.data.labels = eff2.map(function (x) { return x.label; });
      efficiencyChart.data.datasets[0].data = eff2.map(function (x) { return x.actual; });
      efficiencyChart.data.datasets[1].data = eff2.map(function (x) { return x.allowed; });
      efficiencyChart.update();
    }

    setText('tile-resolved-value', tiles2.resolved || 0);
    setText('tile-escalated-value', tiles2.escalated || 0);
    setText('tile-overdue-value', tiles2.overdue || 0);
    var pr = PREV_TILES || {};
    setHtml('tile-resolved-delta', deltaHtml(computeDelta(tiles2.resolved || 0, pr.resolved != null ? pr.resolved : null)));
    setHtml('tile-escalated-delta', deltaHtml(computeDelta(tiles2.escalated || 0, pr.escalated != null ? pr.escalated : null, true)));
    setHtml('tile-overdue-delta', deltaHtml(computeDelta(tiles2.overdue || 0, pr.overdue != null ? pr.overdue : null, true)));

    var asOf = document.getElementById('as-of-time');
    if (asOf) {
      asOf.textContent = new Intl.DateTimeFormat('en-US', {
        timeZone: 'Asia/Manila', hour: 'numeric', minute: '2-digit', hour12: true,
        day: 'numeric', month: 'short', year: 'numeric'
      }).format(new Date());
    }
  }

  // Several reports landing at once (a batch, several tanods updating in
  // the same minute) collapse into one RPC call instead of one per row.
  var refreshTimer = null;
  function scheduleRefresh() {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(function () {
      sb.rpc('dashboard_metrics', { p_from: MONTH_FROM, p_to: MONTH_TO }).then(function (res) {
        if (res.error || !res.data) return; // stale figures beat a half-applied update
        applyMetrics(res.data);
      });
    }, 400);
  }

  sb.channel('dashboard-metrics')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'reports' }, scheduleRefresh)
    .subscribe(function (chStatus) {
      var badge = document.getElementById('live-badge'),
          text  = document.getElementById('live-badge-text');
      if (!badge) return;
      if (chStatus === 'SUBSCRIBED') {
        badge.classList.remove('is-down'); text.textContent = 'Live';
      } else if (chStatus === 'CHANNEL_ERROR' || chStatus === 'TIMED_OUT' || chStatus === 'CLOSED') {
        badge.classList.add('is-down'); text.textContent = 'Reconnecting…';
      }
    });
})();
</script>

<?php layout_foot(); ?>
