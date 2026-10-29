<?php
/**
 * The Workspace widgets' data door (17 Oct 2026). GET only, administrators only, JSON.
 *
 *   widgets.php?catalogue=1            every widget: its library group, whether it was a "new feature", the data groups it reads
 *   widgets.php?w=flood,wx,calc        the data groups those widgets read, each {ok, stale, at, data}
 *   widgets.php?w=...&g=alarm,prefs    plus named groups: alarm (the rules that are firing), prefs (my Workspace),
 *                                      settings (the barangay's switches), meta (the hall, the app link), mine (my cases)
 *   widgets.php?find=rizal             Find a case: up to 8 matches by tracking number, subject or place
 *
 * See includes/widgets.php for the catalogue and each group. Writes go through workspace-act.php.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/widgets.php';

$admin = require_admin_api();
feature_require('workspace', true);
session_write_close();

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: private, no-store');

function wout(array $a, int $code = 200): never
{
    http_response_code($code);
    echo json_encode($a, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    wout(['error' => 'method'], 405);
}

if (isset($_GET['catalogue'])) {
    $list = [];
    foreach (widget_catalogue() as $id => [$group, $status, $needs]) {
        $list[$id] = ['group' => $group, 'status' => $status, 'needs' => $needs];
    }
    $feeds = [];
    foreach (feed_catalogue() as $k => $f) {
        $feeds[$k] = ['name' => $f['name'], 'search' => !empty($f['search'])];
    }
    wout(['widgets' => $list, 'count' => count($list), 'feeds' => $feeds, 'games' => WS_GAMES,
          'default_tabs' => WS_DEFAULT_TABS]);
}

if (isset($_GET['find'])) {
    $q = trim((string) $_GET['find']);
    if (mb_strlen($q) < 2) {
        wout(['results' => []]);
    }
    try {
        $r = db()->rpc('workspace_find', ['p_q' => mb_substr($q, 0, 60)]);
        wout(['results' => is_array($r) ? $r : []]);
    } catch (SupabaseError) {
        wout(['error' => t('The search did not answer. Try again.', 'Hindi sumagot ang paghahanap. Subukan muli.')], 502);
    }
}

$cat = widget_catalogue();
$ids = array_values(array_unique(array_filter(explode(',', (string) ($_GET['w'] ?? '')), static fn ($id) => isset($cat[$id]))));
$extra = array_values(array_filter(explode(',', (string) ($_GET['g'] ?? '')), static fn ($g) => preg_match('/^[a-z]{1,12}$/', $g)));
if (count($ids) > 130 || count($extra) > 8) {
    wout(['error' => 'too many'], 400);
}
$groups = widget_groups_for($ids, $extra);
if (!$groups) {
    wout(['at' => gmdate('c'), 'groups' => new stdClass()]);
}

wout(['at' => gmdate('c'), 'groups' => widget_data(db(), $admin, $groups)]);
