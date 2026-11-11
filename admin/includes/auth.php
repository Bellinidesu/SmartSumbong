<?php
/**
 * Session and access control for the admin portal.
 *
 * The portal is for the barangay admin only. A resident or tanod has a
 * valid account and can sign in against GoTrue, so the role check below
 * is what keeps them out of this interface. Their RLS policies would
 * already stop them reading other people's reports — this just fails
 * honestly at the door instead of showing an empty portal.
 */
declare(strict_types=1);

require_once __DIR__ . '/supabase.php';
require_once __DIR__ . '/features.php';
require_once __DIR__ . '/barangay.php';
require_once __DIR__ . '/access.php';
require_once __DIR__ . '/boot.php';

/**
 * The session is opened once per request. A page view (GET or HEAD) reads it and lets go of it at once (speed work, 7 Nov 2026).
 *
 * PHP locks a session file for as long as a request has it open, so two requests from one person used to run one after the
 * other: a press waited behind the browser's prefetch of the same address, behind a list's live refresh, behind a page open in
 * another tab, each of them a whole page of waits on the database. Now a page view holds the lock only while it reads
 * the session. What it changes on the way (the sidebar's counts, a message shown once and then dropped, a remembered filter, the
 * sign-in's refreshed token) is written back when the request ends: the session is opened again for a moment, and only the
 * entries this request changed are put over what the file holds then, so another request's changes in the meantime are kept.
 * A form (POST and the rest) keeps the lock from start to end, as before: it may sign in, sign out or change who someone is.
 */
function session_start_once(): void
{
    static $opened = false;
    if ($opened || session_status() !== PHP_SESSION_NONE) return;
    $opened = true;
    // Over HTTPS the cookie carries the __Host- prefix (7 Nov 2026): a browser then accepts it only when it is Secure, for the
    // whole site (path /) and set by this host alone, so no other site under a shared domain (onrender.com) can plant or
    // overwrite it. Plain HTTP (the local test site) keeps PHP's own name, since the prefix needs Secure.
    if (request_is_https()) session_name('__Host-ssid');
    session_set_cookie_params([
        'httponly' => true,
        'samesite' => 'Lax',
        // Render terminates HTTPS at its proxy, so PHP itself sees plain
        // HTTP; the proxy says so in X-Forwarded-Proto.
        'secure'   => request_is_https(),
        'path'     => '/',
    ]);
    session_start();
    if (PHP_SAPI !== 'cli' && in_array($_SERVER['REQUEST_METHOD'] ?? 'GET', ['GET', 'HEAD'], true)) {
        session_let_go();
    }
}

/** What the session held when this request let go of it (null: it still holds it, or never let go). */
function &session_snapshot(): ?array
{
    static $snap = null;
    return $snap;
}

/** Reads done: write the session as it is, unlock it, and write this request's changes back when it ends. */
function session_let_go(): void
{
    if (session_status() !== PHP_SESSION_ACTIVE) return;
    $snap = &session_snapshot();
    $snap = $_SESSION;
    session_write_close();
    register_shutdown_function(static function (): void { session_take_back(true); });
}

/**
 * Takes the session back after session_let_go(): opens it again (locking it), puts this request's own changes over what the
 * file holds now, and, at the end of a request, writes and unlocks it. $atEnd = false keeps it open for a request that must
 * change the session as a whole from here on (session_writable()). Nothing changed: nothing is opened.
 */
function session_take_back(bool $atEnd): void
{
    $snap = &session_snapshot();
    if ($snap === null || session_status() === PHP_SESSION_ACTIVE) return;
    $now = $_SESSION ?? [];
    $set = [];
    foreach ($now as $k => $v) {
        if (!array_key_exists($k, $snap) || $snap[$k] !== $v) $set[$k] = $v;
    }
    $gone = array_keys(array_diff_key($snap, $now));
    $snap = null;
    if ($atEnd && !$set && !$gone) return;
    $id = session_id();
    if ($id === '' || $id === false) return;
    if ($atEnd) {
        // the page may already be written: no cookie and no cache headers this time (the cookie is the one the browser sent)
        @ini_set('session.use_cookies', '0');
        @ini_set('session.cache_limiter', '');
    }
    session_id($id);
    if (!@session_start()) return;
    foreach ($set as $k => $v) $_SESSION[$k] = $v;
    foreach ($gone as $k) unset($_SESSION[$k]);
    if ($atEnd) session_write_close();
}

