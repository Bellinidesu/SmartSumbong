<?php
/**
 * What is new in the chats of the cases a person floats (12 Nov 2026, the chat head).
 *
 * GET ?ids=<case id>,<case id>... (at most eight). For each case: its tracking number, the newest messages that came IN (from the
 * resident, or from a tanod on one of its dispatches) and when the barangay last wrote in each conversation. The page turns that
 * into the notification ball and the sound; "unread" is decided there, against what this browser last looked at. Read only, run as
 * the signed-in administrator, so what the database lets them read is all they get. Nothing is stored.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin_api();
session_write_close();

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

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
foreach ($ids as $id) $out[$id] = ['t' => '', 'in' => [], 'out' => (object) []];

try {
    $got = db()->selectMany([
        'reports' => ['reports', ['select' => 'id,tracking_id', 'id' => $list]],
        'msgs'    => ['report_messages', ['select' => 'report_id,from_barangay,body,created_at', 'report_id' => $list, 'order' => 'created_at.desc', 'limit' => '80']],
        'ups'     => ['dispatch_updates', ['select' => 'dispatch_id,author_id,kind,body,created_at,d:dispatches!inner(report_id,tanod_id)',
                                           'd.report_id' => $list, 'kind' => 'eq.message', 'order' => 'created_at.desc', 'limit' => '80']],
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

echo json_encode(['ok' => true, 'cases' => $out], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
