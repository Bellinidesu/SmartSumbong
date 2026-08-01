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
