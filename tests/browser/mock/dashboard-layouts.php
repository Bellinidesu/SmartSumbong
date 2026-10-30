<?php
/**
 * THROWAWAY MOCKUP, test site only (tests/browser/serve.sh copies it beside the portal; it is never in the image).
 * The six dashboard layouts from the Looksmaxxing board, drawn in the real portal chrome with the fake Supabase's demo numbers, in
 * either theme, for any role (?as=super|committee|moderator|captain). Open: /admin/dashboard-layouts.php  (?l=1..6 or ?l=all)
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/forwarding.php';

// the role switcher: the test router reads these two cookies on the next request
if (isset($_GET['as'])) {
    $as = in_array($_GET['as'], ['super', 'committee', 'moderator', 'captain'], true) ? $_GET['as'] : 'super';
    setcookie('ss_tier', $as, 0, '/');
    setcookie('ss_committee', $as === 'committee' || $as === 'moderator' ? 'peace_order' : '', 0, '/');
    header('Location: dashboard-layouts.php' . (isset($_GET['l']) ? '?l=' . urlencode((string) $_GET['l']) : ''));
    exit;
}
$admin = require_admin();
$db = db();
$tier = my_tier();
$scoped = is_scoped();
$l = (string) ($_GET['l'] ?? '1');
if ($l !== 'all' && !in_array($l, ['1', '2', '3', '4', '5', '6'], true)) { $l = '1'; }

// the numbers: the same calls the real Dashboard makes, against the fake backend
$m = $coms = [];
try {
    $m = (array) $db->rpc('dashboard_metrics', ['p_from' => date('Y-m-01') . 'T00:00:00+08:00', 'p_to' => date('Y-m-01', strtotime('+1 month')) . 'T00:00:00+08:00', 'p_category' => null]);
    $coms = (array) $db->rpc('dashboard_committees', ['p_month_from' => date('Y-m-01') . 'T00:00:00+08:00']);
} catch (Throwable) {}
// a believable month for the picture (the fake backend's own series zigzags)
$daily = []; for ($i = 1; $i <= 30; $i++) { $daily[] = ['label' => (string) $i, 'filed' => max(0, (int) round(3 + 2.2 * sin($i / 3.4) + 1.2 * sin($i / 1.3) + ($i > 22 ? 1.5 : 0)))]; }
$status = $m['resolution_status'] ?? ['done' => 30, 'overdue' => 4, 'late' => 3, 'processing' => 12, 'rejected' => 2];
$cats = $m['categories'] ?? [];
usort($cats, fn ($a, $b) => (int) $b['n'] <=> (int) $a['n']);
$needs = $coms['needs_me'] ?? ['escalations' => 1, 'to_place' => 1, 'tanods' => 1, 'overdue' => 4, 'no_committee' => 2, 'open' => 15];
$comRows = $coms['committees'] ?? [];
$none = $coms['none'] ?? ['open' => 2, 'overdue' => 0, 'month' => 2];
$reports = [];
try { $reports = array_slice((array) $db->select('reports', ['select' => 'id,tracking_id,subject,category,status,case_committee', 'order' => 'created_at.desc', 'limit' => '12']), 0, 12); } catch (Throwable) {}
$reasons = [['Overdue 2 days', 'bad'], ['Waiting for a tanod · 40 min', 'warn'], ['Handed up: place it', 'info'], ['Staff flagged it', 'warn'], ['Reroute: pick a tanod · 4 min', 'bad'], ['Overdue 5 h', 'bad'], ['Forwarded to you', 'info'], ['Quiet for 4 days', 'warn']];

// ---------- blocks ----------
function mk_card(string $cls, string $title, string $body, string $more = '', string $sub = ''): string
{
    return '<section class="p-card lm-b ' . $cls . '"><header><h2>' . e($title) . '</h2>' . ($sub !== '' ? '<small>' . e($sub) . '</small>' : '') . '<span class="p-spacer"></span>' . ($more !== '' ? '<a class="lm-more" href="#">' . e($more) . ' &rarr;</a>' : '') . '</header>' . $body . '</section>';
}
function mk_kpis(array $n, string $cls = 'b-kpi'): string
{
    $t = [[t('Waiting for you', 'Naghihintay sa iyo'), (int) $n['escalations'] + (int) $n['to_place'] + (int) $n['tanods'], 'hot', t('to decide or place', 'pagpapasyahan o ilalagay')],
          [t('Overdue', 'Lampas-oras'), (int) $n['overdue'], 'hot', t('open past the deadline', 'bukas na lampas sa deadline')],
          [t('No committee yet', 'Wala pang komite'), (int) $n['no_committee'], 'warn', t('open, nobody has them', 'bukas, walang may hawak')],
          [t('Open now', 'Bukas ngayon'), (int) $n['open'], '', t('across the barangay', 'sa buong barangay')]];
    $o = '<div class="' . $cls . ' lm-k">';
    foreach ($t as [$lab, $v, $tone, $sub]) { $o .= '<a class="p-card lm-kt ' . $tone . '" href="#"><span>' . e($lab) . '</span><b class="p-num">' . $v . '</b><small>' . e($sub) . '</small></a>'; }
    return $o . '</div>';
}
function mk_queue(array $reports, array $reasons, int $n, string $cls, string $title, ?string $more = null): string
{
    $rows = '';
    foreach (array_slice($reports, 0, $n) as $i => $r) {
        [$why, $tone] = $reasons[$i % count($reasons)];
        $rows .= '<li><span class="p-mono-id">' . e($r['tracking_id']) . '</span><span class="lm-subj">' . e($r['subject']) . '</span>'
              . committee_pill($r['case_committee'] ?? null) . '<span class="lm-why ' . $tone . '">' . e($why) . '</span><a class="p-btn p-btn-sm p-btn-orange" href="#">' . e(is_captain() ? t('View', 'Tingnan') : t('Review', 'Suriin')) . '</a></li>';
    }
    return mk_card($cls . ' lm-q', $title, '<ul class="lm-list">' . $rows . '</ul>', $more ?? t('See all', 'Tingnan lahat'), t('most urgent first', 'pinakaapurahan muna'));
}
function mk_trend(array $daily, string $cls, string $title): string
{
    $v = array_map(fn ($d) => (int) ($d['filed'] ?? 0), $daily) ?: [1, 2, 3];
    $W = 760; $H = 190; $max = max(4, max($v)); $n = count($v);
    $pts = []; foreach ($v as $i => $y) { $pts[] = round(24 + ($W - 40) * $i / max(1, $n - 1), 1) . ',' . round(10 + ($H - 36) * (1 - $y / $max), 1); }
    $line = 'M' . implode(' L', $pts);
    $svg = '<svg viewBox="0 0 ' . $W . ' ' . $H . '" class="lm-trend" preserveAspectRatio="none" role="img" aria-label="' . e(t('Reports filed each day', 'Mga ulat na naisampa bawat araw')) . '"><defs><linearGradient id="lg' . md5($cls) . '" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="var(--p-orange)" stop-opacity=".35"/><stop offset="1" stop-color="var(--p-orange)" stop-opacity="0"/></linearGradient></defs>';
    for ($g = 0; $g <= 4; $g++) { $y = 10 + ($H - 36) * $g / 4; $svg .= '<line x1="24" x2="' . ($W - 16) . '" y1="' . $y . '" y2="' . $y . '" stroke="var(--p-line)" stroke-dasharray="3 5"/>'; }
    $svg .= '<path d="' . $line . ' L' . ($W - 16) . ',' . ($H - 26) . ' L24,' . ($H - 26) . ' Z" fill="url(#lg' . md5($cls) . ')"/><path d="' . $line . '" fill="none" stroke="var(--p-orange)" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"/></svg>';
    return mk_card($cls, $title, $svg, t('Report Summary', 'Buod ng Ulat'), date('F Y'));
}
function mk_donut(array $s, string $cls, string $title): string
{
    $parts = [[t('Done', 'Tapos'), (int) $s['done'], '#34C759'], [t('Overdue', 'Lampas-oras'), (int) $s['overdue'], '#F93535'], [t('Finished late', 'Natapos nang huli'), (int) $s['late'], '#F9AB35'], [t('Processing', 'Pinoproseso'), (int) $s['processing'], '#356CF9']];
    $tot = max(1, array_sum(array_column($parts, 1))); $off = 25; $c = ''; $leg = '';
    foreach ($parts as [$lab, $n, $col]) { $len = $n / $tot * 100; $c .= '<circle cx="21" cy="21" r="15.9" fill="none" stroke="' . $col . '" stroke-width="5" stroke-dasharray="' . max(0, $len - 1) . ' ' . (100 - $len + 1) . '" stroke-dashoffset="' . $off . '"/>'; $off -= $len; $leg .= '<li><i style="background:' . $col . '"></i>' . e($lab) . '<b class="p-num">' . $n . '</b></li>'; }
    return mk_card($cls, $title, '<div class="lm-donut"><div class="lm-dsvg"><svg viewBox="0 0 42 42"><circle cx="21" cy="21" r="15.9" fill="none" stroke="var(--p-line)" stroke-width="5"/>' . $c . '</svg><div><b class="p-num">' . $tot . '</b><small>' . e(t('reports', 'ulat')) . '</small></div></div><ul class="lm-leg">' . $leg . '</ul></div>', t('Case Reports', 'Mga Sumbong'));
}
function mk_cats(array $cats, string $cls, string $title, int $n = 6): string
{
    $top = array_slice($cats, 0, $n); $max = max(1, (int) ($top[0]['n'] ?? 1)); $o = '<ul class="lm-bars">';
    foreach ($top as $c) { $o .= '<li><span>' . e(category_label((string) $c['category'])) . '</span><div><i style="width:' . round($c['n'] / $max * 100) . '%;background:' . e(category_colours()[$c['category']] ?? 'var(--p-orange)') . '"></i></div><b class="p-num">' . (int) $c['n'] . '</b></li>'; }
    return mk_card($cls, $title, $o . '</ul>', t('All kinds', 'Lahat ng uri'));
}
function mk_committees(array $rows, array $none, string $cls, string $title): string
{
    $max = 1; foreach ($rows as $r) { $max = max($max, (int) $r['open']); } $o = '<ul class="lm-bars lm-com">';
    foreach ($rows as $r) { $o .= '<li><span>' . committee_pill((string) $r['key']) . '</span><div><i style="width:' . round($r['open'] / $max * 100) . '%;background:' . e(committee_colour((string) $r['key'])) . '"></i></div><b class="p-num">' . (int) $r['open'] . '</b><small class="' . ((int) $r['overdue'] > 0 ? 'bad' : '') . '">' . (int) $r['overdue'] . ' ' . e(t('overdue', 'lampas')) . '</small></li>'; }
    $o .= '<li><span>' . committee_pill(null) . '</span><div><i style="width:' . round($none['open'] / $max * 100) . '%;background:var(--p-red)"></i></div><b class="p-num">' . (int) $none['open'] . '</b><small>' . (int) $none['overdue'] . ' ' . e(t('overdue', 'lampas')) . '</small></li>';
    return mk_card($cls, $title, $o . '</ul>', t('Administrative Services', 'Mga Serbisyong Pang-admin'));
}
function mk_feed(string $cls, string $title): string
{
    $ev = [['SS-2610-1001', t('filed', 'naisampa'), '2 min', 'g'], ['SS-2610-1004', t('forwarded to Environment', 'ipinasa sa Environment'), '9 min', 'i'], ['SS-2610-1007', t('tanod accepted', 'tinanggap ng tanod'), '14 min', 'g'],
           ['SS-2610-1003', t('staff flagged for forwarding', 'in-flag ng kawani'), '31 min', 'w'], ['SS-2610-1012', t('resolved', 'nalutas'), '1 h', 'g'], ['SS-2610-1010', t('no answer: nearest tanod sent', 'walang sagot: ipinadala ang pinakamalapit'), '1 h', 'w']];
    $o = '<ul class="lm-feed">'; foreach ($ev as [$id, $what, $when, $tone]) { $o .= '<li class="' . $tone . '"><i></i><span><span class="p-mono-id">' . e($id) . '</span> ' . e($what) . '</span><small>' . e($when) . '</small></li>'; }
    return mk_card($cls, $title, $o . '</ul>', t('Activity', 'Aktibidad'), t('live', 'live'));
}
function mk_map(string $cls, string $title): string
{
    $pins = [[120, 90, 'peace_order'], [210, 150, 'environment'], [300, 70, 'health_sanitation'], [380, 180, 'peace_order'], [260, 120, 'environment'], [90, 170, 'peace_order'], [340, 120, null], [180, 60, 'health_sanitation']];
    $s = '<svg viewBox="0 0 480 240" class="lm-map" role="img" aria-label="' . e(t('Map of open cases', 'Mapa ng mga bukás na kaso')) . '"><rect width="480" height="240" rx="12" fill="var(--p-surface-2)"/>';
    for ($i = 1; $i < 7; $i++) { $s .= '<ellipse cx="260" cy="130" rx="' . (28 * $i) . '" ry="' . (16 * $i) . '" fill="none" stroke="var(--p-line)" stroke-width="1.4"/>'; }
    $s .= '<path d="M0 190 C120 150 200 210 320 160 S440 120 480 140" fill="none" stroke="var(--p-sky)" stroke-width="3" opacity=".5"/>';
    foreach ($pins as [$x, $y, $k]) { $col = $k ? committee_colour($k) : 'var(--p-red)'; $s .= '<circle cx="' . $x . '" cy="' . $y . '" r="11" fill="' . $col . '" opacity=".22"/><circle cx="' . $x . '" cy="' . $y . '" r="5" fill="' . $col . '" stroke="var(--p-surface)" stroke-width="2"/>'; }
    return mk_card($cls, $title, $s . '</svg><p class="lm-note">' . e(t('Stand-in drawing. The real build uses the live map from Spatial Distribution, pins coloured by committee.', 'Larawang panghalili. Gagamitin sa totoong bersyon ang live na mapa, kulay ayon sa komite.')) . '</p>', t('Spatial Distribution', 'Mapa ng mga Sumbong'));
}

/** One layout, by number. */
function mk_layout(int $n, array $d): string
{
    extract($d);
    $q = fn (int $k, string $cls, string $title, ?string $more = null) => mk_queue($reports, $reasons, $k, $cls, $title, $more);
    $o = '<div class="lm lm' . $n . '">';
    switch ($n) {
        case 1:
            $o .= mk_kpis($needs) . $q(8, 'b-queue', t('Needs me now', 'Kailangan ako ngayon')) . mk_donut($status, 'b-donut', t('Complaint status', 'Katayuan ng mga sumbong')) . mk_cats($cats, 'b-cats', t('Complaints by kind', 'Mga sumbong ayon sa uri'), 5);
            break;
        case 2:
            $o .= mk_kpis($needs) . $q(6, 'b-queue', t('Needs me now', 'Kailangan ako ngayon')) . mk_map('b-map', t('Open cases on the map', 'Mga bukás na kaso sa mapa')) . mk_feed('b-feed', t('Live feed', 'Live na daloy'));
            break;
        case 3:
            $o .= mk_trend($daily, 'b-trend', t('Reports received', 'Mga natanggap na ulat')) . mk_donut($status, 'b-donut', t('Complaint status', 'Katayuan ng mga sumbong')) . mk_kpis($needs, 'b-kpi')
               . mk_cats($cats, 'b-cats', t('Complaints by kind', 'Mga sumbong ayon sa uri'), 5) . mk_committees($comRows, $none, 'b-com', t('The committees', 'Ang mga komite')) . mk_feed('b-feed', t('Live feed', 'Live na daloy'));
            break;
        case 4:
            $o .= mk_committees($comRows, $none, 'b-com', t('The committees', 'Ang mga komite')) . mk_kpis($needs) . mk_trend($daily, 'b-trend', t('Reports received', 'Mga natanggap na ulat'))
               . mk_feed('b-feed', t('Live feed', 'Live na daloy')) . $q(4, 'b-queue', t('Needs me now', 'Kailangan ako ngayon'));
            break;
        case 5:
            $o .= mk_kpis($needs) . mk_trend($daily, 'b-trend', t('Reports received', 'Mga natanggap na ulat')) . $q(5, 'b-queue', t('Needs me now', 'Kailangan ako ngayon'), t('Open the queue', 'Buksan ang pila'))
               . mk_committees($comRows, $none, 'b-com', t('The committees', 'Ang mga komite')) . mk_feed('b-feed', t('Live feed', 'Live na daloy'));
            break;
        case 6:
            $o .= $q(4, 'b-mine', t('My cases', 'Mga kaso ko'), t('All mine', 'Lahat ng akin')) . mk_queue(array_slice($reports, 4), $reasons, 4, 'b-due', t('Due today', 'Takdang oras ngayon'), t('All due', 'Lahat ng due'))
               . mk_committees($comRows, $none, 'b-com', t('Committee load', 'Dami ng gawain ng komite')) . mk_donut($status, 'b-donut', t('Complaint status', 'Katayuan ng mga sumbong')) . mk_cats($cats, 'b-cats', t('Complaints by kind', 'Mga sumbong ayon sa uri'), 5);
            break;
    }
    return $o . '</div>';
}

