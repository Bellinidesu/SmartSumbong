<?php
/**
 * The barangay's name, place and seal (0148: barangay_profile, edited in Settings > Appearance). Read with the publishable key
 * (the sign-in pages show them before anyone signs in) and kept in a short file cache shared by everyone. The values below are
 * the fallback when the table cannot be read.
 *
 *   barangay()              ['name' => 'Barangay 183', 'place' => 'Zone 20, Villamor, Pasay City', 'seal_url' => null]
 *   brgy_line()             "Barangay 183, Zone 20, Villamor, Pasay City"
 *   brgy_seal('png')        the seal's address: the barangay's own upload, or the one shipped with the portal
 *   brgy_seal_img('cls')    the seal as an <img>, sized when it is the shipped one
 *   barangay_forget()       drop the cache (after the profile is saved)
 */
declare(strict_types=1);

require_once __DIR__ . '/supabase.php';

function barangay_cache_file(): string
{
    return sys_get_temp_dir() . '/ss-barangay-' . substr(md5(env('SUPABASE_URL', '')), 0, 8) . '.json';
}

function barangay_forget(): void
{
    @unlink(barangay_cache_file());
}

/** @return array{name:string, place:string, seal_url:?string} */
function barangay(): array
{
    static $memo = null;
    if ($memo !== null) return $memo;
    $fallback = ['name' => BRGY_NAME, 'place' => 'Zone 20, Villamor, ' . BRGY_CITY, 'seal_url' => null];
    $ttl = (int) env('FEATURE_CACHE_TTL', '20');
    $file = barangay_cache_file();
    if ($ttl > 0 && is_file($file) && filemtime($file) > time() - $ttl) {
        $hit = json_decode((string) @file_get_contents($file), true);
        if (is_array($hit) && isset($hit['name'], $hit['place'])) return $memo = $hit + $fallback;
    }
    try {
        $row = (array) ((new Supabase())->select('barangay_profile', ['select' => 'name,place,seal_url', 'id' => 'eq.1'])[0] ?? []);
        if (!isset($row['name'], $row['place'])) throw new RuntimeException('no profile');
        $out = ['name' => (string) $row['name'], 'place' => (string) $row['place'], 'seal_url' => $row['seal_url'] ? (string) $row['seal_url'] : null];
        if ($ttl > 0) @file_put_contents($file, json_encode($out), LOCK_EX);
        return $memo = $out;
    } catch (Throwable) {
        $old = is_file($file) ? json_decode((string) @file_get_contents($file), true) : null;
        return $memo = is_array($old) && isset($old['name'], $old['place']) ? $old + $fallback : $fallback;
    }
}

function brgy_line(): string
{
    return barangay()['name'] . ', ' . barangay()['place'];
}

/** The seal's address; $fmt picks the shipped file (webp on screen, png in print). */
function brgy_seal(string $fmt = 'webp'): string
{
    return barangay()['seal_url'] ?? 'assets/img/brgy-183-seal.' . ($fmt === 'png' ? 'png' : 'webp');
}

function brgy_seal_img(string $class, string $fmt = 'webp'): string
{
    $alt = e(sprintf(t('%s seal', 'Selyo ng %s'), barangay()['name']));
    if (barangay()['seal_url'] !== null) {
        return '<img class="' . e($class) . '" src="' . e(brgy_seal($fmt)) . '" alt="' . $alt . '">';
    }
    [$w, $h] = @getimagesize(dirname(__DIR__) . '/' . brgy_seal($fmt)) ?: [0, 0];
    return '<img class="' . e($class) . '" src="' . e(brgy_seal($fmt)) . '" width="' . (int) $w . '" height="' . (int) $h . '" alt="' . $alt . '">';
}