/** A page view that has to replace or end the session itself (a new id, signing out) takes the lock back first. */
function session_writable(): void
{
    session_start_once();
    session_take_back(false);
}

function current_admin(): ?array
{
    session_start_once();
    return $_SESSION[SESSION_KEY] ?? null;
}

function access_token(): ?string
{
    return current_admin()['access_token'] ?? null;
}

function db(): Supabase
{
    return new Supabase(access_token());
}

/**
 * @throws SupabaseError when the credentials are wrong or the account is
 *         not an administrator.
 */
function attempt_login(string $email, string $password): void
{
    establish_session(Supabase::signIn($email, $password));
}

/**
 * Makes a GoTrue session the portal's signed-in administrator: the profile, the suspension and administrator checks, and the
 * session itself. Used by the password sign-in and by a developer's switch into a test account (view-as.php, 0162).
 *
 * @throws SupabaseError when the session is not an active administrator's
 */
function establish_session(array $session): void
{
    $token   = $session['access_token'] ?? null;
    if (!$token) {
        throw new SupabaseError(t('Sign in failed. Please try again.', 'Hindi nakapag-sign in. Subukan muli.'));
    }

    $client  = new Supabase($token);
    $profile = $client->select('users', [
        'select' => 'id,full_name,email,role,verification_status,is_suspended,is_retired,must_change_password,avatar_url,admin_tier,is_dev,committee,is_test',
        'id'     => 'eq.' . ($session['user']['id'] ?? ''),
        'limit'  => '1',
    ]);

    $me = $profile[0] ?? null;
    if (!$me) {
        throw new SupabaseError(t('No barangay profile is linked to this account.', 'Walang barangay profile na naka-link sa account na ito.'));
    }
    // Suspension is a database flag; GoTrue knows nothing about it, so a
    // suspended account can still authenticate and receive a token. The
    // portal has to refuse it here or suspension is cosmetic for anyone
    // who was an administrator when it happened.
    if (!empty($me['is_suspended'])) {
        logout();
        throw new SupabaseError(t('This account has been suspended. Contact the barangay administrator.', 'Na-suspend ang account na ito. Makipag-ugnayan sa administrator ng barangay.'));
    }

    // 0166: a staff member whose retirement was approved no longer signs in to the portal
    if (!empty($me['is_retired'])) {
        logout();
        throw new SupabaseError(t('This account has retired. Thank you for your service.', 'Nagretiro na ang account na ito. Salamat sa iyong paglilingkod.'));
    }

    if (($me['role'] ?? '') !== 'admin') {
        $client->signOut();
        throw new SupabaseError(t('This portal is for barangay administrators only.', 'Para lamang sa mga administrator ng barangay ang portal na ito.'));
    }

    session_writable();
    session_regenerate_id(true);
    unset($_SESSION['dash_intro']);   // the dashboard animates its charts once per sign-in
    $_SESSION[SESSION_KEY] = [
        'access_token'  => $token,
        'refresh_token' => $session['refresh_token'] ?? '',
        'expires_at'    => time() + (int) ($session['expires_in'] ?? 3600),
        'id'            => $me['id'],
        'full_name'     => $me['full_name'],
        'email'         => $me['email'],
        // Rose (5 Oct 2026): an account issued with a temporary password
        // must choose its own before anything else (change-password.php).
        'must_change'   => !empty($me['must_change_password']),
        'avatar_url'    => $me['avatar_url'] ?? null,
        'seen'          => time(),
        // 0145: what this administrator may see and do (refreshed every two minutes by access_refresh)
        'admin_tier'    => $me['admin_tier'] ?? null,
        'is_dev'        => !empty($me['is_dev']),
        'is_test'       => !empty($me['is_test']),
        'committee'     => $me['committee'] ?? null,
        'access_at'     => time(),
    ];
}

function logout(): void
{
    if ($token = access_token()) {
        (new Supabase($token))->signOut();
    }
    session_writable();
    $_SESSION = [];
    session_destroy();
}

