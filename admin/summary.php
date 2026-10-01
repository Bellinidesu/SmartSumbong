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
// The printable report is the barangay's Complaint Summary form
// (complaint-summary.php, 30 Sep 2026); an old ?print=1 link goes there.
if (isset($_GET['print'])) {
    header('Location: complaint-summary.php?month=' . urlencode($from->format('Y-m')));
    exit;
}

// The seven categories are fixed per the Scope and Limitations — same list
// cases.php's category dropdown draws from.
const CATEGORIES = [
    'street_obstruction', 'public_safety_infrastructure', 'environmental_waste_hazard',
    'animal_welfare', 'traffic_violation', 'barangay_service', 'peace_order_nuisance', 'other',
];
$category = (string) ($_GET['category'] ?? '');
if (!in_array($category, CATEGORIES, true)) { $category = ''; }

{
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
                      . 'due_at,resolved_at,closed_at,referred_to,referral_note,referred_at,'
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

// This report's period can include today (the quick ranges above all do,
// except "Last month"), in which case the figures below can still move
// while it's on screen. A closed, past period is a fixed report and
// should read as one — no live badge, nothing to watch.
$isOngoing = $to >= new DateTimeImmutable('today', $tz);


layout_head(t('Report Summary', 'Buod ng mga Ulat'), 'summary.php');
?>

<div class="p-topbar"><h1><?= e(t('Report Summary', 'Buod ng mga Ulat')) ?></h1></div>

<?php if ($error): ?>
  <div class="p-flash p-flash--error" role="alert"><?= e($error) ?></div>
<?php endif; ?>

<?php if ($truncated): ?>
  <!-- Printed too: a signed report must not pass off a partial count. -->
  <div class="p-flash p-flash--warn" role="alert">
    <?= e(t('This period has more than ', 'Mahigit ')) ?><?= number_format(SUMMARY_MAX) ?><?= e(t(' rows in ', ' na hanay sa ')) ?>
    <?= e(implode(', ', array_map(fn($t) => str_replace('_', ' ', $t), array_keys($truncated)))) ?>;
    <?= e(t('only the first ', 'ang unang ')) ?><?= number_format(SUMMARY_MAX) ?><?= e(t(' are included. Choose a shorter period.', ' lamang ang kasama. Pumili ng mas maikling panahon.')) ?>
  </div>
<?php endif; ?>

<div class="p-band p-period-band">
  <h2><?= e(t('Report Period:', 'Panahon ng Ulat:')) ?>
    <?php if ($isOngoing): ?>
      <span class="p-watching" id="live-badge" title="<?= e(t('This period is still open — watching for new activity', 'Bukas pa ang panahong ito — binabantayan ang bagong aktibidad')) ?>"><i></i><span id="live-badge-text"><?= e(t('Watching', 'Nagbabantay')) ?></span></span>
    <?php endif; ?>
  </h2>
  <form method="get" class="p-period-form">
    <label class="p-pill-select"><span class="p-sr"><?= e(t('From', 'Mula')) ?></span><input type="date" id="from" name="from" value="<?= e($from->format('Y-m-d')) ?>"></label>
    <span class="p-to"><?= e(t('to', 'hanggang')) ?></span>
    <label class="p-pill-select"><span class="p-sr"><?= e(t('To', 'Hanggang')) ?></span><input type="date" id="to" name="to" value="<?= e($to->format('Y-m-d')) ?>"></label>
    <label class="p-pill-select"><span class="p-sr"><?= e(t('Category', 'Kategorya')) ?></span>
      <select id="category" name="category">
        <option value=""><?= e(t('All Categories', 'Lahat ng Kategorya')) ?></option>
        <?php foreach (CATEGORIES as $c): ?>
          <option value="<?= e($c) ?>" <?= $category === $c ? 'selected' : '' ?>><?= e(category_label($c)) ?></option>
        <?php endforeach; ?>
      </select></label>
    <button class="p-btn p-btn-primary p-btn-sm" style="height:36px" type="submit"><?= e(t('Apply', 'Ilapat')) ?></button>
  </form>
  <span class="p-chips-q">
    <?php foreach ($RANGES as $key => [$lbl, $a, $b]): ?>
      <a class="p-chip<?= $range === $key ? ' p-on' : '' ?>" href="?range=<?= e($key) ?>&amp;category=<?= e($category) ?>"><?= e($lbl) ?></a>
    <?php endforeach; ?>
  </span>
  <span class="p-spacer"></span>
  <?php // Rose (30 Sep 2026): the PDF is the barangay's Complaint Summary form. ?>
  <a class="p-btn-pdf2" target="_blank" rel="noopener" href="complaint-summary.php?month=<?= e($from->format('Y-m')) ?>"><?= p_icon('i-dl', 16) ?><?= e(t('Download PDF Report', 'I-download ang PDF na Ulat')) ?></a>
</div>

<?php if ($isOngoing): ?>
  <!-- A signed, printable document should never move under an admin's feet:
       new activity is announced, and included only on an explicit refresh. -->
  <div class="p-fresh p-upd" id="update-banner" role="status"><?= p_icon('i-bell', 16) ?>
    <span><?= e(t('New activity has been recorded for this period.', 'May bagong aktibidad na naitala sa panahong ito.')) ?></span>
    <a class="p-btn p-btn-ghost p-btn-sm" href="summary.php?<?= e(http_build_query(array_filter(['from' => $from->format('Y-m-d'), 'to' => $to->format('Y-m-d'), 'category' => $category, 'range' => $range]))) ?>"><?= e(t('Refresh to include it', 'I-refresh para maisama')) ?></a>
  </div>
<?php endif; ?>

<div class="p-kpis" style="margin-bottom:20px">
  <div class="p-card p-kpi"><div class="p-label"><?= e(t('Total Reports Logged', 'Kabuuang Naitalang Ulat')) ?></div><div class="p-value p-num"><?= str_pad((string) $total, 2, '0', STR_PAD_LEFT) ?></div></div>
  <div class="p-card p-kpi"><div class="p-label"><?= e(t('Case Resolved', 'Nalutas na Kaso')) ?></div><div class="p-value p-num"><?= str_pad((string) $resolved, 2, '0', STR_PAD_LEFT) ?></div>
    <?php if ($total > 0): ?><div class="p-delta p-up"><?= (int) round($resolved / $total * 100) ?><?= e(t('% of logged', '% ng naitala')) ?></div><?php endif; ?></div>
  <div class="p-card p-kpi"><div class="p-label"><?= e(t('Tanod Attendance Rate', 'Antas ng Pagdalo ng Tanod')) ?></div><div class="p-value p-num"><?= $rate === null ? '—' : $rate . '%' ?></div></div>
  <div class="p-card p-kpi"><div class="p-label"><?= e(t('Average Resolution Time', 'Karaniwang Tagal ng Paglutas')) ?></div><div class="p-value p-num"><?= $avgDays === null ? '—' : $avgDays . ' <span style="font-size:20px">' . e(t('days', 'araw')) . '</span>' ?></div>
    <?php if ($avgDays !== null): ?><div class="p-delta"><?= e(t('from filing to resolved', 'mula pagsampa hanggang nalutas')) ?></div><?php endif; ?></div>
</div>

<!-- ---------- Resident Report Ledger ---------- -->
<div class="p-card p-table-card" style="margin-bottom:20px">
  <div class="p-card-head" style="padding-bottom:14px"><h2><?= e(t('Resident Report Ledger', 'Talaan ng mga Ulat ng Residente')) ?></h2><span class="p-spacer"></span><span class="p-hint"><?= count($reports) ?> <?= e(t(count($reports) === 1 ? 'complaint' : 'complaints', 'sumbong')) ?></span></div>
  <div class="p-tscroll" style="max-height:360px"><table class="p-t">
    <thead class="p-orange"><tr>
      <th><?= e(t('Complaint ID', 'ID ng Sumbong')) ?></th><th><?= e(t('Resident', 'Residente')) ?></th><th><?= e(t('Category', 'Kategorya')) ?></th>
      <th><?= e(t('Status', 'Katayuan')) ?></th><th><?= e(t('Filed', 'Naisampa')) ?></th><th><?= e(t('Resolved', 'Nalutas')) ?></th>
    </tr></thead>
    <tbody>
      <?php if (!$reports): ?>
        <tr><td colspan="6" class="p-empty"><?= e(t('No complaints were filed in this period.', 'Walang naisampang sumbong sa panahong ito.')) ?></td></tr>
      <?php endif; ?>
      <?php foreach ($reports as $r): ?>
        <tr class="p-click" data-href="case.php?id=<?= e($r['id'] ?? '') ?>">
          <td><span class="p-mono-id"><?= e($r['tracking_id']) ?></span></td>
          <td><?= !empty($r['is_anonymous'])
                  ? '<span class="p-anon">' . e(t('Anonymous', 'Hindi nagpakilala')) . '</span>'
                  : e($r['resident']['full_name'] ?? t('Unknown', 'Hindi kilala')) ?></td>
          <td><?= e(category_label($r['category'])) ?></td>
          <td><?php if (!empty($r['referred_to'])): ?><span class="p-badge p-b-violet"><?= e(t('Escalated to ', 'In-escalate sa ') . $r['referred_to']) ?></span>
              <?php else: ?><span class="p-badge p-b-<?= e(status_class($r['status'])) ?>"><?= e(status_label($r['status'])) ?><?= report_is_overdue($r) ? e(t(' (overdue)', ' (lampas na)')) : '' ?></span><?php endif; ?></td>
          <td class="p-num"><?= e(short_date($r['created_at'])) ?></td>
          <td class="p-num"><?= e(short_date($r['resolved_at'] ?? $r['closed_at'] ?? null)) ?: '<span class="p-sub">—</span>' ?></td>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table></div>
</div>

<!-- ---------- Referrals (0072) ---------- -->
<?php $referrals = array_values(array_filter($reports, fn($r) => !empty($r['referred_to']))); ?>
<div class="p-card p-table-card" style="margin-bottom:20px">
  <div class="p-card-head" style="padding-bottom:14px"><h2><?= e(t('Escalations to Outside Offices', 'Mga In-escalate sa Ibang Tanggapan')) ?></h2></div>
  <div class="p-tscroll" style="max-height:300px"><table class="p-t">
    <thead class="p-blue"><tr>
      <th scope="col"><?= e(t('Complaint ID', 'ID ng Sumbong')) ?></th><th scope="col"><?= e(t('Category', 'Kategorya')) ?></th>
      <th scope="col"><?= e(t('Escalated to', 'In-escalate sa')) ?></th><th scope="col"><?= e(t('Date', 'Petsa')) ?></th><th scope="col"><?= e(t('Note', 'Tala')) ?></th>
    </tr></thead>
    <tbody>
      <?php if (!$referrals): ?>
        <tr><td colspan="5" class="p-empty"><?= e(t('No complaint was escalated outside the barangay in this period.', 'Walang sumbong na in-escalate sa labas ng barangay sa panahong ito.')) ?></td></tr>
      <?php endif; ?>
      <?php foreach ($referrals as $r): ?>
        <tr>
          <td><span class="p-mono-id"><?= e($r['tracking_id']) ?></span></td>
          <td><?= e(category_label($r['category'])) ?></td>
          <td><b><?= e($r['referred_to']) ?></b></td>
          <td class="p-num"><?= e(short_date($r['referred_at'] ?? null)) ?: '—' ?></td>
          <td><?= !empty($r['referral_note']) ? e($r['referral_note']) : '<span class="p-sub">—</span>' ?></td>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table></div>
</div>

<!-- ---------- Tanod's Activity Timeline ---------- -->
<div class="p-card p-table-card" style="margin-bottom:20px">
  <div class="p-card-head" style="padding-bottom:14px"><h2><?= t('Tanod&rsquo;s Activity Timeline', 'Takbo ng Gawain ng mga Tanod') ?></h2></div>
  <div class="p-tscroll" style="max-height:340px"><table class="p-t">
    <thead class="p-blue"><tr><th>Tanod</th><th><?= e(t('Complaint', 'Sumbong')) ?></th><th><?= e(t('Assigned', 'Na-assign')) ?></th><th><?= e(t('Accepted', 'Tinanggap')) ?></th><th><?= e(t('Outcome', 'Kinalabasan')) ?></th></tr></thead>
    <tbody>
      <?php if (!$dispatches): ?>
        <tr><td colspan="5" class="p-empty"><?= e(t('No dispatches were issued in this period.', 'Walang dispatch na inilabas sa panahong ito.')) ?></td></tr>
      <?php endif; ?>
      <?php foreach ($dispatches as $d): ?>
        <tr>
          <td><b><?= e($d['tanod']['full_name'] ?? t('Unknown', 'Hindi kilala')) ?></b></td>
          <td><span class="p-mono-id"><?= e($d['report']['tracking_id'] ?? '—') ?></span></td>
          <td class="p-num"><?= e(long_datetime($d['assigned_at'])) ?></td>
          <td class="p-num"><?= $d['accepted_at'] ? e(long_datetime($d['accepted_at'])) : '<span class="p-over">' . e(t('Not accepted', 'Hindi tinanggap')) . '</span>' ?></td>
          <td><?= e(status_label($d['state'])) ?></td>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table></div>
</div>

<!-- ---------- Report Case Timeline: pick a complaint, see its changes ---------- -->
<?php
$byReport = [];
foreach ($logs as $l) {
    $tid = $l['report']['tracking_id'] ?? '—';
    $byReport[$tid][] = $l;
}
?>
<div class="p-card">
  <div class="p-card-head"><h2><?= e(t('Report Case Timeline', 'Takbo ng mga Kaso')) ?></h2></div>
  <?php if (!$byReport): ?>
    <p class="p-empty" style="padding:22px"><?= e(t('No case activity was recorded in this period.', 'Walang naitalang aktibidad sa kaso sa panahong ito.')) ?></p>
  <?php else: ?>
  <div class="p-rs-split" style="display:grid;grid-template-columns:minmax(260px,340px) 1fr;padding:14px 0 0">
    <div class="p-tscroll" style="max-height:440px;border-right:1px solid var(--p-line)"><table class="p-t">
      <thead><tr><th><?= e(t('Complaint', 'Sumbong')) ?></th><th class="p-right"><?= e(t('Changes', 'Pagbabago')) ?></th></tr></thead>
      <tbody id="tl-pick">
        <?php $i = 0; foreach ($byReport as $tid => $list): ?>
          <tr class="p-click<?= $i === 0 ? ' p-sel' : '' ?>" data-tl="<?= $i ?>" tabindex="0"><td><span class="p-mono-id"><?= e($tid) ?></span></td><td class="p-right p-num"><?= count($list) ?></td></tr>
        <?php $i++; endforeach; ?>
      </tbody>
    </table></div>
    <div style="padding:6px 22px 22px">
      <?php $i = 0; foreach ($byReport as $tid => $list): ?>
        <div class="p-tl-group" data-tl="<?= $i ?>"<?= $i === 0 ? '' : ' hidden' ?>>
          <p class="p-eyebrow"><?= e($tid) ?></p>
          <ul class="p-tl-change">
            <?php foreach ($list as $l): ?>
              <li><span class="p-w"><?= e(long_datetime($l['created_at'])) ?></span><b><?= e(timeline_title($l)) ?><?php if (($l['repeat'] ?? 1) > 1): ?> <span class="p-sub">× <?= (int) $l['repeat'] ?></span><?php endif; ?></b>
                <span class="p-by"><?= !empty($l['is_system']) ? e(t('System', 'System')) : e($l['by']['full_name'] ?? t('Barangay staff', 'Kawani ng barangay')) ?></span>
                <?php if (!empty($l['remark'])): ?><span class="p-rm"><?= e($l['remark']) ?></span><?php endif; ?></li>
            <?php endforeach; ?>
          </ul>
        </div>
      <?php $i++; endforeach; ?>
    </div>
  </div>
  <?php endif; ?>
</div>
<script>
(function () {
  var pick = document.getElementById('tl-pick'); if (!pick) return;
  function show(i) {
    pick.querySelectorAll('tr').forEach(function (tr) { tr.classList.toggle('p-sel', tr.dataset.tl === i); });
    document.querySelectorAll('.p-tl-group').forEach(function (g) { g.hidden = g.dataset.tl !== i; });
  }
  pick.addEventListener('click', function (e) { var tr = e.target.closest('tr[data-tl]'); if (tr) show(tr.dataset.tl); });
  pick.addEventListener('keydown', function (e) { var tr = e.target.closest('tr[data-tl]'); if (tr && e.key === 'Enter') show(tr.dataset.tl); });
})();
</script>

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
      { accessToken: window.ssAccessToken(TOKEN) }
    );

    sb.channel('summary-period')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'reports' },
        function () { document.getElementById('update-banner').classList.add('p-on'); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'dispatches' },
        function () { document.getElementById('update-banner').classList.add('p-on'); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'status_logs' },
        function () { document.getElementById('update-banner').classList.add('p-on'); })
      .subscribe(function (status) {
        var badge = document.getElementById('live-badge'),
            text  = document.getElementById('live-badge-text');
        if (!badge) return;
        if (status === 'SUBSCRIBED') { badge.classList.remove('p-down'); text.textContent = T('Watching', 'Nagbabantay'); }
        else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
          badge.classList.add('p-down'); text.textContent = T('Reconnecting…', 'Kumokonekta muli…');
        }
      });
  })();
  </script>
  <?php endif; ?>
  <?php layout_foot(); ?>
