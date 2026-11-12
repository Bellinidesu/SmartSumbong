<?php
/**
 * What is new in the chats of the cases a person floats (12 Nov 2026, the chat head).
 *
 * GET ?ids=<case id>,<case id>... (at most eight). For each case: its tracking number, the newest messages that came IN (from the
 * resident, or from a tanod on one of its dispatches) and when the barangay last wrote in each conversation. The page turns that
 * into the notification ball and the sound; "unread" is decided there, against what this browser last looked at. Read only, run as
 * the signed-in administrator, so what the database lets them read is all they get. Each case also carries `st`, where this person was in
 * each of its conversations (read up to, muted: chat_state, 0173), so the unread dots and Hide Alerts follow the person to another browser.
 *
 * POST (JSON, with the page's CSRF token) {items: [{c: case, k: conversation, s?: read-up-to, m?: muted, all?: true}]}: keeps that state through
 * chat_state_set. `all` with `m` mutes (or unmutes) the whole case: its resident conversation and each of its dispatches.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin_api();

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

$uuidRe = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $in = json_decode((string) file_get_contents('php://input'), true);
    if (!is_array($in) || !csrf_check($in['csrf'] ?? null)) {
        http_response_code(403);
        echo json_encode(['ok' => false, 'text' => t('That form expired. Reload the page and try again.', 'Nag-expire ang form. I-reload ang pahina at subukan muli.')]);
        exit;
    }
    session_write_close();
    $db = db();
    $done = 0;
    try {
        foreach (array_slice((array) ($in['items'] ?? []), 0, 24) as $it) {
            if (!is_array($it)) continue;
            $case = strtolower((string) ($it['c'] ?? ''));
            $conv = (string) ($it['k'] ?? '');
            if (!preg_match($uuidRe, $case)) continue;
            $seen = isset($it['s']) && strtotime((string) $it['s']) ? gmdate('Y-m-d\TH:i:s\Z', strtotime((string) $it['s'])) : null;
            $muted = array_key_exists('m', $it) ? (bool) $it['m'] : null;
            $convs = [];
            if (!empty($it['all']) && $muted !== null) {
                $convs = ['r'];
                foreach ((array) $db->select('dispatches', ['select' => 'id', 'report_id' => 'eq.' . $case, 'limit' => '40']) as $d) $convs[] = 'd-' . $d['id'];
                $seen = null;
            } elseif ($conv === 'r' || preg_match('/^d-[0-9a-f-]{36}$/', $conv)) {
                $convs = [$conv];
            }
            foreach ($convs as $k) {
                $p = ['p_report' => $case, 'p_conv' => $k];
                if ($seen !== null) $p['p_seen'] = $seen;
                if ($muted !== null) $p['p_muted'] = $muted;
                $db->rpc('chat_state_set', $p);
                $done++;
            }
        }
    } catch (SupabaseError $ex) {
        http_response_code(400);
        echo json_encode(['ok' => false, 'text' => $ex->getMessage()]);
        exit;
    }
    echo json_encode(['ok' => true, 'n' => $done]);
    exit;
}
session_write_close();

$ids = [];
foreach (explode(',', (string) ($_GET['ids'] ?? '')) as $i) {
    $i = strtolower(trim($i));
    if (preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/', $i)) $ids[$i] = true;
}
$ids = array_slice(array_keys($ids), 0, 8);
if (!$ids) {
    echo json_encode(['ok' => true, 'cases' => (object) []]);
    exit;
}
$list = 'in.(' . implode(',', $ids) . ')';

$iso = static function (?string $s): string {
    $t = $s !== null ? strtotime($s) : false;
    return $t ? gmdate('Y-m-d\TH:i:s\Z', $t) : '';
};

$out = [];
foreach ($ids as $id) $out[$id] = ['t' => '', 'in' => [], 'out' => (object) [], 'st' => (object) []];

try {
    $got = db()->selectMany([
        'reports' => ['reports', ['select' => 'id,tracking_id', 'id' => $list]],
        'msgs'    => ['report_messages', ['select' => 'report_id,from_barangay,body,created_at', 'report_id' => $list, 'order' => 'created_at.desc', 'limit' => '80']],
        'ups'     => ['dispatch_updates', ['select' => 'dispatch_id,author_id,kind,body,created_at,d:dispatches!inner(report_id,tanod_id)',
                                           'd.report_id' => $list, 'kind' => 'eq.message', 'order' => 'created_at.desc', 'limit' => '80']],
        'st'      => ['chat_state', ['select' => 'report_id,conv,seen_at,muted', 'user_id' => 'eq.' . (string) $admin['id'], 'report_id' => $list, 'limit' => '400']],
    ]);
} catch (SupabaseError $ex) {
    http_response_code(503);
    echo json_encode(['ok' => false]);
    exit;
}

foreach ((array) ($got['reports'] ?? []) as $r) {
    if (isset($out[$r['id'] ?? ''])) $out[$r['id']]['t'] = (string) ($r['tracking_id'] ?? '');
}
$outLast = [];
$add = static function (string $case, string $conv, bool $incoming, string $ts, string $text) use (&$out, &$outLast): void {
    if (!isset($out[$case]) || $ts === '') return;
    if ($incoming) {
        if (count($out[$case]['in']) < 30) $out[$case]['in'][] = ['c' => $conv, 'ts' => $ts, 'x' => mb_substr(trim($text), 0, 90)];
    } elseif (!isset($outLast[$case][$conv]) || $ts > $outLast[$case][$conv]) {
        $outLast[$case][$conv] = $ts;
    }
};
foreach ((array) ($got['msgs'] ?? []) as $m) {
    $add((string) $m['report_id'], 'r', empty($m['from_barangay']), $iso($m['created_at'] ?? null), (string) ($m['body'] ?? ''));
}
foreach ((array) ($got['ups'] ?? []) as $u) {
    $d = $u['d'] ?? [];
    $add((string) ($d['report_id'] ?? ''), 'd-' . $u['dispatch_id'], ($u['author_id'] ?? null) === ($d['tanod_id'] ?? '?'), $iso($u['created_at'] ?? null), (string) ($u['body'] ?? ''));
}
foreach ($outLast as $case => $convs) $out[$case]['out'] = $convs;
$stAll = [];
foreach ((array) ($got['st'] ?? []) as $s) {
    $case = (string) ($s['report_id'] ?? '');
    if (isset($out[$case])) $stAll[$case][(string) $s['conv']] = ['s' => $iso($s['seen_at'] ?? null), 'm' => !empty($s['muted'])];
}
foreach ($stAll as $case => $convs) $out[$case]['st'] = $convs;

echo json_encode(['ok' => true, 'cases' => $out], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