$names = [1 => t('1. Triage first', '1. Triage muna'), 2 => t('2. Map at the centre', '2. Mapa sa gitna'), 3 => t('3. Trend hero', '3. Trend ang bida'), 4 => t('4. Side rails', '4. Mga gilid'), 5 => t('5. Summary with drill-downs', '5. Buod na may lalim'), 6 => t('6. My work first', '6. Gawain ko muna')];
$lean = ['super' => 1, 'committee' => 6, 'moderator' => 6, 'captain' => 5][$tier] ?? 1;
$data = compact('needs', 'status', 'cats', 'daily', 'comRows', 'none', 'reports', 'reasons');
layout_head(t('Dashboard layouts', 'Mga layout ng Dashboard'), 'dashboard.php');
?>
<style>
.lm-bar { display: flex; flex-wrap: wrap; gap: 8px 14px; align-items: center; margin: 4px 0 16px; }
.lm-bar nav { display: flex; flex-wrap: wrap; gap: 6px; }
.lm-bar a.lm-t { padding: 7px 14px; border-radius: 999px; border: 1px solid var(--p-line); background: var(--p-surface); color: var(--p-ink); font-weight: 700; font-size: 13px; text-decoration: none; }
.lm-bar a.lm-t.on { background: var(--p-orange); color: #2B1A00; border-color: transparent; }
.lm-bar .lean { font-size: 13px; color: var(--p-muted); }
.lm-bar .lean b { color: var(--p-ink); }
.lm-role { margin-left: auto; display: flex; gap: 6px; align-items: center; font-size: 13px; color: var(--p-muted); }
.lm-warn { padding: 10px 14px; border-radius: 14px; border: 1px dashed var(--p-orange); background: var(--p-orange-50); color: var(--p-ink); font-size: 13.5px; margin-bottom: 18px; }
.lm-h { margin: 28px 0 10px; display: flex; gap: 10px; align-items: baseline; }
.lm-h h2 { margin: 0; font-size: 20px; }
.lm { display: grid; grid-template-columns: repeat(12, minmax(0, 1fr)); gap: 16px; align-items: stretch; }
.lm-b { padding: 16px 18px; display: grid; gap: 12px; align-content: start; min-width: 0; }
.lm-b > header { display: flex; align-items: baseline; gap: 10px; }
.lm-b h2 { margin: 0; font-size: 16px; }
.lm-b small { color: var(--p-muted); }
.lm-more { font-size: 12.5px; font-weight: 700; color: var(--p-link); text-decoration: none; white-space: nowrap; }
.lm-k { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 16px; }
.lm-kt { display: grid; gap: 2px; padding: 14px 16px; text-decoration: none; color: var(--p-ink); }
.lm-kt span { font-size: 13px; color: var(--p-muted); font-weight: 600; }
.lm-kt b { font-size: 34px; line-height: 1.1; }
.lm-kt.hot b { color: var(--p-red); } .lm-kt.warn b { color: var(--p-amber); }
.lm-list { list-style: none; margin: 0; padding: 0; display: grid; }
.lm-list li { display: grid; grid-template-columns: auto minmax(0, 1fr) auto auto auto; gap: 10px; align-items: center; padding: 9px 0; border-top: 1px solid var(--p-line); }
.lm-list li:first-child { border-top: 0; }
.lm-subj { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.lm-why { font-size: 12px; font-weight: 700; padding: 2px 9px; border-radius: 999px; white-space: nowrap; }
.lm-why.bad { background: var(--p-red-bg); color: var(--p-red); } .lm-why.warn { background: var(--p-amber-bg); color: var(--p-amber); } .lm-why.info { background: var(--p-sky-bg); color: var(--p-sky); }
.lm-trend { width: 100%; height: 100%; min-height: 190px; display: block; }
.lm-b.b-trend { grid-template-rows: auto minmax(0, 1fr); }
.lm-donut { display: grid; grid-template-columns: 150px minmax(0, 1fr); gap: 16px; align-items: center; }
.lm-dsvg { position: relative; } .lm-dsvg svg { width: 100%; display: block; transform: rotate(0deg); }
.lm-dsvg > div { position: absolute; inset: 0; display: grid; place-content: center; text-align: center; }
.lm-dsvg b { font-size: 28px; line-height: 1; }
.lm-leg, .lm-bars, .lm-feed { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
.lm-leg li { display: flex; align-items: center; gap: 8px; font-size: 13.5px; } .lm-leg li b { margin-left: auto; }
.lm-leg i { width: 10px; height: 10px; border-radius: 3px; flex: none; }
.lm-bars li { display: grid; grid-template-columns: minmax(90px, 36%) minmax(0, 1fr) auto; gap: 10px; align-items: center; font-size: 13.5px; }
.lm-bars li > div { height: 8px; border-radius: 999px; background: var(--p-line); overflow: hidden; } .lm-bars li > div i { display: block; height: 100%; border-radius: 999px; }
.lm-com li { grid-template-columns: minmax(120px, 44%) minmax(0, 1fr) auto auto; }
.lm-com small.bad { color: var(--p-red); font-weight: 700; }
.lm-feed li { display: grid; grid-template-columns: 10px minmax(0, 1fr) auto; gap: 10px; align-items: baseline; font-size: 13.5px; }
.lm-feed li i { width: 8px; height: 8px; border-radius: 50%; background: var(--p-green); } .lm-feed li.w i { background: var(--p-orange); } .lm-feed li.i i { background: var(--p-sky); }
.lm-map { width: 100%; height: auto; display: block; } .lm-note { font-size: 12px; color: var(--p-muted); margin: 0; }
/* the six grids */
.lm1 .lm-k { grid-column: 1 / -1; } .lm1 .b-queue { grid-column: 1 / 8; grid-row: span 2; } .lm1 .b-donut { grid-column: 8 / -1; } .lm1 .b-cats { grid-column: 8 / -1; }
.lm2 .lm-k { grid-column: 1 / -1; } .lm2 .b-queue { grid-column: 1 / 5; } .lm2 .b-map { grid-column: 5 / 10; } .lm2 .b-feed { grid-column: 10 / -1; }
.lm2 .b-queue .lm-list li { grid-template-columns: auto minmax(0, 1fr) auto; } .lm2 .b-queue .lm-list li > :nth-child(n+3):not(a) { display: none; }
.lm3 .b-trend { grid-column: 1 / 9; grid-row: span 2; } .lm3 .b-donut { grid-column: 9 / -1; } .lm3 .lm-k { grid-column: 9 / -1; grid-template-columns: 1fr 1fr; gap: 12px; } .lm3 .lm-kt b { font-size: 26px; }
.lm3 .b-cats { grid-column: 1 / 5; } .lm3 .b-com { grid-column: 5 / 9; } .lm3 .b-feed { grid-column: 9 / -1; }
.lm3 .b-donut .lm-donut { grid-template-columns: 1fr; } .lm3 .b-donut .lm-dsvg { max-width: 150px; margin-inline: auto; }
.lm4 .b-com { grid-column: 1 / 4; grid-row: span 3; } .lm4 .lm-k { grid-column: 4 / 10; grid-template-columns: repeat(2, 1fr); gap: 12px; } .lm4 .b-trend { grid-column: 4 / 10; grid-row: span 2; }
.lm4 .b-feed { grid-column: 10 / -1; } .lm4 .b-queue { grid-column: 10 / -1; grid-row: span 2; }
.lm4 .b-com .lm-com li { grid-template-columns: 1fr auto; } .lm4 .b-com .lm-com li > div, .lm4 .b-com .lm-com li > small { display: none; }
.lm4 .b-queue .lm-list li { grid-template-columns: auto minmax(0, 1fr) auto; } .lm4 .b-queue .lm-list li > :nth-child(n+3):not(a) { display: none; }
.lm5 .lm-k { grid-column: 1 / -1; } .lm5 .b-trend { grid-column: 1 / -1; } .lm5 .b-queue { grid-column: 1 / 5; } .lm5 .b-com { grid-column: 5 / 9; } .lm5 .b-feed { grid-column: 9 / -1; }
.lm5 .b-queue .lm-list li { grid-template-columns: auto minmax(0, 1fr) auto; } .lm5 .b-queue .lm-list li > :nth-child(n+3):not(a) { display: none; }
.lm6 .b-mine { grid-column: 1 / 7; } .lm6 .b-due { grid-column: 7 / -1; } .lm6 .b-com { grid-column: 1 / -1; } .lm6 .b-donut { grid-column: 1 / 7; } .lm6 .b-cats { grid-column: 7 / -1; }
.lm6 .b-mine .lm-list li, .lm6 .b-due .lm-list li { grid-template-columns: auto minmax(0, 1fr) auto auto; } .lm6 .b-mine .lm-list li > .cm-pill, .lm6 .b-due .lm-list li > .cm-pill { display: none; }
@media (max-width: 1100px) { .lm > * { grid-column: 1 / -1 !important; grid-row: auto !important; } .lm-k { grid-template-columns: repeat(2, 1fr) !important; } }
</style>

<div class="p-topbar"><h1><?= e(t('Dashboard layouts', 'Mga layout ng Dashboard')) ?></h1></div>
<div class="lm-warn" role="note"><?= e(t('Mockup on the test site only: the six layouts from the Looksmaxxing board, drawn with demo numbers. Nothing here is the real Dashboard and none of it is saved. The theme toggle in the sidebar switches dark and light.', 'Mockup lang sa test site: ang anim na layout mula sa Looksmaxxing board, may demo na numero. Hindi ito ang totoong Dashboard at wala itong sine-save. Ang theme toggle sa sidebar ang nagpapalit ng dark at light.')) ?></div>

<div class="lm-bar">
  <nav aria-label="<?= e(t('Layouts', 'Mga layout')) ?>">
    <?php foreach ($names as $k => $nm): ?><a class="lm-t<?= $l === (string) $k ? ' on' : '' ?>" href="?l=<?= $k ?>"><?= e($nm) ?></a><?php endforeach; ?>
    <a class="lm-t<?= $l === 'all' ? ' on' : '' ?>" href="?l=all"><?= e(t('All six', 'Lahat ng anim')) ?></a>
  </nav>
  <span class="lean"><?= e(t('Viewing as', 'Tinitingnan bilang')) ?> <b><?= e(access_label()) ?></b> · <?= e(t('my lean for this role:', 'aking mungkahi para sa papel na ito:')) ?> <b><?= e($names[$lean]) ?></b></span>
  <span class="lm-role"><?= e(t('View as', 'Tingnan bilang')) ?>
    <?php foreach (['super' => t('Super admin', 'Super admin'), 'committee' => t('Kagawad', 'Kagawad'), 'moderator' => t('Staff', 'Kawani'), 'captain' => t('Captain', 'Kapitan')] as $rk => $rl): ?>
      <a class="lm-t<?= $tier === $rk ? ' on' : '' ?>" href="?as=<?= $rk ?>&amp;l=<?= e($l) ?>"><?= e($rl) ?></a><?php endforeach; ?>
  </span>
</div>

<?php if ($l === 'all'): foreach ($names as $k => $nm): ?>
  <div class="lm-h"><h2><?= e($nm) ?></h2><?= $k === $lean ? '<span class="p-badge p-b-done">' . e(t('my lean for this role', 'aking mungkahi para sa papel na ito')) . '</span>' : '' ?></div>
  <?= mk_layout($k, $data) ?>
<?php endforeach; else: ?>
  <div class="lm-h"><h2><?= e($names[(int) $l]) ?></h2><?= (int) $l === $lean ? '<span class="p-badge p-b-done">' . e(t('my lean for this role', 'aking mungkahi para sa papel na ito')) . '</span>' : '' ?></div>
  <?= mk_layout((int) $l, $data) ?>
<?php endif; ?>
<?php layout_foot();
