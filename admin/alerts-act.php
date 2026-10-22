<?php
/**
 * Alerts, as each person sets them up (0136, 22 Oct 2026). POST only, the signed-in administrator, the page's CSRF
 * token, JSON back. Every call runs as that person, so the database pins each choice to their own account.
 *
 *   action=subscribe    endpoint, p256dh, auth, label      this browser gets alerts
 *   action=unsubscribe  endpoint                           this browser, or one of theirs from the list, stops
 *   action=mute         kind, muted (0|1)                  one kind of alert on or off (0044)
 *   action=choices      scope (all|mine), quiet_from, quiet_to (0-23, both empty = none), quiet_urgent (0|1)
 *   action=test         a test alert to their phones and browsers
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/alerts.php';

$admin = require_admin_api();

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function aout(array $a, int $code = 200): never
{
    http_response_code($code);
    echo json_encode($a, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    aout(['error' => 'method'], 405);
}
if (!csrf_check($_POST['csrf'] ?? null)) {
    aout(['error' => t('That form expired. Reload the page and try again.', 'Nag-expire ang form. I-reload ang pahina at subukan muli.')], 403);
}
session_write_close();

$db  = db();
$in  = static fn (string $k, int $max = 1000): string => mb_substr(trim((string) ($_POST[$k] ?? '')), 0, $max);
$hour = static function (string $k) use ($in): ?int {
    $v = $in($k, 2);
    return $v === '' ? null : max(0, min(23, (int) $v));
};

try {
    switch ((string) ($_POST['action'] ?? '')) {
        case 'subscribe':
            $id = $db->rpc('web_push_subscribe', ['p_endpoint' => $in('endpoint'), 'p_p256dh' => $in('p256dh', 120),
                'p_auth' => $in('auth', 40), 'p_label' => $in('label', 80) ?: null]);
            aout(['ok' => true, 'id' => $id]);
        case 'unsubscribe':
            $db->rpc('web_push_unsubscribe', ['p_endpoint' => $in('endpoint')]);
            aout(['ok' => true]);
        case 'mute':
            $kind = $in('kind', 40);
            if (!in_array($kind, ALERT_KINDS, true)) aout(['error' => 'kind'], 400);
            $db->rpc('set_notification_mute', ['p_kind' => $kind, 'p_muted' => $in('muted') === '1']);
            aout(['ok' => true]);
        case 'choices':
            $db->rpc('set_push_choices', ['p_scope' => $in('scope', 4) === 'mine' ? 'mine' : 'all',
                'p_quiet_from' => $hour('quiet_from'), 'p_quiet_to' => $hour('quiet_to'), 'p_quiet_urgent' => $in('quiet_urgent') !== '0']);
            aout(['ok' => true]);
        case 'test':
            $db->rpc('push_test', []);
            aout(['ok' => true]);
        default:
            aout(['error' => 'action'], 400);
    }
} catch (SupabaseError $e) {
    aout(['error' => safe_error($e)], 400);
}
