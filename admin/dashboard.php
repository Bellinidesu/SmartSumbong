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

// Same fixed 7-category list as cases.php/summary.php — only used here to
// scope the Resolution Efficiency chart (0056); every other visual on
// this page stays computed over the whole month.
const CATEGORIES = [
    'street_obstruction', 'public_safety_infrastructure', 'environmental_waste_hazard',
    'animal_welfare', 'traffic_violation', 'barangay_service', 'peace_order_nuisance',
];
$effCategory = (string) ($_GET['eff_category'] ?? '');
if (!in_array($effCategory, CATEGORIES, true)) { $effCategory = ''; }

$error   = null;
$metrics = null;

try {
    $metrics = $db->rpc('dashboard_metrics', [
        'p_from'     => $month->format(DateTimeInterface::ATOM),
        'p_to'       => $next->format(DateTimeInterface::ATOM),
        'p_category' => $effCategory ?: null,
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
    if ($was === 0 && $now === 0) return ['flat', t('no change', 'walang pagbabago'), ''];
    if ($was === 0) return ['up', t('new this month', 'bago ngayong buwan'), $goodWhenDown ? 'bad' : 'good'];

    $pct = (int) round(($now - $was) / $was * 100);
    if ($pct === 0) return ['flat', t('level with last month', 'kapareho ng nakaraang buwan'), ''];

    $dir  = $pct > 0 ? 'up' : 'down';
    $tone = ($pct > 0) === $goodWhenDown ? 'bad' : 'good';
    return [$dir, abs($pct) . t('% vs last month', '% vs nakaraang buwan'), $tone];
}

function delta_html(?array $d): string
{
    if ($d === null) return '';
    [$dir, $text, $tone] = $d;
    $arrow = $dir === 'up' ? '▲' : ($dir === 'down' ? '▼' : '•');
    return '<span class="delta delta--' . $tone . '">' . $arrow . ' ' . e($text) . '</span>';
}

layout_head(t('Dashboard', 'Dashboard'), 'dashboard.php');
$isCurrent = $month->format('Y-m') === (new DateTimeImmutable('now', $tz))->format('Y-m');
?>

<?php if ($error): ?>
  <div class="p-flash p-flash--error" role="alert"><?= e($error) ?></div>
<?php endif; ?>

<div class="p-dash-top">
  <form method="get">
    <label class="p-pill-select"><?= p_icon('i-cal', 16) ?><span class="p-sr"><?= e(t('Reporting month', 'Buwan ng ulat')) ?></span>
      <input type="month" id="month" name="month" value="<?= e($month->format('Y-m')) ?>" onchange="this.form.submit()"></label>
    <input type="hidden" name="eff_category" value="<?= e($effCategory) ?>">
  </form>
  <span class="p-spacer"></span>
  <!-- The kapitan reads these figures over someone's shoulder and asks how current they are. -->
  <span class="p-asof"><?= e(t('Data as of', 'Datos hanggang')) ?> <span id="as-of-time" class="p-num"><?= e((new DateTimeImmutable('now', $tz))->format('g:i A, j M Y')) ?></span></span>
  <?php if ($isCurrent): ?>
    <span class="p-live" id="live-badge" title="<?= e(t("This month's figures update as reports come in — no reload needed", 'Nag-a-update ang mga numero ngayong buwan habang dumarating ang mga ulat — hindi na kailangang i-reload')) ?>"><i></i><span id="live-badge-text"><?= e(t('Live', 'Live')) ?></span></span>
  <?php endif; ?>
</div>

<!-- ---------- reports received ---------- -->
<div class="p-card" style="margin-bottom:20px">
  <div class="p-card-head"><h2><?= e(t('Total reports received', 'Kabuuang natanggap na ulat')) ?></h2><span class="p-spacer"></span>
    <span class="p-hint"><?= e(month_year($month)) ?></span><span class="p-delta-t" id="received-delta"></span></div>
  <div class="p-chart-wrap"><svg id="chart-received" width="100%" height="260" style="display:block" role="img" aria-label="<?= e(t('Reports filed each day', 'Mga ulat na naisampa bawat araw')) ?>"></svg><div class="p-chart-tip"></div>
    <div class="p-empty-state" id="received-empty" hidden><b><?= e(t('No complaints were filed in ', 'Walang naisampang sumbong noong ') . month_year($month)) ?>.</b><span><?= e(t('Pick another month above.', 'Pumili ng ibang buwan sa itaas.')) ?></span></div></div>
</div>

<div class="p-dash-mid p-grid" style="margin-bottom:20px">
  <div class="p-stack">
    <div class="p-card p-tile-s"><span class="p-label"><?= e(t('Reports Resolved', 'Nalutas na Ulat')) ?></span><b class="p-num" id="tile-resolved-value"><?= (int) $tiles['resolved'] ?></b><small><?= e(month_year($month)) ?></small><span class="p-delta-t" id="tile-resolved-delta"></span></div>
    <div class="p-card p-tile-s"><span class="p-label"><?= e(t('Escalated Reports', 'Na-escalate na Ulat')) ?></span><b class="p-num" id="tile-escalated-value"><?= (int) $tiles['escalated'] ?></b><small><?= e(month_year($month)) ?></small><span class="p-delta-t" id="tile-escalated-delta"></span></div>
    <div class="p-card p-tile-s"><span class="p-label"><?= e(t('Overdue Cases', 'Lampas-oras na Kaso')) ?></span><b class="p-num" id="tile-overdue-value"><?= (int) $tiles['overdue'] ?></b><small><?= e(t('Past their resolution target', 'Lampas sa target na paglutas')) ?></small><span class="p-delta-t" id="tile-overdue-delta"></span></div>
  </div>
  <div class="p-card p-donut-card">
    <div class="p-row-between"><h2 class="p-card-title"><?= e(t('Resolution status report', 'Ulat sa katayuan ng paglutas')) ?></h2></div>
    <div class="p-donut"><svg id="donut-status" viewBox="0 0 42 42" width="184" height="184" role="img" aria-label="<?= e(t('Resolution status', 'Katayuan ng paglutas')) ?>"></svg><div class="p-center"><b class="p-num" id="status-donut-total">0</b><span id="status-donut-label"><?= e(t('Reports', 'Ulat')) ?></span></div></div>
    <div class="p-legend" id="legend-status"></div>
    <p class="p-hint" style="margin:0"><?= e(t('Click a segment to open those complaints.', 'I-click ang isang bahagi para buksan ang mga sumbong na iyon.')) ?></p>
    <div class="p-empty-state" id="status-empty" hidden><span><?= e(t('Nothing to chart for this month.', 'Walang maipapakita para sa buwang ito.')) ?></span></div>
  </div>
  <div class="p-card p-donut-card">
    <div class="p-row-between"><h2 class="p-card-title"><?= e(t('Category Distribution', 'Hati ayon sa Kategorya')) ?></h2></div>
    <div class="p-donut"><svg id="donut-category" viewBox="0 0 42 42" width="184" height="184" role="img" aria-label="<?= e(t('Complaints by category', 'Mga sumbong ayon sa kategorya')) ?>"></svg><div class="p-center"><b class="p-num" id="category-donut-total">0</b><span id="category-donut-label"><?= e(t('Reports', 'Ulat')) ?></span></div></div>
    <div class="p-legend" id="legend-category"></div>
    <p class="p-hint" style="margin:0"><?= e(t('Click a segment to open those complaints.', 'I-click ang isang bahagi para buksan ang mga sumbong na iyon.')) ?></p>
    <div class="p-empty-state" id="category-empty" hidden><span><?= e(t('Nothing to chart for this month.', 'Walang maipapakita para sa buwang ito.')) ?></span></div>
  </div>
</div>

<!-- ---------- resolution efficiency ---------- -->
<div class="p-card">
  <div class="p-card-head" style="flex-wrap:wrap"><h2><?= e(t('Resolution efficiency', 'Bilis ng paglutas')) ?></h2><span class="p-spacer"></span>
    <span class="p-hint"><?= e(month_year($month)) ?></span>
    <form method="get">
      <input type="hidden" name="month" value="<?= e($month->format('Y-m')) ?>">
      <label class="p-pill-select"><span class="p-sr"><?= e(t('Filter by category', 'Salain ayon sa kategorya')) ?></span>
        <select name="eff_category" id="eff_category" onchange="this.form.submit()">
          <option value=""><?= e(t('All Categories', 'Lahat ng Kategorya')) ?></option>
          <?php foreach (CATEGORIES as $c): ?>
            <option value="<?= e($c) ?>" <?= $effCategory === $c ? 'selected' : '' ?>><?= e(category_label($c)) ?></option>
          <?php endforeach; ?>
        </select></label>
    </form>
  </div>
  <p class="p-hint p-eff-note"><?= e(t('Average hours taken to finish a complaint, against the hours its category was allowed. Below the dashed line is inside the SLA.',
                                     'Karaniwang oras bago matapos ang isang sumbong, kumpara sa oras na itinakda para sa kategorya nito. Ang nasa ilalim ng putol-putol na linya ay pasok sa SLA.')) ?>
    <?php if ($effCategory): ?><?= e(t('Showing ', 'Ipinapakita lamang ang ') . category_label($effCategory) . t(' only.', '.')) ?><?php endif; ?></p>
  <div class="p-chart-wrap"><svg id="chart-efficiency" width="100%" height="240" style="display:block" role="img" aria-label="<?= e(t('Hours taken against hours allowed', 'Oras na inabot kumpara sa itinakda')) ?>"></svg><div class="p-chart-tip"></div>
    <div class="p-empty-state" id="efficiency-empty" hidden><span><?= e(t('Nothing to chart for this month.', 'Walang maipapakita para sa buwang ito.')) ?></span></div></div>
  <div class="p-eff-legend" id="eff-legend">
    <button type="button" aria-pressed="true" data-s="taken"><i style="border-color:#FF9800"></i><span><?= e(t('Hours taken', 'Oras na inabot')) ?></span></button>
    <button type="button" aria-pressed="true" data-s="allowed"><i class="p-dash" style="border-color:var(--p-muted)"></i><span><?= e(t('Hours allowed', 'Oras na itinakda')) ?></span></button>
  </div>
</div>

<script src="assets/vendor/supabase/supabase.js"></script>
<script>
(function () {
  var M = {
    daily: <?= json_encode($daily, JSON_UNESCAPED_UNICODE) ?>,
    efficiency: <?= json_encode($efficiency, JSON_UNESCAPED_UNICODE) ?>,
    resolution_status: <?= json_encode($status) ?>,
    categories: <?= json_encode($categories, JSON_UNESCAPED_UNICODE) ?>,
    tiles: <?= json_encode($tiles) ?>,
    total: <?= json_encode($total) ?>
  };
  var MONTH = <?= json_encode($month->format('Y-m')) ?>;
  var PREV_TOTAL = <?= json_encode($prev !== null ? $prevTotal : null) ?>;
  var PREV_TILES = <?= json_encode($prevTiles ?: null) ?>;
  var CATEGORY_LABEL = <?= json_encode(array_combine(CATEGORIES, array_map('category_label', CATEGORIES)), JSON_UNESCAPED_UNICODE) ?>;
  // The preview's colours per category, so a category keeps its colour month to month.
  var CATEGORY_COLOUR = { street_obstruction: '#F93535', public_safety_infrastructure: '#356CF9', environmental_waste_hazard: '#F9AB35',
                          animal_welfare: '#34C759', traffic_violation: '#8E9ABB', barangay_service: '#422F8A', peace_order_nuisance: '#E0609A' };

  function css(v) { return getComputedStyle(document.documentElement).getPropertyValue(v).trim(); }
  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }

  function smooth(pts) {
    var d = 'M' + pts[0][0] + ',' + pts[0][1];
    for (var i = 0; i < pts.length - 1; i++) {
      var a = pts[i - 1] || pts[i], b = pts[i], c = pts[i + 1], e = pts[i + 2] || pts[i + 1];
      d += ' C' + (b[0] + (c[0] - a[0]) / 6) + ',' + (b[1] + (c[1] - a[1]) / 6) + ' ' + (c[0] - (e[0] - b[0]) / 6) + ',' + (c[1] - (e[1] - b[1]) / 6) + ' ' + c[0] + ',' + c[1];
    }
    return d;
  }
  function niceStep(x) { var p = Math.pow(10, Math.floor(Math.log10(Math.max(x, 1e-9)))), f = x / p; return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * p; }
  function clampY(path, lo, top) { return path.replace(/(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/g, function (m, a, b) { return a + ',' + Math.min(lo, Math.max(top, +b)); }); }
  function dayTicks(n, W) { var t = W < 560 ? [1, 10, 20, n] : [1, 5, 10, 15, 20, 25, n]; return t.filter(function (d, i) { return d <= n && t.indexOf(d) === i; }); }

  // Reports filed each day: the preview's area chart.
  function received(svg, data, labels) {
    var H = +svg.getAttribute('height'), W = Math.max(300, Math.round(svg.getBoundingClientRect().width || 900)), L = 44, R = 12, T = 16, B = 28, n = data.length;
    svg.setAttribute('viewBox', '0 0 ' + W + ' ' + H);
    if (n < 2) { svg.innerHTML = ''; return; }
    var max = Math.max(4, niceStep(Math.max(1, Math.max.apply(null, data)) / 4) * 4);
    var x = function (i) { return L + (W - L - R) * i / (n - 1); }, y = function (v) { return T + (H - T - B) * (1 - v / max); };
    var violet = css('--p-c-violet'), s = '<defs><linearGradient id="g-recv" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="' + violet + '" stop-opacity=".18"/><stop offset="1" stop-color="' + violet + '" stop-opacity="0"/></linearGradient></defs>';
    for (var g = 0; g <= max; g += max / 4) s += '<line x1="' + L + '" x2="' + (W - R) + '" y1="' + y(g) + '" y2="' + y(g) + '" stroke="' + css('--p-line') + '" stroke-dasharray="' + (g ? '3 4' : '') + '"/><text x="' + (L - 8) + '" y="' + (y(g) + 4) + '" text-anchor="end" font-size="11" fill="' + css('--p-faint') + '" font-family="Inter">' + g + '</text>';
    dayTicks(n, W).forEach(function (d) { s += '<text x="' + x(d - 1) + '" y="' + (H - 8) + '" text-anchor="middle" font-size="11" fill="' + css('--p-faint') + '" font-family="Inter">' + labels[d - 1] + '</text>'; });
    var pts = data.map(function (v, i) { return [x(i), y(v)]; }), lo = y(0), p = clampY(smooth(pts), lo, T);
    s += '<path d="' + p + ' L' + pts[n - 1][0] + ',' + lo + ' L' + pts[0][0] + ',' + lo + ' Z" fill="url(#g-recv)"/><path d="' + p + '" fill="none" stroke="' + violet + '" stroke-width="2.5" stroke-linecap="round"/>';
    s += '<line class="hl" x1="0" x2="0" y1="' + T + '" y2="' + lo + '" stroke="' + css('--p-line-2') + '" stroke-dasharray="3 3" opacity="0"/><circle class="hd" r="5" fill="' + css('--p-surface') + '" stroke="' + violet + '" stroke-width="2.5" opacity="0"/><rect x="' + L + '" y="0" width="' + (W - L - R) + '" height="' + H + '" fill="transparent" class="hit"/>';
    svg.innerHTML = s;
    var tip = svg.parentElement.querySelector('.p-chart-tip'), hit = svg.querySelector('.hit');
    hit.onmousemove = function (e) {
      var r = svg.getBoundingClientRect(), i = Math.max(0, Math.min(n - 1, Math.round(((e.clientX - r.left) / r.width * W - L) / (W - L - R) * (n - 1)))), v = data[i];
      var hl = svg.querySelector('.hl'), hd = svg.querySelector('.hd');
      hl.setAttribute('x1', x(i)); hl.setAttribute('x2', x(i)); hl.setAttribute('opacity', 1);
      hd.setAttribute('cx', x(i)); hd.setAttribute('cy', y(v)); hd.setAttribute('opacity', 1);
      tip.innerHTML = T('Day ', 'Araw ') + esc(labels[i]) + '<b>' + v + '</b>' + T(v === 1 ? 'report' : 'reports', 'ulat');
      tip.style.left = (x(i) / W * r.width + 22) + 'px'; tip.style.top = (y(v) / H * r.height + 8) + 'px'; tip.style.opacity = 1;
    };
    hit.onmouseleave = function () { tip.style.opacity = 0; svg.querySelector('.hl').setAttribute('opacity', 0); svg.querySelector('.hd').setAttribute('opacity', 0); };
  }

  // Hours taken against hours allowed: the preview's two lines and their buttons.
  var effShow = { taken: true, allowed: true };
  function efficiencyChart(svg, taken, allowed, labels) {
    var H = +svg.getAttribute('height'), W = Math.max(300, Math.round(svg.getBoundingClientRect().width || 900)), L = 48, R = 12, T = 16, B = 28, n = taken.length;
    svg.setAttribute('viewBox', '0 0 ' + W + ' ' + H);
    if (n < 2) { svg.innerHTML = ''; return; }
    var all = [].concat(effShow.taken ? taken : [], effShow.allowed ? allowed : []).filter(function (v) { return v != null; });
    var max = niceStep(Math.max.apply(null, [1].concat(all)) / 4) * 4;
    var x = function (i) { return L + (W - L - R) * i / (n - 1); }, y = function (v) { return T + (H - T - B) * (1 - v / max); }, lo = y(0);
    var line = function (d) { var p = d.map(function (v, i) { return v == null ? null : [x(i), y(v)]; }).filter(Boolean); return p.length > 1 ? clampY(smooth(p), lo, T) : ''; };
    var orange = '#FF9800', s = '<defs><linearGradient id="g-eff" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="' + orange + '" stop-opacity=".16"/><stop offset="1" stop-color="' + orange + '" stop-opacity="0"/></linearGradient></defs>';
    for (var g = 0; g <= max; g += max / 4) s += '<line x1="' + L + '" x2="' + (W - R) + '" y1="' + y(g) + '" y2="' + y(g) + '" stroke="' + css('--p-line') + '" stroke-dasharray="' + (g ? '3 4' : '') + '"/><text x="' + (L - 8) + '" y="' + (y(g) + 4) + '" text-anchor="end" font-size="11" fill="' + css('--p-faint') + '" font-family="Inter">' + g + ' h</text>';
    dayTicks(n, W).forEach(function (d) { s += '<text x="' + x(d - 1) + '" y="' + (H - 8) + '" text-anchor="middle" font-size="11" fill="' + css('--p-faint') + '" font-family="Inter">' + labels[d - 1] + '</text>'; });
    var pt = taken.map(function (v, i) { return v == null ? null : [x(i), y(v)]; }).filter(Boolean);
    if (effShow.taken && pt.length) {
      if (pt.length > 1) { var p = line(taken); s += '<path d="' + p + ' L' + pt[pt.length - 1][0] + ',' + lo + ' L' + pt[0][0] + ',' + lo + ' Z" fill="url(#g-eff)"/><path d="' + p + '" fill="none" stroke="' + orange + '" stroke-width="2" stroke-linecap="round"/>'; }
      pt.forEach(function (q) { s += '<circle cx="' + q[0] + '" cy="' + q[1] + '" r="3" fill="' + orange + '"/>'; });
    }
    if (effShow.allowed) s += '<path d="' + line(allowed) + '" fill="none" stroke="' + css('--p-muted') + '" stroke-width="1.5" stroke-dasharray="5 4"/>';
    s += '<line class="hl" x1="0" x2="0" y1="' + T + '" y2="' + lo + '" stroke="' + css('--p-line-2') + '" stroke-dasharray="3 3" opacity="0"/><rect x="' + L + '" y="0" width="' + (W - L - R) + '" height="' + H + '" fill="transparent" class="hit"/>';
    svg.innerHTML = s;
    var tip = svg.parentElement.querySelector('.p-chart-tip'), hit = svg.querySelector('.hit'), hl = svg.querySelector('.hl');
    hit.onmousemove = function (e) {
      var r = svg.getBoundingClientRect(), i = Math.max(0, Math.min(n - 1, Math.round(((e.clientX - r.left) / r.width * W - L) / (W - L - R) * (n - 1))));
      var t = taken[i], a = allowed[i];
      hl.setAttribute('x1', x(i)); hl.setAttribute('x2', x(i)); hl.setAttribute('opacity', 1);
      tip.innerHTML = T('Day ', 'Araw ') + esc(labels[i]) + '<b>' + (t == null ? '—' : t + ' h') + '</b>' + T('Hours allowed', 'Oras na itinakda') + ': ' + (a == null ? '—' : a + ' h');
      tip.style.left = (x(i) / W * r.width + 22) + 'px'; tip.style.top = (y(t != null ? t : (a != null ? a : 0)) / H * r.height + 8) + 'px'; tip.style.opacity = 1;
    };
    hit.onmouseleave = function () { tip.style.opacity = 0; hl.setAttribute('opacity', 0); };
  }

  // The preview's thin-ring donut; each segment and legend row opens its complaints.
  function donut(svg, legend, parts) {
    var total = parts.reduce(function (a, p) { return a + p.n; }, 0), off = 25;
    var s = '<circle cx="21" cy="21" r="15.9" fill="none" stroke="' + css('--p-line') + '" stroke-width="5"/>';
    parts.forEach(function (p, i) { if (!p.n) return; var len = p.n / total * 100; s += '<circle data-i="' + i + '" cx="21" cy="21" r="15.9" fill="none" stroke="' + p.colour + '" stroke-width="5" stroke-dasharray="' + Math.max(0, len - 1.2) + ' ' + (100 - len + 1.2) + '" stroke-dashoffset="' + off + '" style="cursor:pointer"><title>' + esc(p.label) + ': ' + p.n + '</title></circle>'; off -= len; });
    svg.innerHTML = s;
    legend.innerHTML = parts.map(function (p, i) { return '<div data-i="' + i + '" role="link" tabindex="0"><i style="background:' + p.colour + '"></i>' + esc(p.label) + '<span class="p-n">' + p.n + '</span></div>'; }).join('');
    var go = function (e) { var t = e.target.closest('[data-i]'); if (t && parts[+t.dataset.i].href) location.href = parts[+t.dataset.i].href; };
    svg.onclick = go; legend.onclick = go; legend.onkeydown = function (e) { if (e.key === 'Enter') go(e); };
  }

  function delta(now, was, goodWhenDown) {
    if (was === null || was === undefined) return '';
    var d;
    if (was === 0 && now === 0) d = ['•', T('no change', 'walang pagbabago'), 'flat'];
    else if (was === 0) d = ['▲', T('new this month', 'bago ngayong buwan'), goodWhenDown ? 'bad' : 'good'];
    else {
      var pct = Math.round((now - was) / was * 100);
      if (pct === 0) d = ['•', T('level with last month', 'kapareho ng nakaraang buwan'), 'flat'];
      else d = [pct > 0 ? '▲' : '▼', Math.abs(pct) + T('% vs last month', '% vs nakaraang buwan'), (pct > 0) === !!goodWhenDown ? 'bad' : 'good'];
    }
    return '<span class="p-' + d[2] + '">' + d[0] + ' ' + esc(d[1]) + '</span>';
  }

  function render(m) {
    var daily = m.daily || [], eff = m.efficiency || [], st = m.resolution_status || {}, cats = m.categories || [], tiles = m.tiles || {};
    var total = m.total || 0;
    $('received-empty').hidden = total !== 0; $('chart-received').style.visibility = total ? '' : 'hidden';
    received($('chart-received'), daily.map(function (d) { return +d.filed || 0; }), daily.map(function (d) { return d.label; }));
    $('received-delta').innerHTML = delta(total, PREV_TOTAL);

    var parts = [
      { label: T('Done', 'Tapos'), n: +st.done || 0, colour: '#34C759', href: 'cases.php?status=resolved&month=' + MONTH },
      { label: T('Overdue work', 'Lampas-oras'), n: +st.overdue || 0, colour: '#F93535', href: 'cases.php?view=attention&month=' + MONTH },
      { label: T('Work finished late', 'Natapos nang huli'), n: +st.late || 0, colour: '#F9AB35', href: 'cases.php?view=attention&month=' + MONTH },
      { label: T('Processing', 'Pinoproseso'), n: +st.processing || 0, colour: '#356CF9', href: 'cases.php?status=in_progress&month=' + MONTH }
    ];
    if (+st.rejected) parts.push({ label: T('Denied', 'Tinanggihan'), n: +st.rejected, colour: '#8E9ABB', href: 'cases.php?status=rejected&month=' + MONTH });
    var stTotal = parts.reduce(function (a, p) { return a + p.n; }, 0);
    $('status-empty').hidden = stTotal !== 0;
    donut($('donut-status'), $('legend-status'), stTotal ? parts : []);
    $('status-donut-total').textContent = stTotal;
    $('status-donut-label').textContent = T(stTotal === 1 ? 'Report' : 'Reports', 'Ulat');

    var cp = cats.map(function (c) { return { label: CATEGORY_LABEL[c.category] || c.category, n: +c.n || 0, colour: CATEGORY_COLOUR[c.category] || '#8E9ABB', href: 'cases.php?category=' + encodeURIComponent(c.category) + '&month=' + MONTH }; });
    $('category-empty').hidden = cp.length !== 0;
    donut($('donut-category'), $('legend-category'), cp);
    $('category-donut-total').textContent = total;
    $('category-donut-label').textContent = T(total === 1 ? 'Report' : 'Reports', 'Ulat');

    var hasEff = eff.some(function (d) { return d.actual != null || d.allowed != null; });
    $('efficiency-empty').hidden = hasEff; $('chart-efficiency').style.visibility = hasEff ? '' : 'hidden'; $('eff-legend').style.visibility = hasEff ? '' : 'hidden';
    efficiencyChart($('chart-efficiency'), eff.map(function (d) { return d.actual == null ? null : +d.actual; }), eff.map(function (d) { return d.allowed == null ? null : +d.allowed; }), eff.map(function (d) { return d.label; }));

    $('tile-resolved-value').textContent = tiles.resolved || 0;
    $('tile-escalated-value').textContent = tiles.escalated || 0;
    $('tile-overdue-value').textContent = tiles.overdue || 0;
    var pr = PREV_TILES || {};
    $('tile-resolved-delta').innerHTML = delta(tiles.resolved || 0, pr.resolved != null ? pr.resolved : null);
    $('tile-escalated-delta').innerHTML = delta(tiles.escalated || 0, pr.escalated != null ? pr.escalated : null, true);
    $('tile-overdue-delta').innerHTML = delta(tiles.overdue || 0, pr.overdue != null ? pr.overdue : null, true);
  }

  document.querySelectorAll('#eff-legend button').forEach(function (b) {
    b.addEventListener('click', function () {
      var k = b.dataset.s, on = b.getAttribute('aria-pressed') !== 'true';
      if (!on && !effShow[k === 'taken' ? 'allowed' : 'taken']) return; // keep one line showing
      effShow[k] = on; b.setAttribute('aria-pressed', String(on)); render(M);
    });
  });
  var rz; window.addEventListener('resize', function () { clearTimeout(rz); rz = setTimeout(function () { render(M); }, 100); });
  window.addEventListener('themechange', function () { render(M); });
  render(M);

  // This month only: re-run dashboard_metrics when a report changes.
  if (!<?= json_encode($isCurrent) ?> || !window.supabase) return;
  var sb = window.supabase.createClient(<?= json_encode(supabase_url()) ?>, <?= json_encode(supabase_key()) ?>,
                                        { accessToken: window.ssAccessToken(<?= json_encode(access_token()) ?>) });
  var FROM = <?= json_encode($month->format(DateTimeInterface::ATOM)) ?>, TO = <?= json_encode($next->format(DateTimeInterface::ATOM)) ?>, CAT = <?= json_encode($effCategory ?: null) ?>;
  var timer = null, wasDown = false;
  function refresh() {
    clearTimeout(timer);
    timer = setTimeout(function () {
      sb.rpc('dashboard_metrics', { p_from: FROM, p_to: TO, p_category: CAT }).then(function (res) {
        if (res.error || !res.data) return; // stale figures beat a half-applied update
        M = res.data; render(M);
        $('as-of-time').textContent = new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Manila', hour: 'numeric', minute: '2-digit', hour12: true, day: 'numeric', month: 'short', year: 'numeric' }).format(new Date());
      });
    }, 400);
  }
  sb.channel('dashboard-metrics')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'reports' }, refresh)
    .subscribe(function (s) {
      var badge = $('live-badge'), text = $('live-badge-text'); if (!badge) return;
      if (s === 'SUBSCRIBED') { badge.classList.remove('p-down'); text.textContent = T('Live', 'Live'); if (wasDown) { wasDown = false; refresh(); } }
      else if (s === 'CHANNEL_ERROR' || s === 'TIMED_OUT' || s === 'CLOSED') { wasDown = true; badge.classList.add('p-down'); text.textContent = T('Reconnecting…', 'Kumokonekta muli…'); }
    });
})();
</script>

<?php layout_foot(); ?>
