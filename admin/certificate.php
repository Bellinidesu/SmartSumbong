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

$report = null;
$error  = null;
try {
    $rows = $db->select('reports', [
        'select'     => 'id,tracking_id,referred_to,resident:users!reports_resident_id_fkey(full_name,address)',
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
?>
<form class="doc-toolbar" method="get">
  <a href="case.php?id=<?= e($id) ?>">&larr; <?= e($report['tracking_id'] ?? 'Case') ?></a>
  <input type="hidden" name="id" value="<?= e($id) ?>">
  <label>Name <input type="text" name="name" value="<?= e($name) ?>" size="20"></label>
  <label>Address <input type="text" name="address" value="<?= e($address) ?>" size="24"></label>
  <label>Date <input type="date" name="date" value="<?= e($issued->format('Y-m-d')) ?>"></label>
  <label>Requested by <input type="text" name="by" value="<?= e($by) ?>" size="18"></label>
  <span style="flex-basis:100%;height:0"></span>
  <?php foreach (CERT_REASONS as $key => $r): ?>
    <label><input type="checkbox" name="r[]" value="<?= e($key) ?>" <?= in_array($key, $ticked, true) ? 'checked' : '' ?>> <?= e($r['office']) ?></label>
  <?php endforeach; ?>
  <button type="submit" style="background:#fff;color:#00308f">Update</button>
  <span class="spacer"></span>
  <button type="button" onclick="window.print()">Print / Save as PDF</button>
</form>

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
      requested by <span class="fill"><?= e($name !== '' ? $name : '[User Full Name]') ?></span> residing in
      <span class="fill"><?= e($address !== '' ? $address : '[Address]') ?></span> due to the following reason:</p>

    <ul class="reasons">
      <?php foreach (CERT_REASONS as $key => $r): ?>
        <li>
          <span class="box"><?= in_array($key, $ticked, true) ? '&#10003;' : '' ?></span>
          <span><strong><?= e($r['lead']) ?></strong><?= $r['rest'] !== '' ? ' ' . e($r['rest']) : '' ?></span>
        </li>
      <?php endforeach; ?>
    </ul>

    <p class="indent">This Certification is being issued upon the request of the interested party for
      whatever legal purposes this may serve.</p>
    <p class="indent">Issued this <span class="fill"><?= e($issued->format('jS \d\a\y \o\f F Y')) ?></span></p>
  </div>
  <?php endif; ?>

  <?php doc_requested_by($by); ?>
</div>
</body>
</html>
