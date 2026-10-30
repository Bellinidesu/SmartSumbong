<?php
/**
 * Who sees what in the portal (0145). The database decides what each administrator may read and change; this file only
 * shapes the portal to match, so nobody is shown a page or a button the database would refuse.
 *
 *   super      every page                      (at 183: Sir Kiko, Chairperson Zuniga, the development team)
 *   captain    the overview pages, read-only    (no Dashboard, no Settings)
 *   committee  the case pages, its categories   (no Dashboard, no Settings, no residents or personnel)
 *
 * The tier, the developer mark and the committee are read at sign-in and again every two minutes, so a change a super
 * admin makes reaches the person's next page without signing them out.
 */
declare(strict_types=1);

/** Pages each tier may open. A page not listed (the small JSON doors) is open to every administrator. */
const PAGE_TIERS = [
    'dashboard.php'           => ['super'],
    'settings.php'            => ['super'],
    'retirement-requests.php' => ['super'],
    'administrative-services.php' => ['super'],
    'control-room.php'        => ['super'],
    'certificate.php'         => ['super'],
    'workspace.php'           => ['super'],
    'residents.php'           => ['super', 'captain'],
    'personnel.php'           => ['super', 'captain', 'committee'],
    'activity.php'            => ['super', 'captain'],
    'summary.php'             => ['super', 'captain', 'committee', 'moderator'],
    'spatial.php'             => ['super', 'captain', 'committee', 'moderator'],
    'cases.php'               => ['super', 'captain', 'committee', 'moderator'],
    'case.php'                => ['super', 'captain', 'committee', 'moderator'],
    'notifications.php'       => ['super', 'captain', 'committee', 'moderator'],
];

function my_tier(): string
{
    $t = current_admin()['admin_tier'] ?? null;
    return in_array($t, ['super', 'committee', 'moderator', 'captain'], true) ? $t : 'super';   // an empty tier reads as super, as in the database
}
function is_super(): bool      { return my_tier() === 'super'; }
function is_captain(): bool    { return my_tier() === 'captain'; }
function is_committee(): bool  { return my_tier() === 'committee'; }
function is_moderator(): bool  { return my_tier() === 'moderator'; }
/** Sees only a committee's cases: a Kagawad (committee) or a staff member (moderator, 0151). */
function is_scoped(): bool     { return in_array(my_tier(), ['committee', 'moderator'], true); }
function sees_everything(): bool { return !is_scoped(); }
function is_dev_admin(): bool  { return !empty(current_admin()['is_dev']); }

function page_allowed(string $page): bool
{
    return !isset(PAGE_TIERS[$page]) || in_array(my_tier(), PAGE_TIERS[$page], true);
}

/** Where a person lands when a page is not for them: the notifications page is for everyone. */
function landing_page(): string
{
    return 'notifications.php';
}

/** The person's access, fresh from the database every two minutes (called from require_admin). */
function access_refresh(): void
{
    $a = current_admin();
    if (!$a || (($a['access_at'] ?? 0) > time() - 120)) return;
    try {
        $me = db()->select('users', ['select' => 'admin_tier,is_dev,committee', 'id' => 'eq.' . $a['id'], 'limit' => '1'])[0] ?? null;
    } catch (Throwable) {
        return;   // keep what the session has; the database still decides
    }
    if (!is_array($me)) return;
    $a['admin_tier'] = $me['admin_tier'] ?? null;
    $a['is_dev'] = !empty($me['is_dev']);
    $a['committee'] = $me['committee'] ?? null;
    $a['access_at'] = time();
    session_start_once();
    $_SESSION[SESSION_KEY] = $a;
}

/** A page that is not for this tier sends the person to one that is. */
function require_page_access(): void
{
    $page = basename((string) ($_SERVER['SCRIPT_NAME'] ?? $_SERVER['PHP_SELF'] ?? ''));
    if ($page !== '' && !page_allowed($page)) {
        header('Location: ' . landing_page(), true, 302);
        exit;
    }
}

/** The barangay's committees (0145), read once per request: key => [name_en, name_fil, short_en, active, sort]. */
function committees_all(): array
{
    static $memo = null;
    if ($memo !== null) return $memo;
    $memo = [];
    try {
        foreach ((array) db()->select('committees', ['select' => 'key,name_en,name_fil,short_en,active,sort,colour', 'order' => 'sort.asc,key.asc']) as $c) {
            $memo[(string) $c['key']] = $c;
        }
    } catch (Throwable) {}
    return $memo;
}

/** The committees that are on, for pick lists: key => label (the short name; the full name in a tooltip). */
function committees_active(): array
{
    $out = [];
    foreach (committees_all() as $k => $c) { if (!empty($c['active'])) $out[$k] = (string) $c['short_en']; }
    return $out;
}

/** How the signed-in person's access reads under their name in the sidebar. */
function access_label(): string
{
    $a = current_admin() ?? [];
    $tier = my_tier();
    $base = match ($tier) {
        'captain'   => t('Captain · view only', 'Kapitan · tingin lamang'),
        'committee' => ($n = committees_all()[(string) ($a['committee'] ?? '')]['short_en'] ?? null) ? (string) $n : t('Committee', 'Komite'),
        'moderator' => t('Staff', 'Kawani') . (($n = committees_all()[(string) ($a['committee'] ?? '')]['short_en'] ?? null) ? ' · ' . $n : ''),
        default     => t('Super admin', 'Pangunahing admin'),
    };
    return $base . (is_dev_admin() ? ' · DEV' : '');
}
