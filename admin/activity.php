<?php
/**
 * Activity — what is happening on cases, yours first (0087, 6 Oct 2026).
 *
 * One feed built from what the system already records: status changes and
 * their remarks (status_logs), takes and take-overs (case_handler_log),
 * questions and replies (report_messages) and tanod updates
 * (dispatch_updates). Entries on cases this admin handles are highlighted.
 * "Team now" is live presence (assets/js/presence.js): who is online and
 * which case they have open. The page reloads its feed as new rows arrive.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin();
$db    = db();
$show  = in_array($_GET['show'] ?? '', ['mine', 'peers'], true) ? (string) $_GET['show'] : '';

$since = (new DateTimeImmutable('-7 days'))->format(DateTimeInterface::ATOM);
$items = [];
$error = null;
$loads = [];

try {
    $got = $db->selectMany([
        'logs' => ['status_logs', [
            'select'     => 'id,report_id,new_status,remark,is_system,created_at,'
                          . 'by:users!status_logs_changed_by_fkey(id,full_name,role),'
                          . 'report:reports!status_logs_report_id_fkey(tracking_id,subject,handler_id)',
            'created_at' => 'gte.' . $since, 'order' => 'created_at.desc', 'limit' => '80',
        ]],
        'takes' => ['case_handler_log', [
            'select'     => 'id,report_id,action,reason,created_at,admin:users!case_handler_log_admin_id_fkey(id,full_name),'
                          . 'prev:users!case_handler_log_previous_id_fkey(full_name),'
                          . 'report:reports!case_handler_log_report_id_fkey(tracking_id,subject,handler_id)',
            'created_at' => 'gte.' . $since, 'order' => 'created_at.desc', 'limit' => '40',
        ], true],
        'msgs' => ['report_messages', [
            'select'     => 'id,report_id,from_barangay,body,created_at,author:users!report_messages_author_id_fkey(id,full_name,role),'
                          . 'report:reports!report_messages_report_id_fkey(tracking_id,subject,handler_id)',
            'created_at' => 'gte.' . $since, 'order' => 'created_at.desc', 'limit' => '40',
        ], true],
        'mine' => ['reports', [
            'select' => 'id', 'handler_id' => 'eq.' . $admin['id'], 'deleted_at' => 'is.null',
        ], true],
    ]);
} catch (SupabaseError $ex) {
    $error = safe_error($ex);
    $got = [];
}

$who = fn(?array $u) => $u === null ? t('The system', 'Ang sistema') : (($u['id'] ?? '') === $admin['id'] ? t('You', 'Ikaw') : (string) ($u['full_name'] ?? ''));

foreach ((array) ($got['logs'] ?? []) as $l) {
    if (!is_array($l)) continue;
    $by = $l['by'] ?? null;
    $items[] = [
        'at' => $l['created_at'], 'report' => $l['report_id'], 'case' => $l['report'] ?? [],
        'who' => !empty($l['is_system']) ? null : $by,
        'what' => trim((string) ($l['remark'] ?? '')) !== '' ? (string) $l['remark'] : t('Status: ', 'Katayuan: ') . status_label((string) $l['new_status']),
    ];
}
if (isset($got['takes']) && !$got['takes'] instanceof SupabaseError) {
    foreach ((array) $got['takes'] as $h) {
        $items[] = [
            'at' => $h['created_at'], 'report' => $h['report_id'], 'case' => $h['report'] ?? [], 'who' => $h['admin'] ?? null,
            'what' => match ($h['action']) {
                'take' => t('took the case', 'kinuha ang kaso'),
                'release' => t('released the case', 'binitawan ang kaso'),
                default => t('took the case over from ', 'kinuha ang kaso mula kay ') . ($h['prev']['full_name'] ?? ''),
            } . (!empty($h['reason']) ? ' — “' . $h['reason'] . '”' : ''),
        ];
    }
}
if (isset($got['msgs']) && !$got['msgs'] instanceof SupabaseError) {
    foreach ((array) $got['msgs'] as $m) {
        $items[] = [
            'at' => $m['created_at'], 'report' => $m['report_id'], 'case' => $m['report'] ?? [],
            'who' => $m['author'] ?? null,
            'what' => ($m['from_barangay'] ? t('answered the resident: ', 'sinagot ang residente: ') : t('asked the barangay: ', 'nagtanong sa barangay: ')) . '“' . mb_strimwidth((string) $m['body'], 0, 120, '…') . '”',
        ];
    }
}
usort($items, fn($a, $b) => strcmp((string) $b['at'], (string) $a['at']));
$isMine = fn(array $i) => ($i['case']['handler_id'] ?? null) === $admin['id'];
$mineCount = count(array_filter($items, $isMine));
if ($show === 'mine') $items = array_values(array_filter($items, $isMine));
if ($show === 'peers') $items = array_values(array_filter($items, fn($i) => !$isMine($i) && !empty($i['case']['handler_id'])));
$items = array_slice($items, 0, 100);
$myCases = isset($got['mine']) && !$got['mine'] instanceof SupabaseError ? count((array) $got['mine']) : 0;

layout_head(t('Activity', 'Aktibidad'), 'activity.php');
?>
<div class="p-topbar"><h1><?= e(t('Activity', 'Aktibidad')) ?></h1>
  <span class="p-live"><i></i><span><?= e(t('Live', 'Live')) ?></span></span></div>

<?php if ($error): ?><div class="p-flash p-flash--error" role="alert"><?= e($error) ?></div><?php endif; ?>

<div class="p-card p-card-pad" style="margin-bottom:16px">
  <p class="p-eyebrow"><?= e(t('Team now', 'Ang team ngayon')) ?></p>
  <div id="ss-team"><span class="p-hint"><?= e(t('Checking who is online…', 'Tinitingnan kung sino ang online…')) ?></span></div>
  <p class="p-hint" style="margin:12px 0 0"><?= e(sprintf(t('You are handling %d case(s).', 'May hawak kang %d kaso.'), $myCases)) ?>
    <a href="cases.php?who=mine"><?= e(t('See them', 'Tingnan')) ?></a></p>
</div>

<div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:12px">
  <a class="p-chip<?= $show === '' ? ' p-on' : '' ?>" href="activity.php"><?= e(t('Everything', 'Lahat')) ?></a>
  <a class="p-chip<?= $show === 'mine' ? ' p-on' : '' ?>" href="activity.php?show=mine"><?= e(t('My cases', 'Aking mga kaso')) ?> · <?= (int) $mineCount ?></a>
  <a class="p-chip<?= $show === 'peers' ? ' p-on' : '' ?>" href="activity.php?show=peers"><?= e(t("Peers' cases", 'Mga kaso ng iba')) ?></a>
</div>

<div class="p-card p-card-pad">
  <?php if (!$items): ?>
    <p class="p-none-line"><?= e(t('Nothing in the last 7 days.', 'Wala sa nakaraang 7 araw.')) ?></p>
  <?php else: ?>
    <ul class="ss-feed">
      <?php foreach ($items as $i): $u = $i['who']; ?>
        <li class="<?= $isMine($i) ? 'ss-mine' : '' ?>">
          <?= $u ? admin_chip((string) ($u['id'] ?? ''), (string) ($u['full_name'] ?? ''), 32) : '<span class="ss-av" style="width:32px;height:32px;font-size:10px;background:#6B7280">SYS</span>' ?>
          <div style="min-width:0">
            <b><?= e($who($u)) ?></b> <?= e($i['what']) ?>
            <a class="ss-case" href="case.php?id=<?= e($i['report']) ?>"><?= e($i['case']['tracking_id'] ?? '') ?> · <?= e($i['case']['subject'] ?? '') ?></a>
            <span class="ss-time"><?= e(long_datetime($i['at'])) ?><?= $isMine($i) ? ' · ' . e(t('your case', 'iyong kaso')) : '' ?></span>
          </div>
        </li>
      <?php endforeach; ?>
    </ul>
  <?php endif; ?>
</div>

<script src="assets/vendor/supabase/supabase.js"></script>
<script>
// New rows anywhere reload the feed (debounced), the same way Case Reports
// keeps itself current.
(function () {
  const sb = supabase.createClient(<?= json_encode(supabase_url()) ?>, <?= json_encode(supabase_key()) ?>,
    { accessToken: window.ssAccessToken(<?= json_encode(access_token()) ?>) });
  let t = null;
  const later = () => { clearTimeout(t); t = setTimeout(() => location.reload(), 1500); };
  const ch = sb.channel('activity-feed');
  ['status_logs', 'case_handler_log', 'report_messages'].forEach(tb =>
    ch.on('postgres_changes', { event: 'INSERT', schema: 'public', table: tb }, later));
  ch.subscribe();
})();
</script>
<?php layout_foot(); ?>
