<?php
/**
 * SmartSumbong admin portal — configuration.
 *
 * Never commit real values. Copy .env.example to .env and fill it in;
 * .env is gitignored.
 */
declare(strict_types=1);

function env(string $key, ?string $default = null): string
{
    static $vars = null;

    if ($vars === null) {
        $vars = [];
        $path = dirname(__DIR__, 2) . '/.env';
        if (is_readable($path)) {
            foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
                if ($line === '' || $line[0] === '#' || !str_contains($line, '=')) {
                    continue;
                }
                [$k, $v] = explode('=', $line, 2);
                $vars[trim($k)] = trim($v, " \t\"'");
            }
        }
    }

    $value = $vars[$key] ?? (getenv($key) ?: $default);
    if ($value === null || $value === false) {
        throw new RuntimeException("Missing configuration: {$key}");
    }
    return (string) $value;
}

const BRGY_NAME   = 'Barangay 183';
const BRGY_CITY   = 'Pasay City';
const SESSION_KEY = 'smartsumbong_admin';

/**
 * The portal only ever uses the publishable key. Every request carries
 * the signed-in admin's own JWT, so the row level security policies in
 * the database are what authorise each query — not this PHP. A service
 * key would bypass them and must never appear here.
 */
function supabase_url(): string { return rtrim(env('SUPABASE_URL'), '/'); }
/**
 * Supabase renamed the client-side key from "anon" to "publishable".
 * Accept either name so an older .env keeps working — the portal never
 * uses the secret key, whichever name it is stored under.
 */
function supabase_key(): string
{
    foreach (['SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY'] as $name) {
        try {
            return env($name);
        } catch (RuntimeException) {
            continue;
        }
    }
    throw new RuntimeException(
        'Missing configuration: set SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY) in .env'
    );
}

function e(?string $s): string
{
    return htmlspecialchars($s ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/**
 * Cache-buster for our own static assets (15 Sep 2026). app.css and
 * fonts.css were linked with no version string at all, so a browser that
 * had ever cached them kept serving that exact copy indefinitely --
 * Render sends no Cache-Control header on static files, so there was
 * nothing forcing a revalidation. Every CSS fix since (the 0054 avatar
 * sizing rules, the dash-mid alignment fix) was silently invisible to any
 * admin whose browser had a pre-existing cached copy, even after a hard
 * deploy -- confirmed live on residents.php, where a stale cached app.css
 * missing .avatar--sm entirely let a resident's photo render at full
 * native resolution and blow out the whole table.
 *
 * filemtime() of the actual file on disk means the version string changes
 * exactly when the file changes and never otherwise, so this needs no
 * manual bump on every edit.
 */
function asset_version(string $cssFile): string
{
    $path  = __DIR__ . '/../assets/css/' . $cssFile;
    $mtime = @filemtime($path);
    return $mtime !== false ? (string) $mtime : '1';
}
