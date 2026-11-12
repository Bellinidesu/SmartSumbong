<?php
/**
 * Home (4 Nov 2026, Priority 2 part 3): a Kagawad's or staff member's own page, where they land after signing in. Everything on
 * it is read from their module of the SMART engine (smart_module(), 0165), so it shows only their committee's cases. The
 * Dashboard stays the super admins' (Sir Kiko: the Dashboard is for the super admin only).
 *
 *   the committee's banner, and under it what needs the person: a Kagawad's decisions, a staff member's own cases
 *   right now: open, urgent with no tanod, overdue, due in 24 hours, nobody has taken, theirs
 *   the engine's lists: likely to miss the deadline, quiet cases; the tanods now, spikes, recurring problems
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/forwarding.php';   // the committee's banner
require_once __DIR__ . '/includes/module_brain.php';   // the brain button, from the same module

$admin = require_admin();
$db    = db();
$tz    = new DateTimeZone('Asia/Manila');

$m = smart_module_read($db);   // one read, shared with the brain button
$ok   = is_array($m);
$cn   = $ok ? (array) ($m['counts'] ?? []) : [];
$dc   = $ok && is_array($m['decisions'] ?? null) ? $m['decisions'] : null;
$tn   = $ok ? (array) ($m['tanods'] ?? []) : [];
$risk = $ok ? (array) ($m['deadline_risk'] ?? []) : [];
$quiet = $ok ? (array) ($m['quiet'] ?? []) : [];
$spikes = $ok ? (array) ($m['spikes'] ?? []) : [];
$pats = $ok ? (array) ($m['patterns'] ?? []) : [];
$isCom = is_committee();
$ck = (string) ($admin['committee'] ?? '');
$cRow = committees_all()[$ck] ?? null;
$sdTypes = $cRow ? committee_sd_types($db) : [];
$me = (string) ($admin['id'] ?? '');

layout_head(t('Home', 'Tahanan'), 'home.php');

$now = new DateTimeImmutable('now', $tz); $hr = (int) $now->format('G');
$first = trim((string) strtok(display_name((string) ($admin['full_name'] ?? '')), ' '));
$flair = greeting_flair($now, $first);
// a tile: a number that opens the cases behind it
$tile = function (string $href, string $label, $n, string $sub, bool $hot = false): string {
    $n = (int) $n;
    return '<a class="p-card ss-tile hm-tile' . ($hot && $n > 0 ? ' hot' : '') . '" href="' . e($href) . '"><span>' . e($label) . '</span><b class="p-num">' . $n . '</b><small>' . e($sub) . '</small></a>';
};
$riskLabel = fn (string $r): string => $r === 'high' ? t('High', 'Mataas') : t('Medium', 'Katamtaman');
$hoursLeft = function ($h): string {
    $h = (float) $h;
    if ($h < 1) return sprintf(t('%d min', '%d minuto'), max(1, (int) round($h * 60)));
    if ($h < 48) return sprintf(t('%s h', '%s oras'), rtrim(rtrim(number_format($h, 1), '0'), '.'));
    return sprintf(t('%d days', '%d araw'), (int) round($h / 24));
};
?>
<div class="p-dash-top">
  <header class="dh-greet"><h1><?= e($flair['headline']) ?></h1>
    <p><?= e($now->format('l, F j')) ?><?php if ($flair['event'] !== null): ?> &middot; <span class="dh-event"><?= e($flair['event']) ?></span><?php endif; ?> &middot;<?= e($isCom ? t('here is what needs you today.', 'narito ang kailangan mo ngayon.') : t('here is what needs handling today.', 'narito ang dapat asikasuhin ngayon.')) ?></p></header>
  <span class="p-spacer"></span>
  <span class="p-asof"><?= e(t('Data as of', 'Datos hanggang')) ?> <span class="p-num"><?= e($now->format('g:i A, j M Y')) ?></span></span>
  <?= module_brain($db, false) ?>
</div>

<?php if (!$ok): ?>
  <div class="p-flash p-flash--error" role="alert"><?= e(t('The SMART engine could not be read just now. Try again in a moment; your cases are in Case Reports.', 'Hindi mabasa ang SMART engine ngayon. Subukan muli mamaya; nasa Case Reports ang mga kaso mo.')) ?></div>
<?php else: ?>

<!-- the committee's banner, joined to what needs this person -->
<section class="hm-lead" aria-label="<?= e($isCom ? t('Needs your decision', 'Kailangan ng desisyon mo') : t('Your work', 'Ang trabaho mo')) ?>">
  <?php if ($cRow): ?>
    <div class="cm-chips cmx-banner hm-banner"><a class="cm-chip cm-sd" href="cases.php" title="<?= e((string) $cRow['name_en']) ?>" style="<?= e(cm_banner_style($ck, $sdTypes)) ?>"><?= cm_sym_tag($ck, $sdTypes, (string) $cRow['short_en']) ?><span class="cm-n"><?= e((string) $cRow['short_en']) ?><small class="pc-gn">· <?= e($isCom ? t('needs your decision', 'kailangan ng desisyon mo') : t('your work', 'ang trabaho mo')) ?></small></span><b><?= (int) ($cn['open'] ?? 0) ?></b></a></div>
  <?php endif; ?>
  <div class="hm-row hm-row-4">
    <?php if ($isCom && $dc !== null): ?>
      <?= $tile('notifications.php', t('Escalations to approve', 'Eskalasyong aaprubahan'), $dc['escalations'] ?? 0, t('a tanod asked for an outside office', 'humingi ang tanod ng ibang tanggapan'), true) ?>
      <?= $tile('inbox.php?app=mail', t('Tanods to pick', 'Tanod na pipiliin'), $dc['reroute'] ?? 0, t('no tanod of yours was free', 'walang bakanteng tanod mo'), true) ?>
      <?= $tile('cases.php?com=fwd', t('Forwarded to you', 'Ipinasa sa iyo'), $dc['forwarded'] ?? 0, t('from another committee', 'mula sa ibang komite')) ?>
      <?= $tile('cases.php?com=flagged', t('Staff flags', 'Mga flag ng kawani'), $dc['flags'] ?? 0, t('your staff ask to forward', 'hiling ng kawani na ipasa')) ?>
    <?php else: ?>
      <?= $tile('cases.php?who=' . rawurlencode($me), t('Yours', 'Hawak mo'), $cn['mine'] ?? 0, t('cases you are handling', 'mga kasong hawak mo')) ?>
      <?= $tile('cases.php?who=unclaimed', t('Nobody has taken', 'Walang humahawak'), $cn['untaken'] ?? 0, t('open, waiting for someone', 'bukas, naghihintay ng hahawak'), true) ?>
      <?= $tile('cases.php?tanod=needs', t('Urgent, no tanod yet', 'Urgent, wala pang tanod'), $cn['urgent_waiting'] ?? 0, sprintf(t('%d more at high', '%d pa sa mataas'), (int) ($cn['high_waiting'] ?? 0)), true) ?>
      <?= $tile('cases.php?view=attention', t('Overdue', 'Lampas-oras'), $cn['overdue'] ?? 0, t('open past the deadline', 'bukas na lampas sa deadline'), true) ?>
    <?php endif; ?>
  </div>
</section>

<p class="p-eyebrow hm-h"><?= e(t('Right now', 'Ngayon')) ?></p>
<div class="hm-row hm-row-4">
  <?php if ($isCom): // 12 Nov 2026: four tiles under the four decisions, so every column lines up with the one above and with the two lists below ?>
    <?= $tile('cases.php', t('Open cases', 'Bukas na kaso'), $cn['open'] ?? 0, sprintf(t('in your committee, %d are yours', 'sa komite mo, %d ang hawak mo'), (int) ($cn['mine'] ?? 0))) ?>
    <?= $tile('cases.php?tanod=needs', t('Urgent, no tanod yet', 'Urgent, wala pang tanod'), $cn['urgent_waiting'] ?? 0, sprintf(t('%d more at high', '%d pa sa mataas'), (int) ($cn['high_waiting'] ?? 0)), true) ?>
    <?= $tile('cases.php?view=attention', t('Overdue', 'Lampas-oras'), $cn['overdue'] ?? 0, sprintf(t('open past the deadline, %d more due in 24 hours', 'lampas sa deadline, %d pa ang sa loob ng 24 oras'), (int) ($cn['due_24h'] ?? 0)), true) ?>
    <?= $tile('cases.php?who=unclaimed', t('Nobody has taken', 'Walang humahawak'), $cn['untaken'] ?? 0, t('open, waiting for someone', 'bukas, naghihintay ng hahawak')) ?>
  <?php else: ?>
    <?= $tile('cases.php', t('Open cases', 'Bukas na kaso'), $cn['open'] ?? 0, t('in your committee', 'sa komite mo')) ?>
    <?= $tile('cases.php', t('At risk of the deadline', 'Nanganganib sa deadline'), count($risk), t('the engine reading', 'basa ng engine'), true) ?>
    <?= $tile('cases.php', t('Quiet cases', 'Mga tahimik na kaso'), count($quiet), t('no news for days', 'ilang araw nang walang balita')) ?>
    <?= $tile('cases.php?view=attention', t('Due in 24 hours', 'Deadline sa loob ng 24 oras'), $cn['due_24h'] ?? 0, t('still open', 'bukas pa')) ?>
  <?php endif; ?>
</div>

<?php $hmCards = []; $hmClear = []; $hmStrip = ''; // what has something to show is a card; what has nothing is one line in "All clear" (12 Nov 2026), so an empty list never takes a card of space ?>
<?php if ($risk): ob_start(); ?>
<section class="p-card hm-list">
      <div class="p-card-head"><h2><?= e(t('Likely to miss the deadline', 'Maaaring lumampas sa deadline')) ?></h2><span class="p-badge-n p-badge-n--quiet"><?= count($risk) ?></span></div>
      
      <table class="ss-table"><thead><tr><th><?= e(t('Case', 'Kaso')) ?></th><th><?= e(t('Due', 'Deadline')) ?></th><th class="n"><?= e(t('Time left', 'Natitirang oras')) ?></th><th><?= e(t('Risk', 'Panganib')) ?></th></tr></thead><tbody>
      <?php foreach ($risk as $r): ?>
        <tr class="p-click" data-href="case.php?id=<?= e((string) $r['report_id']) ?>"><td><a class="p-mono-id" href="case.php?id=<?= e((string) $r['report_id']) ?>"><?= e((string) $r['tracking_id']) ?></a></td>
          <td><?= e(!empty($r['due_at']) ? (new DateTimeImmutable((string) $r['due_at']))->setTimezone($tz)->format('M j, g:i A') : '—') ?></td>
          <td class="n"><?= e($hoursLeft($r['hours_left'] ?? 0)) ?></td>
          <td><span class="hm-risk hm-risk-<?= e((string) ($r['risk'] ?? 'medium')) ?>"><?= e($riskLabel((string) ($r['risk'] ?? ''))) ?></span></td></tr>
      <?php endforeach; ?></tbody></table>
    </section>
<?php $hmCards[] = [ob_get_clean(), 3 + count($risk)]; else: $hmClear[] = [t('Likely to miss the deadline', 'Maaaring lumampas sa deadline'), t('Nothing at risk. Every open case is on pace for its deadline.', 'Walang nanganganib. Nasa tamang bilis ang bawat bukas na kaso.')]; endif; ?>
<?php if ($quiet): ob_start(); ?>
<section class="p-card hm-list">
      <div class="p-card-head"><h2><?= e(t('Quiet cases', 'Mga tahimik na kaso')) ?></h2><span class="p-badge-n p-badge-n--quiet"><?= count($quiet) ?></span></div>
      
      <table class="ss-table"><thead><tr><th><?= e(t('Case', 'Kaso')) ?></th><th><?= e(t('Status', 'Katayuan')) ?></th><th class="n"><?= e(t('Quiet for', 'Tahimik nang')) ?></th><th><?= e(t('Last news', 'Huling balita')) ?></th></tr></thead><tbody>
      <?php foreach ($quiet as $q): ?>
        <tr class="p-click" data-href="case.php?id=<?= e((string) $q['report_id']) ?>"><td><a class="p-mono-id" href="case.php?id=<?= e((string) $q['report_id']) ?>"><?= e((string) $q['tracking_id']) ?></a></td>
          <td><?= e(status_label((string) $q['status'])) ?></td>
          <td class="n"><?= e(sprintf((int) $q['days_quiet'] === 1 ? t('%d day', '%d araw') : t('%d days', '%d araw'), (int) $q['days_quiet'])) ?></td>
          <td><?= e((string) ($q['last_activity'] ?? '')) ?></td></tr>
      <?php endforeach; ?></tbody></table>
    </section>
<?php $hmCards[] = [ob_get_clean(), 3 + count($quiet)]; else: $hmClear[] = [t('Quiet cases', 'Mga tahimik na kaso'), t('No open case has gone quiet.', 'Walang bukas na kasong natahimik.')]; endif; ?>
<?php if ((int) ($tn['total'] ?? 0) > 0): ob_start(); ?>
<section class="p-card hm-tanods">
      <div class="p-card-head"><h2><?= e($isCom ? t('Your tanods now', 'Ang mga tanod mo ngayon') : t('The committee\'s tanods now', 'Ang mga tanod ng komite ngayon')) ?></h2><span class="p-spacer"></span><a class="dh-more" href="personnel.php"><?= e(t('Personnel', 'Mga Tanod')) ?> &rarr;</a></div>
      <?php $tot = max(1, (int) ($tn['total'] ?? 0));
        $parts = [['on_duty', t('Free', 'Bakante'), '#1FA24A'], ['busy', t('On a case', 'May kaso'), '#1E6FD9'], ['lunch', t('Lunch', 'Tanghalian'), '#F59E0B'], ['break', t('Break', 'Pahinga'), '#F2C94C'], ['offline', t('Off', 'Wala'), '#9AA3B5']]; ?>
      
      <div class="hm-bar" role="img" aria-label="<?= e(implode(', ', array_map(fn ($p) => $p[1] . ' ' . (int) ($tn[$p[0]] ?? 0), $parts))) ?>"><?php foreach ($parts as [$k, , $c]): $n = (int) ($tn[$k] ?? 0); if ($n > 0): ?><i style="flex:<?= $n ?>;background:<?= e($c) ?>"></i><?php endif; endforeach; ?></div>
      <ul class="hm-legend"><?php foreach ($parts as [$k, $lb, $c]): ?><li><i style="background:<?= e($c) ?>"></i><span><?= e($lb) ?></span><b class="p-num"><?= (int) ($tn[$k] ?? 0) ?></b></li><?php endforeach; ?></ul>
      
    </section>
<?php $hmStrip = ob_get_clean(); else: $hmClear[] = [$isCom ? t('Your tanods now', 'Ang mga tanod mo ngayon') : t('The committee\'s tanods now', 'Ang mga tanod ng komite ngayon'), t('No tanods in your committee yet. A Kagawad proposes them in Personnel.', 'Wala pang tanod sa komite mo. Iminumungkahi sila ng Kagawad sa Personnel.')]; endif; ?>
<?php if ($spikes): ob_start(); ?>
<section class="p-card hm-list">
      <div class="p-card-head"><h2><?= e(t('Spikes this week', 'Biglang dami ngayong linggo')) ?></h2></div>
      
      <table class="ss-table"><thead><tr><th><?= e(t('Kind', 'Uri')) ?></th><th class="n"><?= e(t('This week', 'Linggong ito')) ?></th><th class="n"><?= e(t('Usually', 'Karaniwan')) ?></th><th><?= e(t('Mostly', 'Karamihan')) ?></th></tr></thead><tbody>
      <?php foreach (array_slice($spikes, 0, 5) as $sp): ?>
        <tr><td><?= e(category_label((string) $sp['category'])) ?></td><td class="n"><?= (int) $sp['this_week'] ?></td><td class="n"><?= e(rtrim(rtrim(number_format((float) $sp['usual'], 1), '0'), '.')) ?></td><td><?= e((string) ($sp['place'] ?? '')) ?></td></tr>
      <?php endforeach; ?></tbody></table>
    </section>
<?php $hmCards[] = [ob_get_clean(), 3 + min(5, count($spikes))]; else: $hmClear[] = [t('Spikes this week', 'Biglang dami ngayong linggo'), t('Nothing is coming in more than usual.', 'Walang dumarating nang higit sa karaniwan.')]; endif; ?>
<?php if ($pats): ob_start(); ?>
<section class="p-card hm-list">
      <div class="p-card-head"><h2><?= e(t('Recurring problems', 'Paulit-ulit na problema')) ?></h2><span class="p-spacer"></span><a class="dh-more" href="spatial.php"><?= e(t('On the map', 'Sa mapa')) ?> &rarr;</a></div>
      
      <table class="ss-table"><thead><tr><th><?= e(t('Kind', 'Uri')) ?></th><th class="n"><?= e(t('Reports', 'Ulat')) ?></th><th class="n"><?= e(t('Weeks', 'Linggo')) ?></th><th class="n"><?= e(t('Still open', 'Bukas pa')) ?></th></tr></thead><tbody>
      <?php foreach ($pats as $pt): ?>
        <tr><td><?= e(category_label((string) $pt['category'])) ?></td><td class="n"><?= (int) $pt['reports'] ?></td><td class="n"><?= (int) $pt['weeks'] ?></td><td class="n<?= (int) $pt['still_open'] > 0 ? ' dc-hot' : '' ?>"><?= (int) $pt['still_open'] ?></td></tr>
      <?php endforeach; ?></tbody></table>
    </section>
<?php $hmCards[] = [ob_get_clean(), 3 + count($pats)]; else: $hmClear[] = [t('Recurring problems', 'Paulit-ulit na problema'), t('No problem keeps coming back at the same spot.', 'Walang problemang paulit-ulit sa iisang lugar.')]; endif; ?>
<?= $hmStrip ?? '' ?>
<?php if ($hmCards):   // two columns, each card to the lighter one in turn, the last card of each stretching so the two end level (12 Nov 2026)
    $colA = $colB = ''; $wA = $wB = 0;
    foreach ($hmCards as [$h, $w]) { if ($wA <= $wB) { $colA .= $h; $wA += $w; } else { $colB .= $h; $wB += $w; } } ?>
<div class="hm-cols<?= $colB === '' ? ' hm-one' : '' ?>"><div class="hm-col"><?= $colA ?></div><?php if ($colB !== ''): ?><div class="hm-col"><?= $colB ?></div><?php endif; ?></div>
<?php endif; ?>
<?php if ($hmClear): ?>
<section class="p-card hm-clear" aria-label="<?= e(t('All clear', 'Maayos lahat')) ?>">
  <div class="p-card-head"><h2><?= e(t('All clear', 'Maayos lahat')) ?></h2></div>
  <ul><?php foreach ($hmClear as [$ct, $cm]): ?><li><i aria-hidden="true"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i><b><?= e($ct) ?></b><span><?= e($cm) ?></span></li><?php endforeach; ?></ul>
</section>
<?php endif; ?>
<?php endif; ?>
<?= $cRow ? committee_banner_script() : '' ?>
<?php layout_foot(); ?>
