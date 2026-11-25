<?php
/**
 * Live updates (25 Nov 2026, Ace; looks approved by Rose): "all pages and everything that appears and pops up in any press must
 * update itself without needing constant reloads."
 *
 * A page that opts in names its live parts (data-live="name" on stable wrappers) and the tables whose changes concern it. The
 * browser layer (assets/js/live.js) listens on Supabase Realtime for those tables (or, when Realtime is down, asks every 25
 * seconds while the tab is visible), fetches the SAME page again with an X-Live: 1 header and morphs only the named parts in
 * place. A part someone is typing in, has a dialog or menu open in, or has pressed something in, waits until they are done.
 * The server still renders every page and still decides who may see what: Realtime is only the signal, never the data.
 *
 *   live_on()                      false when switched off (the kill switch below); the pages then behave as before
 *   live_page($page, $tables)      the page opts in (before layout_head); layout_head writes the layer's tags
 *   live_request()                 this request is the layer's background refetch (X-Live: 1)
 *   live_background()              any background refetch (the layer's, or the press flow's quiet refresh)
 *
 * The kill switch, two ways, either one turns it off for everyone:
 *   - the environment variable LIVE_UPDATES=off (Render > Environment; Render restarts the service when it is saved);
 *   - a feature switch row with key live_updates and enabled false (Settings > Parts of the system lists every row, so once the
 *     row exists it is a toggle, no redeploy). There is no migration for it (the backend is frozen): a missing row means ON.
 * One viewer can turn it off for their own browser with localStorage ss-live=off (docs/LIVE_UPDATES.md).
 */
declare(strict_types=1);

/** The tables in the supabase_realtime publication (the baseline's list). A table outside it can never push, so it is never asked for. */
const LIVE_PUBLISHED = ['case_handler_log', 'detail_requests', 'dispatch_updates', 'dispatches', 'escalation_requests', 'notifications',
                        'report_messages', 'reports', 'retirement_requests', 'status_logs'];

function live_on(): bool
{
    static $memo = null;
    if ($memo !== null) return $memo;
    $env = strtolower(trim((string) env('LIVE_UPDATES', 'on')));
    if (in_array($env, ['off', '0', 'false', 'no'], true)) return $memo = false;
    // the feature switch is read only when it can be (a signed-in administrator); a missing row, or a table that cannot be read, is ON
    $f = function_exists('features_read') && function_exists('access_token') && access_token() !== null ? features_read() : [];
    return $memo = !(array_key_exists('live_updates', $f) && $f['live_updates'] === false);
}

function live_request(): bool
{
    return ($_SERVER['HTTP_X_LIVE'] ?? '') === '1' && ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'GET';
}

/** A refetch the page makes by itself: it does not count as use (the idle sign-out) and takes no one-time message away. */
function live_background(): bool
{
    return live_request() || ($_SERVER['HTTP_X_PRESS_QUIET'] ?? '') === '1';
}

/**
 * The page opts in. $tables: [table => filter or ''] (a PostgREST-style Realtime filter such as 'report_id=eq.<uuid>'); only
 * published tables are kept. $opts: 'poll' (seconds between checks while Realtime is down, default 25), 'safety' (seconds between
 * checks while it is up, for the parts no table pushes, default 120), 'gap' (the least seconds between two refetches, default 3).
 */
function live_page(string $page, array $tables, array $opts = []): void
{
    $t = [];
    foreach ($tables as $name => $filter) {
        if (!in_array($name, LIVE_PUBLISHED, true)) continue;
        $t[] = ['t' => $name, 'f' => (string) $filter];
    }
    $GLOBALS['ss_live'] = ['page' => preg_replace('/[^a-z0-9-]/', '', strtolower($page)), 'tables' => $t,
        'poll' => max(15, (int) ($opts['poll'] ?? 25)), 'safety' => max(30, (int) ($opts['safety'] ?? 120)), 'gap' => max(3, (int) ($opts['gap'] ?? 3))];
    if (live_request()) {
        header('Cache-Control: no-store');
        header('Vary: X-Live', false);
    }
}

/** The layer's tags for layout_head(): its style, its settings and its script. Nothing when the page did not opt in or it is off. */
function live_head(): string
{
    $p = $GLOBALS['ss_live'] ?? null;
    if (!$p || !live_on()) return '';
    $cfg = $p + [
        'url'   => supabase_url(),
        'key'   => supabase_key(),
        'token' => access_token(),
        'me'    => current_admin()['id'] ?? null,
        'txt'   => [
            'live'      => t('Live', 'Live'),
            'liveTip'   => t('Updates as they happen, no reload needed', 'Nag-a-update habang nangyayari, hindi na kailangang i-reload'),
            'poll'      => t('Polling', 'Sinusuri'),
            'pollTip'   => t('Live updates are not reaching this page right now: it checks for changes every few seconds instead', 'Hindi umaabot ngayon ang live na update sa pahinang ito: sinusuri nito ang mga pagbabago bawat ilang segundo'),
            'off'       => t('Offline', 'Offline'),
            'offTip'    => t('You seem to be offline. The page updates again when you are back online.', 'Mukhang offline ka. Mag-a-update muli ang pahina kapag online ka na.'),
            'chip'      => t('Updated while you were busy here', 'Na-update habang abala ka rito'),
            'apply'     => t('Show the update', 'Ipakita ang update'),
            'later'     => t('Not now', 'Mamaya na'),
            'applied'   => t('Page updated', 'Na-update ang pahina'),
            'gone'      => t('This page has changed and is no longer shown to you here. It may have moved to another committee, or your access changed.', 'Nagbago ang pahinang ito at hindi na ito ipinapakita sa iyo rito. Maaaring nailipat ito sa ibang komite, o nagbago ang iyong access.'),
            'goneBack'  => t('Open it again', 'Buksan muli'),
        ],
    ];
    $v = static fn (string $f): string => e(asset_version($f));
    return '<link href="assets/css/live.css?v=' . $v('live.css') . '" rel="stylesheet">'
        . '<script nonce="' . csp_nonce() . '" type="application/json" id="ss-live-cfg">' . json_encode($cfg, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_UNESCAPED_SLASHES) . '</script>'
        . '<script nonce="' . csp_nonce() . '" src="assets/js/live.js?v=' . $v('../js/live.js') . '" defer></script>';
}
