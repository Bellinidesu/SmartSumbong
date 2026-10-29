<?php
/**
 * Feature switches (0144): parts of the system that can be switched off without removing them. The Workspace and the command
 * center ship off (29 Oct 2026, until after the defense). Read from the database's feature_switches table with the signed-in
 * administrator's token and kept in a short file cache, shared by everyone, so a page costs no extra trip to the database most
 * of the time. A part that cannot be read counts as OFF: a switched-off part never comes on by accident.
 *
 *   feature_on('workspace')        true when the part is on
 *   ws_href('?own=free')           the Workspace's address, or the case list's while the Workspace is off
 *   feature_forget()               drop the cache (after a switch is flipped)
 */
declare(strict_types=1);

function feature_cache_file(): string
{
    return sys_get_temp_dir() . '/ss-features-' . substr(md5(env('SUPABASE_URL', '')), 0, 8) . '.json';
}

function feature_forget(): void
{
    @unlink(feature_cache_file());
}

/** @return array<string,bool> */
function features_read(): array
{
    static $memo = null;
    if ($memo !== null) return $memo;
    // the table is for administrators: a signed-out visitor would read an empty list, and that must never be cached for everyone
    if (access_token() === null) return $memo = [];
    $ttl = (int) env('FEATURE_CACHE_TTL', '20');
    $file = feature_cache_file();
    if ($ttl > 0 && is_file($file) && filemtime($file) > time() - $ttl) {
        $hit = json_decode((string) @file_get_contents($file), true);
        if (is_array($hit)) return $memo = $hit;
    }
    $out = null;
    try {
        $rows = db()->select('feature_switches', ['select' => 'key,enabled']);
        $out = [];
        foreach ((array) $rows as $r) { $out[(string) $r['key']] = (bool) $r['enabled']; }
        if ($ttl > 0) @file_put_contents($file, json_encode($out), LOCK_EX);
    } catch (Throwable) {
        // a stale copy is better than guessing; no copy at all means everything off
        $old = is_file($file) ? json_decode((string) @file_get_contents($file), true) : null;
        $out = is_array($old) ? $old : [];
    }
    return $memo = $out;
}

function feature_on(string $key): bool
{
    return features_read()[$key] ?? false;
}

function ws_href(string $query = ''): string
{
    return feature_on('workspace') ? 'workspace.php' . $query : 'cases.php';
}

/** A JSON door or page of a switched-off part answers like a page that does not exist. */
function feature_require(string $key, bool $json = false): void
{
    if (feature_on($key)) return;
    http_response_code(404);
    if ($json) {
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['error' => 'switched_off']);
    }
    exit;
}
