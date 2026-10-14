<?php
/**
 * The work board's small JSON door: a quick look at a case (GET) and the two actions that can finish without leaving
 * the board (POST: dispatch a tanod, pass a case up the ladder). Both go through the same functions the case page uses
 * (includes/case_ops.php), the same stale-page check, and the same database guards (one handler per case), so the
 * board can never do less checking than the page.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/case_ops.php';

$admin = require_admin();
$db    = db();

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function out(array $a, int $code = 200): never
{
    http_response_code($code);
    echo json_encode($a, JSON_UNESCAPED_UNICODE);
    exit;
}

$id = (string) ($_GET['id'] ?? $_POST['id'] ?? '');
if (!preg_match('/^[0-9a-f-]{36}$/i', $id)) {
    out(['error' => t('That case could not be found.', 'Hindi mahanap ang kasong iyon.')], 400);
}

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        if (!csrf_check($_POST['csrf'] ?? null)) {
            out(['error' => t('That form expired. Reload the page and try again.', 'Nag-expire ang form. I-reload ang pahina at subukan muli.')], 403);
        }
        // the page the person was looking at must still be the current one
        $now = $db->select('reports', ['select' => 'version', 'id' => 'eq.' . $id, 'limit' => '1']);
        if (isset($_POST['v']) && $now && (string) $now[0]['version'] !== (string) $_POST['v']) {
            out(['error' => t('This case changed while you were looking at it. The board will refresh; open it again.', 'Nagbago ang kasong ito habang tinitingnan mo. Magre-refresh ang tablero; buksan itong muli.'), 'stale' => true], 409);
        }
        $act = (string) ($_POST['action'] ?? '');
        $msg = match ($act) {
            'dispatch' => op_dispatch($db, $id, $_POST),
            'escalate' => op_escalate($db, $id, $_POST),
            default    => throw new SupabaseError(t('Unknown action.', 'Hindi kilalang aksyon.')),
        };
        out(['ok' => true, 'message' => $msg]);
    }

    $got = $db->selectMany([
        'r'      => ['reports', ['select' => 'id,tracking_id,subject,category,status,due_at,handler_id,tier,is_sensitive,version,handler:users!reports_handler_id_fkey(id,full_name,official_role,committee)',
                                 'id' => 'eq.' . $id, 'limit' => '1']],
        'card'   => ['rpc/smart_case_card', ['p_report' => $id], true],
        'roster' => ['rpc/tanod_roster', ['p_report' => $id], true],
        'rank'   => ['rpc/smart_tanod_ranking', ['p_report' => $id], true],
        'com'    => ['committee_for_category', ['select' => 'category,committee'], true],
    ]);
    $r = $got['r'][0] ?? null;
    if (!$r) { out(['error' => t('That case could not be found.', 'Hindi mahanap ang kasong iyon.')], 404); }
    $ok   = fn(string $k): array => ($got[$k] instanceof SupabaseError || !is_array($got[$k])) ? [] : $got[$k];
    $card = is_array($got['card'] ?? null) && !($got['card'] instanceof SupabaseError) ? $got['card'] : [];
    $place = [];
    foreach ($ok('rank') as $i => $rk) { $place[$rk['tanod_id']] = $i; }
    $roster = [];
    foreach ($ok('roster') as $t) {
        $live = !empty($t['assignable']) && !empty($t['location_fresh']);
        $roster[] = ['id' => $t['tanod_id'], 'name' => formal_name((string) $t['full_name']), 'live' => $live,
                     'metres' => $t['metres'] !== null ? (int) $t['metres'] : null,
                     'why' => $live ? '' : (!empty($t['assignable']) ? 'reading old' : (string) ($t['unavailable_why'] ?? 'offline')),
                     'place' => $place[$t['tanod_id']] ?? 99];
    }
    usort($roster, fn($a, $b) => [!$a['live'], $a['place']] <=> [!$b['live'], $b['place']]);
    $dc = null;
    foreach ($ok('com') as $c) { if ($c['category'] === $r['category']) { $dc = $c['committee']; } }
    $labels = [];
    foreach (committee_labels() as $k => $l) { $labels[$k] = $l[0]; }
    $reasons = [];
    foreach ((array) ($card['reasons'] ?? []) as $rs) { $reasons[] = ['t' => (string) ($rs['detail'] ?? $rs['factor'] ?? ''), 'p' => (int) ($rs['points'] ?? 0)]; }
    $mine = ($r['handler_id'] ?? null) === $admin['id'];
    $h = $r['handler'] ?? null;
    out([
        'id' => $r['id'], 'tracking' => $r['tracking_id'], 'subject' => $r['subject'], 'category' => category_label((string) $r['category']),
        'status' => $r['status'], 'tier' => (int) $r['tier'], 'sensitive' => !empty($r['is_sensitive']), 'version' => $r['version'],
        'level' => $card['effective_level'] ?? null, 'score' => $card['score'] ?? null, 'reasons' => $reasons,
        'due' => local_input_value($r['due_at'] ?? null),
        'handler' => $h ? ['name' => display_name((string) $h['full_name']), 'role' => rank_of($h['official_role'] ?? null), 'committee' => $h['committee'] ?? null] : null,
        'mine' => $mine, 'canAct' => empty($r['handler_id']) || $mine,
        'roster' => $roster, 'committees' => $labels, 'defaultCommittee' => $dc,
        'open' => !in_array($r['status'], ['resolved', 'closed', 'archived', 'rejected', 'cancelled'], true),
    ]);
} catch (SupabaseError $ex) {
    out(['error' => safe_error($ex)], 422);
}
