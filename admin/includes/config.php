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

// Moving hosts (7 Oct 2026): set PORTAL_MOVED_TO=https://new-host on the
// old service and every page answers with a permanent redirect to the same
// path there, so old links and bookmarks keep working. Unset, nothing happens.
if (PHP_SAPI !== 'cli' && ($movedTo = getenv('PORTAL_MOVED_TO')) && preg_match('#^https://[a-z0-9.-]+$#i', $movedTo)) {
    header('Location: ' . $movedTo . ($_SERVER['REQUEST_URI'] ?? '/'), true, 301);
    exit;
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
 * Cloudinary, for the photos an admin attaches (0079). The cloud name and
 * the unsigned preset are public (the app ships both inside its APK), so
 * they have defaults; an environment variable overrides either.
 */
function cloudinary_cloud(): string { return env('CLOUDINARY_CLOUD_NAME', 'nwb2kryl'); }
function cloudinary_preset(): string { return env('CLOUDINARY_UPLOAD_PRESET', 'smartsumbong_unsigned'); }
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

require_once __DIR__ . '/i18n.php';

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

/**
 * Content-Security-Policy (industry passes 3 and 6, 7 Oct 2026). The
 * browser runs only scripts this server put in the page: every <script>
 * carries a random per-request nonce (added below, as the page is sent),
 * so an injected script, inline or remote, is refused. Data, images and
 * fonts load only from this site and the services the portal really uses:
 * Supabase (data, sign-in, live updates), Cloudinary (photos),
 * OpenFreeMap (map tiles), Open-Meteo (rain), Nominatim (addresses) and
 * Google Fonts (the printable documents). Inline styles stay allowed.
 */
function csp_nonce(): string
{
    static $n = null;
    return $n ??= rtrim(strtr(base64_encode(random_bytes(18)), '+/', '-_'), '=');
}

function send_security_policy(): void
{
    if (PHP_SAPI === 'cli' || headers_sent()) return;
    try { $sb = supabase_url(); } catch (Throwable) { $sb = ''; }
    $ws = preg_replace('#^http#', 'ws', $sb);
    $nonce = csp_nonce();
    $policy = [
        "default-src 'self'",
        "script-src 'self' 'nonce-{$nonce}'",
        "script-src-attr 'none'",
        "worker-src 'self' blob:",
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
        "font-src 'self' data: https://fonts.gstatic.com",
        "img-src 'self' data: blob: https://res.cloudinary.com https://tiles.openfreemap.org https://upload.wikimedia.org https://*.mapillary.com https://*.fbcdn.net",
        "media-src 'self' blob: https://res.cloudinary.com",
        "connect-src 'self' {$sb} {$ws} https://tiles.openfreemap.org https://api.open-meteo.com https://air-quality-api.open-meteo.com https://nominatim.openstreetmap.org https://graph.mapillary.com https://commons.wikimedia.org https://*.mapillary.com https://*.fbcdn.net",
        "manifest-src 'self'",
        "frame-ancestors 'self'",
        "base-uri 'self'",
        "form-action 'self'",
        "object-src 'none'",
        "upgrade-insecure-requests",
    ];
    header('Content-Security-Policy: ' . implode('; ', $policy));
    // Stamp the nonce on every <script> of an HTML page as it goes out.
    ob_start(function (string $out) use ($nonce): string {
        foreach (headers_list() as $h) {
            if (stripos($h, 'content-type:') === 0 && stripos($h, 'text/html') === false) return $out;
        }
        return preg_replace('/<script\b(?![^>]*\bnonce=)/i', '<script nonce="' . $nonce . '"', $out) ?? $out;
    });
}
send_security_policy();

/**
 * Error tracking (industry pass 6, 0097): an uncaught exception or fatal
 * error is recorded in portal_errors (shown in Settings → System status),
 * still written to the server log, and the visitor gets the friendly 500
 * page instead of a blank one.
 */
function report_portal_error(string $message, string $detail = ''): void
{
    static $sent = 0;
    if ($sent++ >= 3) return;
    try {
        $ch = curl_init(supabase_url() . '/rest/v1/rpc/log_portal_error');
        curl_setopt_array($ch, [
            CURLOPT_POST => true, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 3, CURLOPT_CONNECTTIMEOUT => 2,
            CURLOPT_HTTPHEADER => ['apikey: ' . supabase_key(), 'Authorization: Bearer ' . supabase_key(), 'Content-Type: application/json'],
            CURLOPT_POSTFIELDS => json_encode([
                'p_source' => 'server',
                'p_page' => strtok((string) ($_SERVER['REQUEST_URI'] ?? '?'), '?'),
                'p_message' => $message,
                'p_detail' => $detail,
            ]),
        ]);
        curl_exec($ch);
    } catch (Throwable) {
        // Recording must never be the thing that fails.
    }
}

if (PHP_SAPI !== 'cli') {
    set_exception_handler(function (Throwable $e): void {
        error_log((string) $e);
        report_portal_error(get_class($e) . ': ' . $e->getMessage(), basename($e->getFile()) . ':' . $e->getLine());
        if (!headers_sent()) { http_response_code(500); }
        while (ob_get_level() > 0) { ob_end_clean(); }
        $_SERVER['REDIRECT_STATUS'] = 500;
        include __DIR__ . '/../error.php';
    });
    register_shutdown_function(function (): void {
        $e = error_get_last();
        if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR], true)) {
            report_portal_error('Fatal: ' . $e['message'], basename($e['file']) . ':' . $e['line']);
        }
    });
}
