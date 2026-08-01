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
            'secure'   => !empty($_SERVER['HTTPS']),
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
        throw new SupabaseError('Sign in failed. Please try again.');
    }

    $client  = new Supabase($token);
    $profile = $client->select('users', [
        'select' => 'id,full_name,email,role,verification_status',
        'id'     => 'eq.' . ($session['user']['id'] ?? ''),
        'limit'  => '1',
    ]);

    $me = $profile[0] ?? null;
    if (!$me) {
        throw new SupabaseError('No barangay profile is linked to this account.');
    }
    if (($me['role'] ?? '') !== 'admin') {
        $client->signOut();
        throw new SupabaseError('This portal is for barangay administrators only.');
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
            $admin = null;
        }
    }

    if (!$admin) {
        header('Location: login.php?expired=1');
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
