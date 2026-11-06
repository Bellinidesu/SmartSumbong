<?php
/**
 * The shared cache (speed work, 7 Nov 2026): the barangay's reference lists (its committees, the complaint types and their
 * options, which committee sees which type) are the same for every administrator and change only when a super admin saves
 * them in Settings. Every page used to read them again, one wait on the database each. They are now kept in a small file
 * beside the feature switches' (features.php), shared by everyone, for FEATURE_CACHE_TTL seconds (20 by default), and the
 * save that changes one drops its copy at once (shared_forget), so the person who saved sees the change on their next page.
 *
 * Rules that keep it safe:
 *   - only a signed-in administrator's read fills it (the tables' policies give every administrator the same rows, and a
 *     signed-out or resident read sees fewer, which must never be served to anyone);
 *   - an empty answer or a failed read is never kept;
 *   - a read that fails while a copy exists uses the copy, however old: a stale list is better than an empty one.
 *
 *   shared_cache('committees', fn () => [...rows...], $canFill)   the list, from the copy or from the loader
 *   shared_forget('committees', 'committee_categories')           drop copies after a save
 */
declare(strict_types=1);

/**
 * How long a small cache (the reference lists, the feature switches, the barangay's profile, the wording) is kept, in seconds:
 * FEATURE_CACHE_TTL, 300 by default (7 Nov 2026; it was 20). Every save in the portal that changes one drops its copy at once, so a
 * longer life costs no freshness for what the portal edits; it saves the waits a page paid each time a copy had expired.
 */
function cache_ttl(): int
{
    return (int) env('FEATURE_CACHE_TTL', '300');
}

/** True when a cache file is missing or older than cache_ttl() (or caching is off), so the next read goes to the database. */
function cache_file_cold(string $file): bool
{
    $ttl = cache_ttl();
    return $ttl <= 0 || !is_file($file) || @filemtime($file) <= time() - $ttl;
}

function shared_cache_cold(string $name): bool
{
    return cache_file_cold(shared_cache_file($name));
}

function shared_cache_file(string $name): string
{
    $safe = preg_replace('/[^a-z0-9_]/', '', strtolower($name));
    return sys_get_temp_dir() . '/ss-shared-' . $safe . '-' . substr(md5((string) env('SUPABASE_URL', '')), 0, 8) . '.json';
}

/**
 * @param callable():?array $load reads the list; returns null (or throws) when it could not
 * @param bool $canFill true only when the reader is a signed-in administrator
 */
function shared_cache(string $name, callable $load, bool $canFill): array
{
    $ttl = cache_ttl();
    $file = shared_cache_file($name);
    $copy = null;
    if ($ttl > 0 && is_file($file)) {
        $copy = json_decode((string) @file_get_contents($file), true);
        if (!is_array($copy)) $copy = null;
        if ($copy !== null && $canFill && @filemtime($file) > time() - $ttl) return $copy;
    }
    try { $fresh = $load(); } catch (Throwable) { $fresh = null; }
    // someone who may not fill the copy reads for themselves, as before, and is never handed the administrators' copy
    if (!$canFill) return is_array($fresh) ? $fresh : [];
    if (is_array($fresh) && $fresh !== []) {
        if ($ttl > 0) {
            // written beside and renamed over, so a page reading at the same moment never sees half a file
            $tmp = $file . '.' . bin2hex(random_bytes(4));
            if (@file_put_contents($tmp, json_encode($fresh, JSON_UNESCAPED_UNICODE)) !== false) {
                if (!@rename($tmp, $file)) @unlink($tmp);
            }
        }
        return $fresh;
    }
    return $copy ?? (is_array($fresh) ? $fresh : []);
}

function shared_forget(string ...$names): void
{
    foreach ($names as $n) @unlink(shared_cache_file($n));
}
