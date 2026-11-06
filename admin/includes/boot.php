<?php
/**
 * The request's boot batch (speed work, 7 Nov 2026).
 *
 * A page keeps a handful of small things in short caches: the committees, the complaint types and their options, which
 * committee sees which type, the feature switches, the barangay's profile, the wording (files, shared by everyone), and the
 * sidebar's counts, the storm banner, the avatar rings, the access check and the DEV pill's accounts (the person's session). Each
 * reader filled its own cache when it found it expired, one wait on the database after another: measured on the live portal, a
 * page opened after a pause made 13 waits of ~300 ms each, four seconds before anything showed.
 *
 * Now require_admin() first asks every reader whose cache is cold for the read it would make, and sends them all in ONE batch.
 * The readers then run as before and find their answers in the request's read memo (supabase.php), so they fill their caches
 * without a wait. A page after a pause waits twice (this batch, then its own); a page with warm caches, once. Each part of the
 * batch is optional: one that fails is simply read again by its reader, as before.
 */
declare(strict_types=1);

/** The client a shared, public read uses: the signed-in person's own access when there is one (the same public rows), else none. */
function boot_client(): Supabase
{
    return (function_exists('access_token') && access_token() !== null) ? db() : new Supabase();
}

/** Every read whose cache is cold right now, as selectMany entries, each from its reader's own definition. */
function boot_reads(): array
{
    if (!function_exists('access_token') || access_token() === null) return [];
    $e = [];
    if (function_exists('committees_read_entry') && shared_cache_cold('committees')) $e['committees'] = committees_read_entry();
    if (function_exists('committee_categories_read_entry') && shared_cache_cold('committee_categories')) $e['committee_categories'] = committee_categories_read_entry();
    if (function_exists('categories_read_entry') && shared_cache_cold('complaint_categories')) $e['complaint_categories'] = categories_read_entry();
    if (function_exists('complaint_options_read_entry') && shared_cache_cold('complaint_options')) $e['complaint_options'] = complaint_options_read_entry();
    if (function_exists('features_read_entry') && cache_file_cold(feature_cache_file())) $e['features'] = features_read_entry();
    if (function_exists('barangay_read_entry') && cache_file_cold(barangay_cache_file())) $e['barangay'] = barangay_read_entry();
    if (function_exists('wording_read_entry') && cache_file_cold(wording_cache_file())) $e['wording'] = wording_read_entry();
    if (function_exists('access_refresh_entry') && access_refresh_due()) $e['access'] = access_refresh_entry();
    if (function_exists('storm_read_entry') && storm_cold()) $e['storm'] = storm_read_entry();
    if (function_exists('ranks_read_entry') && ranks_cold()) $e['ranks'] = ranks_read_entry();
    if (function_exists('nav_counts_entries') && nav_counts_cold()) {
        foreach (nav_counts_entries() as $k => $x) { $x[3] = 'count'; $e['nav:' . $k] = $x; }
    }
    // the DEV pill's test accounts: a developer, not switched into a test account (then the pill reads with another session)
    $me = current_admin() ?? [];
    $dl = $_SESSION['ss_dev_levels'] ?? null;
    if (!empty($me['is_dev']) && empty($_SESSION['dev_origin'])
        && !(is_array($dl) && ($dl['k'] ?? '') === hash('sha256', (string) access_token()) && ($dl['at'] ?? 0) > time() - 60)) {
        $e['dev_levels'] = ['rpc/dev_levels', [], true];
    }
    return $e;
}

/** Fill the cold caches' reads in one wait (require_admin calls it before the page runs). */
function boot_prefetch(): void
{
    // a save (POST) writes, which empties the read memo, and is answered with a redirect: nothing to gain there
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') return;
    $e = boot_reads();
    if (count($e) < 2) return;   // one read costs its reader the same single wait
    foreach ($e as $k => $x) { $e[$k][2] = true; }
    try { db()->selectMany($e); } catch (Throwable) { /* each reader reads for itself, as before */ }
}
