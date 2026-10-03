<?php
/**
 * Certification of Lack of Jurisdiction (Rose, 30 Sep 2026) — the
 * barangay's own form, for one complaint. Issued when the barangay cannot
 * give a Certification to File Action because the matter belongs elsewhere;
 * it goes with the escalation to an outside office.
 *
 * The reason is ticked from the office the complaint was escalated to
 * (case.php, refer_report); the admin can change any field before printing.
 * Name and address come from the resident's account.
 *
 * The editor is a "document desk" (3 Oct 2026): the certificate on a desk
 * with zoom, and an inspector beside it — a Ready to print checklist, the
 * requester's details, the reasons, and the case's history. Printing is
 * logged on the case's own trail (status_logs, as the admin), so History
 * and the case timeline both show when a certificate went out. The
 * certificate itself, and what prints, are unchanged.
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/doc_print.php';

$admin = require_admin();
$db    = db();
$tz    = new DateTimeZone('Asia/Manila');
$id    = (string) ($_GET['id'] ?? '');

/** The form's reasons, in its order, with the office each one goes with. */
const CERT_REASONS = [
    'kp' => [
        'office' => 'Lupong Tagapamayapa',
        'lead'   => 'The complaint is under the Katarungang Pambarangay.',
        'rest'   => '',
    ],
    'criminal' => [
        'office' => 'Philippine National Police',
        'lead'   => 'The nature of the complaint involves a criminal offense.',
        'rest'   => 'The complaint is hereby referred directly to the Philippine National Police (PNP), Villamor Substation.',
    ],
    'vawc' => [
        'office' => 'VAWC Desk',
        'lead'   => 'The nature of the complaint involves Violence Against Women and Their Children (VAWC).',
        'rest'   => 'By law, VAWC is a public crime and is strictly prohibited from being subjected to barangay conciliation. The complainant is hereby referred to the VAWC Desk Support.',
    ],
    'official' => [
        'office' => 'Office of the Ombudsman',
        'lead'   => 'One of the parties involved is a public officer or employee, and the dispute relates to the performance of their official functions.',
        'rest'   => 'The complainant is advised to file the appropriate administrative or criminal action before the Office of the Ombudsman or the relevant government agency.',
    ],
    'residence' => [
        'office' => 'Regular Courts',
        'lead'   => 'The disputing parties do not actually reside in the same city or municipality.',
        'rest'   => 'The complainant is advised to file the case directly with the appropriate regular courts.',
    ],
];

const CERT_PRINT_REMARK = 'Certification of Lack of Jurisdiction printed';

$report = null;
$error  = null;
try {
    $rows = $db->select('reports', [
        'select'     => 'id,tracking_id,status,referred_to,resident:users!reports_resident_id_fkey(full_name,address)',
        'id'         => 'eq.' . $id,
        'deleted_at' => 'is.null',
        'limit'      => '1',
    ]);
    $report = $rows[0] ?? null;
    if (!$report) {
        $error = 'That complaint could not be found.';
    }
} catch (SupabaseError $ex) {
    $error = safe_error($ex);
}

// Print, logged on the case's trail: the same status in and out, with a remark.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['do'] ?? '') === 'printed') {
    header('Content-Type: application/json');
    if (!$report || !csrf_check($_POST['csrf'] ?? null)) { http_response_code(400); echo '{"ok":false}'; exit; }
    $for = trim((string) ($_POST['for'] ?? ''));
    try {
        $db->insert('status_logs', [
            'report_id'  => $report['id'],
            'changed_by' => $admin['id'],
            'old_status' => $report['status'],
            'new_status' => $report['status'],
            'remark'     => CERT_PRINT_REMARK . ($for !== '' ? ' for ' . mb_substr($for, 0, 120) : ''),
        ]);
        echo '{"ok":true}';
    } catch (Throwable $e) {
        http_response_code(500); echo '{"ok":false}';
    }
    exit;
}

