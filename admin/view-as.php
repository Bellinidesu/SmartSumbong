<?php
/**
 * Seeing the portal as each rung of the ladder (0162), for the development team only.
 *
 * A developer (users.is_dev) has a real test account for each rung: super admin, captain, Kagawad and staff. Switching signs into
 * that account through the level-switch Edge Function (no password), and the developer's own session is kept here, in
 * $_SESSION['dev_origin'], to come back to. Because the test account is a real account of that rung, the database shows it exactly
 * what that rung may see and do. Every switch is recorded (dev_level_switches).
 *
 *   POST action=setup   committee=<key>   make the missing test accounts, or move the Kagawad and staff to another committee
 *   POST action=switch  level=<rung>      become that test account
 *   POST action=back                      be yourself again
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin();
session_start_once();
$back = $_POST['from'] ?? '';
$go = static function (string $to): never { header('Location: ' . $to); exit; };
$here = (is_string($back) && preg_match('/^[a-z-]+\.php(\?[^\s<>"]*)?$/', $back)) ? $back : landing_page();

if ($_SERVER['REQUEST_METHOD'] !== 'POST' || !csrf_check($_POST['csrf'] ?? null)) $go($here);

/** The developer's own session, refreshed if it is near its end. */
function dev_origin(): ?array
{
    $o = $_SESSION['dev_origin'] ?? (!empty(current_admin()['is_dev']) ? current_admin() : null);
    if (!is_array($o)) return null;
    if (($o['expires_at'] ?? 0) < time() + 60) {
        try {
            $f = Supabase::refresh((string) ($o['refresh_token'] ?? ''));
            $o['access_token'] = $f['access_token']; $o['refresh_token'] = $f['refresh_token'] ?? $o['refresh_token']; $o['expires_at'] = time() + (int) ($f['expires_in'] ?? 3600);
        } catch (SupabaseError) { return null; }
        if (isset($_SESSION['dev_origin'])) $_SESSION['dev_origin'] = $o;
    }
    return $o;
}

$origin = dev_origin();
if (!$origin || empty($origin['is_dev'])) $go($here);   // only the development team, and only from their own session
$dev = new Supabase((string) $origin['access_token']);
$act = (string) ($_POST['action'] ?? '');
try {
    if ($act === 'back') {
        if (isset($_SESSION['dev_origin'])) {
            try { (new Supabase((string) access_token()))->signOut(); } catch (Throwable) {}
            session_regenerate_id(true);
            $_SESSION[SESSION_KEY] = $origin;
            unset($_SESSION['dev_origin'], $_SESSION['dev_view']);
        }
        $go('administrative-services.php#admins');
    }
    if ($act === 'setup') {
        $dev->rpc('dev_test_accounts_ensure', ['p_committee' => (string) ($_POST['committee'] ?? '') ?: null]);
        $_SESSION['dev_flash'] = t('Your test accounts are ready. Pick a level to see the portal as it does.', 'Handa na ang iyong mga test account. Pumili ng antas para makita ang portal gaya nito.');
        $go($here);
    }
    if ($act === 'switch') {
        $level = (string) ($_POST['level'] ?? '');
        $session = $dev->invoke('level-switch', ['level' => $level]);
        if (!is_array($session) || empty($session['access_token'])) throw new SupabaseError(t('Could not switch. Try again.', 'Hindi makapagpalit. Subukan muli.'));
        $keep = $origin;
        establish_session($session);   // regenerates the session id and replaces the signed-in administrator
        $_SESSION['dev_origin'] = $keep;
        $_SESSION['dev_view'] = $level;
        unset($_SESSION['dash_intro']);
        $go(page_allowed('dashboard.php') ? 'dashboard.php' : landing_page());
    }
} catch (SupabaseError $ex) {
    $_SESSION['dev_flash'] = safe_error($ex);
}
$go($here);