/** Call at the top of every protected page. */
/**
 * Idle sign-out (industry pass 3, 7 Oct 2026): a session nobody has used
 * for this long ends, so a portal left open on a shared barangay computer
 * does not stay signed in. Only real use counts (opening a page, saving a
 * form); a live page refreshing its token in the background does not.
 */
const IDLE_LIMIT = 2 * 3600;

function session_idle_expired(?array $admin): bool
{
    return $admin !== null && isset($admin['seen']) && $admin['seen'] < time() - IDLE_LIMIT;
}

function require_admin(): array
{
    $admin = current_admin();
    if (session_idle_expired($admin)) {
        unset($_SESSION[SESSION_KEY]);
        header('Location: login.php?expired=1');
        exit;
    }
    if ($admin) {
        $admin['seen'] = time();
        $_SESSION[SESSION_KEY] = $admin;
    }

    if ($admin && $admin['expires_at'] < time() + 60) {
        // Token is about to lapse. Renew silently so a long shift on the
        // dashboard does not end in a surprise logout mid-task.
        try {
            $fresh = Supabase::refresh($admin['refresh_token']);
            $admin['access_token']  = $fresh['access_token'];
            $admin['refresh_token'] = $fresh['refresh_token'] ?? $admin['refresh_token'];
            $admin['expires_at']    = time() + (int) ($fresh['expires_in'] ?? 3600);
            $_SESSION[SESSION_KEY]  = $admin;
        } catch (SupabaseError) {
            // The refresh token is dead too (the portal was left overnight).
            // Forget the login entirely: leaving it in the session made
            // login.php see "signed in" and bounce back here, which bounced
            // to login.php again — ERR_TOO_MANY_REDIRECTS until the cookie
            // was cleared by hand.
            unset($_SESSION[SESSION_KEY]);
            $admin = null;
        }
    }

    if (!$admin) {
        header('Location: login.php?expired=1');
        exit;
    }
    if (!empty($admin['must_change']) && basename($_SERVER['SCRIPT_NAME'] ?? '') !== 'change-password.php'
        && basename($_SERVER['SCRIPT_NAME'] ?? '') !== 'logout.php') {
        header('Location: change-password.php');
        exit;
    }
    // a form sent: this person's engine copies go (supabase.php), so what they just did shows on their next page
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') engine_forget_mine(current_admin()['access_token'] ?? null);
    boot_prefetch();   // every cold cache's read in one wait (boot.php), before the page and its readers run
    access_refresh();
    require_page_access();
    return current_admin() ?? $admin;
}

/**
 * For the JSON doors a page calls in the background (the Workspace widgets): the signed-in administrator with a live
 * token, or a 401 answer. Unlike require_admin() it never redirects, and a background call does not count as use, so
 * a Workspace left open still signs out after IDLE_LIMIT.
 */
function require_admin_api(): array
{
    $admin = current_admin();
    if (!$admin || session_idle_expired($admin)) {
        http_response_code(401);
        header('Content-Type: application/json');
        echo json_encode(['error' => 'signed_out']);
        exit;
    }
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') engine_forget_mine($admin['access_token'] ?? null);
    if ($admin['expires_at'] < time() + 60) {
        try {
            $fresh = Supabase::refresh($admin['refresh_token']);
            $admin['access_token']  = $fresh['access_token'];
            $admin['refresh_token'] = $fresh['refresh_token'] ?? $admin['refresh_token'];
            $admin['expires_at']    = time() + (int) ($fresh['expires_in'] ?? 3600);
            $_SESSION[SESSION_KEY]  = $admin;
        } catch (SupabaseError) {
            unset($_SESSION[SESSION_KEY]);
            http_response_code(401);
            header('Content-Type: application/json');
            echo json_encode(['error' => 'signed_out']);
            exit;
        }
    }
    if (!empty($admin['must_change'])) {
        http_response_code(403);
        header('Content-Type: application/json');
        echo json_encode(['error' => 'must_change_password']);
        exit;
    }
    return $admin;
}

function csrf_token(): string
{
    session_start_once();
    return $_SESSION['csrf'] ??= bin2hex(random_bytes(32));
}

function csrf_check(?string $sent): bool
{
    session_start_once();
    return is_string($sent) && hash_equals($_SESSION['csrf'] ?? '', $sent);
}