// The case's history, newest first.
$history = [];
if ($report) {
    try {
        $history = $db->select('status_logs', [
            'select'    => 'old_status,new_status,remark,created_at,by:users!status_logs_changed_by_fkey(full_name)',
            'report_id' => 'eq.' . $report['id'],
            'order'     => 'created_at.desc',
            'limit'     => '8',
        ]);
    } catch (Throwable) { $history = []; }
}

// Defaults from the complaint; anything in the query string wins.
$suggested = [];
foreach (CERT_REASONS as $key => $r) {
    if (($report['referred_to'] ?? null) === $r['office']) {
        $suggested[] = $key;
    }
}
$ticked  = isset($_GET['r']) ? array_values(array_intersect((array) $_GET['r'], array_keys(CERT_REASONS))) : $suggested;
$name    = trim((string) ($_GET['name'] ?? ($report['resident']['full_name'] ?? '')));
$address = trim((string) ($_GET['address'] ?? ($report['resident']['address'] ?? '')));
$by      = trim((string) ($_GET['by'] ?? $name));
try {
    $issued = new DateTimeImmutable((string) ($_GET['date'] ?? 'today'), $tz);
} catch (Exception) {
    $issued = new DateTimeImmutable('today', $tz);
}

doc_head('Certification of Lack of Jurisdiction');
$short = ['kp' => 'KP', 'criminal' => 'PNP', 'vawc' => 'VAWC', 'official' => 'OMB', 'residence' => 'RTC'];
$tzM   = new DateTimeZone('Asia/Manila');
$when  = fn(string $iso) => (new DateTimeImmutable($iso))->setTimezone($tzM)->format('j M Y, g:i A');
?>
<style>
  /* ── Document desk (screen only) ── */
  @media screen {
    html, body { height: 100%; }
    body { display: flex; flex-direction: column; font-family: Urbanist, "Segoe UI", Arial, sans-serif; font-size: 15px; color: var(--cd-ink); background: var(--cd-bg); }
    body::before { display: none; }
    :root { --cd-ink: #141B34; --cd-ink2: #3A4058; --cd-muted: #6E7489; --cd-bg: #E9EDF5; --cd-surface: #fff; --cd-surface2: #F8F9FC; --cd-line: #E3E6EE; --cd-dot: rgba(20,27,52,.16);
            --cd-green: #1F8A45; --cd-green-bg: #E5F6EA; --cd-amber: #A36400; --cd-amber-bg: #FFF1D6; --cd-blue: #00308F; --cd-blue-50: #EEF3FF; --z: 1; }
    :root[data-theme="dark"] { --cd-ink: #E9ECF5; --cd-ink2: #C3C8D8; --cd-muted: #9096AB; --cd-bg: #0B101C; --cd-surface: #161C2E; --cd-surface2: #1B2236; --cd-line: #273050; --cd-dot: rgba(200,210,255,.12);
            --cd-green: #5FD68A; --cd-green-bg: #173424; --cd-amber: #FFC061; --cd-amber-bg: #3A2C12; --cd-blue-50: #17264A; }
    .cd-bar { flex: none; display: flex; align-items: center; gap: 12px; padding: 10px 16px; background: var(--cd-surface); border-bottom: 1px solid var(--cd-line); flex-wrap: wrap; }
    .cd-back { display: inline-flex; align-items: center; height: 34px; padding: 0 12px; border-radius: 10px; border: 1px solid var(--cd-line); background: var(--cd-surface2); font-weight: 700; font-size: 13px; color: var(--cd-ink); text-decoration: none; }
    .cd-crumb { color: var(--cd-muted); font-size: 13.5px; font-weight: 600; }
    .cd-crumb a { color: inherit; text-decoration: none; } .cd-crumb b { color: var(--cd-ink); }
    .cd-sp { flex: 1; }
    .cd-state { font: 700 12px Inter, sans-serif; padding: 5px 11px; border-radius: 99px; display: inline-flex; align-items: center; gap: 6px; }
    .cd-state::before { content: ""; width: 7px; height: 7px; border-radius: 50%; background: currentColor; }
    .cd-state.ok { background: var(--cd-green-bg); color: var(--cd-green); } .cd-state.wait { background: var(--cd-amber-bg); color: var(--cd-amber); }
    .cd-btn { height: 38px; padding: 0 18px; border-radius: 11px; border: 0; background: #FF9800; color: #fff; font: 800 14px Urbanist, Arial, sans-serif; box-shadow: 0 4px 12px rgba(255,152,0,.3); cursor: pointer; }
    .cd-btn:hover { background: #F08A00; }
    .cd-btn[disabled] { opacity: .45; cursor: not-allowed; box-shadow: none; }
    .cd-work { flex: 1; min-height: 0; display: grid; grid-template-columns: minmax(0, 1fr) 340px; }
    .cd-desk { position: relative; overflow: auto; background: radial-gradient(circle at 1px 1px, var(--cd-dot) 1px, transparent 0) 0 0 / 18px 18px, var(--cd-bg); }
    .cd-stage { padding: 32px 24px 96px; display: grid; justify-content: center; }
    .cd-wrap { width: calc(8.5in * var(--z)); height: calc(11in * var(--z)); }
    .cd-wrap .doc-page { color: #111; background: #fff; font-family: "Century Gothic", "Questrial", "Avenir", "Segoe UI", Arial, sans-serif; font-size: 12.5pt; margin: 0; transform: scale(var(--z)); transform-origin: top left; box-shadow: 0 2px 6px rgba(20,27,52,.10), 0 22px 60px rgba(20,27,52,.22); border-radius: 2px; }
    .doc-page .fill { border-radius: 3px; transition: background .25s; }
    .doc-page .fill.cd-empty { color: #b45309; }
    .doc-page .fill.cd-flash { background: #DCE7FF; }
    .reasons li { border-radius: 4px; transition: background .25s, box-shadow .25s; }
    .reasons li.cd-on { background: #FFF7D6; box-shadow: 0 0 0 4px #FFF7D6; }
    .cd-tools { position: sticky; bottom: 16px; margin: -72px auto 0; width: max-content; display: flex; gap: 4px; padding: 5px; border-radius: 12px; background: var(--cd-surface); border: 1px solid var(--cd-line); box-shadow: 0 8px 24px rgba(20,27,52,.18); z-index: 2; }
    .cd-tools button, .cd-tools span { height: 32px; min-width: 32px; padding: 0 10px; border-radius: 8px; border: 0; background: none; font: 700 12.5px Inter, sans-serif; color: var(--cd-ink2); display: grid; place-items: center; cursor: pointer; }
    .cd-tools span { cursor: default; } .cd-tools button:hover { background: var(--cd-surface2); }
    .cd-tools .cd-z { min-width: 58px; color: var(--cd-ink); }
    .cd-tools .cd-sep { width: 1px; min-width: 1px; padding: 0; background: var(--cd-line); margin: 6px 2px; }
    .cd-insp { background: var(--cd-surface); border-left: 1px solid var(--cd-line); overflow: auto; }
    .cd-sec { padding: 16px 18px; border-bottom: 1px solid var(--cd-line); display: grid; gap: 11px; }
    .cd-sec h2 { margin: 0; display: flex; justify-content: space-between; align-items: center; font: 700 11.5px Inter, sans-serif; letter-spacing: .09em; text-transform: uppercase; color: var(--cd-muted); }
    .cd-count { font: 700 11.5px Inter, sans-serif; padding: 3px 9px; border-radius: 99px; letter-spacing: 0; }
    .cd-count.ok { background: var(--cd-green-bg); color: var(--cd-green); } .cd-count.wait { background: var(--cd-amber-bg); color: var(--cd-amber); }
    .cd-chk { display: grid; gap: 8px; font-size: 13.5px; }
    .cd-chk div { display: flex; gap: 9px; align-items: center; color: var(--cd-ink2); }
    .cd-chk i { width: 18px; height: 18px; border-radius: 50%; display: grid; place-items: center; font: 800 10px Inter, sans-serif; font-style: normal; flex: none; }
    .cd-chk .y i { background: var(--cd-green); color: #fff; } .cd-chk .n i { border: 2px solid var(--cd-amber); } .cd-chk .n { color: var(--cd-muted); }
    .cd-field { display: grid; gap: 5px; }
    .cd-field label { font: 700 11px Inter, sans-serif; letter-spacing: .06em; text-transform: uppercase; color: var(--cd-muted); }
    .cd-field input { height: 40px; border: 1px solid var(--cd-line); border-radius: 11px; background: var(--cd-surface2); padding: 0 12px; font: 600 14px Urbanist, Arial, sans-serif; color: var(--cd-ink); width: 100%; }
    .cd-field input:focus { outline: none; border-color: var(--cd-blue); box-shadow: 0 0 0 3px rgba(0,48,143,.18); background: var(--cd-surface); }
    .cd-field input::placeholder { color: var(--cd-muted); font-weight: 500; font-style: italic; }
    .cd-seg { display: grid; grid-template-columns: repeat(5, 1fr); gap: 5px; }
    .cd-seg button { height: 34px; border-radius: 9px; border: 1px solid var(--cd-line); background: var(--cd-surface2); font: 700 11.5px Inter, sans-serif; color: var(--cd-ink2); position: relative; cursor: pointer; }
    .cd-seg button[aria-pressed="true"] { background: var(--cd-blue); border-color: var(--cd-blue); color: #fff; }
    .cd-seg button.sug::after { content: ""; position: absolute; top: -4px; right: -4px; width: 9px; height: 9px; border-radius: 50%; background: #FF9800; border: 2px solid var(--cd-surface); }
    .cd-why { font-size: 12.5px; color: var(--cd-muted); line-height: 1.45; min-height: 36px; }
    .cd-why b { color: var(--cd-ink); }
    .cd-note { font-size: 12.5px; background: var(--cd-blue-50); color: var(--cd-ink2); border-radius: 9px; padding: 8px 10px; display: flex; gap: 8px; align-items: center; line-height: 1.4; }
    .cd-note i { width: 8px; height: 8px; border-radius: 50%; background: #FF9800; flex: none; }
    .cd-note.warn { background: var(--cd-amber-bg); color: var(--cd-amber); }
    .cd-hist { list-style: none; margin: 0; padding: 0; display: grid; gap: 10px; font-size: 12.5px; color: var(--cd-muted); }
    .cd-hist li { display: grid; grid-template-columns: 10px 1fr; gap: 10px; }
    .cd-hist li::before { content: ""; width: 8px; height: 8px; border-radius: 50%; background: var(--cd-line); margin-top: 4px; }
    .cd-hist li:first-child::before { background: var(--cd-blue); }
    .cd-hist li.cd-print::before { background: #FF9800; }
    .cd-hist b { color: var(--cd-ink); }
    .cd-toast { position: fixed; left: 50%; bottom: 24px; transform: translate(-50%, 20px); opacity: 0; background: var(--cd-ink); color: var(--cd-surface); padding: 10px 16px; border-radius: 10px; font-weight: 600; font-size: 13.5px; transition: .25s; pointer-events: none; z-index: 9; }
    .cd-toast.on { opacity: 1; transform: translate(-50%, 0); }
    @media (max-width: 900px) { .cd-work { grid-template-columns: 1fr; } .cd-insp { border-left: 0; border-top: 1px solid var(--cd-line); } .cd-desk { min-height: 70vh; } }
  }
  @media print {
    .cd-bar, .cd-insp, .cd-tools, .cd-toast { display: none !important; }
    .cd-work, .cd-desk, .cd-stage, .cd-wrap { display: block; width: auto; height: auto; padding: 0; margin: 0; background: none; overflow: visible; }
    .cd-wrap .doc-page { transform: none; }
    .reasons li.cd-on { background: none; box-shadow: none; }
    .doc-page .fill.cd-empty { color: inherit; }
  }
</style>

<header class="cd-bar">
  <a class="cd-back" href="case.php?id=<?= e($id) ?>">&lsaquo; <?= e($report['tracking_id'] ?? 'Case') ?></a>
  <span class="cd-crumb"><a href="cases.php">Case Reports</a> &rsaquo; <a href="case.php?id=<?= e($id) ?>"><?= e($report['tracking_id'] ?? '') ?></a> &rsaquo; <b>Certification of Lack of Jurisdiction</b></span>
  <span class="cd-sp"></span>
  <span class="cd-state wait" id="cd-state">Checking…</span>
  <button class="cd-btn" id="cd-print" type="button" disabled>Print / Save as PDF</button>
</header>

<div class="cd-work">
  <section class="cd-desk" id="cd-desk" aria-label="Certificate">
    <div class="cd-stage"><div class="cd-wrap">
<div class="doc-page">
  <?php doc_letterhead(); ?>
  <p class="doc-title">CERTIFICATION OF LACK OF JURISDICTION</p>

  <?php if ($error): ?>
    <p style="color:#a01818"><?= e($error) ?></p>
  <?php else: ?>
  <style>
    .cert p { line-height: 1.45; text-align: justify; margin: 0 0 12px; }
    .cert .indent { text-indent: 0.5in; }
    .reasons { list-style: none; margin: 18px 0 18px 0.35in; padding: 0; }
    .reasons li { display: grid; grid-template-columns: 22px 1fr; gap: 6px; margin-bottom: 12px; text-align: justify; line-height: 1.4; }
    .box { width: 16px; height: 16px; border: 1.2px solid #111; margin-top: 3px; display: grid; place-items: center; font-size: 13px; line-height: 1; }
  </style>
  <div class="cert">
    <p class="indent">This office certifies that it cannot possibly issue the Certification to File Action being
      requested by <span class="fill" data-fill="name" data-empty="[User Full Name]"><?= e($name !== '' ? $name : '[User Full Name]') ?></span> residing in
      <span class="fill" data-fill="address" data-empty="[Address]"><?= e($address !== '' ? $address : '[Address]') ?></span> due to the following reason:</p>

    <ul class="reasons">
      <?php foreach (CERT_REASONS as $key => $r): ?>
        <li data-li="<?= e($key) ?>">
          <span class="box" data-box="<?= e($key) ?>"><?= in_array($key, $ticked, true) ? '&#10003;' : '' ?></span>
          <span><strong><?= e($r['lead']) ?></strong><?= $r['rest'] !== '' ? ' ' . e($r['rest']) : '' ?></span>
        </li>
      <?php endforeach; ?>
    </ul>

    <p class="indent">This Certification is being issued upon the request of the interested party for
      whatever legal purposes this may serve.</p>
    <p class="indent">Issued this <span class="fill" data-fill="date"><?= e($issued->format('jS \d\a\y \o\f F Y')) ?></span></p>
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

  <aside class="cd-insp" aria-label="Certificate details">
    <div class="cd-sec"><h2>Ready to print <span class="cd-count wait" id="cd-cnt"></span></h2><div class="cd-chk" id="cd-chk"></div></div>
    <div class="cd-sec"><h2>Requester</h2>
      <div class="cd-field"><label for="f-name">Name</label><input id="f-name" data-k="name" value="<?= e($name) ?>" autocomplete="off"></div>
      <div class="cd-field"><label for="f-address">Address</label><input id="f-address" data-k="address" value="<?= e($address) ?>" placeholder="House no., street, Barangay 183" autocomplete="off"></div>
      <div class="cd-field"><label for="f-date">Date issued</label><input id="f-date" data-k="date" type="date" value="<?= e($issued->format('Y-m-d')) ?>"></div>
      <div class="cd-field"><label for="f-by">Requested by</label><input id="f-by" data-k="by" value="<?= e($by) ?>" autocomplete="off"></div>
    </div>
    <div class="cd-sec"><h2>Reason</h2>
      <?php if (!empty($report['referred_to']) && $suggested): ?>
        <div class="cd-note"><i></i><span>The case was escalated to the <b><?= e($report['referred_to']) ?></b>, so <?= e($short[$suggested[0]]) ?> is suggested.</span></div>
      <?php elseif (!empty($report['referred_to'])): ?>
        <div class="cd-note warn"><span>Escalated to <b><?= e($report['referred_to']) ?></b>, which is not one of this form's reasons. Choose the reason that applies.</span></div>
      <?php endif; ?>
      <div class="cd-seg" id="cd-seg" role="group" aria-label="Reasons">
        <?php foreach (CERT_REASONS as $key => $r): ?>
          <button type="button" data-r="<?= e($key) ?>" class="<?= in_array($key, $suggested, true) ? 'sug' : '' ?>" title="<?= e($r['office']) ?>" aria-pressed="<?= in_array($key, $ticked, true) ? 'true' : 'false' ?>"><?= e($short[$key]) ?></button>
        <?php endforeach; ?>
      </div>
      <div class="cd-why" id="cd-why"></div>
    </div>
    <div class="cd-sec"><h2>History</h2>
      <ul class="cd-hist" id="cd-hist">
        <?php if (!$history): ?><li><span>No activity recorded yet.</span></li><?php endif; ?>
        <?php foreach ($history as $h):
          $printed = str_starts_with((string) ($h['remark'] ?? ''), CERT_PRINT_REMARK);
          $what = $printed ? 'Certificate printed' : ($h['old_status'] === null ? 'Filed' : status_label((string) $h['new_status'])); ?>
          <li class="<?= $printed ? 'cd-print' : '' ?>"><span><b><?= e($what) ?></b><?= !empty($h['by']['full_name']) ? ' by ' . e($h['by']['full_name']) : '' ?>
            <?php if (!$printed && !empty($h['remark'])): ?><br><?= e(mb_strimwidth((string) $h['remark'], 0, 90, '…')) ?><?php endif; ?>
            <br><?= e($when((string) $h['created_at'])) ?></span></li>
        <?php endforeach; ?>
      </ul>
    </div>
  </aside>
</div>
<div class="cd-toast" id="cd-toast" role="status"></div>

<script>
(function () {
  var REASONS = <?= json_encode(array_map(fn($k, $r) => [$k, $short[$k], $r['office'], $r['lead']], array_keys(CERT_REASONS), CERT_REASONS), JSON_UNESCAPED_UNICODE) ?>;
  var CSRF = <?= json_encode(csrf_token()) ?>, ADMIN = <?= json_encode($admin['full_name'] ?? 'Admin') ?>;
  var EMPTY = { name: '[User Full Name]', address: '[Address]', by: 'Name of Requestor' };
  var $ = function (id) { return document.getElementById(id); };
  var esc = function (s) { return String(s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  var ticked = {}; document.querySelectorAll('#cd-seg [aria-pressed="true"]').forEach(function (b) { ticked[b.dataset.r] = true; });

  function ord(n) { var s = ['th', 'st', 'nd', 'rd'], v = n % 100; return n + (s[(v - 20) % 10] || s[v] || s[0]); }
  function dateText(v) { if (!v) return ''; var p = v.split('-').map(Number), d = new Date(p[0], p[1] - 1, p[2]); return ord(p[2]) + ' day of ' + d.toLocaleString('en-US', { month: 'long' }) + ' ' + p[0]; }
  function fill(k, flash) {
    var v = $('f-' + k).value.trim();
    var els = k === 'by' ? document.querySelectorAll('.req .fill') : document.querySelectorAll('[data-fill="' + k + '"]');
    els.forEach(function (el) {
      el.textContent = k === 'date' ? (dateText(v) || '[date]') : (v || EMPTY[k]);
      el.classList.toggle('cd-empty', !v);
      if (flash) { el.classList.add('cd-flash'); clearTimeout(el._t); el._t = setTimeout(function () { el.classList.remove('cd-flash'); }, 600); }
    });
  }
  function render() {
    document.querySelectorAll('.reasons li').forEach(function (li) { var on = !!ticked[li.dataset.li]; li.classList.toggle('cd-on', on); li.querySelector('.box').innerHTML = on ? '&#10003;' : ''; });
    document.querySelectorAll('#cd-seg button').forEach(function (b) { b.setAttribute('aria-pressed', ticked[b.dataset.r] ? 'true' : 'false'); });
    var on = REASONS.filter(function (r) { return ticked[r[0]]; });
    $('cd-why').innerHTML = on.length ? on.map(function (r) { return '<b>' + r[1] + '</b> · ' + esc(r[2]); }).join('<br>') : 'Choose at least one reason. Point at a button to see its office.';
    var checks = [["Requester's name", !!$('f-name').value.trim()], ['Address', !!$('f-address').value.trim()], ['At least one reason', on.length > 0], ['Date of issue', !!$('f-date').value]];
    var done = checks.filter(function (c) { return c[1]; }).length, ready = done === checks.length;
    $('cd-chk').innerHTML = checks.map(function (c) { return '<div class="' + (c[1] ? 'y' : 'n') + '"><i>' + (c[1] ? '&#10003;' : '') + '</i>' + c[0] + '</div>'; }).join('');
    $('cd-cnt').textContent = done + ' of ' + checks.length; $('cd-cnt').className = 'cd-count ' + (ready ? 'ok' : 'wait');
    $('cd-state').textContent = ready ? 'Ready to print' : (checks.length - done) + ' left to fill'; $('cd-state').className = 'cd-state ' + (ready ? 'ok' : 'wait');
    $('cd-print').disabled = !ready;
  }
  document.querySelectorAll('.cd-insp input').forEach(function (i) { i.addEventListener('input', function () { fill(i.dataset.k, true); render(); }); });
  $('cd-seg').addEventListener('click', function (e) { var b = e.target.closest('button'); if (!b) return; var k = b.dataset.r; ticked[k] = !ticked[k]; render();
    var li = document.querySelector('.reasons li[data-li="' + k + '"]'); if (li && ticked[k]) li.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); });
  $('cd-seg').addEventListener('mouseover', function (e) { var b = e.target.closest('button'); if (!b) return; var r = REASONS.filter(function (x) { return x[0] === b.dataset.r; })[0]; $('cd-why').innerHTML = '<b>' + r[1] + '</b> · ' + esc(r[2]) + '<br>' + esc(r[3]); });
  $('cd-seg').addEventListener('mouseleave', render);

  // Zoom.
  var z = 1, inch = 96;
  function setZ(v) { z = Math.max(.4, Math.min(1.6, Math.round(v * 100) / 100)); document.documentElement.style.setProperty('--z', z); $('cd-zl').textContent = Math.round(z * 100) + '%'; }
  $('cd-zi').onclick = function () { setZ(z + .1); }; $('cd-zo').onclick = function () { setZ(z - .1); };
  $('cd-zf').onclick = function () { var d = $('cd-desk'); setZ(Math.min((d.clientWidth - 48) / (8.5 * inch), (d.clientHeight - 64) / (11 * inch))); };
  $('cd-zw').onclick = function () { setZ(($('cd-desk').clientWidth - 48) / (8.5 * inch)); };

  function toast(t) { $('cd-toast').textContent = t; $('cd-toast').classList.add('on'); clearTimeout(toast._t); toast._t = setTimeout(function () { $('cd-toast').classList.remove('on'); }, 2600); }
  // Print: log it on the case's trail, then open the print dialog.
  $('cd-print').onclick = function () {
    var who = $('f-name').value.trim(), body = new URLSearchParams({ do: 'printed', csrf: CSRF, for: who });
    fetch(location.href, { method: 'POST', body: body, credentials: 'same-origin' }).then(function (r) { return r.json(); }).then(function (j) {
      if (!j.ok) return;
      var h = $('cd-hist'), li = document.createElement('li'); li.className = 'cd-print';
      li.innerHTML = '<span><b>Certificate printed</b> by ' + esc(ADMIN) + '<br>' + new Date().toLocaleString('en-US', { day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit' }) + '</span>';
      if (h.firstElementChild && /No activity/.test(h.firstElementChild.textContent)) h.innerHTML = '';
      h.prepend(li);
    }).catch(function () { toast('Printed, but it could not be logged on the case.'); });
    window.print();
  };
  ['name', 'address', 'date', 'by'].forEach(function (k) { fill(k); });
  render();
  requestAnimationFrame(function () { $('cd-zf').click(); });
})();
</script>
</body>
</html>
