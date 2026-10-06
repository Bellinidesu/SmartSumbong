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

function session_start_once(): void
{
    if (session_status() === PHP_SESSION_NONE) {
        session_set_cookie_params([
            'httponly' => true,
            'samesite' => 'Lax',
            // Render terminates HTTPS at its proxy, so PHP itself sees plain
            // HTTP; the proxy says so in X-Forwarded-Proto.
            'secure'   => !empty($_SERVER['HTTPS']) || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https',
        ]);
        session_start();
    }
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
    $session = Supabase::signIn($email, $password);
    $token   = $session['access_token'] ?? null;
    if (!$token) {
        throw new SupabaseError(t('Sign in failed. Please try again.', 'Hindi nakapag-sign in. Subukan muli.'));
    }

    $client  = new Supabase($token);
    $profile = $client->select('users', [
        'select' => 'id,full_name,email,role,verification_status,is_suspended,must_change_password,avatar_url',
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

    if (($me['role'] ?? '') !== 'admin') {
        $client->signOut();
        throw new SupabaseError(t('This portal is for barangay administrators only.', 'Para lamang sa mga administrator ng barangay ang portal na ito.'));
    }

    session_start_once();
    session_regenerate_id(true);
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
    ];
}

function logout(): void
{
    if ($token = access_token()) {
        (new Supabase($token))->signOut();
    }
    session_start_once();
    $_SESSION = [];
    session_destroy();
}

/** Call at the top of every protected page. */
function require_admin(): array
{
    $admin = current_admin();

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
