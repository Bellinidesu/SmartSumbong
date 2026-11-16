<?php
/**
 * Who sees what in the portal (0145). The database decides what each administrator may read and change; this file only
 * shapes the portal to match, so nobody is shown a page or a button the database would refuse.
 *
 *   super      every page                      (at 183: Sir Kiko, Chairperson Zuniga, the development team)
 *   captain    the overview pages, read-only    (no Dashboard, no Settings)
 *   committee  the case pages, its categories   (no Dashboard, no residents); Personnel: its tanods and staff; its own Settings
 *   moderator  the case pages, its categories   as a Kagawad, but Personnel is view only (0164); its own Settings
 *
 * The tier, the developer mark and the committee are read at sign-in and again every two minutes, so a change a super
 * admin makes reaches the person's next page without signing them out.
 */
declare(strict_types=1);

/** Pages each tier may open. A page not listed (the small JSON doors) is open to every administrator. */
const PAGE_TIERS = [
    'dashboard.php'           => ['super', 'captain'],   // 15 Nov 2026 (Rose): the Dashboard is one of the four pages of viewing mode
    'home.php'                => [],   // 15 Nov 2026 (Rose): no Home for anyone; a Kagawad and staff land on Notifications
    'settings.php'            => ['super', 'committee', 'moderator'],   // a Kagawad's and staff's own: look, their committee, their SMART module (4 Nov 2026)
    'retirement-requests.php' => ['super'],
    'administrative-services.php' => ['super'],
    'committee-editor.php'    => ['super'],   // 16 Nov 2026 (Ace): making or editing a committee, a page of its own with the committee's sidebar live beside it
    'control-room.php'        => ['super'],
    'certificate.php'         => ['super', 'committee', 'moderator'],   // the referral certificate: whoever may refer a case prints it (7 Nov 2026); row level security keeps it to the cases they see
    'workspace.php'           => ['super'],
    'residents.php'           => ['super'],
    'personnel.php'           => ['super', 'committee', 'moderator'],   // a Kagawad: their tanods, their staff, their tanods' retirement requests; staff: the same tanods and staff, view only (0164)
    'activity.php'            => ['super'],
    'summary.php'             => ['super', 'captain', 'committee'],   // not staff (Rose, 15 Nov)
    'spatial.php'             => ['super', 'captain', 'committee', 'moderator'],
    'places.php'              => ['super'],   // 15 Nov 2026 (Ace): the barangay's places, moved from Settings to a button on the side of Spatial Distribution
    'cases.php'               => ['super', 'captain', 'committee', 'moderator'],
    'case.php'                => ['super', 'captain', 'committee', 'moderator'],
    'notifications.php'       => ['super', 'committee', 'moderator'],
    'inbox.php'               => ['super', 'committee', 'moderator'],
];

/**
 * Viewing mode (15 Nov 2026, Rose): the Chairman is a super admin who can switch to looking only. While it is on the portal behaves as the view-only
 * tier: Dashboard, Report Summary, Spatial Distribution and Case Reports, nothing can be changed (auth.php refuses every form), exports still work.
 */
function can_view_mode(): bool
{
    $a = current_admin();
    return is_array($a) && (($a['admin_tier'] ?? 'super') === 'super') && (($a['official_role'] ?? '') === 'chairman');
}
function view_mode_on(): bool
{
    session_start_once();
    return can_view_mode() && ($_SESSION['view_mode'] ?? false) === true;
}

function my_tier(): string
{
    if (view_mode_on()) return 'captain';
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

/**
 * Where a person lands after signing in, or when a page is not for them: Notifications; the view-only tier (a Captain account, and the Chairman in viewing
 * mode) the Dashboard. 16 Nov 2026 (the sweep): a Captain account landed on Notifications, which it may not open, so every refused page and the sign-in
 * itself sent it round in a loop ("too many redirects").
 */
function landing_page(): string
{
    $to = my_tier() === 'captain' ? 'dashboard.php' : 'notifications.php';
    return page_allowed($to) ? $to : 'cases.php';   // never a page the person cannot open: that is the loop
}

/** True when the person's access is due to be read again (every two minutes). */
function access_refresh_due(): bool
{
    $a = current_admin();
    return (bool) $a && (($a['access_at'] ?? 0) <= time() - 120);
}

/** The access read, for the request's boot batch (boot.php) and for access_refresh() alike. */
function access_refresh_entry(): array
{
    return ['users', ['select' => 'admin_tier,is_dev,committee,official_role', 'id' => 'eq.' . (current_admin()['id'] ?? '0'), 'limit' => '1'], true];
}

/** The person's access, fresh from the database every two minutes (called from require_admin). */
function access_refresh(): void
{
    $a = current_admin();
    if (!access_refresh_due()) return;
    try {
        $me = db()->select('users', access_refresh_entry()[1])[0] ?? null;
    } catch (Throwable) {
        return;   // keep what the session has; the database still decides
    }
    if (!is_array($me)) return;
    $a['admin_tier'] = $me['admin_tier'] ?? null;
    $a['is_dev'] = !empty($me['is_dev']);
    $a['committee'] = $me['committee'] ?? null;
    $a['official_role'] = $me['official_role'] ?? null;
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

/**
 * The barangay's committees (0145): key => [name_en, name_fil, short_en, active, sort, colour, logo_url]. Read once per request,
 * from the shared cache (shared_cache.php) most of the time; Settings drops the copy when a committee is saved.
 */
function committees_all(): array
{
    static $memo = null;
    if ($memo !== null) return $memo;
    $rows = shared_cache('committees', static function (): ?array {
        try { [, $cq] = committees_read_entry(); return (array) db()->select('committees', $cq); } catch (Throwable) {}
        // logo_url arrives with 0164; until it is applied the committees are read without it
        try { return (array) db()->select('committees', ['select' => 'key,name_en,name_fil,short_en,active,sort,colour', 'order' => 'sort.asc,key.asc']); } catch (Throwable) {}
        return null;
    }, access_token() !== null);
    $memo = [];
    foreach ($rows as $c) { $memo[(string) $c['key']] = $c + ['logo_url' => null]; }
    return $memo;
}

/** The committees' read and the committee-categories read, for the request's boot batch (boot.php) and for the readers alike. */
function committees_read_entry(): array
{
    return ['committees', ['select' => 'key,name_en,name_fil,short_en,active,sort,colour,logo_url', 'order' => 'sort.asc,key.asc'], true];
}

function committee_categories_read_entry(): array
{
    return ['committee_categories', ['select' => 'committee,category'], true];
}

/** Which complaint types each committee sees (0145, committee_categories): committee key => list of category keys. Shared cache. */
function committee_categories_all(): array
{
    static $memo = null;
    if ($memo !== null) return $memo;
    $rows = shared_cache('committee_categories', static fn (): array => (array) db()->select('committee_categories', committee_categories_read_entry()[1]),
                         access_token() !== null);
    $memo = [];
    foreach ($rows as $r) { $memo[(string) $r['committee']][] = (string) $r['category']; }
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
