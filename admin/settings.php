<?php
/**
 * Settings (3 Oct 2026): System status and Plan and usage.
 *
 * System status checks every service the portal depends on and says in
 * plain words what is wrong and what it means for the barangay. Supabase,
 * Cloudinary and the push function are checked from this server (?check=
 * server); map tiles, address lookup, rain data, live updates and the
 * Project NOAH file are checked from the admin's own browser, because
 * that is where they load.
 *
 * Plan and usage shows how close the barangay is to each plan's limits:
 * Supabase's database size, file storage and active users come from the
 * database itself (system_usage(), 0078); Cloudinary's credits need its
 * API key and secret in the server's environment; the rest are the
 * providers' published limits. No key or password ever reaches the page.
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/qr.php';
require_once __DIR__ . '/includes/forwarding.php';   // the committee banners (committee_sd_types, cm_banner_style, sd_icon_for)
require_once __DIR__ . '/includes/app_editor.php';   // the Control Room's live view of the app

$admin = require_admin();
$db    = db();

// One tab engine, three pages (30 Oct 2026, docs/ROLES_AND_PAGES.md): Settings keeps the system's own tabs, Administrative
// Services takes the barangay's people and paperwork, the Control Room takes how the app behaves for this barangay. Each page
// sets ST_PAGE and includes this file; a form posts to the page it is on and comes back to its tab on the page that owns it.
const ST_PAGES = [
    'settings' => ['file' => 'settings.php', 'tabs' => ['status', 'usage', 'smart', 'look']],
    'admin'    => ['file' => 'administrative-services.php', 'tabs' => ['access', 'admins', 'ladder', 'plan']],
    'control'  => ['file' => 'control-room.php', 'tabs' => ['types', 'rules', 'hotlines', 'wording', 'brgy', 'parts', 'updates']],
];
$stPage = defined('ST_PAGE') && isset(ST_PAGES[ST_PAGE]) ? ST_PAGE : 'settings';

function st_on(string $tab): bool
{
    return in_array($tab, ST_PAGES[$GLOBALS['stPage']]['tabs'], true);
}

/** A tab's address on the page that owns it ('places' is a card inside Appearance). */
function st_url(string $tab, string $query = ''): string
{
    $own = $tab === 'places' ? 'look' : $tab;
    foreach (ST_PAGES as $p) {
        if (in_array($own, $p['tabs'], true)) return $p['file'] . $query . '#' . $tab;
    }
    return 'settings.php' . $query . '#' . $tab;
}

// 0084 (Rose): add an administrator, or issue one a new temporary
// password. The password is shown once, here, and never stored by the portal.
// 0130 (defense, 7 Sep): the barangay's positions. Which Kagawad chairs which committee, who is the Chairman, which tanods are the
// designated women responders, and which committee usually takes which kind of complaint. Each is one action here.
// The committees are a table since 0145 (committees_all() in includes/access.php), made and edited on the Access tab.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['set_role', 'set_responder', 'set_committee_map'], true)) {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            $uid = (string) ($_POST['user'] ?? '');
            if ($_POST['action'] === 'set_role') {
                $role = (string) ($_POST['official_role'] ?? '');
                $comm = (string) ($_POST['committee'] ?? '');
                $db->rpc('set_official_role', ['p_user' => $uid, 'p_role' => $role === '' ? null : $role,
                                              'p_committee' => in_array($role, ['kagawad', 'secretary'], true) && isset(committees_all()[$comm]) ? $comm : null, 'p_women' => null]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Position saved. The access that goes with it is set too: Chairman super admin, Kagawad committee, secretary moderator.', 'Nai-save ang posisyon. Naitakda rin ang kasamang access: Punong Barangay super admin, Kagawad komite, kalihim moderator.')];
            } elseif ($_POST['action'] === 'set_responder') {
                $db->rpc('set_official_role', ['p_user' => $uid, 'p_role' => null, 'p_committee' => null, 'p_women' => !empty($_POST['on'])]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Responder designation saved.', 'Nai-save ang pagtatalaga ng responder.')];
            } elseif ($act === 'smart_word') {
                // Words to learn (SMART_SCREENS 6c, 0128): an administrator approves every word; nothing is learned silently.
                $how = (string) ($_POST['as'] ?? ''); $word = trim((string) ($_POST['word'] ?? ''));
                $db->rpc('smart_teach_word', ['p_word' => $word, 'p_as' => $how, 'p_target' => trim((string) ($_POST['target'] ?? '')) ?: null]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => $how === 'dismiss'
                    ? t('Not a word to learn. It will not be suggested again.', 'Hindi salitang aaralin. Hindi na ito imumungkahi.')
                    : t('Learned. Open reports were scored again.', 'Natutunan. Muling minarkahan ang mga bukas na ulat.')];
            } else {
                $cat = (string) ($_POST['category'] ?? ''); $comm = (string) ($_POST['committee'] ?? '');
                if (isset(committees_all()[$comm]) && preg_match('/^[a-z_]+$/', $cat)) {
                    $db->update('committee_for_category', ['category' => 'eq.' . $cat], ['committee' => $comm]);
                    $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Committee saved.', 'Nai-save ang komite.')];
                }
            }
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: ' . st_url(($_POST['action'] ?? '') === 'set_role' ? 'admins' : 'ladder'));
    exit;
}

// Settings -> SMART (docs/SMART_SCREENS.md, 6 and 6b): the rules, storm mode, the digest, trying a rule, re-scoring.
/** The barangay's limits (operational_settings, 0147 in the portal): column => [English, Tagalog, hint EN, hint TL, min, max]. */
const RULE_LIMITS = [
    'max_deadline_extensions'    => ['Times a deadline may be moved', 'Ilang beses mauusog ang deadline', 'After this the case goes to a higher official.', 'Pagkatapos nito, sa mas mataas na opisyal ang kaso.', 0, 10],
    'awaiting_alert_hours'       => ['Hours a report may wait unattended', 'Oras na puwedeng maghintay ang ulat', 'Then the administrators are told nobody is on it.', 'Saka sasabihan ang mga administrator na walang humahawak.', 1, 48],
    'max_active_dispatches'      => ['Jobs a tanod may hold at once', 'Trabahong sabay na hawak ng tanod', 'A tanod at this many is not offered another.', 'Hindi na aalukin ang tanod na umabot dito.', 1, 20],
    'location_freshness_minutes' => ['Minutes a tanod\'s position stays fresh', 'Minutong sariwa ang lokasyon ng tanod', 'An older position is not used for "nearest".', 'Hindi ginagamit sa "pinakamalapit" ang mas lumang lokasyon.', 1, 120],
    'max_report_photos'          => ['Photos per report', 'Litrato bawat ulat', 'Up to 5, the most the app attaches.', 'Hanggang 5, ang pinakamaraming kayang ilakip ng app.', 1, 5],
    'reroute_ask_urgent_minutes' => ['Minutes a Kagawad has to pick a tanod (urgent)', 'Minutong may ang Kagawad para pumili ng tanod (apurahan)', 'On a reroute with none of the committee\'s tanods free; then the nearest from any committee is sent.', 'Sa reroute na walang bakanteng tanod ang komite; saka ipapadala ang pinakamalapit mula sa kahit anong komite.', 1, 60],
    'reroute_ask_minutes'        => ['Minutes a Kagawad has to pick a tanod (other cases)', 'Minutong may ang Kagawad para pumili ng tanod (ibang kaso)', 'The same, for a case that is not urgent.', 'Ganoon din, para sa kasong hindi apurahan.', 1, 120],
    // 0158: how long the records with no other limit are kept (docs/PRIVACY_INVENTORY.md); the audit trail is always kept
    'keep_otp_days'              => ['Days to keep SMS reset codes', 'Araw na itatago ang SMS reset code', 'Hashed codes; the team proposed 30.', 'Naka-hash na code; 30 ang mungkahi ng team.', 1, 90],
    'keep_attendance_days'       => ['Days to keep tanod attendance', 'Araw na itatago ang attendance ng tanod', 'Older duty logs are deleted every night.', 'Binubura gabi-gabi ang mas lumang duty log.', 30, 3650],
    'keep_punch_days'            => ['Days to keep the punch card', 'Araw na itatago ang punch card', 'Sign-ins and sign-outs of Kagawads and staff.', 'Pag-sign in at pag-sign out ng mga Kagawad at kawani.', 30, 3650],
    'keep_inbox_days'            => ['Days to keep Inbox messages', 'Araw na itatago ang mga mensahe sa Inbox', 'Older messages are deleted every night.', 'Binubura gabi-gabi ang mas lumang mensahe.', 30, 3650],
    'keep_workspace_days'        => ['Days to keep Workspace check-ins', 'Araw na itatago ang check-in sa Workspace', 'Shift check-ins and removed team posts.', 'Mga shift check-in at inalis na post ng team.', 30, 3650],
    'max_reports_per_day'        => ['Reports one resident may file a day', 'Ulat ng isang residente bawat araw', 'Stops flooding; real reports rarely come close.', 'Pumipigil sa pagbaha ng ulat; bihirang maabot ng totoong ulat.', 1, 200],
];

// The limits, in the groups a super admin thinks in (every column of RULE_LIMITS shows; one not listed here goes in a last group).
const RULE_GROUPS = [
    ['Dispatch', 'Pagpapadala', ['max_active_dispatches', 'location_freshness_minutes', 'awaiting_alert_hours', 'max_deadline_extensions']],
    ['When a Kagawad has to pick a tanod', 'Kapag pipili ang Kagawad ng tanod', ['reroute_ask_urgent_minutes', 'reroute_ask_minutes']],
    ['Reports', 'Mga ulat', ['max_report_photos', 'max_reports_per_day']],
    ['How long records are kept', 'Gaano katagal itinatago ang mga talaan', ['keep_otp_days', 'keep_attendance_days', 'keep_punch_days', 'keep_inbox_days', 'keep_workspace_days']],
];

// Wording (0149): the barangay's own words for a label, or the code's own back.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['action'] ?? '') === 'wording_save') {
    session_start_once();
    $wq = trim((string) ($_POST['wq'] ?? ''));
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            $src = (string) ($_POST['source'] ?? '');
            $en = trim((string) ($_POST['en'] ?? '')); $fil = trim((string) ($_POST['fil'] ?? ''));
            $code = wording_catalog()[$src] ?? null;
            if ($code === null) throw new SupabaseError(t('That label is not in the portal or the app.', 'Wala sa portal o sa app ang label na iyan.'));
            // the same as the code's own is no change at all
            $en = $en === '' || $en === $code['en'] ? null : mb_substr($en, 0, 600);
            $fil = $fil === '' || $fil === $code['fil'] ? null : mb_substr($fil, 0, 600);
            if (!empty($_POST['reset']) || ($en === null && $fil === null)) {
                $db->delete('wording', ['source' => 'eq.' . $src]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('The label is back to its own wording.', 'Ibinalik ang label sa sarili nitong salita.')];
            } else {
                $db->upsert('wording', ['source' => $src, 'en' => $en, 'fil' => $fil, 'updated_by' => current_admin()['id'] ?? null, 'updated_at' => gmdate('c')], 'source');
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Saved. The portal shows it now; the app, the next time it opens with signal.', 'Nai-save. Makikita na ito sa portal; sa app, sa susunod na pagbukas nito na may signal.')];
            }
            wording_forget();
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: ' . st_url('wording', '?wq=' . rawurlencode($wq)));
    exit;
}

/** Every label of the portal and the app (generated by .github/scripts/wording-catalog.php): English => [en, fil, in]. */
function wording_catalog(): array
{
    static $memo = null;
    if ($memo !== null) return $memo;
    $memo = [];
    foreach ((array) json_decode((string) @file_get_contents(__DIR__ . '/includes/wording_catalog.json'), true) as $e) {
        if (isset($e['en'])) $memo[(string) $e['en']] = $e;
    }
    return $memo;
}

// The barangay (0148): its name, place and seal, shown on the sign-in pages, the portal's title and every printed document.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['action'] ?? '') === 'brgy_save') {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            $name = trim((string) ($_POST['name'] ?? '')); $place = trim((string) ($_POST['place'] ?? ''));
            if (mb_strlen($name) < 3 || mb_strlen($place) < 3) throw new SupabaseError(t('Type the barangay\'s name and its place.', 'I-type ang pangalan ng barangay at ang lugar nito.'));
            $patch = ['name' => mb_substr($name, 0, 80), 'place' => mb_substr($place, 0, 120), 'updated_by' => current_admin()['id'] ?? null, 'updated_at' => gmdate('c')];
            if (!empty($_POST['seal_shipped'])) {
                $patch['seal_url'] = null;
            } elseif ($pic = cloudinary_upload_files('seal', 1, 'barangay')) {
                $patch['seal_url'] = $pic[0]['media_url'];
            }
            $db->update('barangay_profile', ['id' => 'eq.1'], $patch);
            barangay_forget();
            $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Saved. The sign-in pages, the title and new printouts show it now; the app shows the name the next time it opens with signal.', 'Nai-save. Makikita na ito sa sign-in, sa pamagat at sa mga bagong printout; makikita ng app ang pangalan sa susunod na pagbukas nito na may signal.')];
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: ' . st_url('brgy'));
    exit;
}

// Rules (0147): the limits above, pausing new reports, and the deadlines of each category.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['action'] ?? '') === 'rules_save') {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            $patch = ['updated_at' => gmdate('c'), 'updated_by' => current_admin()['id'] ?? null,
                      'filing_paused' => !empty($_POST['filing_paused']), 'filing_paused_message' => trim((string) ($_POST['filing_paused_message'] ?? '')) ?: null];
            foreach (RULE_LIMITS as $col => [, , , , $lo, $hi]) {
                $patch[$col] = max($lo, min($hi, (int) ($_POST['lim'][$col] ?? $lo)));
            }
            $db->update('operational_settings', ['id' => 'eq.1'], $patch);
            foreach ((array) ($_POST['sla'] ?? []) as $cat => $v) {
                if (!isset(categories_all()[$cat])) continue;
                $db->upsert('sla_policies', ['category' => $cat, 'resolution_hours' => max(1, min(720, (int) ($v['hours'] ?? 72))),
                    'accept_minutes' => max(1, min(240, (int) ($v['accept'] ?? 30))), 'updated_at' => gmdate('c')], 'category');
            }
            $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Rules saved. New reports follow them from now on.', 'Nai-save ang mga patakaran. Susundin ito ng mga bagong ulat mula ngayon.')];
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: ' . st_url('rules'));
    exit;
}

// Hotlines (0025's tables, edited here since 0147): a group of numbers, or a number in a group.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['hl_group', 'hl_number'], true)) {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            $p = static fn (string $k): string => trim((string) ($_POST[$k] ?? ''));
            $id = preg_match('/^[0-9a-f-]{36}$/', $p('id')) ? $p('id') : null;
            $now = gmdate('c');
            if ($_POST['action'] === 'hl_group') {
                $row = ['name' => mb_substr($p('name'), 0, 120), 'display' => $p('display') === 'link' ? 'link' : 'inline', 'updated_at' => $now];
                if ($row['name'] === '') throw new SupabaseError(t('Name the group.', 'Pangalanan ang grupo.'));
                if ($id) {
                    $db->update('hotline_groups', ['id' => 'eq.' . $id], $row + ['is_active' => !empty($_POST['active'])]);
                } else {
                    $parent = preg_match('/^[0-9a-f-]{36}$/', $p('parent')) ? $p('parent') : null;
                    $db->insert('hotline_groups', $row + ['parent_id' => $parent, 'sort_order' => (int) $p('sort')]);
                }
            } else {
                $row = ['label' => mb_substr($p('label'), 0, 120) ?: null, 'number' => mb_substr($p('number'), 0, 32), 'carrier' => mb_substr($p('carrier'), 0, 20) ?: null, 'updated_at' => $now];
                if (mb_strlen($row['number']) < 3) throw new SupabaseError(t('Type the number.', 'I-type ang numero.'));
                if ($id) {
                    $db->update('hotline_numbers', ['id' => 'eq.' . $id], $row + ['is_active' => !empty($_POST['active'])]);
                } elseif (preg_match('/^[0-9a-f-]{36}$/', $p('group'))) {
                    $db->insert('hotline_numbers', $row + ['group_id' => $p('group'), 'sort_order' => (int) $p('sort')]);
                }
            }
            $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Hotlines saved. Phones get them the next time the Emergency screen opens with signal.', 'Nai-save ang mga hotline. Makukuha ito ng mga telepono sa susunod na pagbukas ng Emergency screen na may signal.')];
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: ' . st_url('hotlines'));
    exit;
}

// Complaint types (0146): the categories and the options residents pick from.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['cat_save', 'opt_save'], true)) {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            $p = static fn (string $k): string => trim((string) ($_POST[$k] ?? ''));
            if ($_POST['action'] === 'cat_save') {
                $isNew = $p('key') === '';
                $madeKey = $db->rpc('category_save', ['p_key' => $p('key') ?: null, 'p_label_en' => $p('label_en'), 'p_label_fil' => $p('label_fil') ?: null,
                    'p_colour' => preg_match('/^#[0-9a-fA-F]{6}$/', $p('colour')) ? $p('colour') : null, 'p_icon' => preg_match('/^[a-z_]+$/', $p('icon')) ? $p('icon') : null,
                    'p_active' => $isNew ? true : !empty($_POST['active']), 'p_sort' => null]);
                if ($isNew && $madeKey) $db->rpc('catalogue_fill');
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => $isNew
                    ? t('Category made. Residents can pick it once the app refreshes its list.', 'Nagawa ang kategorya. Mapipili ito ng mga residente kapag na-refresh ng app ang listahan.')
                    : t('Category saved.', 'Nai-save ang kategorya.')];
            } else {
                $isNew = $p('id') === '';
                $db->rpc('option_save', ['p_id' => $isNew ? null : (int) $p('id'), 'p_category' => $p('category'), 'p_label_en' => $p('label_en'),
                    'p_label_fil' => $p('label_fil') ?: null, 'p_active' => $isNew ? true : !empty($_POST['active']), 'p_sort' => null]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => $isNew ? t('Option added.', 'Naidagdag ang opsyon.') : t('Option saved.', 'Nai-save ang opsyon.')];
            }
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: ' . st_url('types'));
    exit;
}

// Access (0145): an administrator's tier, committee and developer mark; the committees and what each sees; the feature switches.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['set_access', 'committee_save', 'feature_toggle', 'super_colour'], true)) {
    session_start_once();
    $back = 'access';
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            if ($_POST['action'] === 'set_access') {
                $back = 'admins';
                $tier = (string) ($_POST['tier'] ?? '');
                $db->rpc('set_admin_access', ['p_user' => (string) ($_POST['user'] ?? ''), 'p_tier' => $tier,
                    'p_committee' => in_array($tier, ['committee', 'moderator'], true) ? ((string) ($_POST['committee'] ?? '') ?: null) : null, 'p_dev' => !empty($_POST['dev'])]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Access saved. It applies on their next page.', 'Nai-save ang access. Magkakabisa sa susunod nilang pahina.')];
            } elseif ($_POST['action'] === 'committee_save') {
                $key = (string) ($_POST['key'] ?? '');
                $saved = $db->rpc('committee_save', ['p_key' => $key ?: null, 'p_name_en' => trim((string) ($_POST['name_en'] ?? '')),
                    'p_name_fil' => trim((string) ($_POST['name_fil'] ?? '')) ?: null, 'p_active' => $key === '' ? true : !empty($_POST['active']),
                    'p_short' => trim((string) ($_POST['short_en'] ?? '')) ?: null,
                    'p_colour' => preg_match('/^#[0-9a-fA-F]{6}$/', (string) ($_POST['colour'] ?? '')) ? strtoupper((string) $_POST['colour']) : null]);
                $cats = array_values(array_filter((array) ($_POST['cats'] ?? []), fn ($c) => isset(category_pairs()[$c])));
                if (is_string($saved) && ($key !== '' || $cats)) {
                    $db->rpc('committee_set_categories', ['p_key' => $saved, 'p_categories' => '{' . implode(',', $cats) . '}']);
                }
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => $key === '' ? t('Committee made.', 'Nagawa ang komite.') : t('Committee saved.', 'Nai-save ang komite.')];
            } elseif ($_POST['action'] === 'super_colour') {
                // 0150: the one colour of every super admin; the database refuses one near an active committee's
                $hex = preg_match('/^#[0-9a-fA-F]{6}$/', (string) ($_POST['colour'] ?? '')) ? strtoupper((string) $_POST['colour']) : SUPER_BLUE;
                $db->update('barangay_profile', ['id' => 'eq.1'], ['super_colour' => $hex, 'updated_by' => current_admin()['id'] ?? null, 'updated_at' => gmdate('c')]);
                barangay_forget();
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Super admin colour saved. Every super admin\'s sidebar wears it from their next page.', 'Nai-save ang kulay ng super admin. Suot ito ng sidebar ng bawat super admin mula sa susunod nilang pahina.')];
            } else {
                $back = 'parts';
                $db->rpc('feature_set', ['p_key' => (string) ($_POST['key'] ?? ''), 'p_on' => !empty($_POST['on'])]);
                feature_forget();
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Saved. It applies to everyone now.', 'Nai-save. May bisa na sa lahat ngayon.')];
            }
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: ' . st_url($back));
    exit;
}

// App updates (0161): a super admin publishes a version for the self-updater, or withdraws one.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['release_publish', 'release_active'], true)) {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            if ($_POST['action'] === 'release_publish') {
                $db->rpc('app_release_publish', ['p_version' => trim((string) ($_POST['version'] ?? '')), 'p_build' => (int) ($_POST['build'] ?? 0), 'p_url' => trim((string) ($_POST['apk_url'] ?? '')),
                    'p_sha256' => trim((string) ($_POST['sha256'] ?? '')), 'p_notes_en' => trim((string) ($_POST['notes_en'] ?? '')) ?: null, 'p_notes_fil' => trim((string) ($_POST['notes_fil'] ?? '')) ?: null,
                    'p_mandatory' => !empty($_POST['mandatory'])]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Published. Phones are offered it the next time the app opens.', 'Nailathala. Iaalok ito sa mga telepono sa susunod na pagbukas ng app.')];
            } else {
                $db->rpc('app_release_set_active', ['p_id' => (string) ($_POST['id'] ?? ''), 'p_on' => !empty($_POST['on'])]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Saved.', 'Nai-save.')];
            }
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: ' . st_url('updates'));
    exit;
}

// The command center (0143): SMART may switch a mode on by itself, and the hall display's links.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['cmd_auto', 'cmd_link', 'cmd_unlink'], true)) {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            if ($_POST['action'] === 'cmd_auto') {
                $db->rpc('command_set_auto', ['p_on' => !empty($_POST['on'])]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => !empty($_POST['on'])
                    ? t('SMART may now switch a mode on by itself. The administrators are told each time.', 'Maaari nang mag-on ng mode ang SMART nang mag-isa. Sinasabihan ang mga administrator sa bawat pagkakataon.')
                    : t('SMART will only suggest a mode.', 'Magmumungkahi na lamang ng mode ang SMART.')];
            } elseif ($_POST['action'] === 'cmd_link') {
                $tok = $db->rpc('command_display_link_create', ['p_label' => trim((string) ($_POST['label'] ?? ''))]);
                if (is_string($tok) && preg_match('/^[0-9a-f]{48}$/', $tok)) {
                    $_SESSION['cmd_link'] = portal_url('hall.php?k=' . $tok);   // shown once, below
                }
            } else {
                $db->rpc('command_display_link_revoke', ['p_id' => (string) ($_POST['id'] ?? '')]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('That display link no longer works.', 'Hindi na gumagana ang display link na iyon.')];
            }
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: ' . st_url('smart'));
    exit;
}

// Planning (0142): a recurring problem becomes a work order for the council; a work order moves open -> planned -> done.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['wo_create', 'wo_set'], true)) {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            if ($_POST['action'] === 'wo_create') {
                $db->rpc('smart_workorder_create', ['p_pattern_key' => (string) ($_POST['pattern'] ?? ''), 'p_title' => trim((string) ($_POST['title'] ?? '')),
                    'p_note' => trim((string) ($_POST['note'] ?? '')) ?: null]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Work order opened.', 'Nabuksan ang work order.')];
            } else {
                $db->rpc('smart_workorder_set', ['p_id' => (string) ($_POST['id'] ?? ''), 'p_status' => (string) ($_POST['status'] ?? ''), 'p_note' => trim((string) ($_POST['note'] ?? '')) ?: null]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Saved.', 'Nai-save.')];
            }
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: ' . st_url('plan'));
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['smart_rules', 'smart_storm', 'smart_digest', 'smart_try', 'smart_rescore', 'smart_word', 'smart_rollback'], true)) {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            $act = (string) $_POST['action'];
            if ($act === 'smart_rules') {
                $pts = [];
                foreach (array_keys(category_pairs()) as $ck) { $pts[$ck] = max(0, min(60, (int) ($_POST['pts'][$ck] ?? 0))); }
                $changes = [
                    'category_points' => $pts,
                    'urgent_from'     => max(1, min(100, (int) ($_POST['urgent_from'] ?? 70))),
                    'high_from'       => max(1, min(100, (int) ($_POST['high_from'] ?? 45))),
                    'normal_from'     => max(1, min(100, (int) ($_POST['normal_from'] ?? 25))),
                ];
                if (($_POST['do'] ?? '') === 'replay') {
                    // 0141: what the change would do to the last 90 days of reports. Saves nothing.
                    $_SESSION['smart_replay'] = ['changes' => $changes, 'result' => $db->rpc('smart_replay', ['p_changes' => $changes, 'p_days' => 90, 'p_limit' => 1000])];
                    $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Nothing was saved. This is what the change would do.', 'Walang na-save. Ito ang magiging epekto ng pagbabago.')];
                    header('Location: ' . st_url('smart'));
                    exit;
                }
                $reason = trim((string) ($_POST['reason'] ?? ''));
                if ($reason === '') { throw new SupabaseError(t('Say why the rules are changing.', 'Sabihin kung bakit binabago ang mga patakaran.')); }
                $db->rpc('smart_save_rules', ['p_changes' => $changes, 'p_reason' => mb_substr($reason, 0, 300)]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('The rules were saved. Press "Re-score open reports" to apply them to cases already open.', 'Nai-save ang mga patakaran. Pindutin ang "Muling markahan ang mga bukas na ulat" para ilapat sa mga kasong bukas na.')];
            } elseif ($act === 'smart_storm') {
                $on = ($_POST['on'] ?? '') === '1';
                $db->rpc('smart_storm_mode', ['p_on' => $on, 'p_reason' => trim((string) ($_POST['reason'] ?? '')) ?: null, 'p_hours' => max(1, min(168, (int) ($_POST['hours'] ?? 24)))]);
                unset($_SESSION['ss_storm']);   // the banner on every page reads it fresh
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => $on ? t('Storm mode is on.', 'Naka-on ang storm mode.') : t('Storm mode is off.', 'Naka-off ang storm mode.')];
            } elseif ($act === 'smart_digest') {
                $db->update('smart_rules', ['id' => 'eq.1'], ['digest_enabled' => ($_POST['on'] ?? '') === '1']);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Saved.', 'Nai-save.')];
            } elseif ($act === 'smart_rollback') {
                $reason = trim((string) ($_POST['reason'] ?? ''));
                if ($reason === '') { throw new SupabaseError(t('Say why you are rolling back.', 'Sabihin kung bakit ibabalik.')); }
                $new = $db->rpc('smart_rollback', ['p_version' => (int) ($_POST['version'] ?? 0), 'p_reason' => mb_substr($reason, 0, 300)]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => sprintf(t('Rolled back. This is now version %d, and the open reports were re-scored.', 'Naibalik. Bersyon %d na ito ngayon, at muling minarkahan ang mga bukas na ulat.'), (int) $new)];
            } elseif ($act === 'smart_rescore') {
                $n = $db->rpc('smart_retriage', []);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => sprintf(t('%d open reports were re-scored.', '%d na bukas na ulat ang muling minarkahan.'), (int) $n)];
            } else {
                $cat = (string) ($_POST['category'] ?? '');
                $lat = trim((string) ($_POST['lat'] ?? '')); $lng = trim((string) ($_POST['lng'] ?? ''));
                $_SESSION['smart_try'] = $db->rpc('smart_preview', [
                    'p_category' => $cat, 'p_subject' => trim((string) ($_POST['subject'] ?? '')), 'p_description' => trim((string) ($_POST['description'] ?? '')),
                    'p_lat' => is_numeric($lat) ? (float) $lat : null, 'p_lng' => is_numeric($lng) ? (float) $lng : null]);
            }
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: ' . st_url('smart'));
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['add_admin', 'reset_admin'], true)) {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            // Rose (6 Oct 2026): nobody but the new admin sees a password.
            // The account is made with a random one nobody is shown, and
            // the admin's own email gets a link to choose theirs.
            $who = trim((string) ($_POST['email'] ?? ''));
            if ($_POST['action'] === 'add_admin') {
                $db->rpc('create_admin_account', [
                    'p_email'     => $who,
                    'p_full_name' => trim((string) ($_POST['last_name'] ?? '')) . ', ' . trim((string) ($_POST['first_name'] ?? '')),
                    'p_mobile'    => trim((string) ($_POST['mobile'] ?? '')),
                ]);
            }
            $secure = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
                   || strtolower((string) ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https';
            Supabase::recover($who, ($secure ? 'https://' : 'http://') . $_SERVER['HTTP_HOST']
                . dirname($_SERVER['SCRIPT_NAME']) . '/reset-password.php');
            $_SESSION['st_flash'] = ['level' => 'ok', 'who' => $who, 'new' => $_POST['action'] === 'add_admin'];
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: ' . st_url('admins'));
    exit;
}

// The plan each service is on. These are the free tiers the barangay
// started on; change them here if an account is upgraded.
const PLAN_TIERS = ['supabase' => 'Free', 'cloudinary' => 'Free', 'render' => 'Free'];

// Where each service runs, as looked up on 3 Oct 2026: Supabase from the
// project's settings (ap-south-1), the others from where their addresses
// answer. Render's region is set in its dashboard and not visible outside.
const SERVICE_PLACES = [
    'db'    => ['IN',  'Mumbai, India'],
    'auth'  => ['IN',  'Mumbai, India'],
    'live'  => ['IN',  'Mumbai, India'],
    'media' => ['CDN', 'Nearest Cloudflare edge'],
    'push'  => ['CDN', 'Nearest Google edge'],
    'tiles' => ['CDN', 'Nearest Cloudflare edge'],
    'geo'   => ['PH',  'Manila edge (Fastly)'],
    'rain'  => ['DE',  'Falkenstein, Germany'],
    'noah'  => ['—',   'With the portal (Render)'],
];

/** One timed HTTP request: any answer below 500 means the service is reachable. */
function probe(string $url, array $headers = [], string $method = 'GET'): array
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_NOBODY         => $method === 'HEAD',
        CURLOPT_CUSTOMREQUEST  => $method === 'HEAD' ? null : $method,
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_TIMEOUT        => 8,
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_FOLLOWLOCATION => false,
    ]);
    $t0 = microtime(true);
    curl_exec($ch);
    $ms   = (int) round((microtime(true) - $t0) * 1000);
    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    return ['ok' => $code > 0 && $code < 500, 'ms' => $code > 0 ? $ms : null, 'code' => $code];
}

if (($_GET['check'] ?? '') === 'server') {
    header('Content-Type: application/json');
    header('Cache-Control: no-store');
    $out = [];
    // Database: a real one-row read with this admin's session.
    $t0 = microtime(true);
    try { $db->select('reports', ['select' => 'id', 'limit' => '1']); $out['db'] = ['ok' => true, 'ms' => (int) round((microtime(true) - $t0) * 1000)]; }
    catch (Throwable $e) { $out['db'] = ['ok' => false, 'ms' => null]; }
    $key = ['apikey: ' . supabase_key()];
    $out['auth']  = probe(supabase_url() . '/auth/v1/health', $key);
    $out['push']  = probe(supabase_url() . '/functions/v1/send-dispatch-push', $key, 'OPTIONS');
    $cloud = env('CLOUDINARY_CLOUD_NAME', '');
    $out['media'] = $cloud !== '' ? probe('https://res.cloudinary.com/' . rawurlencode($cloud) . '/image/upload/v1/ping', [], 'HEAD') : ['ok' => false, 'ms' => null, 'unset' => true];
    $fcm = probe('https://fcm.googleapis.com/', [], 'HEAD');
    if ($out['push']['ok'] && !$fcm['ok']) { $out['push'] = ['ok' => false, 'ms' => null]; }
    echo json_encode($out);
    exit;
}

if (($_GET['usage'] ?? '') === '1') {
    header('Content-Type: application/json');
    header('Cache-Control: no-store');
    $tz    = new DateTimeZone('Asia/Manila');
    $month = (new DateTimeImmutable('first day of this month', $tz))->setTime(0, 0)->format(DateTimeInterface::ATOM);
    $out = ['plans' => PLAN_TIERS];
    try { $out['supabase'] = $db->rpc('system_usage'); } catch (Throwable $e) { $out['supabase'] = null; }
    try {
        $media = $db->select('report_media', ['select' => 'bytes', 'limit' => '20000']);
        $out['photos'] = ['files' => count($media), 'bytes' => array_sum(array_map(fn($m) => (int) $m['bytes'], $media))];
    } catch (Throwable $e) { $out['photos'] = null; }
    try { $out['alerts'] = $db->count('dispatches', ['assigned_at' => 'gte.' . $month]); } catch (Throwable $e) { $out['alerts'] = null; }
    // Cloudinary's own usage figures, only when its API key and secret are set.
    $cloud = env('CLOUDINARY_CLOUD_NAME', ''); $ck = env('CLOUDINARY_API_KEY', ''); $cs = env('CLOUDINARY_API_SECRET', '');
    $out['cloudinary'] = null;
    if ($cloud !== '' && $ck !== '' && $cs !== '') {
        $ch = curl_init('https://api.cloudinary.com/v1_1/' . rawurlencode($cloud) . '/usage');
        curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_USERPWD => $ck . ':' . $cs, CURLOPT_TIMEOUT => 8]);
        $body = curl_exec($ch); $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE); curl_close($ch);
        if ($code === 200 && ($u = json_decode((string) $body, true))) {
            $out['cloudinary'] = ['plan' => $u['plan'] ?? null, 'credits_used' => $u['credits']['usage'] ?? null, 'credits_limit' => $u['credits']['limit'] ?? null,
                                  'storage' => $u['storage']['usage'] ?? null, 'bandwidth' => $u['bandwidth']['usage'] ?? null];
        }
    }
    echo json_encode($out);
    exit;
}

// The barangay's own places (0134): what search finds that no map has, by the names residents and tanods use.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['place_save', 'place_remove'], true)) {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            if ($_POST['action'] === 'place_remove') {
                $db->rpc('place_remove', ['p_id' => (int) ($_POST['id'] ?? 0)]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Removed. Search no longer finds it.', 'Inalis. Hindi na ito mahahanap.')];
            } else {
                $aliases = array_values(array_filter(array_map('trim', explode(',', (string) ($_POST['aliases'] ?? ''))), fn ($a) => $a !== ''));
                $db->rpc('place_save', ['p_id' => (int) ($_POST['id'] ?? 0) ?: null, 'p_name' => trim((string) ($_POST['name'] ?? '')),
                    'p_grp' => (string) ($_POST['grp'] ?? ''), 'p_lat' => (float) ($_POST['lat'] ?? 0), 'p_lng' => (float) ($_POST['lng'] ?? 0),
                    'p_aliases' => array_slice($aliases, 0, 8)]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Saved. Search finds it now.', 'Na-save. Mahahanap na ito.')];
            }
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: ' . st_url('places'));
    exit;
}
$places = []; $kinds = [];
try {
    $got = $db->selectMany([
        'places' => ['places', ['select' => 'id,name,grp,aliases,lat,lng', 'source' => 'eq.barangay', 'active' => 'eq.true', 'order' => 'name.asc', 'limit' => '200'], true],
        'kinds'  => ['place_kinds', ['select' => 'grp,label', 'order' => 'label.asc'], true],
    ]);
    $places = is_array($got['places'] ?? null) ? $got['places'] : [];
    $kinds  = is_array($got['kinds'] ?? null) ? $got['kinds'] : [];
} catch (SupabaseError $ex) { /* the card says so below */ }

$stTitle = ['settings' => t('Settings', 'Mga Setting'), 'admin' => t('Administrative Services', 'Mga Serbisyong Pang-admin'),
            'control' => t('Control Room', 'Silid-Kontrol')][$stPage];
layout_head($stTitle, ST_PAGES[$stPage]['file']);
?>
<div class="p-topbar"><h1><?= e($stTitle) ?></h1><?php if (st_on('status')): ?><span class="p-updated" id="st-checked"></span><span style="flex:1"></span>
  <button class="p-btn p-btn-primary p-btn-sm" id="st-check" type="button"><?= e(t('Check again', 'Suriin muli')) ?></button><?php endif; ?></div>

<?php
$stLabels = ['status' => t('System status', 'Kalagayan ng sistema'), 'usage' => t('Plan and usage', 'Plano at paggamit'), 'smart' => 'SMART',
    'look' => t('Appearance', 'Itsura'), 'access' => t('Committees', 'Mga komite'), 'admins' => t('Administrators', 'Mga Administrator'), 'ladder' => t('Escalation and responders', 'Eskalasyon at mga responder'),
    'plan' => t('Planning', 'Pagpaplano'), 'types' => t('Complaint types', 'Mga uri ng reklamo'), 'rules' => t('Rules', 'Mga patakaran'),
    'hotlines' => t('Hotlines', 'Mga hotline'), 'wording' => t('Wording', 'Mga salita'), 'brgy' => t('The barangay', 'Ang barangay'),
    'parts' => t('Parts of the system', 'Mga bahagi ng sistema'), 'updates' => t('App updates', 'Mga update ng app')];
?>
<div class="p-seg-mini st-tabs" role="tablist" aria-label="<?= e(sprintf(t('%s sections', 'Mga bahagi ng %s'), $stTitle)) ?>">
  <?php foreach (ST_PAGES[$stPage]['tabs'] as $k => $tb): ?>
    <button type="button" class="<?= $k === 0 ? 'p-on' : '' ?>" role="tab" data-st="<?= e($tb) ?>"><?= e($stLabels[$tb]) ?></button>
    <?php if ($tb === 'admins'): ?><a class="st-link" role="tab" aria-selected="false" href="retirement-requests.php"><?= e(t('Retirement requests', 'Mga kahilingang magretiro')) ?></a><?php endif; ?>
  <?php endforeach; ?>
</div>

<?php if ($stPage === 'control'): ?><div class="ed-wrap" id="ed-wrap" data-screen="report" data-map="<?= e(json_encode(APP_EDITOR_SCREENS)) ?>"><div class="ed-main"><?php endif; ?>

<?php
// Rose (5 Oct 2026): every administrator, and whether they still hold a
// temporary password. Adding one from here comes with the account service.
$stFlash = $_SESSION['st_flash'] ?? null;
unset($_SESSION['st_flash']);
$admins = [];
try {
    $admins = $db->select('users', [
        'select' => 'id,full_name,email,must_change_password,is_suspended,created_at,official_role,committee,admin_tier,is_dev',
        'role'   => 'eq.admin',
        'order'  => 'created_at.asc',
    ]);
    $tanods  = $db->select('users', ['select' => 'id,full_name,women_responder', 'role' => 'eq.tanod', 'is_suspended' => 'is.false', 'order' => 'full_name.asc']);
    $cmap    = $db->select('committee_for_category', ['select' => 'category,committee', 'order' => 'category.asc']);
} catch (SupabaseError $e) { $admins = []; $tanods = []; $cmap = []; }
?>
<?php if (st_on('admins')): ?>
<section class="st-pane" data-pane="admins" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'ok'): ?>
    <div class="p-flash p-flash--ok" role="status">
      <?= e(!empty($stFlash['new']) ? t('Account created. A link to set a password was emailed to', 'Nagawa ang account. Naipadala ang link para magtakda ng password sa') : t('A link to set a new password was emailed to', 'Naipadala ang link para magtakda ng bagong password sa')) ?>
      <b><?= e($stFlash['who']) ?></b>. <?= e(t('Only they can see it.', 'Sila lang ang makakakita nito.')) ?>
    </div>
  <?php elseif ($stFlash && $stFlash['level'] === 'info'): ?>
    <div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash): ?>
    <div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div>
  <?php endif; ?>
  <?php $roleOpts = ['' => t('Staff', 'Kawani'), 'secretary' => t('Secretary', 'Kalihim'), 'kagawad' => t('Councilor (Kagawad)', 'Kagawad'), 'chairman' => t('Chairman', 'Punong Barangay')]; ?>
  <div class="p-band ss-pband">
    <h2><?= e(t('Administrators', 'Mga Administrator')) ?><span class="p-badge-n p-badge-n--quiet" id="jp-count"><?= count($admins) ?></span></h2>
    <form class="p-search" role="search">
      <?= p_icon('i-search', 16) ?><label class="p-sr" for="jp-q"><?= e(t('Search for names', 'Hanapin ang pangalan')) ?></label>
      <input type="search" id="jp-q" placeholder="<?= e(t('Search for names', 'Hanapin ang pangalan')) ?>" autocomplete="off">
    </form>
    <span class="p-spacer"></span>
    <label class="p-pill-select" hidden><span class="p-lbl"><?= e(t('Position', 'Posisyon')) ?></span>
      <select id="jp-role" aria-label="<?= e(t('Position', 'Posisyon')) ?>"><option value=""><?= e(t('All', 'Lahat')) ?></option>
        <?php foreach ($roleOpts as $rv => $rl): ?><option value="<?= $rv === '' ? 'staff' : e($rv) ?>"><?= e($rl) ?></option><?php endforeach; ?>
      </select></label>
    <button type="button" class="jp-add" id="jp-add" aria-controls="jp-addcard" aria-expanded="false"><?= e(t('Add administrator', 'Magdagdag ng administrator')) ?></button>
  </div>
  <?php
  $rkN = ['' => count($admins)]; foreach ($admins as $x0) { $k0 = ($x0['official_role'] ?? '') === '' ? 'staff' : (string) $x0['official_role']; $rkN[$k0] = ($rkN[$k0] ?? 0) + 1; }
  $rkDef = ['' => [t('All', 'Lahat'), '#2D5BFF', '#00A3FF', '#FFFFFF', 'layers'], 'chairman' => [t('Chairman', 'Punong Barangay'), '#E5383B', '#FF6A3D', '#FFFFFF', 'focus'],
            'kagawad' => [t('Councilor', 'Kagawad'), '#7A5AE0', '#B15CFF', '#FFFFFF', 'handler'], 'secretary' => [t('Secretary', 'Kalihim'), '#0097B8', '#35D0E8', '#FFFFFF', 'calendar'],
            'staff' => [t('Staff', 'Kawani'), '#6C7A9C', '#9AA6C4', '#FFFFFF', 'copy']]; ?>
  <nav class="cm-chips ad-roles" aria-label="<?= e(t('Position', 'Posisyon')) ?>">
    <?php foreach ($rkDef as $rk => [$rl, $c1, $c2, $ink, $ic]): ?>
      <a class="cm-chip cm-sd<?= $rk === '' ? ' p-on' : '' ?>" href="#" data-role="<?= e($rk) ?>" style="--cc:<?= e($c1) ?>;--ct:<?= e($ink) ?>;--g1:<?= e($c1) ?>;--g2:<?= e($c2) ?>;--g3:<?= e($c2) ?>" title="<?= e($rl) ?>"><i class="cm-sym"><svg class="cm-ic" data-ic="<?= e($ic) ?>" viewBox="0 0 24 24" aria-hidden="true"></svg></i><span class="cm-n"><?= e($rl) ?></span><b><?= (int) ($rkN[$rk] ?? 0) ?></b></a>
    <?php endforeach; ?>
  </nav>
  <script>
  (function () {   // a position banner filters the table the way the position menu did
    var sel = document.getElementById('jp-role'), chips = [].slice.call(document.querySelectorAll('.ad-roles .cm-chip')); if (!sel) return;
    chips.forEach(function (c) { c.addEventListener('click', function (e) { e.preventDefault(); sel.value = c.dataset.role; sel.dispatchEvent(new Event('change', { bubbles: true })); chips.forEach(function (x) { x.classList.toggle('p-on', x === c); x.toggleAttribute('aria-current', x === c); }); }); });
  })();
  </script>
  <div class="p-card p-table-card jp-scope ss-people ss-adm" id="ss-people"><div class="p-tscroll">
    <table class="p-t ss-ohead">
    <thead><tr>
      <th scope="col"><?= e(t('Administrator', 'Tagapangasiwa')) ?></th>
      <th scope="col"><?= e(t('Position', 'Posisyon')) ?></th>
      <th scope="col"><?= e(t('Committee', 'Komite')) ?></th>
      <th scope="col"><?= e(t('Status', 'Katayuan')) ?></th>
      <th scope="col"><?= e(t('Access', 'Pahintulot')) ?></th>
      <th scope="col"><?= e(t('Online now', 'Online ngayon')) ?></th>
      <th scope="col" class="p-right"><span class="p-sr"><?= e(t('Actions', 'Mga aksyon')) ?></span></th>
    </tr></thead>
    <tbody id="jp-rows">
    <?php foreach ($admins as $a): $isK = ($a['official_role'] ?? '') === 'kagawad'; $hasC = in_array($a['official_role'] ?? '', ['kagawad', 'secretary'], true); $me = $a['id'] === $admin['id']; ?>
      <tr class="ss-arow" data-id="<?= e($a['id']) ?>" data-name="<?= e(strtolower(($a['full_name'] ?? '') . ' ' . ($a['email'] ?? ''))) ?>" data-role="<?= e(($a['official_role'] ?? '') === '' ? 'staff' : (string) $a['official_role']) ?>">
        <td><div class="p-person"><?= admin_chip($a['id'], (string) $a['full_name'], 30) ?><span><?= e(formal_name($a['full_name'])) ?><?= $me ? ' <small>(' . e(t('you', 'ikaw')) . ')</small>' : '' ?><small class="ss-mail"><?= e((string) ($a['email'] ?? '')) ?></small></span></div></td>
        <td><?= rank_chip($a['official_role'] ?? null, null, false) ?></td>
        <td><?php if ($isK && !empty($a['committee'])): ?><span class="ss-comm"><span class="cdot" style="--cc:<?= e(committee_colour($a['committee'])) ?>" aria-hidden="true"></span><?= e(committee_labels()[$a['committee']][0] ?? '') ?></span><?php else: ?><span class="p-sub">&mdash;</span><?php endif; ?></td>
        <td><div class="p-badges"><?php if (!empty($a['is_suspended'])): ?><span class="p-badge p-b-denied"><?= e(t('Suspended', 'Suspendido')) ?></span><?php elseif (!empty($a['must_change_password'])): ?><span class="p-badge p-b-pending"><?= e(t('Must change password', 'Kailangang palitan ang password')) ?></span><?php else: ?><span class="p-badge p-b-done"><?= e(t('Active', 'Aktibo')) ?></span><?php endif; ?></div></td>
        <td><?php $tierA = $a['admin_tier'] ?? 'super'; ?><div class="p-badges"><span class="p-badge <?= $tierA === 'super' ? 'p-b-progress' : ($tierA === 'captain' ? 'p-b-grey' : 'p-b-done') ?>"><?= e(match ($tierA) { 'captain' => t('Captain, view only', 'Kapitan, tingin lamang'), 'committee' => t('Committee', 'Komite') . (!empty($a['committee']) ? ': ' . (committees_all()[$a['committee']]['short_en'] ?? $a['committee']) : ''), 'moderator' => t('Staff', 'Kawani') . (!empty($a['committee']) ? ': ' . (committees_all()[$a['committee']]['short_en'] ?? $a['committee']) : ''), default => t('Super admin', 'Pangunahing admin') }) ?></span><?php if (!empty($a['is_dev'])): ?><span class="p-badge p-b-violet">DEV</span><?php endif; ?></div></td>
        <td class="ss-online" data-admin="<?= e($a['id']) ?>"><span class="ss-dot"></span><?= e(t('Offline', 'Offline')) ?></td>
        <td class="p-right"><button type="button" class="p-btn p-btn-sm ss-edit-btn" data-edit="<?= e($a['id']) ?>" aria-expanded="false"><?= e(t('Edit', 'I-edit')) ?></button></td>
      </tr>
      <tr class="ss-erow" data-for="<?= e($a['id']) ?>" hidden>
        <td colspan="7">
          <div class="ss-epanel">
            <form method="post" class="ss-eform">
              <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
              <input type="hidden" name="action" value="set_role">
              <input type="hidden" name="user" value="<?= e($a['id']) ?>">
              <div class="ss-ef"><span class="ss-efl"><?= e(t('Position', 'Posisyon')) ?></span><label class="p-pill-select ss-ps"><span class="p-sr"><?= e(t('Position', 'Posisyon')) ?></span><select name="official_role" data-role-sel>
                  <?php foreach ($roleOpts as $rv => $rl): ?><option value="<?= e($rv) ?>" <?= ($a['official_role'] ?? '') === $rv ? 'selected' : '' ?>><?= e($rl) ?></option><?php endforeach; ?>
                </select></label></div>
              <div class="ss-ef"><span class="ss-efl"><?= e(t('Committee', 'Komite')) ?></span><label class="p-pill-select ss-ps"><span class="p-sr"><?= e(t('Committee', 'Komite')) ?></span><select name="committee" data-comm-sel <?= $hasC ? '' : 'disabled' ?>>
                  <option value=""><?= e(t('No committee', 'Walang komite')) ?></option>
                  <?php foreach (committees_active() as $cv => $cl): ?><option value="<?= e($cv) ?>" <?= ($a['committee'] ?? '') === $cv ? 'selected' : '' ?>><?= e($cl) ?></option><?php endforeach; ?>
                </select></label></div>
              <button class="p-btn p-btn-sm ss-save" type="submit"><?= e(t('Save', 'I-save')) ?></button>
              <button class="p-btn p-btn-ghost p-btn-sm" type="button" data-edit="<?= e($a['id']) ?>"><?= e(t('Cancel', 'Kanselahin')) ?></button>
              <span class="ss-ehint" data-hint hidden><?= e(t('A Kagawad or a secretary needs a committee.', 'Kailangan ng komite ang Kagawad o ang kalihim.')) ?></span>
            </form>
            <form method="post" class="ss-eform ss-access">
              <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
              <input type="hidden" name="action" value="set_access">
              <input type="hidden" name="user" value="<?= e($a['id']) ?>">
              <div class="ss-ef"><span class="ss-efl"><?= e(t('Access', 'Pahintulot')) ?></span><label class="p-pill-select ss-ps"><span class="p-sr"><?= e(t('Access', 'Pahintulot')) ?></span><select name="tier">
                  <?php foreach (['super' => t('Super admin: everything', 'Super admin: lahat'), 'committee' => t('Kagawad: its committee', 'Kagawad: ang komite nito'), 'moderator' => t('Staff: works its committee\'s cases', 'Kawani: gumagawa sa mga kaso ng komite nito'), 'captain' => t('Captain: sees all, changes nothing', 'Kapitan: nakikita lahat, walang binabago')] as $tv => $tl): ?><option value="<?= e($tv) ?>" <?= ($a['admin_tier'] ?? 'super') === $tv ? 'selected' : '' ?>><?= e($tl) ?></option><?php endforeach; ?>
                </select></label></div>
              <div class="ss-ef"><span class="ss-efl"><?= e(t('Sees', 'Nakikita')) ?></span><label class="p-pill-select ss-ps"><span class="p-sr"><?= e(t('Committee whose categories it sees', 'Komiteng nakikita ang mga kategorya')) ?></span><select name="committee">
                  <option value=""><?= e(t('Choose a committee', 'Pumili ng komite')) ?></option>
                  <?php foreach (committees_active() as $cv => $cl): ?><option value="<?= e($cv) ?>" <?= ($a['committee'] ?? '') === $cv ? 'selected' : '' ?>><?= e($cl) ?></option><?php endforeach; ?>
                </select></label></div>
              <label class="sd-c"><input type="checkbox" name="dev" value="1" <?= !empty($a['is_dev']) ? 'checked' : '' ?>> <?= e(t('Developer (DEV)', 'Tagabuo (DEV)')) ?></label>
              <button class="p-btn p-btn-sm ss-save" type="submit"><?= e(t('Save access', 'I-save ang access')) ?></button>
            </form>
            <?php if (!$me): ?>
            <form method="post" class="ss-eform ss-ereset" data-captcha data-native-confirm="<?= e(t('Email this administrator a link to set a new password?', 'I-email sa administrator na ito ang link para magtakda ng bagong password?')) ?>">
              <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
              <input type="hidden" name="action" value="reset_admin">
              <input type="hidden" name="user" value="<?= e($a['id']) ?>">
              <input type="hidden" name="email" value="<?= e((string) ($a['email'] ?? '')) ?>">
              <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Email a password link', 'I-email ang link ng password')) ?></button>
            </form>
            <?php endif; ?>
          </div>
        </td>
      </tr>
    <?php endforeach; ?>
    <tr id="jp-none" hidden><td colspan="7" class="p-empty"><?= e(t('No administrator matches that.', 'Walang administrator na tugma.')) ?></td></tr>
    </tbody>
  </table></div></div>
  <div class="p-card p-card-pad ss-addadmin" id="jp-addcard" hidden>
    <p class="p-eyebrow"><?= e(t('Add an administrator', 'Magdagdag ng administrator')) ?></p>
    <p class="p-hint"><?= e(t('The new administrator gets an email with a link to choose their own password. Nobody else ever sees it. Use their real email address.', 'Makakatanggap ang bagong administrator ng email na may link para pumili ng sariling password. Walang ibang makakakita nito. Gamitin ang tunay nilang email.')) ?></p>
    <form method="post" class="ss-form" data-captcha data-native-confirm="<?= e(t('Add this administrator? They get an email to set their password.', 'Idagdag ang administrator na ito? Makakatanggap sila ng email para sa password.')) ?>">
      <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
      <input type="hidden" name="action" value="add_admin">
      <input class="p-input-plain" name="first_name" required maxlength="60" placeholder="<?= e(t('First name', 'Pangalan')) ?>" aria-label="<?= e(t('First name', 'Pangalan')) ?>">
      <input class="p-input-plain" name="last_name" required maxlength="60" placeholder="<?= e(t('Last name', 'Apelyido')) ?>" aria-label="<?= e(t('Last name', 'Apelyido')) ?>">
      <input class="p-input-plain" name="email" type="email" required maxlength="160" placeholder="<?= e(t('Email address', 'Email address')) ?>">
      <input class="p-input-plain" name="mobile" required pattern="09[0-9]{9}" placeholder="09XXXXXXXXX">
      <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Create account', 'Gumawa ng account')) ?></button>
    </form>
  </div>
</section>
<?php endif; ?>

<?php if (st_on('ladder')): ?>
<section class="st-pane" data-pane="ladder" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'info'): ?><div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash && $stFlash['level'] === 'error'): ?><div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div><?php endif; ?>
  <?php
  $chairs  = array_values(array_filter($admins, fn($x) => ($x['official_role'] ?? '') === 'chairman'));
  $nTanods = count($tanods);
  ?>
  <div class="p-band ss-pband ss-subband">
    <h2><?= e(t('Layered escalation', 'Patong-patong na eskalasyon')) ?><span class="p-badge-n p-badge-n--quiet">3</span></h2>
    <span class="p-spacer"></span>
    <span class="ss-subnote"><?= e(t('A case goes up one step at a time, and only when a person sends it. Nothing moves by itself.', 'Isang hakbang bawat pag-akyat ng kaso, at kapag may taong nagpadala lang. Walang kusang gumagalaw.')) ?></span>
  </div>
  <div class="ss-levels">
    <div class="ss-lvl" style="--lc:var(--rk-tanod)">
      <span class="ss-num">1</span>
      <div class="p-card ss-lbox">
        <h3><?= e(t('Tanod', 'Tanod')) ?><small><?= e(t('first on the case', 'unang hahawak')) ?></small></h3>
        <p><?= e(t('Whoever the barangay dispatches. They can escalate from the app, on site or from the job screen.', 'Sinumang ipadala ng barangay. Maaari silang mag-escalate mula sa app, sa lugar o sa job screen.')) ?></p>
        <span class="p-badge p-b-progress"><?= $nTanods ?> <?= e(t($nTanods === 1 ? 'active tanod' : 'active tanods', 'aktibong tanod')) ?></span>
      </div>
    </div>
    <div class="ss-lvl" style="--lc:var(--rk-kagawad)">
      <span class="ss-num">2</span>
      <div class="p-card p-table-card ss-lbox ss-lbox--tbl">
        <h3><?= e(t('Kagawad of the committee', 'Kagawad ng komite')) ?><small><?= e(t('when the Tanod escalates', 'kapag nag-escalate ang Tanod')) ?></small></h3>
        <p><?= e(t('Pick which committee takes each kind of complaint first. A Kagawad needs a committee.', 'Piliin kung aling komite ang unang hahawak sa bawat uri ng reklamo. Kailangan ng komite ang Kagawad.')) ?></p>
        <div class="p-tscroll jp-scope ss-people ss-adm ss-lst"><table class="p-t ss-ohead">
          <thead><tr><th scope="col"><?= e(t('Kind of complaint', 'Uri ng reklamo')) ?></th><th scope="col"><?= e(t('Committee that takes it first', 'Komiteng unang hahawak')) ?></th><th scope="col"><?= e(t('Kagawad on it now', 'Kagawad ngayon')) ?></th></tr></thead>
          <tbody>
          <?php foreach ($cmap as $m):
            $holders = array_values(array_filter($admins, fn($x) => ($x['official_role'] ?? '') === 'kagawad' && ($x['committee'] ?? '') === $m['committee'])); ?>
            <tr>
              <td><?php $lc = (string) (categories_all()[(string) $m['category']]['colour'] ?? '#78909C'); ?><span class="cmx-t cmx-t-ro ss-lname" style="--tc:<?= e($lc) ?>;--tk:<?= e(ink_on_bold([$lc])) ?>"><svg class="cm-ic cmx-ti" data-ic="<?= e(sd_icon_for((string) $m['category'], (array) (categories_all()[(string) $m['category']] ?? []))) ?>" viewBox="0 0 24 24" aria-hidden="true"></svg><span><?= e(category_label((string) $m['category'])) ?></span></span></td>
              <td>
                <form method="post" class="ss-inline">
                  <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
                  <input type="hidden" name="action" value="set_committee_map">
                  <input type="hidden" name="category" value="<?= e($m['category']) ?>">
                  <label class="p-pill-select ss-ps"><span class="p-sr"><?= e(category_label((string) $m['category'])) ?></span>
                    <select name="committee" data-autosubmit>
                      <?php foreach (committees_all() as $cv => $cc): if (empty($cc['active']) && $m['committee'] !== $cv) continue; ?><option value="<?= e($cv) ?>" <?= $m['committee'] === $cv ? 'selected' : '' ?>><?= e((string) $cc['short_en']) ?></option><?php endforeach; ?>
                    </select></label>
                </form>
              </td>
              <td><?php if ($holders): foreach ($holders as $h): ?><span class="ss-who ss-holder"><?= admin_chip($h['id'], (string) $h['full_name'], 24) ?><?= e(formal_name($h['full_name'])) ?></span> <?php endforeach; else: ?><span class="p-badge p-b-pending"><?= e(t('No Kagawad yet: goes to the Chairman', 'Wala pang Kagawad: sa Punong Barangay')) ?></span><?php endif; ?></td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table></div>
      </div>
    </div>
    <div class="ss-lvl" style="--lc:var(--rk-chair)">
      <span class="ss-num">3</span>
      <div class="p-card ss-lbox">
        <h3><?= e(t('Chairman', 'Punong Barangay')) ?><small><?= e(t('final step: when the Kagawad escalates', 'huling hakbang: kapag nag-escalate ang Kagawad')) ?></small></h3>
        <?php if ($chairs): foreach ($chairs as $c): ?><span class="ss-who ss-holder"><?= admin_chip($c['id'], (string) $c['full_name'], 28) ?><?= e(formal_name($c['full_name'])) ?></span><?php endforeach; else: ?>
          <span class="p-badge p-b-denied"><?= e(t('No Chairman yet', 'Wala pang Punong Barangay')) ?></span><?php endif; ?>
        <p class="p-sub"><?= e(t('There is one Chairman. Cases that need an outside office are sent from the case page.', 'Iisa ang Punong Barangay. Ang mga kasong kailangan ng labas na tanggapan ay ipinapadala mula sa pahina ng kaso.')) ?></p>
      </div>
    </div>
  </div>

  <nav class="cm-chips wr-banner" aria-label="<?= e(t('Women responders', 'Mga responder para sa kababaihan')) ?>">
    <a class="cm-chip cm-sd" tabindex="-1" style="--cc:#E5408A;--ct:#FFFFFF;--g1:#D81B72;--g2:#FF5FA8;--g3:#FF9CC8"><i class="cm-sym"><svg class="cm-ic" data-ic="handler" viewBox="0 0 24 24" aria-hidden="true"></svg></i><span class="cm-n"><?= e(t('Women responders', 'Mga responder para sa kababaihan')) ?><small class="pc-gn">· <?= e(t('specialized: women and children cases (the VAWC desk). Sensitive cases show them first when a tanod is chosen.', 'espesyalisado: mga kaso ng kababaihan at bata (VAWC desk). Una silang ipinapakita sa mga sensitibong kaso kapag pumipili ng tanod.')) ?></small></span><b id="wr-count"><?= count(array_filter($tanods, fn($x) => !empty($x['women_responder']))) ?></b></a>
  </nav>
  <div class="p-card p-table-card jp-scope ss-people ss-adm ss-lst"><div class="p-tscroll">
    <table class="p-t ss-ohead">
      <thead><tr><th scope="col"><?= e(t('Tanod', 'Tanod')) ?></th><th scope="col"><?= e(t('Role', 'Tungkulin')) ?></th><th scope="col"><?= e(t('Status', 'Katayuan')) ?></th></tr></thead>
      <tbody>
      <?php if (!$tanods): ?><tr><td colspan="3" class="p-empty"><?= e(t('No tanod accounts yet.', 'Wala pang account ng tanod.')) ?></td></tr><?php endif; ?>
      <?php foreach ($tanods as $tn): $on = !empty($tn['women_responder']); ?>
        <tr>
          <td><div class="p-person"><?= admin_chip($tn['id'], (string) $tn['full_name'], 30) ?><span><?= e(formal_name($tn['full_name'])) ?></span></div></td>
          <td>
            <form method="post" class="ss-inline">
              <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
              <input type="hidden" name="action" value="set_responder">
              <input type="hidden" name="user" value="<?= e($tn['id']) ?>">
              <label class="p-pill-select ss-ps"><span class="p-sr"><?= e(formal_name($tn['full_name'])) ?></span>
                <select name="on" data-autosubmit>
                  <option value="" <?= $on ? '' : 'selected' ?>><?= e(t('Tanod', 'Tanod')) ?></option>
                  <option value="1" <?= $on ? 'selected' : '' ?>><?= e(t('Women responder', 'Responder para sa kababaihan')) ?></option>
                </select></label>
            </form>
          </td>
          <td><?php if ($on): ?><span class="p-badge p-b-done"><?= e(t('Women responder', 'Responder para sa kababaihan')) ?></span><?php else: ?><span class="p-sub">&mdash;</span><?php endif; ?></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table></div></div>
</section>
<?php endif; ?>

<?php if (st_on('status')):
// 0096 (industry pass 5): the database pings the portal every 10 minutes
// and keeps score.
$up = null;
try { $up = $db->rpc('portal_uptime_summary'); } catch (SupabaseError) {}
$eng = null;   // the engine (0137): reads ID photos on the server
try { $eng = $db->rpc('engine_status'); } catch (SupabaseError) {}
// 0140: is SMART running, and how often was its advice taken and its fixes confirmed
$smh = $smp = $smf = null;
try { $smh = $db->rpc('smart_engine_health'); } catch (SupabaseError) {}
try { $smp = $db->rpc('smart_pick_stats', ['p_days' => 90]); } catch (SupabaseError) {}
try { $smf = $db->rpc('smart_fix_stats', ['p_days' => 90]); } catch (SupabaseError) {}
$errs = null;
try { $errs = $db->select('portal_errors', ['select' => 'source,page,message,count,last_seen', 'order' => 'last_seen.desc', 'limit' => '5']); } catch (SupabaseError) {}
// 0119: what the hourly health check found and has not seen clear yet.
$alerts = [];
try { $alerts = $db->select('system_alerts', ['select' => 'key,message,raised_at', 'cleared_at' => 'is.null', 'order' => 'raised_at.desc']); } catch (SupabaseError) {}
$upPct = fn(int $ok, int $n) => $n > 0 ? rtrim(rtrim(number_format($ok / $n * 100, 2), '0'), '.') . '%' : '—';
endif;
?>
<?php if (st_on('access')):
// ---------- Access (0145) ----------
$cmCats = [];
$switches = [];
try {
    $got = $db->selectMany([
        'cc' => ['committee_categories', ['select' => 'committee,category'], true],
        'fs' => ['feature_switches', ['select' => 'key,label_en,label_fil,enabled,note', 'order' => 'key.asc'], true],
    ]);
    foreach ((array) (($got['cc'] ?? null) instanceof SupabaseError ? [] : $got['cc']) as $r) { $cmCats[$r['committee']][] = $r['category']; }
    $switches = ($got['fs'] ?? null) instanceof SupabaseError ? [] : (array) $got['fs'];
} catch (SupabaseError) {}
endif;
?>
<?php if (st_on('access')): ?>
<section class="st-pane" data-pane="access" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'info'): ?><div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash && $stFlash['level'] === 'error'): ?><div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div><?php endif; ?>
  <datalist id="cm-palette"><?php foreach (COMMITTEE_PALETTE as $ph): ?><option value="<?= e(strtolower($ph)) ?>"></option><?php endforeach; ?></datalist>

  <?php
  $cmLead = []; $cmTanods = [];
  foreach ($admins as $x) { if (($x['official_role'] ?? '') === 'kagawad' && !empty($x['committee'])) $cmLead[(string) $x['committee']][] = formal_name((string) $x['full_name']); }
  try {
      foreach ((array) $db->rpc('personnel_committees') as $r) {
          foreach ((array) ($r['committees'] ?? []) as $c) { if (($c['status'] ?? '') === 'approved') $cmTanods[(string) $c['key']] = ($cmTanods[(string) $c['key']] ?? 0) + 1; }
      }
  } catch (SupabaseError) {}
  ?>
  <?php
  $sdTypes = committee_sd_types($db);
  $catAll = categories_all();
  $seen = [];
  foreach (committees_all() as $ck0 => $cc0) { if (!empty($cc0['active'])) { foreach ($cmCats[$ck0] ?? [] as $cv0) { $seen[$cv0] = true; } } }
  $unowned = array_filter(category_pairs(), fn ($k) => !isset($seen[$k]) && !empty($catAll[$k]['active']), ARRAY_FILTER_USE_KEY);
  // a complaint type as a tap-to-toggle chip in its own colour and symbol
  $typeChips = function (array $ticked, string $prefix) use ($catAll): void {
      foreach (category_pairs() as $cv => $cl):
          $col = (string) ($catAll[$cv]['colour'] ?? '#78909C'); ?>
        <label class="cmx-t" style="--tc:<?= e($col) ?>;--tk:<?= e(ink_on_bold([$col])) ?>"><input type="checkbox" name="cats[]" value="<?= e($cv) ?>" data-c="<?= e($col) ?>" data-ic="<?= e(sd_icon_for((string) $cv, (array) ($catAll[$cv] ?? []))) ?>" <?= in_array($cv, $ticked, true) ? 'checked' : '' ?>>
          <svg class="cm-ic cmx-ti" data-ic="<?= e(sd_icon_for((string) $cv, (array) ($catAll[$cv] ?? []))) ?>" viewBox="0 0 24 24" aria-hidden="true"></svg><span><?= e(t($cl[0], $cl[1])) ?></span></label>
      <?php endforeach;
  }; ?>
  <div id="acc-committees" class="cmx">
    <div class="cmx-intro">
      <h2><?= e(t('Committees', 'Mga komite')) ?></h2>
      <p><?= e(t('A committee sees only the kinds of complaint you connect to it. Tap a kind to connect or disconnect it; the committee\'s banner takes the colours and symbols of the kinds it has. Turning a committee off keeps its history but nobody can be put in it.', 'Ang komite ay nakikita lamang ang mga uri ng reklamong ikinonekta mo rito. Pindutin ang isang uri para ikonekta o alisin; ang banner ng komite ay may kulay at simbolo ng mga uring mayroon ito. Kapag in-off ang komite, nananatili ang kasaysayan nito pero walang maidadagdag dito.')) ?></p>
    </div>
    <?php if ($unowned): ?>
      <div class="cmx-note cmx-warn" role="note"><b><?= e(t('Nobody sees these yet:', 'Walang nakakakita nito:')) ?></b>
        <?php foreach ($unowned as $uk => $ul): $uc = (string) ($catAll[$uk]['colour'] ?? '#78909C'); ?><span class="cmx-t cmx-t-ro" style="--tc:<?= e($uc) ?>;--tk:<?= e(ink_on_bold([$uc])) ?>"><svg class="cm-ic cmx-ti" data-ic="<?= e(sd_icon_for((string) $uk, (array) ($catAll[$uk] ?? []))) ?>" viewBox="0 0 24 24" aria-hidden="true"></svg><span><?= e(t($ul[0], $ul[1])) ?></span></span><?php endforeach; ?>
        <span><?= e(t('Connect each to a committee below, or those complaints go only to the super admins.', 'Ikonekta ang bawat isa sa komite sa ibaba, o mapupunta lamang ang mga reklamong iyon sa mga super admin.')) ?></span></div>
    <?php else: ?>
      <div class="cmx-note cmx-ok" role="note"><?= e(t('Every kind of complaint is seen by at least one committee.', 'Ang bawat uri ng reklamo ay nakikita ng kahit isang komite.')) ?></div>
    <?php endif; ?>
    <div class="cmx-grid">
    <?php foreach (committees_all() as $ck => $cc): $ticked = $cmCats[$ck] ?? []; $lead = $cmLead[$ck] ?? []; $nT = (int) ($cmTanods[$ck] ?? 0); $cHex = committee_colour($ck); ?>
      <form method="post" class="acc-row cmx-card<?= empty($cc['active']) ? ' acc-off' : '' ?>">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="committee_save"><input type="hidden" name="key" value="<?= e($ck) ?>">
        <div class="cm-chips cmx-banner" aria-hidden="true"><a class="cm-chip cm-sd" tabindex="-1" style="<?= e(cm_banner_style($ck, $sdTypes)) ?>"><?= cm_sym_tag($ck, $sdTypes, (string) $cc['short_en']) ?><span class="cm-n"><?= e((string) $cc['short_en']) ?></span><b><?= $nT ?></b></a></div>
        <div class="cmx-body">
          <div class="acc-meta"><span class="<?= $lead ? '' : 'acc-warn' ?>"><?= $lead ? e(t('Led by', 'Pinangungunahan ni')) . ' <b>' . e(implode(', ', $lead)) . '</b>' : e(t('No Kagawad yet', 'Wala pang Kagawad')) ?></span><span><?= e($nT === 0 ? t('No tanods', 'Walang tanod') : ($nT === 1 ? t('1 tanod', 'Isang tanod') : sprintf(t('%d tanods', '%d tanod'), $nT))) ?></span></div>
          <div class="cmx-names">
            <label class="ty-f" for="cn-<?= e($ck) ?>"><span><?= e(t('Full name', 'Buong pangalan')) ?></span>
              <input class="p-input-plain" id="cn-<?= e($ck) ?>" name="name_en" value="<?= e((string) $cc['name_en']) ?>" title="<?= e((string) $cc['name_en']) ?>" required minlength="3" maxlength="120"></label>
            <label class="ty-f" for="cf-<?= e($ck) ?>"><span><?= e(t('In Tagalog', 'Sa Tagalog')) ?></span>
              <input class="p-input-plain" id="cf-<?= e($ck) ?>" name="name_fil" value="<?= e((string) $cc['name_fil']) ?>" title="<?= e((string) $cc['name_fil']) ?>" maxlength="120"></label>
            <label class="ty-f" for="cs-<?= e($ck) ?>"><span><?= e(t('Short name', 'Maikling pangalan')) ?></span>
              <input class="p-input-plain" id="cs-<?= e($ck) ?>" name="short_en" value="<?= e((string) $cc['short_en']) ?>" maxlength="40"></label>
          </div>
          <fieldset class="cmx-types acc-cats"><legend><?= e(t('Kinds of complaint it sees', 'Mga uri ng reklamong nakikita nito')) ?></legend>
            <div class="cmx-chips"><?php $typeChips($ticked, $ck); ?></div></fieldset>
          <div class="cmx-foot acc-act">
            <label class="acc-col cmx-col" title="<?= e(t('The colour of this committee\'s admins\' sidebar', 'Ang kulay ng sidebar ng mga admin ng komiteng ito')) ?>"><span><?= e(t('Sidebar colour', 'Kulay ng sidebar')) ?></span><input type="color" name="colour" value="<?= e(strtolower($cHex)) ?>" list="cm-palette"></label>
            <label class="cmx-sw"><input type="checkbox" name="active" value="1" <?= !empty($cc['active']) ? 'checked' : '' ?>><i aria-hidden="true"></i><span><?= e(t('On', 'Naka-on')) ?></span></label>
            <span class="cmx-dirty-note" aria-live="polite"><?= e(t('Unsaved changes', 'May hindi pang-save na pagbabago')) ?></span>
            <button class="p-btn p-btn-sm cmx-save" type="submit" disabled><?= e(t('Save changes', 'I-save ang mga pagbabago')) ?></button>
          </div>
        </div>
      </form>
    <?php endforeach; ?>
    </div>
    <details class="cmx-newd">
      <summary><span class="cmx-plus" aria-hidden="true">+</span><?= e(t('Add a committee', 'Magdagdag ng komite')) ?></summary>
      <form method="post" class="acc-row acc-new cmx-card cmx-card-new">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="committee_save"><input type="hidden" name="key" value="">
        <div class="cm-chips cmx-banner" aria-hidden="true"><a class="cm-chip cm-sd" tabindex="-1" style="--cc:#78909C;--ct:#FFFFFF;--g1:#78909C;--g2:#78909C;--g3:#78909C"><i class="cm-sym cm-sym-sd"></i><span class="cm-n"><?= e(t('Your new committee', 'Ang bago mong komite')) ?></span><b>0</b></a></div>
        <div class="cmx-body">
          <div class="cmx-names">
            <label class="ty-f" for="cn-new"><span><?= e(t('Full name', 'Buong pangalan')) ?></span>
              <input class="p-input-plain" id="cn-new" name="name_en" required minlength="3" maxlength="120" placeholder="<?= e(t('For example: Committee on Senior Citizens', 'Halimbawa: Komite sa mga Nakatatanda')) ?>"></label>
            <label class="ty-f" for="cf-new"><span><?= e(t('In Tagalog', 'Sa Tagalog')) ?></span>
              <input class="p-input-plain" id="cf-new" name="name_fil" maxlength="120"></label>
            <label class="ty-f" for="cs-new"><span><?= e(t('Short name', 'Maikling pangalan')) ?></span>
              <input class="p-input-plain" id="cs-new" name="short_en" maxlength="40"></label>
          </div>
          <fieldset class="cmx-types acc-cats"><legend><?= e(t('Kinds of complaint it sees', 'Mga uri ng reklamong nakikita nito')) ?></legend>
            <div class="cmx-chips"><?php $typeChips([], 'new'); ?></div></fieldset>
          <div class="cmx-foot acc-act">
            <?php $freeHex = '#78909C'; foreach (COMMITTEE_PALETTE as $ph) { if (colour_clash($ph) === null) { $freeHex = $ph; break; } } ?>
            <label class="acc-col cmx-col" title="<?= e(t('The colour of this committee\'s admins\' sidebar', 'Ang kulay ng sidebar ng mga admin ng komiteng ito')) ?>"><span><?= e(t('Sidebar colour', 'Kulay ng sidebar')) ?></span><input type="color" name="colour" value="<?= e(strtolower($freeHex)) ?>" list="cm-palette"></label>
            <button class="p-btn p-btn-sm" type="submit"><?= e(t('Make committee', 'Gumawa ng komite')) ?></button>
          </div>
        </div>
      </form>
    </details>
    <?= committee_banner_script() ?>
    <script>
    (function () {
      var I = window.SD_ICONS || {};
      function draw(svg, name) { svg.setAttribute('fill', 'none'); svg.setAttribute('stroke', 'currentColor'); svg.setAttribute('stroke-width', '2'); svg.setAttribute('stroke-linecap', 'round'); svg.setAttribute('stroke-linejoin', 'round'); svg.innerHTML = I[name] || I.other || ''; }
      document.querySelectorAll('.cmx-ti').forEach(function (s) { draw(s, s.dataset.ic); });
      function lum(h) { var n = parseInt(h.slice(1), 16), r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255; return (0.299 * r + 0.587 * g + 0.114 * b) / 255; }
      document.querySelectorAll('#acc-committees form.cmx-card').forEach(function (f) {
        var chip = f.querySelector('.cmx-banner .cm-chip'), sym = chip.querySelector('.cm-sym'), initial = new URLSearchParams(new FormData(f)).toString();
        var save = f.querySelector('.cmx-save'), isNew = f.classList.contains('acc-new');
        function banner() {
          var on = [].slice.call(f.querySelectorAll('.cmx-t input:checked')), cols = on.slice(0, 3).map(function (i) { return i.dataset.c; });
          if (!cols.length) cols = [f.querySelector('input[name="colour"]').value];
          chip.style.setProperty('--g1', cols[0]); chip.style.setProperty('--g2', cols[1] || cols[0]); chip.style.setProperty('--g3', cols[2] || cols[1] || cols[0]);
          chip.style.setProperty('--cc', f.querySelector('input[name="colour"]').value);
          chip.style.setProperty('--ct', cols.reduce(function (a, c) { return a + lum(c); }, 0) / cols.length > 0.62 ? '#2B1A00' : '#FFFFFF');
          sym.className = 'cm-sym cm-sym-sd'; sym.innerHTML = '';
          on.slice(0, 3).forEach(function (i) { var s = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); s.setAttribute('class', 'cm-ic'); s.setAttribute('viewBox', '0 0 24 24'); s.setAttribute('aria-hidden', 'true'); draw(s, i.dataset.ic); sym.appendChild(s); });
          if (on.length > 3) { var m = document.createElement('b'); m.className = 'cm-more'; m.textContent = '+' + (on.length - 3); sym.appendChild(m); }
          var old = chip.querySelector('.cm-bg'); if (old) old.remove();
          var first = sym.querySelector('svg'); if (first) { var g = first.cloneNode(true); g.setAttribute('class', 'cm-bg'); g.setAttribute('aria-hidden', 'true'); chip.appendChild(g); }
          var nm = (f.querySelector('input[name="short_en"]').value || f.querySelector('input[name="name_en"]').value || '').trim();
          chip.querySelector('.cm-n').textContent = nm || chip.querySelector('.cm-n').textContent;
        }
        function dirty() { var d = new URLSearchParams(new FormData(f)).toString() !== initial; f.classList.toggle('cmx-dirty', d); if (save) save.disabled = !d; f.classList.toggle('acc-off', !isNew && !f.querySelector('input[name="active"]').checked); }
        f.addEventListener('input', function () { banner(); dirty(); }); f.addEventListener('change', function () { banner(); dirty(); });
        banner();
      });
    })();
    </script>
  </div>
  <?php $supHex = (string) (barangay()['super_colour'] ?? SUPER_BLUE); ?>
  <div class="p-card p-card-pad" id="acc-super">
    <p class="p-eyebrow"><?= e(t('Super admin colour', 'Kulay ng super admin')) ?></p>
    <p class="p-hint"><?= e(t('One colour for every super admin\'s sidebar. No committee may use it or anything close to it, so a screenshot is never ambiguous. Change it and branding blue is free for a committee.', 'Iisang kulay para sa sidebar ng bawat super admin. Walang komiteng makagagamit nito o ng malapit dito, kaya hindi kailanman nakalilito ang screenshot. Palitan ito at magagamit ng komite ang branding blue.')) ?></p>
    <form method="post" class="acc-sup">
      <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="super_colour">
      <label class="acc-col"><span class="p-sr"><?= e(t('Super admin colour', 'Kulay ng super admin')) ?></span><input type="color" name="colour" value="<?= e(strtolower($supHex)) ?>"></label>
      <code><?= e($supHex) ?></code><?php if ($supHex === SUPER_BLUE): ?><span class="p-badge p-b-progress"><?= e(t('Branding blue', 'Asul ng branding')) ?></span><?php endif; ?>
      <button class="p-btn p-btn-sm" type="submit"><?= e(t('Save colour', 'I-save ang kulay')) ?></button>
      <?php if ($supHex !== SUPER_BLUE): ?><button class="p-btn p-btn-ghost p-btn-sm" type="submit" name="colour" value="<?= e(SUPER_BLUE) ?>"><?= e(t('Back to branding blue', 'Ibalik sa branding blue')) ?></button><?php endif; ?>
    </form>
  </div>

</section>
<?php endif; ?>

<?php if (st_on('updates')):
// ---------- App updates (0161) ----------
$releases = [];
try { $releases = (array) $db->select('app_releases', ['select' => 'id,version,build,apk_url,sha256,notes_en,notes_fil,mandatory,active,created_at', 'order' => 'build.desc']); } catch (SupabaseError) {}
$relMax = $releases ? max(array_map(fn ($r) => (int) $r['build'], $releases)) : 0;
$relNow = null; foreach ($releases as $r0) { if (!empty($r0['active'])) { $relNow = (int) $r0['build']; break; } }
?>
<section class="st-pane" data-pane="updates" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'info'): ?><div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash && $stFlash['level'] === 'error'): ?><div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div><?php endif; ?>
  <div class="p-card p-card-pad cmx-page" id="updates-card">
    <h2 class="cmx-h"><?= e(t('App updates', 'Mga update ng app')) ?></h2>
    <p class="p-hint"><?= e(t('Publish a new version and phones with an older build are offered it the next time the app opens. A version marked must update cannot be skipped. The app checks the SHA-256 before it installs, and Android refuses an APK signed with a different key. Build the APK, host it at any https link, and paste the link here.', 'Mag-publish ng bagong bersyon at iaalok ito sa mga telepono na may mas lumang build sa susunod na pagbukas ng app. Hindi malalampasan ang bersyong minarkahang kailangang i-update. Sinusuri ng app ang SHA-256 bago mag-install, at tinatanggihan ng Android ang APK na may ibang susi. I-build ang APK, i-host sa anumang https link, at i-paste ang link dito.')) ?></p>
    <form method="post" class="up-form" id="up-form">
      <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="release_publish">
      <label class="ty-f"><span><?= e(t('Version', 'Bersyon')) ?></span><input class="p-input-plain" name="version" required pattern="[0-9]+(\.[0-9]+){1,3}" placeholder="1.0.1" maxlength="20"></label>
      <label class="ty-f"><span><?= e(t('Build number (higher than the last, which is', 'Build number (mas mataas sa huli, na')) ?> <?= (int) $relMax ?>)</span><input class="p-input-plain" type="number" name="build" required min="<?= $relMax + 1 ?>" value="<?= $relMax + 1 ?>"></label>
      <label class="ty-f up-wide"><span><?= e(t('Link to the APK (https)', 'Link ng APK (https)')) ?></span><input class="p-input-plain" type="url" name="apk_url" required pattern="https://.+" maxlength="500" placeholder="https://"></label>
      <label class="ty-f up-wide"><span><?= e(t('SHA-256 of the APK (in PowerShell: Get-FileHash app.apk -Algorithm SHA256)', 'SHA-256 ng APK (sa PowerShell: Get-FileHash app.apk -Algorithm SHA256)')) ?></span><input class="p-input-plain up-mono" name="sha256" required pattern="[0-9a-fA-F]{64}" maxlength="64" minlength="64" placeholder="64 characters"></label>
      <label class="ty-f"><span><?= e(t('What is new (English)', 'Ano ang bago (English)')) ?></span><textarea class="p-input-plain" name="notes_en" rows="2" maxlength="600"></textarea></label>
      <label class="ty-f"><span><?= e(t('What is new (Tagalog)', 'Ano ang bago (Tagalog)')) ?></span><textarea class="p-input-plain" name="notes_fil" rows="2" maxlength="600"></textarea></label>
      <label class="cmx-sw up-sw"><input type="checkbox" name="mandatory" value="1"><i aria-hidden="true"></i><span><?= e(t('Must update: the app cannot be used until it is installed', 'Kailangang i-update: hindi magagamit ang app hangga\'t hindi na-install')) ?></span></label>
      <div class="up-act"><button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Publish this version', 'I-publish ang bersyong ito')) ?></button></div>
    </form>
    <p class="p-eyebrow" style="margin-top:22px"><?= e(t('Published versions', 'Mga nailathalang bersyon')) ?> <span class="p-badge-n p-badge-n--quiet"><?= count($releases) ?></span></p>
    <?php if (!$releases): ?><p class="p-hint"><?= e(t('Nothing published yet: no phone is offered an update.', 'Wala pang nailathala: walang teleponong inaalukan ng update.')) ?></p><?php endif; ?>
    <ul class="up-list">
      <?php foreach ($releases as $r): $isNow = !empty($r['active']) && (int) $r['build'] === $relNow; $host = (string) (parse_url((string) $r['apk_url'], PHP_URL_HOST) ?: ''); ?>
        <li class="up-rel<?= empty($r['active']) ? ' up-off' : '' ?>">
          <div class="up-main">
            <b>v<?= e((string) $r['version']) ?></b><small><?= e(t('build', 'bilang ng build')) ?> <?= (int) $r['build'] ?> · <?= e(long_datetime((string) $r['created_at'])) ?> · <?= e($host) ?></small>
            <span class="up-tags"><?php if ($isNow): ?><span class="p-badge p-b-done"><?= e(t('Offered now', 'Inaalok ngayon')) ?></span><?php endif; ?><?php if (!empty($r['mandatory'])): ?><span class="p-badge p-b-denied"><?= e(t('Must update', 'Kailangang i-update')) ?></span><?php endif; ?><?php if (empty($r['active'])): ?><span class="p-badge p-b-grey"><?= e(t('Withdrawn', 'Binawi')) ?></span><?php endif; ?></span>
            <?php if (!empty($r['notes_en']) || !empty($r['notes_fil'])): ?><p class="up-notes"><?= e(t((string) ($r['notes_en'] ?? ''), (string) ($r['notes_fil'] ?? $r['notes_en'] ?? ''))) ?></p><?php endif; ?>
          </div>
          <form method="post" class="up-sw2"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="release_active"><input type="hidden" name="id" value="<?= e((string) $r['id']) ?>">
            <label class="cmx-sw"><input type="checkbox" name="on" value="1" data-autosubmit <?= !empty($r['active']) ? 'checked' : '' ?>><i aria-hidden="true"></i><span><?= e(t('Offered', 'Inaalok')) ?></span></label></form>
        </li>
      <?php endforeach; ?>
    </ul>
  </div>
</section>
<?php endif; ?>

<?php if (st_on('parts')):
// ---------- Parts of the system (0144) ----------
$switches = [];
try { $switches = (array) $db->select('feature_switches', ['select' => 'key,label_en,label_fil,enabled,note', 'order' => 'key.asc']); } catch (SupabaseError) {}
?>
<section class="st-pane" data-pane="parts" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'info'): ?><div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash && $stFlash['level'] === 'error'): ?><div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div><?php endif; ?>
  <div class="p-card p-card-pad" id="acc-switches">
    <p class="p-eyebrow"><?= e(t('Parts of the system', 'Mga bahagi ng sistema')) ?></p>
    <p class="p-hint"><?= e(t('A part that is switched off stays in the system, unused, until it is switched on again.', 'Nananatili sa sistema ang bahaging naka-off, hindi ginagamit, hanggang i-on muli.')) ?></p>
    <ul class="ss-vlist"><?php foreach ($switches as $sw): ?>
      <li><div><b><?= e(t((string) $sw['label_en'], (string) $sw['label_fil'])) ?></b><?php if (!empty($sw['note'])): ?><small><?= e((string) $sw['note']) ?></small><?php endif; ?></div>
        <form method="post" class="ss-vroll"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="feature_toggle"><input type="hidden" name="key" value="<?= e((string) $sw['key']) ?>">
          <label class="cmx-sw"><input type="checkbox" name="on" value="1" data-autosubmit <?= !empty($sw['enabled']) ? 'checked' : '' ?>><i aria-hidden="true"></i><span><?= e(t('On', 'Naka-on')) ?></span></label></form></li>
    <?php endforeach; ?></ul>
  </div>
</section>
<?php endif; ?>

<?php if (st_on('types')):
// ---------- Complaint types (0146) ----------
$catOpts = [];
try {
    foreach ((array) $db->select('complaint_options', ['select' => 'id,category,label_en,label_fil,active,sort', 'order' => 'category.asc,sort.asc,id.asc']) as $o) {
        $catOpts[(string) $o['category']][] = $o;
    }
} catch (SupabaseError) {}
$iconChoices = ['street_obstruction' => t('Obstruction', 'Sagabal'), 'public_safety_infrastructure' => t('Infrastructure', 'Imprastraktura'),
    'environmental_waste_hazard' => t('Waste', 'Basura'), 'animal_welfare' => t('Animal', 'Hayop'), 'traffic_violation' => t('Traffic', 'Trapiko'),
    'barangay_service' => t('Service', 'Serbisyo'), 'peace_order_nuisance' => t('Noise', 'Ingay'), 'other' => t('Other', 'Iba pa')];
endif;
?>
<?php if (st_on('types')): ?>
<section class="st-pane" data-pane="types" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'info'): ?><div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash && $stFlash['level'] === 'error'): ?><div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div><?php endif; ?>
  <?php
  // who sees each kind of complaint: the active committees it is connected to
  $tyOwn = [];
  try { foreach ((array) $db->select('committee_categories', ['select' => 'committee,category']) as $r0) { if (!empty(committees_all()[$r0['committee']]['active'])) $tyOwn[(string) $r0['category']][] = (string) (committees_all()[$r0['committee']]['short_en'] ?? $r0['committee']); } } catch (SupabaseError) {}
  ?>
  <div class="p-card p-card-pad cmx-page" id="types-card">
    <h2 class="cmx-h"><?= e(t('Complaint types', 'Mga uri ng reklamo')) ?></h2>
    <p class="p-hint"><?= e(t('The categories and the options residents pick from in the app, in English and Tagalog. Nothing is deleted: switch a category or an option off and residents stop seeing it, while the reports filed under it keep it.', 'Ang mga kategorya at ang mga opsyong pinipili ng mga residente sa app, sa Ingles at Tagalog. Walang binubura: i-off ang kategorya o opsyon at hindi na ito makikita ng mga residente, pero nananatili ito sa mga ulat na naisampa sa ilalim nito.')) ?></p>
    <?php foreach (categories_all() as $ck => $cc): $opts = $catOpts[$ck] ?? []; $on = count(array_filter($opts, fn ($o) => !empty($o['active']))); ?>
      <details class="ty-cat<?= $cc['active'] ? '' : ' ty-off' ?>">
        <summary><span class="cmx-t cmx-t-ro ty-chip" style="--tc:<?= e($cc['colour']) ?>;--tk:<?= e(ink_on_bold([(string) $cc['colour']])) ?>"><svg class="cm-ic cmx-ti" data-ic="<?= e(sd_icon_for((string) $ck, (array) $cc)) ?>" viewBox="0 0 24 24" aria-hidden="true"></svg><b><?= e(t($cc['en'], $cc['fil'])) ?></b></span>
          <em class="ty-own<?= empty($tyOwn[$ck]) ? ' ty-own-none' : '' ?>"><?= e(!empty($tyOwn[$ck]) ? t('Seen by', 'Nakikita ng') . ' ' . implode(', ', $tyOwn[$ck]) : t('No committee sees it yet', 'Wala pang komiteng nakakakita')) ?></em>
          <small><?= e($on === 0 ? t('No options', 'Walang opsyon') : ($on === 1 ? sprintf(t('%d option', '%d opsyon'), $on) : sprintf(t('%d options', '%d opsyon'), $on))) ?></small><?php if (!$cc['active']): ?><span class="p-badge p-b-grey"><?= e(t('Off', 'Naka-off')) ?></span><?php endif; ?></summary>
        <form method="post" class="ty-row">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="cat_save"><input type="hidden" name="key" value="<?= e($ck) ?>">
          <label class="ty-f"><span><?= e(t('In English', 'Sa Ingles')) ?></span><input class="p-input-plain" name="label_en" value="<?= e($cc['en']) ?>" required minlength="2" maxlength="60"></label>
          <label class="ty-f"><span><?= e(t('In Tagalog', 'Sa Tagalog')) ?></span><input class="p-input-plain" name="label_fil" value="<?= e($cc['fil']) ?>" maxlength="60"></label>
          <label class="ty-f ty-col"><span><?= e(t('Colour', 'Kulay')) ?></span><input type="color" name="colour" value="<?= e($cc['colour']) ?>"></label>
          <label class="ty-f"><span><?= e(t('Symbol on the map', 'Simbolo sa mapa')) ?></span><select class="p-input-plain" name="icon"><?php foreach ($iconChoices as $iv => $il): ?><option value="<?= e($iv) ?>" <?= $cc['icon'] === $iv ? 'selected' : '' ?>><?= e($il) ?></option><?php endforeach; ?></select></label>
          <label class="sd-c ty-on"><input type="checkbox" name="active" value="1" <?= $cc['active'] ? 'checked' : '' ?>> <?= e(t('Residents can pick it', 'Mapipili ng mga residente')) ?></label>
          <button class="p-btn p-btn-sm" type="submit"><?= e(t('Save category', 'I-save ang kategorya')) ?></button>
        </form>
        <ul class="ty-opts">
          <?php foreach ($opts as $o): ?>
            <li><form method="post" class="ty-opt<?= empty($o['active']) ? ' ty-off' : '' ?>">
              <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="opt_save"><input type="hidden" name="id" value="<?= (int) $o['id'] ?>"><input type="hidden" name="category" value="<?= e($ck) ?>">
              <label class="p-sr" for="oe-<?= (int) $o['id'] ?>"><?= e(t('Option in English', 'Opsyon sa Ingles')) ?></label><input class="p-input-plain" id="oe-<?= (int) $o['id'] ?>" name="label_en" value="<?= e((string) $o['label_en']) ?>" required minlength="2" maxlength="60">
              <label class="p-sr" for="of-<?= (int) $o['id'] ?>"><?= e(t('Option in Tagalog', 'Opsyon sa Tagalog')) ?></label><input class="p-input-plain" id="of-<?= (int) $o['id'] ?>" name="label_fil" value="<?= e((string) $o['label_fil']) ?>" maxlength="60">
              <label class="sd-c"><input type="checkbox" name="active" value="1" <?= !empty($o['active']) ? 'checked' : '' ?>> <?= e(t('On', 'Naka-on')) ?></label>
              <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Save', 'I-save')) ?></button>
            </form></li>
          <?php endforeach; ?>
          <li><form method="post" class="ty-opt ty-add">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="opt_save"><input type="hidden" name="id" value=""><input type="hidden" name="category" value="<?= e($ck) ?>">
            <label class="p-sr" for="oe-new-<?= e($ck) ?>"><?= e(t('New option in English', 'Bagong opsyon sa Ingles')) ?></label><input class="p-input-plain" id="oe-new-<?= e($ck) ?>" name="label_en" required minlength="2" maxlength="60" placeholder="<?= e(t('New option, for example: Overgrown trees', 'Bagong opsyon, halimbawa: Lumagong puno')) ?>">
            <label class="p-sr" for="of-new-<?= e($ck) ?>"><?= e(t('New option in Tagalog', 'Bagong opsyon sa Tagalog')) ?></label><input class="p-input-plain" id="of-new-<?= e($ck) ?>" name="label_fil" maxlength="60" placeholder="<?= e(t('In Tagalog', 'Sa Tagalog')) ?>">
            <span></span>
            <button class="p-btn p-btn-sm" type="submit"><?= e(t('Add option', 'Idagdag ang opsyon')) ?></button>
          </form></li>
        </ul>
      </details>
    <?php endforeach; ?>
    <form method="post" class="ty-row ty-new">
      <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="cat_save"><input type="hidden" name="key" value="">
      <label class="ty-f"><span><?= e(t('New category', 'Bagong kategorya')) ?></span><input class="p-input-plain" name="label_en" required minlength="2" maxlength="60" placeholder="<?= e(t('For example: Overgrown Trees', 'Halimbawa: Lumagong Puno')) ?>"></label>
      <label class="ty-f"><span><?= e(t('In Tagalog', 'Sa Tagalog')) ?></span><input class="p-input-plain" name="label_fil" maxlength="60"></label>
      <label class="ty-f ty-col"><span><?= e(t('Colour', 'Kulay')) ?></span><input type="color" name="colour" value="#2E7D32"></label>
      <label class="ty-f"><span><?= e(t('Symbol on the map', 'Simbolo sa mapa')) ?></span><select class="p-input-plain" name="icon"><?php foreach ($iconChoices as $iv => $il): ?><option value="<?= e($iv) ?>"><?= e($il) ?></option><?php endforeach; ?></select></label>
      <span></span>
      <button class="p-btn p-btn-sm" type="submit"><?= e(t('Make category', 'Gumawa ng kategorya')) ?></button>
    </form>
  </div>
</section>
<?php endif; ?>

<?php if (st_on('rules') || st_on('hotlines')):
// ---------- Rules and Hotlines (0147) ----------
$ops = []; $slas = []; $hlGroups = []; $hlNums = [];
try {
    $got = $db->selectMany([
        'ops' => ['operational_settings', ['select' => '*', 'id' => 'eq.1']],
        'sla' => ['sla_policies', ['select' => 'category,resolution_hours,accept_minutes']],
        'hg'  => ['hotline_groups', ['select' => 'id,parent_id,name,display,sort_order,is_active', 'order' => 'sort_order.asc,name.asc']],
        'hn'  => ['hotline_numbers', ['select' => 'id,group_id,label,number,carrier,sort_order,is_active', 'order' => 'sort_order.asc']],
    ]);
    $rows = static fn (string $k): array => is_array($got[$k] ?? null) ? $got[$k] : [];
    $ops = (array) ($rows('ops')[0] ?? []);
    foreach ($rows('sla') as $x) $slas[(string) $x['category']] = $x;
    $hlGroups = $rows('hg');
    foreach ($rows('hn') as $x) $hlNums[(string) $x['group_id']][] = $x;
} catch (SupabaseError) {}
$otherSla = $slas['other'] ?? ['resolution_hours' => 120, 'accept_minutes' => 60];
$hlTop = array_values(array_filter($hlGroups, fn ($g) => empty($g['parent_id'])));
$hlKids = [];
foreach ($hlGroups as $g) { if (!empty($g['parent_id'])) $hlKids[(string) $g['parent_id']][] = $g; }
$hlNext = static fn (array $rows): int => $rows ? max(array_map(fn ($r) => (int) $r['sort_order'], $rows)) + 1 : 1;
endif;
?>
<?php if (st_on('rules')): ?>
<section class="st-pane" data-pane="rules" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'info'): ?><div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash && $stFlash['level'] === 'error'): ?><div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div><?php endif; ?>
  <form method="post" class="cmx-page ru-form" id="rules-card">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="rules_save">
    <div class="p-card p-card-pad ru-sec">
    <h2 class="cmx-h"><?= e(t('Deadlines for each kind of complaint', 'Mga deadline sa bawat uri ng reklamo')) ?></h2>
    <p class="p-hint"><?= e(t('A new report is due this many hours after it is filed; a tanod has this many minutes to accept a job. Reports already filed keep their deadline.', 'Dapat matapos ang bagong ulat sa ganitong dami ng oras mula nang maisampa; may ganitong dami ng minuto ang tanod para tanggapin ang trabaho. Hindi nagbabago ang deadline ng mga naisampa na.')) ?></p>
    <div class="p-tscroll"><table class="p-t ru-t">
      <thead><tr><th scope="col"><?= e(t('Kind of complaint', 'Uri ng reklamo')) ?></th><th scope="col"><?= e(t('Hours to resolve', 'Oras para malutas')) ?></th><th scope="col"><?= e(t('Minutes to accept', 'Minuto para tanggapin')) ?></th></tr></thead>
      <tbody>
      <?php foreach (categories_all() as $ck => $cc): $sl = $slas[$ck] ?? $otherSla; ?>
        <tr<?= $cc['active'] ? '' : ' class="ty-off"' ?>><td><span class="cmx-t cmx-t-ro ty-chip" style="--tc:<?= e($cc['colour']) ?>;--tk:<?= e(ink_on_bold([(string) $cc['colour']])) ?>"><svg class="cm-ic cmx-ti" data-ic="<?= e(sd_icon_for((string) $ck, (array) $cc)) ?>" viewBox="0 0 24 24" aria-hidden="true"></svg><b><?= e(t($cc['en'], $cc['fil'])) ?></b></span></td>
          <td><label class="p-sr" for="sh-<?= e($ck) ?>"><?= e(t('Hours to resolve', 'Oras para malutas')) ?>, <?= e(t($cc['en'], $cc['fil'])) ?></label><input class="p-input-plain" id="sh-<?= e($ck) ?>" type="number" name="sla[<?= e($ck) ?>][hours]" min="1" max="720" value="<?= (int) $sl['resolution_hours'] ?>"></td>
          <td><label class="p-sr" for="sa-<?= e($ck) ?>"><?= e(t('Minutes to accept', 'Minuto para tanggapin')) ?>, <?= e(t($cc['en'], $cc['fil'])) ?></label><input class="p-input-plain" id="sa-<?= e($ck) ?>" type="number" name="sla[<?= e($ck) ?>][accept]" min="1" max="240" value="<?= (int) $sl['accept_minutes'] ?>"></td></tr>
      <?php endforeach; ?>
      </tbody>
    </table></div>
    </div>
    <h2 class="cmx-h ru-lh"><?= e(t('Limits', 'Mga hangganan')) ?></h2>
    <?php
    $ruGroups = RULE_GROUPS;
    $ruLeft = array_values(array_diff(array_keys(RULE_LIMITS), array_merge(...array_column($ruGroups, 2))));
    if ($ruLeft) { $ruGroups[] = ['More', 'Iba pa', $ruLeft]; }
    foreach ($ruGroups as [$gen, $gfil, $gcols]): ?>
    <div class="ru-group p-card p-card-pad"><h3 class="ru-gh"><?= e(t($gen, $gfil)) ?></h3>
    <div class="ru-grid">
      <?php foreach ($gcols as $col): [$en, $fil, $hen, $hfil, $lo, $hi] = RULE_LIMITS[$col]; ?>
        <div class="ru-f"><label for="lim-<?= e($col) ?>"><?= e(t($en, $fil)) ?></label>
          <input class="p-input-plain" id="lim-<?= e($col) ?>" type="number" name="lim[<?= e($col) ?>]" min="<?= $lo ?>" max="<?= $hi ?>" value="<?= (int) ($ops[$col] ?? $lo) ?>">
          <small><?= e(t($hen, $hfil)) ?></small></div>
      <?php endforeach; ?>
    </div></div>
    <?php endforeach; ?>
    <div class="p-card p-card-pad ru-pause<?= !empty($ops['filing_paused']) ? ' ru-pause-on' : '' ?>">
    <h2 class="cmx-h"><?= e(t('New reports', 'Mga bagong ulat')) ?></h2>
    <label class="cmx-sw ru-sw"><input type="checkbox" name="filing_paused" value="1" <?= !empty($ops['filing_paused']) ? 'checked' : '' ?>><i aria-hidden="true"></i><span><?= e(t('Pause new reports (a resident who sends one gets the message below, and nothing is filed)', 'Ihinto muna ang mga bagong ulat (makukuha ng residenteng magpapadala ang mensahe sa ibaba, at walang maisasampa)')) ?></span></label>
    <div class="p-cfield" style="margin-top:8px"><label class="p-flabel" for="ru-msg"><?= e(t('Message while paused', 'Mensahe habang nakahinto')) ?></label>
      <input class="p-input-plain" id="ru-msg" name="filing_paused_message" maxlength="300" value="<?= e((string) ($ops['filing_paused_message'] ?? '')) ?>" placeholder="<?= e(t('For example: Closed for the holidays; call the hall for emergencies.', 'Halimbawa: Sarado ngayong pista opisyal; tumawag sa hall kung emergency.')) ?>"></div>
    </div>
    <div class="ss-posform ru-bar"><span class="cmx-dirty-note" aria-live="polite"><?= e(t('Unsaved changes', 'May hindi pang-save na pagbabago')) ?></span><button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Save rules', 'I-save ang mga patakaran')) ?></button></div>
    <script>
    (function () {   // the bar says so while there is something to save
      var f = document.getElementById('rules-card'), snap = new URLSearchParams(new FormData(f)).toString();
      function chk() { f.classList.toggle('cmx-dirty', new URLSearchParams(new FormData(f)).toString() !== snap); }
      f.addEventListener('input', chk); f.addEventListener('change', chk);
    })();
    </script>
  </form>
</section>
<?php endif; ?>

<?php if (st_on('hotlines')): ?>
<section class="st-pane" data-pane="hotlines" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'info'): ?><div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash && $stFlash['level'] === 'error'): ?><div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div><?php endif; ?>
  <div class="p-card p-card-pad cmx-page" id="hotlines-card">
    <h2 class="cmx-h"><?= e(t('Emergency hotlines', 'Mga emergency hotline')) ?></h2>
    <p class="p-hint"><?= e(t('What residents see on the app\'s Emergency screen, as it shows them. A group shows its numbers on the first screen, or opens as its own list. Switch a number off instead of deleting it.', 'Ang nakikita ng mga residente sa Emergency screen ng app. Ipinapakita ng grupo ang mga numero nito sa unang screen, o bumubukas bilang sariling listahan. I-off ang numero sa halip na burahin.')) ?></p>
    <?php
    $hlGroup = function (array $g, int $depth) use (&$hlGroup, $hlKids, $hlNums, $hlNext): void {
        $gid = (string) $g['id']; $nums = $hlNums[$gid] ?? []; ?>
      <details class="ty-cat hl-g<?= $depth ? ' hl-sub' : '' ?><?= !empty($g['is_active']) ? '' : ' ty-off' ?>">
        <summary><b><?= e((string) $g['name']) ?></b><small><?= e(count($nums) === 0 ? t('No numbers yet', 'Wala pang numero') : (count($nums) === 1 ? t('1 number', '1 numero') : sprintf(t('%d numbers', '%d numero'), count($nums)))) ?></small><?php if (empty($g['is_active'])): ?><span class="p-badge p-b-grey"><?= e(t('Off', 'Naka-off')) ?></span><?php endif; ?></summary>
        <form method="post" class="hl-row">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="hl_group"><input type="hidden" name="id" value="<?= e($gid) ?>">
          <label class="ty-f"><span><?= e(t('Group name', 'Pangalan ng grupo')) ?></span><input class="p-input-plain" name="name" value="<?= e((string) $g['name']) ?>" required maxlength="120"></label>
          <label class="ty-f"><span><?= e(t('On the first screen', 'Sa unang screen')) ?></span><select class="p-input-plain" name="display"><option value="inline" <?= $g['display'] === 'inline' ? 'selected' : '' ?>><?= e(t('Show its numbers', 'Ipakita ang mga numero')) ?></option><option value="link" <?= $g['display'] === 'link' ? 'selected' : '' ?>><?= e(t('A row that opens it', 'Hilerang nagbubukas nito')) ?></option></select></label>
          <label class="sd-c ty-on"><input type="checkbox" name="active" value="1" <?= !empty($g['is_active']) ? 'checked' : '' ?>> <?= e(t('Shown', 'Ipinapakita')) ?></label>
          <button class="p-btn p-btn-sm" type="submit"><?= e(t('Save group', 'I-save ang grupo')) ?></button>
        </form>
        <ul class="ty-opts">
          <?php foreach ($nums as $n): $nid = (string) $n['id']; ?>
            <li><form method="post" class="hl-num<?= empty($n['is_active']) ? ' ty-off' : '' ?>">
              <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="hl_number"><input type="hidden" name="id" value="<?= e($nid) ?>">
              <label class="p-sr" for="hl-l-<?= e($nid) ?>"><?= e(t('Label', 'Pangalan')) ?></label><input class="p-input-plain" id="hl-l-<?= e($nid) ?>" name="label" value="<?= e((string) $n['label']) ?>" maxlength="120" placeholder="<?= e(t('Label', 'Pangalan')) ?>">
              <label class="p-sr" for="hl-n-<?= e($nid) ?>"><?= e(t('Number', 'Numero')) ?></label><input class="p-input-plain" id="hl-n-<?= e($nid) ?>" name="number" value="<?= e((string) $n['number']) ?>" required minlength="3" maxlength="32" inputmode="tel">
              <label class="p-sr" for="hl-c-<?= e($nid) ?>"><?= e(t('Network', 'Network ng SIM')) ?></label><input class="p-input-plain" id="hl-c-<?= e($nid) ?>" name="carrier" value="<?= e((string) $n['carrier']) ?>" maxlength="20" placeholder="<?= e(t('Network', 'Network ng SIM')) ?>">
              <label class="sd-c"><input type="checkbox" name="active" value="1" <?= !empty($n['is_active']) ? 'checked' : '' ?>> <?= e(t('On', 'Naka-on')) ?></label>
              <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Save', 'I-save')) ?></button>
            </form></li>
          <?php endforeach; ?>
          <li><form method="post" class="hl-num ty-add">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="hl_number"><input type="hidden" name="id" value=""><input type="hidden" name="group" value="<?= e($gid) ?>"><input type="hidden" name="sort" value="<?= $hlNext($nums) ?>">
            <label class="p-sr" for="hl-l-new-<?= e($gid) ?>"><?= e(t('New number\'s label', 'Label ng bagong numero')) ?></label><input class="p-input-plain" id="hl-l-new-<?= e($gid) ?>" name="label" maxlength="120" placeholder="<?= e(t('Label, for example: Duty officer', 'Label, halimbawa: Duty officer')) ?>">
            <label class="p-sr" for="hl-n-new-<?= e($gid) ?>"><?= e(t('New number', 'Bagong numero')) ?></label><input class="p-input-plain" id="hl-n-new-<?= e($gid) ?>" name="number" required minlength="3" maxlength="32" inputmode="tel" placeholder="<?= e(t('Number', 'Numero')) ?>">
            <label class="p-sr" for="hl-c-new-<?= e($gid) ?>"><?= e(t('New number\'s network', 'Network ng bagong numero')) ?></label><input class="p-input-plain" id="hl-c-new-<?= e($gid) ?>" name="carrier" maxlength="20" placeholder="<?= e(t('Network', 'Network ng SIM')) ?>">
            <span></span>
            <button class="p-btn p-btn-sm" type="submit"><?= e(t('Add number', 'Idagdag ang numero')) ?></button>
          </form></li>
        </ul>
        <?php foreach ($hlKids[$gid] ?? [] as $k) $hlGroup($k, $depth + 1); ?>
      </details>
    <?php };
    foreach ($hlTop as $g) $hlGroup($g, 0); ?>
    <form method="post" class="hl-row ty-new">
      <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="hl_group"><input type="hidden" name="id" value=""><input type="hidden" name="sort" value="<?= $hlNext($hlGroups) ?>">
      <label class="ty-f"><span><?= e(t('New group', 'Bagong grupo')) ?></span><input class="p-input-plain" name="name" required maxlength="120" placeholder="<?= e(t('For example: Health Center', 'Halimbawa: Health Center')) ?>"></label>
      <label class="ty-f"><span><?= e(t('On the first screen', 'Sa unang screen')) ?></span><select class="p-input-plain" name="display"><option value="inline"><?= e(t('Show its numbers', 'Ipakita ang mga numero')) ?></option><option value="link"><?= e(t('A row that opens it', 'Hilerang nagbubukas nito')) ?></option></select></label>
      <label class="ty-f"><span><?= e(t('Inside', 'Sa loob ng')) ?></span><select class="p-input-plain" name="parent"><option value=""><?= e(t('The first screen', 'Ang unang screen')) ?></option><?php foreach ($hlTop as $g): ?><option value="<?= e((string) $g['id']) ?>"><?= e((string) $g['name']) ?></option><?php endforeach; ?></select></label>
      <button class="p-btn p-btn-sm" type="submit"><?= e(t('Make group', 'Gumawa ng grupo')) ?></button>
    </form>
  </div>
</section>
<?php endif; ?>

<?php if (st_on('wording')):
// ---------- Wording (0149) ----------
$wq = trim((string) ($_GET['wq'] ?? ''));
$wOwn = [];
try { foreach ((array) $db->select('wording', ['select' => 'source,en,fil,updated_at', 'order' => 'updated_at.desc']) as $x) $wOwn[(string) $x['source']] = $x; } catch (SupabaseError) {}
$wHits = [];
if (mb_strlen($wq) >= 2) {
    foreach (wording_catalog() as $src => $c) {
        $ov = $wOwn[$src] ?? [];
        if (mb_stripos($src . "\n" . $c['fil'] . "\n" . ($ov['en'] ?? '') . "\n" . ($ov['fil'] ?? ''), $wq) !== false) $wHits[$src] = $c;
        if (count($wHits) >= 40) break;
    }
}
$wRow = static function (string $src, array $c, ?array $ov, string $wq): void { $id = substr(md5($src), 0, 10); ?>
  <form method="post" class="wd-row<?= $ov ? ' wd-own' : '' ?>">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="wording_save">
    <input type="hidden" name="source" value="<?= e($src) ?>"><input type="hidden" name="wq" value="<?= e($wq) ?>">
    <p class="wd-src"><?php foreach ((array) ($c['in'] ?? []) as $w): ?><span class="p-badge p-b-grey wd-o wd-o-<?= $w === 'app' ? 'app' : 'portal' ?>"><?= e($w === 'app' ? t('App', 'Sa app') : t('Portal', 'Sa portal')) ?></span> <?php endforeach; ?><b><?= e($src) ?></b></p>
    <label class="ty-f"><span><?= e(t('In English', 'Sa Ingles')) ?></span><textarea class="p-input-plain" id="wd-en-<?= $id ?>" name="en" rows="1" maxlength="600"><?= e((string) ($ov['en'] ?? $c['en'])) ?></textarea></label>
    <label class="ty-f"><span><?= e(t('In Tagalog', 'Sa Tagalog')) ?></span><textarea class="p-input-plain" id="wd-fil-<?= $id ?>" name="fil" rows="1" maxlength="600"><?= e((string) ($ov['fil'] ?? $c['fil'])) ?></textarea></label>
    <div class="wd-btns">
      <button class="p-btn p-btn-sm" type="submit"><?= e(t('Save', 'I-save')) ?></button>
      <?php if ($ov): ?><button class="p-btn p-btn-ghost p-btn-sm" type="submit" name="reset" value="1"><?= e(t('Use its own wording', 'Gamitin ang sariling salita')) ?></button><?php endif; ?>
    </div>
  </form>
<?php };
endif;
?>
<?php if (st_on('wording')): ?>
<section class="st-pane" data-pane="wording" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'info'): ?><div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash && $stFlash['level'] === 'error'): ?><div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div><?php endif; ?>
  <div class="p-card p-card-pad" id="wording-card">
    <p class="p-eyebrow"><?= e(t('Wording', 'Mga salita')) ?></p>
    <p class="p-hint"><?= e(t('Change what any label of the portal or the app says, in English, in Tagalog or both. Search for the words as they show now. A label put together while the page runs (with a number or a name in it) cannot be changed here.', 'Baguhin ang sinasabi ng anumang label ng portal o ng app, sa Ingles, sa Tagalog o pareho. Hanapin ang mga salita kung paano ito lumalabas ngayon. Hindi mababago rito ang label na binubuo habang tumatakbo ang pahina (may numero o pangalan).')) ?></p>
    <form method="get" action="<?= e(st_url('wording')) ?>" class="wd-search" role="search">
      <label class="p-sr" for="wd-q"><?= e(t('Search the labels', 'Hanapin ang mga label')) ?></label>
      <input class="p-input-plain" id="wd-q" type="search" name="wq" value="<?= e($wq) ?>" minlength="2" placeholder="<?= e(t('For example: Case Reports', 'Halimbawa: Case Reports')) ?>">
      <button class="p-btn p-btn-sm" type="submit"><?= e(t('Search', 'Hanapin')) ?></button>
    </form>
    <?php if ($wq !== ''): ?>
      <p class="p-eyebrow" style="margin-top:14px"><?= e(sprintf(t('%d labels found', '%d label ang nakita'), count($wHits))) ?><?= count($wHits) >= 40 ? e(t(' (the first 40; search for more words)', ' (ang unang 40; maghanap ng mas maraming salita)')) : '' ?></p>
      <?php foreach ($wHits as $src => $c) $wRow($src, $c, $wOwn[$src] ?? null, $wq); ?>
    <?php endif; ?>
    <p class="p-eyebrow" style="margin-top:18px"><?= e(t('Changed by the barangay', 'Binago ng barangay')) ?> <span class="p-badge-n p-badge-n--quiet"><?= count($wOwn) ?></span></p>
    <?php if (!$wOwn): ?><p class="p-hint"><?= e(t('Nothing yet: every label says what it came with.', 'Wala pa: sinasabi ng bawat label ang orihinal nito.')) ?></p><?php endif; ?>
    <?php foreach ($wOwn as $src => $ov) $wRow($src, wording_catalog()[$src] ?? ['en' => $src, 'fil' => $src, 'in' => []], $ov, $wq); ?>
  </div>
</section>
<?php endif; ?>

<?php if (st_on('status')): ?>
<section class="st-pane" data-pane="status">
  <div class="st-banner" id="st-banner"></div>
  <?php if ($alerts): ?>
  <div class="p-card p-card-pad st-alerts" role="alert">
    <p class="p-eyebrow"><?= e(t('Needs attention', 'Kailangang tingnan')) ?></p>
    <ul class="st-err-list">
      <?php foreach ($alerts as $al): ?>
        <li><span class="p-badge p-b-denied"><?= e(t('Open', 'Bukas')) ?></span>
          <div><b><?= e(ucfirst((string) $al['message'])) ?></b><small><?= e(t('Since ', 'Mula ') . relative_time($al['raised_at'])) ?></small></div></li>
      <?php endforeach; ?>
    </ul>
    <p class="st-note"><?= e(t('Checked every hour. An alert closes on its own once the problem is gone; see docs/INCIDENTS.md for what to do.', 'Sinusuri bawat oras. Kusang nagsasara ang alerto kapag nawala na ang problema; tingnan ang docs/INCIDENTS.md.')) ?></p>
  </div>
  <?php endif; ?>
  <div class="st-statgrid">
  <?php if (is_array($up)): ?>
  <div class="p-card p-card-pad st-uptime">
    <p class="p-eyebrow"><?= e(t('Portal uptime', 'Uptime ng portal')) ?></p>
    <div class="st-uptime-tiles">
      <div class="st-uptime-tile"><b><?= e($upPct((int) $up['day_ok'], (int) $up['day_checks'])) ?></b><span><?= e(sprintf(t('Last 24 hours · %d checks', 'Nakaraang 24 oras · %d pagsusuri'), (int) $up['day_checks'])) ?></span></div>
      <div class="st-uptime-tile"><b><?= e($upPct((int) $up['week_ok'], (int) $up['week_checks'])) ?></b><span><?= e(sprintf(t('Last 7 days · %d checks', 'Nakaraang 7 araw · %d pagsusuri'), (int) $up['week_checks'])) ?></span></div>
      <div class="st-uptime-tile<?= $up['last_ok'] === false ? ' st-down' : '' ?>"><b><?= e($up['last_at'] ? ($up['last_ok'] ? t('Answering', 'Sumasagot') : t('Not answering', 'Hindi sumasagot')) : '—') ?></b><span><?= e($up['last_at'] ? t('Last check ', 'Huling pagsusuri ') . relative_time($up['last_at']) : t('No checks yet', 'Wala pang pagsusuri')) ?></span></div>
    </div>
    <p class="st-note"><?= e(t('The database asks the portal for a tiny page every 10 minutes, which also keeps the free server from going to sleep.', 'Tuwing 10 minuto, humihingi ang database ng maliit na pahina sa portal; pinipigilan din nito ang pagtulog ng libreng server.')) ?></p>
  </div>
  <?php endif; ?>
  <?php if (is_array($up)): $mLim = $up['mem_limit'] ?? null; $mOf = static fn ($v) => $v === null ? '—' : $v . ' MB'; ?>
  <div class="p-card p-card-pad st-uptime" id="memory">
    <p class="p-eyebrow"><?= e(t('Server memory', 'Memorya ng server')) ?></p>
    <?php if (empty($up['mem_samples'])): ?>
      <p class="p-none-line"><?= e(t('No reading yet. The check every 10 minutes starts recording it after the next deploy.', 'Wala pang sukat. Magsisimulang itala ito ng pagsusuri bawat 10 minuto pagkatapos ng susunod na deploy.')) ?></p>
    <?php else: ?>
    <div class="st-uptime-tiles">
      <div class="st-uptime-tile"><b><?= e($mOf($up['mem_now'] ?? null)) ?></b><span><?= e($mLim ? sprintf(t('In use now, of %d MB', 'Gamit ngayon, sa %d MB'), (int) $mLim) : t('In use now', 'Gamit ngayon')) ?></span></div>
      <div class="st-uptime-tile<?= $mLim && ($up['mem_week_max'] ?? 0) > $mLim * 0.85 ? ' st-down' : '' ?>"><b><?= e($mOf($up['mem_week_max'] ?? null)) ?></b><span><?= e(t('Highest this week', 'Pinakamataas ngayong linggo')) ?></span></div>
      <div class="st-uptime-tile"><b><?= e($mOf($up['mem_week_avg'] ?? null)) ?></b><span><?= e(sprintf(t('Average this week · %d readings', 'Karaniwan ngayong linggo · %d sukat'), (int) $up['mem_samples'])) ?></span></div>
    </div>
    <?php endif; ?>
    <p class="st-note"><?= e(t('Render\'s free plan shows no metrics, so the portal reports its own with each check. Reading an ID photo on this server would need about 220 MB more, for under a second.', 'Walang metrics ang libreng plan ng Render, kaya ang portal mismo ang nag-uulat sa bawat pagsusuri. Ang pagbasa ng ID sa server na ito ay mangangailangan ng mga 220 MB pa, sa wala pang isang segundo.')) ?></p>
  </div>
  <?php endif; ?>
  <?php if (is_array($smh)): ?>
  <div class="p-card p-card-pad st-uptime" id="smart-health">
    <p class="p-eyebrow"><?= e(t('SMART engine', 'Makina ng SMART')) ?></p>
    <div class="st-uptime-tiles">
      <div class="st-uptime-tile<?= empty($smh['watch_last_ok']) ? ' st-down' : '' ?>"><b><?= e(!empty($smh['watch_last_at']) ? relative_time($smh['watch_last_at']) : '—') ?></b><span><?= e(!empty($smh['watch_last_ok']) ? t('The watcher last ran, and succeeded', 'Huling tumakbo ang watcher, at nagtagumpay') : t('The watcher last ran, and failed', 'Huling tumakbo ang watcher, at pumalpak')) ?></span></div>
      <div class="st-uptime-tile<?= (int) ($smh['unscored'] ?? 0) > 0 ? ' st-down' : '' ?>"><b><?= (int) ($smh['unscored'] ?? 0) ?></b><span><?= e(sprintf(t('Open reports not scored, of %d', 'Bukas na ulat na walang marka, sa %d'), (int) ($smh['open_reports'] ?? 0))) ?></span></div>
      <div class="st-uptime-tile<?= (int) ($smh['watch_failures_24h'] ?? 0) > 0 ? ' st-down' : '' ?>"><b><?= (int) ($smh['watch_failures_24h'] ?? 0) ?></b><span><?= e(sprintf(t('Failed runs in 24 hours · %d things decided or asked', 'Pumalpak na takbo sa 24 oras · %d ang pinasya o itinanong'), (int) ($smh['events_24h'] ?? 0))) ?></span></div>
    </div>
    <p class="st-note"><?= e(t('SMART scores every report, ranks the tanods and keeps the queue. It runs inside the database every few minutes; this says whether it did.', 'Minamarkahan ng SMART ang bawat ulat, nire-rank ang mga tanod at pinananatili ang pila. Tumatakbo ito sa loob ng database kada ilang minuto; ito ang nagsasabi kung ginawa nga.')) ?></p>
  </div>
  <?php endif; ?>
  <?php if (is_array($eng)): ?>
  <div class="p-card p-card-pad st-uptime" id="engine">
    <p class="p-eyebrow"><?= e(t('Engine', 'Makina')) ?></p>
    <div class="st-uptime-tiles">
      <div class="st-uptime-tile<?= $eng['configured'] ? '' : ' st-down' ?>"><b><?= e($eng['configured'] ? t('On', 'Bukas') : t('Not set up', 'Hindi pa naka-set up')) ?></b><span><?= e(t('Reads ID photos on the server', 'Nagbabasa ng ID sa server')) ?></span></div>
      <div class="st-uptime-tile"><b><?= (int) $eng['read_week'] ?></b><span><?= e(t('Read in the last 7 days', 'Nabasa sa nakaraang 7 araw')) ?><?= !empty($eng['last_read_at']) ? e(' · ' . relative_time($eng['last_read_at'])) : '' ?></span></div>
      <div class="st-uptime-tile<?= (int) $eng['failed_week'] > 0 ? ' st-down' : '' ?>"><b><?= (int) $eng['waiting'] ?></b><span><?= e(sprintf(t('Waiting · %d could not be read this week', 'Naghihintay · %d hindi nabasa ngayong linggo'), (int) $eng['failed_week'])) ?></span></div>
    </div>
    <p class="st-note"><?= e(t('Every minute the database hands the engine the ID photos of new sign-ups to read (type, name and number), and saves what it reads. A reading only points to what to check; a person verifies.', 'Bawat minuto, ibinibigay ng database sa engine ang mga ID ng bagong nag-sign up para basahin (uri, pangalan at numero), at sine-save ang nabasa. Tinuturo lamang ng pagbasa kung ano ang susuriin; tao ang nagve-verify.')) ?></p>
  </div>
  <?php endif; ?>
  </div>
  <?php if (is_array($errs)): ?>
  <div class="p-card p-card-pad st-errors">
    <p class="p-eyebrow"><?= e(t('Recent errors', 'Mga kamakailang error')) ?></p>
    <?php if (!$errs): ?>
      <p class="p-none-line"><?= e(t('No errors recorded. Anything that goes wrong on the portal, on the server, in a browser or in an Edge Function, is listed here.', 'Walang naitalang error. Dito lalabas ang anumang mali sa portal, sa server man o sa browser.')) ?></p>
    <?php else: ?>
      <ul class="st-err-list">
        <?php foreach ($errs as $er): ?>
          <li><span class="p-badge <?= $er['source'] === 'browser' ? 'p-b-progress' : 'p-b-denied' ?>"><?= e(match ($er['source']) { 'server' => t('Server', 'Server'), 'function' => t('Function', 'Function'), default => t('Browser', 'Browser') }) ?></span>
            <div><b><?= e($er['message']) ?></b><small><?= e($er['page']) ?> · <?= e(sprintf(t('%d time(s)', '%d beses'), (int) $er['count'])) ?> · <?= e(relative_time($er['last_seen'])) ?></small></div></li>
        <?php endforeach; ?>
      </ul>
    <?php endif; ?>
  </div>
  <?php endif; ?>
  <div class="p-band ss-pband st-svcband"><h2><?= e(t('Services', 'Mga serbisyo')) ?></h2><span class="p-spacer"></span><small class="ss-subnote"><?= e(t('Each one this portal depends on, and how it answered just now', 'Bawat isang umaasa ang portal na ito, at paano sila sumagot ngayon lang')) ?></small></div>
  <div class="p-card p-table-card st-svc"><div class="p-tscroll"><table class="p-t st-table">
    <thead><tr><th><?= e(t('Service', 'Serbisyo')) ?></th><th><?= e(t('Where it runs', 'Saan tumatakbo')) ?></th><th class="p-right"><?= e(t('Response', 'Tugon')) ?></th><th><?= e(t('Status', 'Katayuan')) ?></th></tr></thead>
    <tbody id="st-rows"></tbody></table></div></div>
  <p class="st-note"><?= e(t('Supabase, Cloudinary and push alerts are checked from the portal\'s server; maps, address lookup, rain data, live updates and the flood map from this browser, so a failure there can also mean this computer\'s internet connection. No keys or passwords are shown.', 'Sinusuri mula sa server ang Supabase, Cloudinary at push alert; mula sa browser na ito ang mapa, address, ulan, live na update at mapa ng baha.')) ?></p>
  <details class="p-card p-card-pad st-mapd"><summary><span class="p-eyebrow"><?= e(t('How the portal connects', 'Paano kumokonekta ang portal')) ?></span><small><?= e(t('The same services as a diagram', 'Ang parehong serbisyo bilang diagram')) ?></small></summary><div id="st-map"></div></details>
  <div class="p-card p-card-pad st-credits"><p class="p-eyebrow"><?= e(t('Map credits', 'Mga kredito ng mapa')) ?></p>
    <p class="st-credit-line"><?= e(t('Map data © OpenStreetMap contributors (ODbL) · tiles by OpenFreeMap and OpenMapTiles · building footprints also from Overture Maps (Google Open Buildings, Microsoft ML Buildings) · tree heights from the Meta and World Resources Institute canopy height map (CC BY 4.0) · floor counts from Overture Maps and OpenStreetMap · flood hazard maps © UP NOAH Center (Project NOAH) · air quality and rain by Open-Meteo · street imagery © Mapillary contributors (CC BY-SA) · photos from Wikimedia Commons, credited where shown · icons from Lucide (ISC) and Tabler Icons (MIT).', 'Datos ng mapa © OpenStreetMap contributors (ODbL) · tiles mula sa OpenFreeMap at OpenMapTiles · mga hugis ng gusali mula rin sa Overture Maps (Google Open Buildings, Microsoft ML Buildings) · taas ng puno mula sa canopy height map ng Meta at World Resources Institute (CC BY 4.0) · mapa ng baha © UP NOAH Center (Project NOAH) · kalidad ng hangin at ulan mula sa Open-Meteo · street imagery © Mapillary contributors (CC BY-SA) · mga larawan mula sa Wikimedia Commons, may kredito kung saan ipinapakita · mga icon mula sa Lucide (ISC) at Tabler Icons (MIT).')) ?></p></div>
</section>
<?php endif; ?>

<?php if (st_on('smart') || st_on('plan')):
// ---------- SMART ----------
$sr = null; $cal = []; $fac = []; $digest = ''; $words = [];
$try = $_SESSION['smart_try'] ?? null; unset($_SESSION['smart_try']);
$replay = $_SESSION['smart_replay'] ?? null; unset($_SESSION['smart_replay']);   // 0141: the last "test before saving"
// 0142: planning, one parallel round. Each part may fail on its own; the card then says so.
$plan = ['roster' => null, 'forecast' => null, 'fair' => null, 'patterns' => null, 'orders' => null];
try {
    $pg = $db->selectMany([
        'roster'   => ['rpc/smart_roster_suggestion', ['p_days' => 90], true],
        'forecast' => ['rpc/smart_forecast', ['p_days' => 28], true],
        'fair'     => ['rpc/smart_fairness', ['p_days' => 14], true],
        'patterns' => ['rpc/smart_patterns', ['p_days' => 90], true],
        'orders'   => ['smart_work_orders', ['select' => 'id,pattern_key,title,category,status,note,evidence,created_at', 'order' => 'created_at.desc', 'limit' => '40'], true],
    ]);
    foreach ($plan as $pk => $_) { $plan[$pk] = ($pg[$pk] ?? null) instanceof SupabaseError ? null : ($pg[$pk] ?? null); }
} catch (SupabaseError) {}
$hist = [];
try { $hist = $db->rpc('smart_rule_history', ['p_limit' => 12]); $hist = is_array($hist) ? $hist : []; } catch (SupabaseError) {}
try {
    $got = $db->selectMany([
        'rules'  => ['smart_rules', ['select' => '*', 'id' => 'eq.1', 'limit' => '1'], true],
        'cal'    => ['rpc/smart_calibration', ['p_days' => 90], true],
        'fac'    => ['rpc/smart_factor_stats', ['p_days' => 90], true],
        'digest' => ['rpc/smart_digest_preview', [], true],
        'words'  => ['rpc/smart_word_suggestions', ['p_days' => 30], true],
        'cmd'    => ['command_state', ['select' => 'auto_switch', 'id' => 'eq.1', 'limit' => '1'], true],
        'links'  => ['command_display_links', ['select' => 'id,label,created_at,revoked_at,last_seen_at', 'order' => 'created_at.desc', 'limit' => '8'], true],
        'runs'   => ['command_sessions', ['select' => 'id,mode,how,reason,started_at,ended_at,end_note,starter:users!command_sessions_started_by_fkey(full_name)', 'order' => 'started_at.desc', 'limit' => '5'], true],
    ]);
    $sr     = !($got['rules'] instanceof SupabaseError) ? ($got['rules'][0] ?? null) : null;
    $cal    = !($got['cal'] instanceof SupabaseError) ? (array) $got['cal'] : [];
    $fac    = !($got['fac'] instanceof SupabaseError) ? array_slice((array) $got['fac'], 0, 12) : [];
    $words  = !($got['words'] instanceof SupabaseError) ? array_slice((array) $got['words'], 0, 12) : [];
    $digest = !($got['digest'] instanceof SupabaseError) && is_string($got['digest']) ? $got['digest'] : '';
    $cmd = ['auto' => !($got['cmd'] instanceof SupabaseError) && !empty($got['cmd'][0]['auto_switch']),
            'links' => !($got['links'] instanceof SupabaseError) ? (array) $got['links'] : [],
            'runs' => !($got['runs'] instanceof SupabaseError) ? (array) $got['runs'] : []];
} catch (SupabaseError) { /* the tab says so below */ }
$cmd ??= ['auto' => false, 'links' => [], 'runs' => []];
$cmdLink = $_SESSION['cmd_link'] ?? null; unset($_SESSION['cmd_link']);
$lvl = ['low' => t('Low', 'Mababa'), 'normal' => t('Normal', 'Katamtaman'), 'high' => t('High', 'Mataas'), 'urgent' => t('Urgent', 'Madalian')];
endif;
?>
<?php if (st_on('smart')): ?>
<section class="st-pane" data-pane="smart" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'info'): ?><div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash && $stFlash['level'] === 'error'): ?><div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div><?php endif; ?>
  <div class="ss-head"><?= smart_logo(44) ?><p><?= e(t('How the engine scores and sorts complaints. Change a rule, try it, then re-score.', 'Paano minamarkahan at inaayos ng engine ang mga sumbong. Baguhin ang patakaran, subukan, saka muling markahan.')) ?></p></div>
  <nav class="st-tabs sm-tabs" id="sm-tabs" role="tablist" aria-label="<?= e(t('SMART sections', 'Mga bahagi ng SMART')) ?>">
    <button type="button" class="st-link p-on" role="tab" data-go="overview" aria-selected="true"><?= e(t('Overview', 'Buod')) ?></button>
    <button type="button" class="st-link" role="tab" data-go="rules" aria-selected="false"><?= e(t('Rules', 'Mga patakaran')) ?><?php if (!empty($hist)): ?><b class="pd-tn"><?= count($hist) ?></b><?php endif; ?></button>
    <button type="button" class="st-link" role="tab" data-go="words" aria-selected="false"><?= e(t('Words', 'Mga salita')) ?><?php if (!empty($words)): ?><b class="pd-tn"><?= count($words) ?></b><?php endif; ?></button>
    <button type="button" class="st-link" role="tab" data-go="test" aria-selected="false"><?= e(t('Try and measure', 'Subukan at sukatin')) ?></button>
  </nav>
  <script>
  (function () {   // one group of the SMART tab at a time; the one you were in is the one you come back to after a save
    var bar = document.getElementById('sm-tabs'), pane = bar && bar.closest('.st-pane'); if (!pane) return;
    var KEY = 'ss-smart-sub', ok = ['overview', 'rules', 'words', 'test'];
    function show(g) {
      [].forEach.call(pane.querySelectorAll('[data-sm]'), function (e) { e.hidden = e.dataset.sm !== g; });
      [].forEach.call(bar.querySelectorAll('[data-go]'), function (b) { var on = b.dataset.go === g; b.classList.toggle('p-on', on); b.setAttribute('aria-selected', on ? 'true' : 'false'); });
    }
    var start = 'overview'; try { var v = localStorage.getItem(KEY); if (ok.indexOf(v) >= 0) start = v; } catch (e) {}
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { show(start); }); else show(start);   // the cards below are not parsed yet
    bar.addEventListener('click', function (e) { var b = e.target.closest('[data-go]'); if (!b) return; show(b.dataset.go); try { localStorage.setItem(KEY, b.dataset.go); } catch (er) {} });
  })();
  </script>
  <?php if (is_array($smp) || is_array($smf)): $pk = (array) $smp; $fx = (array) $smf; ?>
  <div class="p-card p-card-pad st-uptime" id="smart-measured" data-sm="overview">
    <p class="p-eyebrow"><?= e(t('How SMART is doing, last 90 days', 'Kumusta ang SMART, nakaraang 90 araw')) ?></p>
    <div class="st-uptime-tiles">
      <div class="st-uptime-tile"><b><?= isset($pk['top_pick_pct']) ? e(rtrim(rtrim(number_format((float) $pk['top_pick_pct'], 1), '0'), '.')) . '%' : '—' ?></b><span><?= e(sprintf(t('Its first choice of tanod was taken · %d of %d dispatches ranked', 'Kinuha ang unang pinili nitong tanod · %d sa %d na dispatch ang na-rank'), (int) ($pk['top_pick'] ?? 0), (int) ($pk['ranked'] ?? 0))) ?></span></div>
      <div class="st-uptime-tile"><b><?= (int) ($fx['answered'] ?? 0) > 0 ? e((string) round(100 * (int) ($fx['fixed'] ?? 0) / (int) $fx['answered'])) . '%' : '—' ?></b><span><?= e(sprintf(t('Residents confirmed it was fixed · %d of %d answered', 'Kinumpirma ng mga residente na naayos · %d sa %d ang sumagot'), (int) ($fx['fixed'] ?? 0), (int) ($fx['answered'] ?? 0))) ?></span></div>
      <div class="st-uptime-tile<?= (int) ($fx['waiting_for_barangay'] ?? 0) > 0 ? ' st-down' : '' ?>"><b><?= (int) ($fx['waiting_for_barangay'] ?? 0) ?></b><span><?= e(t('Cases a resident says are not fixed, waiting for the barangay', 'Mga kasong sabi ng residente ay hindi pa naayos, naghihintay sa barangay')) ?></span></div>
    </div>
    <p class="st-note"><?= e(t('SMART advises; the barangay decides. The first figure is how often the barangay chose the tanod SMART ranked first. It is not a score of anyone: a lower pick is often the right call.', 'Nagpapayo ang SMART; ang barangay ang nagpapasya. Ang unang bilang ay kung gaano kadalas pinili ng barangay ang tanod na unang nire-rank ng SMART. Hindi ito marka ng sinuman: madalas tama ang mas mababang pinili.')) ?></p>
  </div>
  <?php endif; ?>
  <?php if (!$sr): ?>
    <p class="p-none-line"><?= e(t('SMART could not be read. Try again in a moment.', 'Hindi mabasa ang SMART. Subukan muli mamaya.')) ?></p>
  <?php else: ?>
  <div class="ss-two" data-sm="overview">
    <div class="p-card p-card-pad">
      <p class="p-eyebrow"><?= e(t('Storm mode', 'Panahon ng bagyo')) ?></p>
      <p class="p-hint"><?= e(t('While it is on, flood zones and flood, live-wire and collapse reports count double, and the case list says so.', 'Habang naka-on, doble ang bilang ng mga lugar na binabaha at ng mga ulat ng baha, nakakuryente at pagguho.')) ?></p>
      <?php if (!empty($sr['storm_mode'])): ?>
        <p><b><?= e(t('On until', 'Naka-on hanggang')) ?> <?= e((new DateTimeImmutable((string) $sr['storm_until']))->setTimezone(new DateTimeZone('Asia/Manila'))->format('M j, g:i A')) ?></b><?= !empty($sr['storm_reason']) ? ' · ' . e((string) $sr['storm_reason']) : '' ?></p>
        <form method="post" class="ss-posform"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_storm"><input type="hidden" name="on" value="0">
          <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('End storm mode', 'Tapusin ang storm mode')) ?></button></form>
      <?php else: ?>
        <form method="post" class="p-ctl-stack"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_storm"><input type="hidden" name="on" value="1">
          <div class="p-cfield"><label class="p-flabel" for="sm-why"><?= e(t('Why (for example, the PAGASA warning)', 'Bakit (halimbawa, babala ng PAGASA)')) ?></label><input class="p-input-plain" id="sm-why" name="reason" required minlength="3" maxlength="200"></div>
          <div class="p-cfield"><label class="p-flabel" for="sm-h"><?= e(t('Hours', 'Oras')) ?></label><input class="p-input-plain" id="sm-h" type="number" name="hours" min="1" max="168" value="24"></div>
          <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Turn on', 'I-on')) ?></button></form>
      <?php endif; ?>
    </div>
    <div class="p-card p-card-pad">
      <p class="p-eyebrow"><?= e(t('Morning digest', 'Buod sa umaga')) ?></p>
      <p class="p-hint"><?= e(t('A short note each morning to the administrators: what is urgent, what may miss its deadline, what keeps coming back.', 'Maikling paalala tuwing umaga sa mga administrator: ano ang madalian, ano ang maaaring lumampas sa oras, ano ang paulit-ulit.')) ?></p>
      <form method="post" class="ss-posform"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_digest">
        <label class="sd-c"><input type="checkbox" name="on" value="1" data-autosubmit <?= !empty($sr['digest_enabled']) ? 'checked' : '' ?>> <?= e(t('Send it', 'Ipadala')) ?></label></form>
      <?php if ($digest !== ''): ?><p class="ss-digest"><?= nl2br(e($digest)) ?></p><?php endif; ?>
    </div>
  </div>

  <?php if (feature_on('command_center')): ?>
  <section class="p-card p-card-pad" id="cmd-settings" data-sm="overview">
    <p class="p-eyebrow"><?= e(t('Command center', 'Sentro ng Pamamahala')) ?></p>
    <p class="p-hint"><?= e(t('Spatial Distribution becomes a command center for one situation at a time: Fire Surroundings, Quake Check, Flood Watch or Typhoon Board. SMART suggests a mode with its reason, and an administrator turns it on. Only a person turns a mode off, with a note.', 'Nagiging command center ang Spatial Distribution para sa isang sitwasyon sa bawat pagkakataon: Paligid ng Sunog, Suri sa Lindol, Bantay-baha o Pisara ng Bagyo. Nagmumungkahi ang SMART ng mode kasama ang dahilan, at ini-o-on ito ng administrator. Tao lamang ang nag-o-off ng mode, na may note.')) ?></p>
    <form method="post" class="ss-posform"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="cmd_auto">
      <label class="sd-c"><input type="checkbox" name="on" value="1" data-autosubmit <?= $cmd['auto'] ? 'checked' : '' ?>> <?= e(t('Let SMART switch a mode on by itself (checked every 5 minutes; the administrators are told)', 'Hayaang mag-on ng mode ang SMART nang mag-isa (sinusuri kada 5 minuto; sinasabihan ang mga administrator)')) ?></label></form>
    <?php if ($cmd['runs']): ?>
      <p class="st-note" style="margin-top:14px"><b><?= e(t('Recently', 'Kamakailan')) ?></b></p>
      <ul class="ss-vlist"><?php foreach ($cmd['runs'] as $run):
          $mn = ['fire' => t('Fire Surroundings', 'Paligid ng Sunog'), 'quake' => t('Quake Check', 'Suri sa Lindol'), 'flood' => t('Flood Watch', 'Bantay-baha'), 'typhoon' => t('Typhoon Board', 'Pisara ng Bagyo')][$run['mode']] ?? $run['mode'];
          $when = static fn (?string $iso): string => $iso ? (new DateTimeImmutable($iso))->setTimezone(new DateTimeZone('Asia/Manila'))->format('M j, g:i A') : ''; ?>
        <li><div><b><?= e($mn) ?></b><?php if (!$run['ended_at']): ?> <span class="p-badge p-b-done"><?= e(t('On', 'Naka-on')) ?></span><?php endif; ?>
            <small><?= e($when($run['started_at'])) ?><?= $run['ended_at'] ? ' – ' . e($when($run['ended_at'])) : '' ?> · <?= e($run['how'] === 'auto' ? t('switched on by SMART', 'ini-on ng SMART') : formal_name((string) ($run['starter']['full_name'] ?? ''))) ?></small>
            <span class="ss-vwhy"><?= e((string) $run['reason']) ?></span>
            <?php if (!empty($run['end_note'])): ?><small><?= e(t('Closed:', 'Isinara:')) ?> <?= e((string) $run['end_note']) ?></small><?php endif; ?></div></li>
      <?php endforeach; ?></ul>
    <?php endif; ?>
    <p class="p-eyebrow" style="margin-top:18px"><?= e(t('Hall display', 'Display sa hall')) ?></p>
    <p class="p-hint"><?= e(t('A television in the barangay hall can show counts only (no names, places or tracking numbers) through its own link. It needs no account. Turn a link off at any time.', 'Maaaring magpakita ng mga bilang lamang (walang pangalan, lugar o tracking number) ang telebisyon sa barangay hall gamit ang sarili nitong link. Hindi ito nangangailangan ng account. I-off ang link anumang oras.')) ?></p>
    <?php if ($cmdLink): ?>
      <div class="cmd-new" role="status">
        <img src="<?= e(qr_data_uri($cmdLink)) ?>" alt="<?= e(t('QR code of the new display link', 'QR code ng bagong display link')) ?>" width="132" height="132">
        <div><p><b><?= e(t('The new display link. Copy it now: it is shown only once.', 'Ang bagong display link. Kopyahin ngayon: minsan lamang itong ipinapakita.')) ?></b></p>
          <label class="p-sr" for="cmd-url"><?= e(t('Display link', 'Link ng display')) ?></label>
          <input class="p-input-plain" id="cmd-url" readonly value="<?= e($cmdLink) ?>">
          <p class="st-note"><?= e(t('Open it in the hall television\'s browser, or scan the code with the phone that casts to it.', 'Buksan ito sa browser ng telebisyon sa hall, o i-scan ang code gamit ang teleponong nagka-cast dito.')) ?></p></div>
      </div>
    <?php endif; ?>
    <?php if ($cmd['links']): ?>
      <ul class="ss-vlist"><?php foreach ($cmd['links'] as $lk): ?>
        <li><div><b><?= e((string) $lk['label']) ?></b><?php if ($lk['revoked_at']): ?> <span class="p-badge p-b-denied"><?= e(t('Off', 'Naka-off')) ?></span><?php endif; ?>
            <small><?= e(t('Made', 'Ginawa')) ?> <?= e(relative_time($lk['created_at'])) ?> · <?= $lk['last_seen_at'] ? e(t('last shown', 'huling ipinakita')) . ' ' . e(relative_time($lk['last_seen_at'])) : e(t('not opened yet', 'hindi pa nabubuksan')) ?></small></div>
          <?php if (!$lk['revoked_at']): ?>
          <form method="post" class="ss-vroll"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="cmd_unlink"><input type="hidden" name="id" value="<?= e((string) $lk['id']) ?>">
            <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Turn off', 'I-off')) ?></button></form>
          <?php endif; ?></li>
      <?php endforeach; ?></ul>
    <?php endif; ?>
    <form method="post" class="ss-vroll cmd-make"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="cmd_link">
      <label class="p-sr" for="cmd-label"><?= e(t('Name of the display', 'Pangalan ng display')) ?></label>
      <input class="p-input-plain" id="cmd-label" name="label" required minlength="2" maxlength="60" placeholder="<?= e(t('Name it, for example: Hall TV', 'Pangalanan, halimbawa: TV sa hall')) ?>">
      <button class="p-btn p-btn-sm" type="submit"><?= e(t('Make a display link', 'Gumawa ng display link')) ?></button></form>
  </section>
  <?php endif; ?>

  <section class="p-card p-card-pad" id="smart-words" data-sm="words">
    <p class="p-eyebrow"><?= e(t('Words to learn', 'Mga salitang aaralin')) ?><em><?= count($words) ?></em></p>
    <p class="p-hint"><?= e(t('Words residents keep using that SMART does not know yet. You teach each one, or dismiss it; nothing is learned on its own.', 'Mga salitang madalas gamitin ng mga residente na hindi pa alam ng SMART. Ikaw ang nagtuturo ng bawat isa, o hindi ito pinapansin; walang natututuhan nang kusa.')) ?></p>
    <?php if (!$words): ?>
      <p class="p-hint"><?= e(t('Nothing new right now. A word shows here once it appears in 3 reports within 30 days.', 'Wala pang bago. Lalabas dito ang isang salita kapag nasa 3 ulat ito sa loob ng 30 araw.')) ?></p>
    <?php else: ?>
    <ul class="ss-words">
      <?php foreach ($words as $w): $wd = (string) $w['word']; $kindLabel = category_pairs()[(string) ($w['mostly_category'] ?? '')] ?? null; ?>
        <li>
          <div class="sw-head"><b class="sw-w"><?= e($wd) ?></b>
            <span class="p-hint"><?= (int) $w['reports'] ?> <?= e(t('reports', 'ulat')) ?><?= $kindLabel ? ' · ' . (int) round((float) $w['share'] * 100) . '% ' . e(t($kindLabel[0], $kindLabel[1])) : '' ?></span></div>
          <?php if (!empty($w['example'])): ?><p class="sw-ex">&ldquo;<?= e((string) $w['example']) ?>&rdquo;</p><?php endif; ?>
          <?php if (!empty($w['likely_spelling_of'])): ?><p class="sw-likely"><?= e(t('Likely a spelling of', 'Posibleng baybay ng')) ?> <b><?= e((string) $w['likely_spelling_of']) ?></b></p><?php endif; ?>
          <details class="sw-teach"><summary><?= e(t('Teach it', 'Ituro ito')) ?></summary>
            <div class="sw-forms">
              <form method="post" class="ss-posform"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_word"><input type="hidden" name="word" value="<?= e($wd) ?>">
                <label class="p-flabel" for="sw-m-<?= e($wd) ?>"><?= e(t('It means a known word', 'Ibig sabihin ay kilalang salita')) ?></label>
                <select class="p-input-plain" name="as" aria-label="<?= e(t('How it relates', 'Paano ito nauugnay')) ?>"><option value="spelling"><?= e(t('Spelling of', 'Baybay ng')) ?></option><option value="synonym"><?= e(t('Same meaning as', 'Kapareho ng kahulugan ng')) ?></option><option value="form"><?= e(t('Another form of', 'Ibang anyo ng')) ?></option></select>
                <input class="p-input-plain" id="sw-m-<?= e($wd) ?>" name="target" maxlength="30" placeholder="<?= e(t('e.g. sunog', 'hal. sunog')) ?>" value="<?= e((string) ($w['likely_spelling_of'] ?? '')) ?>" required>
                <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Save', 'I-save')) ?></button></form>
              <form method="post" class="ss-posform"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_word"><input type="hidden" name="word" value="<?= e($wd) ?>"><input type="hidden" name="as" value="category">
                <label class="p-flabel" for="sw-k-<?= e($wd) ?>"><?= e(t('A word for a kind of complaint', 'Salita para sa isang uri ng sumbong')) ?></label>
                <select class="p-input-plain" id="sw-k-<?= e($wd) ?>" name="target"><?php foreach (category_pairs() as $ck => $cl): ?><option value="<?= e($ck) ?>"<?= (string) ($w['mostly_category'] ?? '') === $ck ? ' selected' : '' ?>><?= e(t($cl[0], $cl[1])) ?></option><?php endforeach; ?></select>
                <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Save', 'I-save')) ?></button></form>
              <?php if (!empty($sr['keyword_groups']) && is_array($sr['keyword_groups'])): ?>
              <form method="post" class="ss-posform"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_word"><input type="hidden" name="word" value="<?= e($wd) ?>"><input type="hidden" name="as" value="urgent">
                <label class="p-flabel" for="sw-u-<?= e($wd) ?>"><?= e(t('An urgent word for', 'Madalian na salita para sa')) ?></label>
                <select class="p-input-plain" id="sw-u-<?= e($wd) ?>" name="target"><?php foreach ($sr['keyword_groups'] as $g): ?><option value="<?= e((string) ($g['label'] ?? '')) ?>"><?= e((string) ($g['label'] ?? '')) ?> (+<?= (int) ($g['points'] ?? 0) ?>)</option><?php endforeach; ?></select>
                <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Save', 'I-save')) ?></button></form>
              <?php endif; ?>
              <form method="post" class="ss-posform"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_word"><input type="hidden" name="word" value="<?= e($wd) ?>"><input type="hidden" name="as" value="dismiss">
                <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Not a word to learn', 'Hindi salitang aaralin')) ?></button></form>
            </div></details>
        </li>
      <?php endforeach; ?>
    </ul>
    <?php endif; ?>
  </section>

  <form method="post" class="p-card p-card-pad" data-sm="rules">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_rules">
    <p class="p-eyebrow"><?= e(t('Points for each kind of complaint', 'Puntos sa bawat uri ng sumbong')) ?></p>
    <p class="p-hint"><?= e(t('A report starts with these points; words, hazard zones, neighbours reporting the same thing and the hour add to them. The total decides the level.', 'Nagsisimula ang ulat sa mga puntos na ito; dinadagdagan ito ng mga salita, lugar na may panganib, kapitbahay na nag-ulat ng pareho at oras. Ang kabuuan ang magpapasya ng antas.')) ?></p>
    <div class="ss-cmap">
      <?php foreach (category_pairs() as $ck => $cl): ?>
        <div class="ss-cmap-row"><label for="pt-<?= e($ck) ?>"><?= e(t($cl[0], $cl[1])) ?></label>
          <input class="p-input-plain" id="pt-<?= e($ck) ?>" type="number" name="pts[<?= e($ck) ?>]" min="0" max="60" value="<?= (int) ($sr['category_points'][$ck] ?? 0) ?>"></div>
      <?php endforeach; ?>
    </div>
    <p class="p-eyebrow" style="margin-top:14px"><?= e(t('Where the levels start (out of 100)', 'Kung saan nagsisimula ang mga antas (sa 100)')) ?></p>
    <div class="ss-cmap ss-cmap--3">
      <?php foreach (['urgent_from' => t('Urgent from', 'Madalian mula'), 'high_from' => t('High from', 'Mataas mula'), 'normal_from' => t('Normal from', 'Katamtaman mula')] as $fk => $fl): ?>
        <div class="ss-cmap-row"><label for="lv-<?= e($fk) ?>"><?= e($fl) ?></label><input class="p-input-plain" id="lv-<?= e($fk) ?>" type="number" name="<?= e($fk) ?>" min="1" max="100" value="<?= (int) $sr[$fk] ?>"></div>
      <?php endforeach; ?>
    </div>
    <p class="p-hint"><?= e(t('Urgent must be higher than High, and High higher than Normal.', 'Dapat mas mataas ang Madalian kaysa Mataas, at ang Mataas kaysa Katamtaman.')) ?></p>
    <div class="p-cfield" style="margin-top:12px"><label class="p-flabel" for="rl-why"><?= e(t('Why are the rules changing? (kept with the version)', 'Bakit binabago ang mga patakaran? (itatago kasama ng bersyon)')) ?></label>
      <input class="p-input-plain" id="rl-why" name="reason" maxlength="300" placeholder="<?= e(t('For example: flood reports were rated too low in the storm season', 'Halimbawa: masyadong mababa ang marka ng mga ulat ng baha noong bagyo')) ?>"></div>
    <div class="ss-posform">
      <button class="p-btn p-btn-ghost p-btn-sm" type="submit" name="do" value="replay" formnovalidate><?= e(t('Test on the last 90 days', 'Subukan sa nakaraang 90 araw')) ?></button>
      <button class="p-btn p-btn-primary p-btn-sm" type="submit" name="do" value="save"><?= e(t('Save rules', 'I-save ang mga patakaran')) ?></button>
    </div>
    <p class="p-hint"><?= e(t('Test first: it shows how many past reports would change level, and saves nothing.', 'Subukan muna: ipinapakita kung ilang nakaraang ulat ang magbabago ng antas, at walang sine-save.')) ?></p>
  </form>
  <?php if (is_array($replay) && is_array($replay['result'] ?? null)): $rp = $replay['result']; ?>
  <div class="p-card p-card-pad" id="smart-replay" data-sm="rules">
    <p class="p-eyebrow"><?= e(t('What the change would do', 'Ano ang gagawin ng pagbabago')) ?></p>
    <p><b><?= (int) ($rp['moved'] ?? 0) ?></b> <?= e(sprintf(t('of %d reports from the last %d days would change level.', 'sa %d ulat sa nakaraang %d araw ang magbabago ng antas.'), (int) ($rp['reports'] ?? 0), (int) ($rp['days'] ?? 90))) ?>
      <?= e(t('Nothing was saved.', 'Walang na-save.')) ?></p>
    <?php $tr = array_values(array_filter((array) ($rp['transitions'] ?? []), fn ($x) => ($x['from'] ?? '') !== ($x['to'] ?? ''))); ?>
    <?php if ($tr): ?>
      <ul class="st-err-list"><?php foreach ($tr as $x): ?>
        <li><span class="p-badge p-b-progress"><?= (int) $x['reports'] ?></span><div><b><?= e(ucfirst((string) $x['from']) . ' → ' . ucfirst((string) $x['to'])) ?></b></div></li>
      <?php endforeach; ?></ul>
    <?php else: ?><p class="p-none-line"><?= e(t('No report would change level.', 'Walang ulat na magbabago ng antas.')) ?></p><?php endif; ?>
    <?php $moved = array_slice((array) ($rp['changed'] ?? []), 0, 8); ?>
    <?php if ($moved): ?>
      <p class="p-eyebrow" style="margin-top:14px"><?= e(t('The biggest moves', 'Ang pinakamalalaking pagbabago')) ?></p>
      <ul class="st-err-list"><?php foreach ($moved as $m): ?>
        <li><span class="p-badge p-b-progress"><?= (int) $m['score_before'] ?> → <?= (int) $m['score_after'] ?></span>
          <div><b><?= e((string) $m['tracking_id']) ?> · <?= e((string) $m['subject']) ?></b><small><?= e(ucfirst((string) $m['level_before']) . ' → ' . ucfirst((string) $m['level_after'])) ?></small></div></li>
      <?php endforeach; ?></ul>
    <?php endif; ?>
    <p class="st-note"><?= e(t('The form above keeps what you typed. Add a reason and press Save rules to make the change.', 'Nasa form sa itaas pa rin ang tinype mo. Maglagay ng dahilan at pindutin ang I-save ang mga patakaran para gawin ang pagbabago.')) ?></p>
  </div>
  <?php endif; ?>
  <form method="post" class="ss-posform" data-sm="rules"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_rescore">
    <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Re-score open reports', 'Muling markahan ang mga bukas na ulat')) ?></button>
    <span class="p-hint"><?= e(t('Applies the rules above to every case that is still open. Levels an administrator set by hand stay.', 'Ilalapat ang mga patakaran sa lahat ng kasong bukas pa. Mananatili ang antas na itinakda ng administrator.')) ?></span></form>

  <?php if ($hist): ?>
  <div class="p-card p-card-pad" id="smart-history" data-sm="rules">
    <p class="p-eyebrow"><?= e(t('Versions of the rules', 'Mga bersyon ng mga patakaran')) ?><em><?= count($hist) ?></em></p>
    <p class="p-hint"><?= e(t('Every change to the rules or the word list is kept, with who made it and why. Rolling back restores a version as a new one, and re-scores the open reports.', 'Itinatago ang bawat pagbabago sa mga patakaran o listahan ng salita, kasama kung sino at bakit. Ibinabalik ng rollback ang isang bersyon bilang bago, at muling minamarkahan ang mga bukas na ulat.')) ?></p>
    <ul class="ss-vlist">
      <?php foreach ($hist as $h): ?>
        <li>
          <div><b><?= e(t('Version', 'Bersyon')) ?> <?= (int) $h['version'] ?></b><?= !empty($h['current']) ? ' <span class="p-badge p-b-done">' . e(t('Now', 'Ngayon')) . '</span>' : '' ?>
            <small><?= e(long_datetime($h['at'])) ?> · <?= e((string) ($h['by'] ?? t('the system', 'ang sistema'))) ?></small>
            <span class="ss-vwhy"><?= e((string) $h['reason']) ?></span>
            <?php if (!empty($h['changed'])): ?><small><?= e(t('Changed: ', 'Binago: ') . implode(', ', array_map(fn ($k) => str_replace('_', ' ', (string) $k), (array) $h['changed']))) ?></small><?php endif; ?></div>
          <?php if (empty($h['current'])): ?>
          <form method="post" class="ss-vroll"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_rollback"><input type="hidden" name="version" value="<?= (int) $h['version'] ?>">
            <label class="p-sr" for="rb-<?= (int) $h['version'] ?>"><?= e(t('Why roll back?', 'Bakit ibabalik?')) ?></label>
            <input class="p-input-plain" id="rb-<?= (int) $h['version'] ?>" name="reason" required maxlength="300" placeholder="<?= e(t('Why roll back?', 'Bakit ibabalik?')) ?>">
            <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Roll back to this', 'Ibalik sa bersyong ito')) ?></button></form>
          <?php endif; ?>
        </li>
      <?php endforeach; ?>
    </ul>
  </div>
  <?php endif; ?>

  <form method="post" class="p-card p-card-pad" data-sm="test">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_try">
    <p class="p-eyebrow"><?= e(t('Try it', 'Subukan')) ?></p>
    <p class="p-hint"><?= e(t('Type a complaint and see what level SMART would give it, and why. Nothing is saved.', 'Mag-type ng sumbong at tingnan ang antas na ibibigay ng SMART, at kung bakit. Walang mase-save.')) ?></p>
    <div class="p-ctl-stack">
      <div class="p-cfield"><label class="p-flabel" for="tr-cat"><?= e(t('Kind of complaint', 'Uri ng sumbong')) ?></label>
        <select class="p-input-plain" id="tr-cat" name="category"><?php foreach (category_pairs() as $ck => $cl): ?><option value="<?= e($ck) ?>"><?= e(t($cl[0], $cl[1])) ?></option><?php endforeach; ?></select></div>
      <div class="p-cfield"><label class="p-flabel" for="tr-sub"><?= e(t('Subject', 'Paksa')) ?></label><input class="p-input-plain" id="tr-sub" name="subject" required maxlength="120"></div>
      <div class="p-cfield"><label class="p-flabel" for="tr-desc"><?= e(t('What happened', 'Ano ang nangyari')) ?></label><textarea class="p-note" id="tr-desc" name="description" rows="2" maxlength="600"></textarea></div>
      <div class="p-cfield"><label class="p-flabel" for="tr-lat"><?= e(t('Latitude and longitude (optional)', 'Latitude at longitude (opsyonal)')) ?></label>
        <div class="ss-posform"><input class="p-input-plain" id="tr-lat" name="lat" inputmode="decimal" placeholder="14.5"><input class="p-input-plain" name="lng" inputmode="decimal" placeholder="121.0" aria-label="Longitude"></div></div>
      <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Score it', 'Markahan')) ?></button>
    </div>
    <?php if (is_array($try)): ?>
      <div class="ss-tryout"><p><b><?= e($lvl[$try['level'] ?? ''] ?? (string) ($try['level'] ?? '')) ?></b> · <?= (int) ($try['score'] ?? 0) ?>/100</p>
        <ul class="ss-reasons"><?php foreach ((array) ($try['reasons'] ?? []) as $rs): ?><li><span><?= e((string) ($rs['detail'] ?? $rs['factor'] ?? '')) ?></span><b>+<?= (int) ($rs['points'] ?? 0) ?></b></li><?php endforeach; ?></ul></div>
    <?php endif; ?>
  </form>

  <?php if ($cal || $fac): ?>
  <div class="ss-two" data-sm="test">
    <?php if ($cal): ?><section class="p-card p-card-pad"><p class="p-eyebrow"><?= e(t('How the levels are doing (90 days)', 'Kumusta ang mga antas (90 araw)')) ?></p>
      <table class="ss-table"><thead><tr><th><?= e(t('Level', 'Antas')) ?></th><th class="n"><?= e(t('Reports', 'Ulat')) ?></th><th class="n"><?= e(t('Raised', 'Itinaas')) ?></th><th class="n"><?= e(t('Lowered', 'Ibinaba')) ?></th><th class="n"><?= e(t('To dispatch (min)', 'Hanggang dispatch (min)')) ?></th></tr></thead><tbody>
      <?php foreach ($cal as $c): ?><tr><td><?= e($lvl[$c['level']] ?? (string) $c['level']) ?></td><td class="n"><?= (int) $c['reports'] ?></td><td class="n"><?= (int) $c['raised'] ?></td><td class="n"><?= (int) $c['lowered'] ?></td><td class="n"><?= $c['median_minutes_to_dispatch'] === null ? '—' : (int) round((float) $c['median_minutes_to_dispatch']) ?></td></tr><?php endforeach; ?>
      </tbody></table>
      <p class="p-hint"><?= e(t('If administrators often lower reports with a given factor, it may deserve fewer points.', 'Kung madalas ibaba ng mga administrator ang mga ulat na may isang salik, maaaring bawasan ang puntos nito.')) ?></p></section><?php endif; ?>
    <?php if ($fac): ?><section class="p-card p-card-pad"><p class="p-eyebrow"><?= e(t('Factors administrators change', 'Mga salik na binabago ng administrator')) ?></p>
      <table class="ss-table"><thead><tr><th><?= e(t('Factor', 'Salik')) ?></th><th class="n"><?= e(t('Reports', 'Ulat')) ?></th><th class="n"><?= e(t('Raised', 'Itinaas')) ?></th><th class="n"><?= e(t('Lowered', 'Ibinaba')) ?></th></tr></thead><tbody>
      <?php foreach ($fac as $f): ?><tr><td><?= e(trim((string) $f['factor'] . ' ' . (string) ($f['detail'] ?? ''))) ?></td><td class="n"><?= (int) $f['reports'] ?></td><td class="n"><?= (int) $f['raised'] ?></td><td class="n"><?= (int) $f['lowered'] ?></td></tr><?php endforeach; ?>
      </tbody></table></section><?php endif; ?>
  </div>
  <?php endif; ?>
  <?php endif; ?>
</section>
<?php endif; ?>

<?php if (st_on('plan')): ?>
<section class="st-pane" data-pane="plan" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'info'): ?><div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash && $stFlash['level'] === 'error'): ?><div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div><?php endif; ?>
  <div class="ss-head"><?= smart_logo(44) ?><p><?= e(t('What the barangay\'s own history says about the days ahead. These are counts of past reports, not predictions about anyone, and nothing here is enforced.', 'Ang sinasabi ng sariling kasaysayan ng barangay tungkol sa mga susunod na araw. Mga bilang ito ng mga nakaraang ulat, hindi hula tungkol sa sinuman, at walang ipinatutupad dito.')) ?></p></div>
  <?php
  $dayEn = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  $dayTl = ['Lin', 'Lun', 'Mar', 'Miy', 'Huw', 'Biy', 'Sab'];
  $hr = static fn (int $h): string => date('g A', mktime($h % 24, 0, 0));
  $fc = is_array($plan['forecast']) ? $plan['forecast'] : null;
  $ro = is_array($plan['roster']) ? $plan['roster'] : null;
  $fa = is_array($plan['fair']) ? $plan['fair'] : null;
  ?>
  <div class="p-card p-card-pad st-uptime" id="plan-forecast">
    <p class="p-eyebrow"><?= e(t('Looking ahead', 'Tanaw sa susunod')) ?></p>
    <?php if (!$fc): ?><p class="p-none-line"><?= e(t('The forecast could not be read just now.', 'Hindi mabasa ang forecast ngayon.')) ?></p><?php else: ?>
    <div class="st-uptime-tiles">
      <div class="st-uptime-tile"><b><?= (int) $fc['open_now'] ?></b><span><?= e(t('Open cases now', 'Bukas na kaso ngayon')) ?></span></div>
      <div class="st-uptime-tile"><b><?= e(rtrim(rtrim(number_format((float) $fc['arrive_per_day'], 1), '0'), '.')) ?> / <?= e(rtrim(rtrim(number_format((float) $fc['close_per_day'], 1), '0'), '.')) ?></b><span><?= e(t('Filed / finished per day, lately', 'Naisampa / natapos kada araw, kamakailan')) ?></span></div>
      <div class="st-uptime-tile<?= (int) $fc['open_in_7_days'] > (int) $fc['open_now'] ? ' st-down' : '' ?>"><b><?= (int) $fc['open_in_7_days'] ?></b><span><?= e(t('Open in a week at this pace', 'Bukas sa isang linggo sa ganitong takbo')) ?></span></div>
    </div>
    <?php if (!empty($fc['this_week'])): ?>
      <p class="st-note"><b><?= e(t('Expected this week, by kind:', 'Inaasahan ngayong linggo, ayon sa uri:')) ?></b>
        <?= e(implode(' · ', array_map(fn ($x) => category_label((string) $x['category']) . ' ' . rtrim(rtrim(number_format((float) $x['expected'], 1), '0'), '.'), array_slice((array) $fc['this_week'], 0, 6)))) ?></p>
    <?php endif; ?>
    <p class="st-note"><?= !empty($fc['seasonal_ready'])
        ? e(t('This month last year:', 'Ngayong buwan noong nakaraang taon:') . ' ' . implode(' · ', array_map(fn ($x) => category_label((string) $x['category']) . ' ' . (int) $x['last_year'], array_slice((array) ($fc['seasonal'] ?? []), 0, 6))))
        : e(sprintf(t('A seasonal forecast (this month last year) needs a year of history. There are %d days so far, so SMART does not guess.', 'Ang seasonal forecast (ngayong buwan noong nakaraang taon) ay nangangailangan ng isang taong kasaysayan. %d araw pa lamang ang mayroon, kaya hindi humuhula ang SMART.'), (int) $fc['history_days'])) ?></p>
    <?php endif; ?>
  </div>

  <div class="p-card p-card-pad" id="plan-roster">
    <p class="p-eyebrow"><?= e(t('Duty roster, suggested', 'Mungkahing duty roster')) ?></p>
    <?php if (!$ro || empty($ro['blocks'])): ?><p class="p-none-line"><?= e(t('Not enough reports yet to suggest a roster.', 'Kulang pa ang mga ulat para magmungkahi ng roster.')) ?></p><?php else:
        $blocks = array_values(array_filter((array) $ro['blocks'], fn ($b) => (int) $b['reports'] > 0));
        usort($blocks, fn ($a, $b) => (float) $b['expected'] <=> (float) $a['expected']);
        $blocks = array_slice($blocks, 0, 8); ?>
      <ul class="st-err-list"><?php foreach ($blocks as $b): $gap = (float) $b['gap']; ?>
        <li><span class="p-badge <?= $gap > 0 ? 'p-b-denied' : 'p-b-done' ?>"><?= e($gap > 0 ? sprintf(t('needs +%s', 'kulang ng %s'), rtrim(rtrim(number_format($gap, 1), '0'), '.')) : t('covered', 'sapat')) ?></span>
          <div><b><?= e(t($dayEn[(int) $b['dow']], $dayTl[(int) $b['dow']]) . ' ' . $hr((int) $b['from_hour']) . '–' . $hr((int) $b['from_hour'] + 3)) ?></b>
            <small><?= e(sprintf(t('About %s reports a week · suggest %d tanod(s) · usually %s on duty', 'Mga %s ulat kada linggo · mungkahi: %d tanod · karaniwang %s ang naka-duty'), rtrim(rtrim(number_format((float) $b['expected'], 1), '0'), '.'), (int) $b['suggested'], rtrim(rtrim(number_format((float) $b['usual'], 1), '0'), '.'))) ?></small></div></li>
      <?php endforeach; ?></ul>
      <p class="st-note"><?= e(sprintf(t('The busiest 3-hour blocks over the last %d days (%s weeks of history). One tanod is suggested for about every two reports a week. A suggestion to talk about, not a rule.', 'Ang pinakaabalang 3-oras na bloke sa nakaraang %d araw (%s linggo ng kasaysayan). Isang tanod bawat mga dalawang ulat kada linggo ang mungkahi. Mungkahing pag-usapan, hindi patakaran.'), (int) $ro['days'], rtrim(rtrim(number_format((float) $ro['weeks'], 1), '0'), '.'))) ?></p>
    <?php endif; ?>
  </div>

  <div class="p-card p-card-pad" id="plan-hotspots">
    <p class="p-eyebrow"><?= e(t('Problems that keep coming back', 'Mga problemang paulit-ulit')) ?></p>
    <?php $pats = is_array($plan['patterns']) ? $plan['patterns'] : []; $orders = is_array($plan['orders']) ? $plan['orders'] : [];
          $openKeys = []; foreach ($orders as $o) { if (in_array($o['status'], ['open', 'planned'], true)) { $openKeys[$o['pattern_key']] = true; } } ?>
    <?php if (!$pats): ?><p class="p-none-line"><?= e(t('No problem has come back often enough in the last 90 days.', 'Walang problemang bumalik nang sapat sa nakaraang 90 araw.')) ?></p><?php else: ?>
    <ul class="ss-vlist"><?php foreach (array_slice($pats, 0, 6) as $pt): ?>
      <li><div><b><?= e(category_label((string) $pt['category'])) ?></b>
            <small><?= e(sprintf(t('%d reports over %d weeks from %d residents · %d still open', '%d ulat sa loob ng %d linggo mula sa %d residente · %d bukas pa'), (int) $pt['reports'], (int) $pt['weeks'], (int) $pt['residents'], (int) $pt['still_open'])) ?><?= !empty($pt['hazard']) ? e(' · ' . $pt['hazard']) : '' ?></small>
            <small><?= e(implode(', ', array_slice((array) ($pt['tracking_ids'] ?? []), 0, 4))) ?></small></div>
        <?php if (isset($openKeys[$pt['pattern_key']])): ?><span class="p-badge p-b-progress ss-vtag"><?= e(t('Work order open', 'May bukas na work order')) ?></span>
        <?php else: ?>
        <form method="post" class="ss-vroll"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="wo_create"><input type="hidden" name="pattern" value="<?= e((string) $pt['pattern_key']) ?>">
          <label class="p-sr" for="wo-<?= e(md5((string) $pt['pattern_key'])) ?>"><?= e(t('Title of the permanent fix', 'Pamagat ng permanenteng ayos')) ?></label>
          <input class="p-input-plain" id="wo-<?= e(md5((string) $pt['pattern_key'])) ?>" name="title" required minlength="3" maxlength="140" placeholder="<?= e(t('Permanent fix, for example: replace the drain', 'Permanenteng ayos, halimbawa: palitan ang kanal')) ?>">
          <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Make a work order', 'Gumawa ng work order')) ?></button></form>
        <?php endif; ?></li>
    <?php endforeach; ?></ul>
    <?php endif; ?>
    <?php if ($orders): ?>
      <p class="p-eyebrow" style="margin-top:16px"><?= e(t('Work orders for the council', 'Mga work order para sa konseho')) ?><em><?= count($orders) ?></em></p>
      <ul class="ss-vlist"><?php foreach ($orders as $o): $ev = (array) ($o['evidence'] ?? []); ?>
        <li><div><b><?= e((string) $o['title']) ?></b>
              <small><?= e(category_label((string) $o['category'])) ?> · <?= e(sprintf(t('%d reports as evidence', '%d ulat bilang ebidensya'), (int) ($ev['reports'] ?? 0))) ?> · <?= e(relative_time($o['created_at'])) ?></small>
              <small><?= e(implode(', ', array_slice((array) ($ev['tracking_ids'] ?? []), 0, 6))) ?></small></div>
          <form method="post" class="ss-vroll"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="wo_set"><input type="hidden" name="id" value="<?= e((string) $o['id']) ?>">
            <label class="p-sr" for="ws-<?= e((string) $o['id']) ?>"><?= e(t('Status', 'Katayuan')) ?></label>
            <select class="p-input-plain" id="ws-<?= e((string) $o['id']) ?>" name="status" data-autosubmit>
              <?php foreach (['open' => t('Open', 'Bukas'), 'planned' => t('Planned', 'Nakaplano'), 'done' => t('Done', 'Tapos na'), 'dropped' => t('Dropped', 'Itinigil')] as $sv => $sl): ?>
                <option value="<?= e($sv) ?>" <?= $o['status'] === $sv ? 'selected' : '' ?>><?= e($sl) ?></option><?php endforeach; ?></select></form></li>
      <?php endforeach; ?></ul>
    <?php endif; ?>
  </div>

  <div class="p-card p-card-pad" id="plan-fair">
    <p class="p-eyebrow"><?= e(t('Sharing the work', 'Pagbabahagi ng trabaho')) ?></p>
    <?php if (!$fa || (empty($fa['tanods']) && empty($fa['admins']))): ?><p class="p-none-line"><?= e(t('Nothing to compare yet.', 'Wala pang maikukumpara.')) ?></p><?php else: ?>
      <?php if (($fa['tanod_note'] ?? null) === 'one_tanod_most'): ?><p class="p-hint"><b><?= e(t('One tanod had most of the dispatches.', 'Isang tanod ang may pinakamaraming dispatch.')) ?></b> <?= e(t('That may be right (the nearest, the one on duty). It is worth a look so the load is shared on purpose.', 'Maaaring tama iyon (pinakamalapit, ang naka-duty). Sulit tingnan para sinasadya ang pagbabahagi.')) ?></p><?php endif; ?>
      <?php if (($fa['admin_note'] ?? null) === 'one_admin_most'): ?><p class="p-hint"><b><?= e(t('One administrator holds most of the open cases.', 'Isang administrator ang may hawak ng karamihan ng bukas na kaso.')) ?></b> <?= e(t('Consider sharing some of them.', 'Pag-isipang ibahagi ang ilan.')) ?></p><?php endif; ?>
      <div class="ss-two">
        <div><p class="st-note"><b><?= e(sprintf(t('Tanods, last %d days', 'Mga tanod, nakaraang %d araw'), (int) $fa['days'])) ?></b></p>
          <ul class="st-err-list"><?php foreach (array_slice((array) $fa['tanods'], 0, 8) as $x): ?>
            <li><span class="p-badge p-b-progress"><?= (int) $x['share_pct'] ?>%</span><div><b><?= e(formal_name((string) $x['name'])) ?></b><small><?= e(sprintf(t('%d dispatches · %d resolved%s', '%d dispatch · %d natapos%s'), (int) $x['assigned'], (int) $x['resolved'], $x['median_accept_minutes'] !== null ? sprintf(t(' · accepts in about %s min', ' · tumatanggap sa mga %s min'), rtrim(rtrim(number_format((float) $x['median_accept_minutes'], 1), '0'), '.')) : '')) ?></small></div></li>
          <?php endforeach; ?></ul></div>
        <div><p class="st-note"><b><?= e(t('Open cases by administrator', 'Mga bukas na kaso ayon sa administrator')) ?></b></p>
          <ul class="st-err-list"><?php foreach (array_slice((array) $fa['admins'], 0, 8) as $x): ?>
            <li><span class="p-badge p-b-progress"><?= (int) $x['share_pct'] ?>%</span><div><b><?= e(formal_name((string) $x['name'])) ?></b><small><?= e(sprintf(t('%d open cases', '%d bukas na kaso'), (int) $x['open'])) ?></small></div></li>
          <?php endforeach; ?></ul></div>
      </div>
      <p class="st-note"><?= e(t('Counts only. A tanod with the most dispatches is often the one nearest, and a low share is not a mark against anyone.', 'Mga bilang lamang. Ang tanod na may pinakamaraming dispatch ay madalas ang pinakamalapit, at ang mababang bahagi ay hindi bahid sa sinuman.')) ?></p>
    <?php endif; ?>
  </div>
</section>
<?php endif; ?>

<?php if (st_on('brgy')): ?>
<section class="st-pane" data-pane="brgy" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'info'): ?><div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash && $stFlash['level'] === 'error'): ?><div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div><?php endif; ?>
  <form method="post" enctype="multipart/form-data" class="p-card p-card-pad cmx-page" id="brgy-card">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="brgy_save">
    <p class="p-eyebrow"><?= e(t('The barangay', 'Ang barangay')) ?></p>
    <p class="p-hint"><?= e(t('Shown on the sign-in pages, in the portal\'s title, on every printed document and in the app.', 'Makikita sa sign-in, sa pamagat ng portal, sa bawat dokumentong ipi-print at sa app.')) ?></p>
    <div class="bp-row">
      <div class="bp-seal"><?= brgy_seal_img('bp-img') ?></div>
      <div class="bp-fields">
        <label class="ty-f"><span><?= e(t('Name', 'Pangalan')) ?></span><input class="p-input-plain" name="name" value="<?= e(barangay()['name']) ?>" required minlength="3" maxlength="80"></label>
        <label class="ty-f"><span><?= e(t('Place, from the smallest to the city', 'Lugar, mula sa pinakamaliit hanggang sa lungsod')) ?></span><input class="p-input-plain" name="place" value="<?= e(barangay()['place']) ?>" required minlength="3" maxlength="120"></label>
        <label class="ty-f"><span><?= e(t('A new seal (PNG, JPEG or WebP, square)', 'Bagong selyo (PNG, JPEG o WebP, parisukat)')) ?></span><input class="bp-file" type="file" name="seal[]" accept="image/png,image/jpeg,image/webp"></label>
        <?php if (barangay()['seal_url'] !== null): ?><label class="sd-c"><input type="checkbox" name="seal_shipped" value="1"> <?= e(t('Go back to the seal the portal came with', 'Ibalik ang selyong kasama ng portal')) ?></label><?php endif; ?>
      </div>
    </div>
    <div class="ss-posform ru-bar"><span class="cmx-dirty-note" aria-live="polite"><?= e(t('Unsaved changes', 'May hindi pang-save na pagbabago')) ?></span><button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Save', 'I-save')) ?></button></div>
    <script>
    (function () {
      var f = document.getElementById('brgy-card'), snap = new URLSearchParams(new FormData(f)).toString();
      function chk() { f.classList.toggle('cmx-dirty', new URLSearchParams(new FormData(f)).toString() !== snap); }
      f.addEventListener('input', chk); f.addEventListener('change', chk);
    })();
    </script>
  </form>
</section>
<?php endif; ?>

<?php if (st_on('look')): ?>
<section class="st-pane" data-pane="look" hidden>
  <div class="p-card p-card-pad st-look">
    <p class="p-eyebrow"><?= e(t('Theme and language', 'Tema at wika')) ?></p>
    <div class="st-prefs">
      <div class="st-pref"><span class="st-pref-l"><?= p_icon('i-moon', 18) ?><b><?= e(t('Theme', 'Tema')) ?></b></span>
        <div class="p-seg-mini" id="st-theme" role="group" aria-label="<?= e(t('Theme', 'Tema')) ?>">
          <button type="button" data-set-theme="light"><?= e(t('Light', 'Maliwanag')) ?></button>
          <button type="button" data-set-theme="dark"><?= e(t('Dark', 'Madilim')) ?></button>
        </div></div>
      <div class="st-pref"><span class="st-pref-l"><?= p_icon('i-dash', 18) ?><b><?= e(t('Sidebar', 'Gilid na menu')) ?></b></span>
        <div class="p-seg-mini" id="st-side" role="group" aria-label="<?= e(t('Sidebar', 'Gilid na menu')) ?>">
          <button type="button" data-mode="handle" title="<?= e(t('A small handle on its edge shrinks it to icons and back', 'Isang maliit na hawakan sa gilid ang magpapaliit nito at magbabalik')) ?>"><?= e(t('Handle', 'Hawakan')) ?></button>
          <button type="button" data-mode="hover" title="<?= e(t('Icons only; it opens when you point at it', 'Mga icon lang; bumubukas kapag tinuro mo')) ?>"><?= e(t('Hover rail', 'Riles na bumubukas')) ?></button>
        </div></div>
      <div class="st-pref"><span class="st-pref-l"><?= p_icon('i-flag', 18) ?><b><?= e(t('Language', 'Wika')) ?></b></span>
        <div class="p-seg-mini pref-lang" role="group" aria-label="<?= e(t('Language', 'Wika')) ?>">
          <button type="button" data-lang="en" aria-pressed="<?= lang() === 'en' ? 'true' : 'false' ?>" class="<?= lang() === 'en' ? 'p-on' : '' ?>"><?= lang_flag('us') ?><span>English</span></button>
          <button type="button" data-lang="fil" aria-pressed="<?= lang() === 'en' ? 'false' : 'true' ?>" class="<?= lang() === 'en' ? '' : 'p-on' ?>"><?= lang_flag('ph') ?><span>Tagalog</span></button>
        </div></div>
    </div>
  </div>
  <div class="p-card p-card-pad st-look">
    <p class="p-eyebrow"><?= e(t('Map surfaces', 'Ibabaw ng mapa')) ?></p>
    <p class="st-note" style="margin-top:0"><?= e(t('How the panels and buttons floating on the Spatial Distribution map are drawn. Glass lets the map show through; Solid is flat and plain, easier on older screens and in bright rooms. This is kept on this computer.', 'Kung paano iginuhit ang mga panel at button sa mapa. Hinahayaan ng Glass na makita ang mapa; ang Solid ay patag at simple, mas magaan sa lumang screen at sa maliwanag na silid. Nakatago ito sa computer na ito.')) ?></p>
    <div class="st-surfs" role="radiogroup" aria-label="<?= e(t('Map surfaces', 'Ibabaw ng mapa')) ?>">
      <button type="button" class="st-surf" role="radio" data-surf="glass" aria-checked="true"><span class="sv-pic g"><i></i><b></b></span><span class="ss-t"><b><?= e(t('Glass', 'Salamin')) ?></b><small><?= e(t('Frosted panels, lit edges', 'Frosted na panel, may ilaw ang gilid')) ?></small></span></button>
      <button type="button" class="st-surf" role="radio" data-surf="solid" aria-checked="false"><span class="sv-pic s"><i></i><b></b></span><span class="ss-t"><b><?= e(t('Solid', 'Buo')) ?></b><small><?= e(t('Flat graphite, no blur or gloss', 'Patag na graphite, walang blur o kinang')) ?></small></span></button>
    </div>
  </div>
  <div class="p-card p-card-pad st-places" id="places">
    <p class="p-eyebrow"><?= e(t('The barangay\'s places', 'Mga lugar ng barangay')) ?><em><?= count($places) ?></em></p>
    <p class="st-note" style="margin-top:0"><?= e(t('Search on the map and in the app finds these first: the landmarks the barangay keeps, and any place no map has, by the names people use (Other names, separated by commas). To add one, open Spatial Distribution, right-click the spot (or press and hold), and choose Add a place here. Places only, never anyone\'s home.', 'Ito ang unang nahahanap sa mapa at sa app: ang mga landmark ng barangay, at anumang lugar na wala sa mapa, sa pangalang ginagamit ng mga tao (Ibang pangalan, pinaghihiwalay ng kuwit). Para magdagdag, buksan ang Spatial Distribution, i-right-click ang lugar (o pindutin nang matagal), at piliin ang Magdagdag ng lugar dito. Mga lugar lamang, hindi kailanman ang bahay ng sinuman.')) ?></p>
    <?php if (!$places): ?>
      <p class="st-note"><?= e(t('No places yet, or they could not be read just now.', 'Wala pang lugar, o hindi mabasa ngayon.')) ?></p>
    <?php else: ?>
    <ul class="st-plist">
      <?php foreach ($places as $pl): ?>
        <li>
          <form method="post" class="st-prow">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="place_save">
            <input type="hidden" name="id" value="<?= (int) $pl['id'] ?>"><input type="hidden" name="lat" value="<?= e((string) $pl['lat']) ?>"><input type="hidden" name="lng" value="<?= e((string) $pl['lng']) ?>">
            <label class="p-sr" for="pl-n-<?= (int) $pl['id'] ?>"><?= e(t('Name', 'Pangalan')) ?></label>
            <input class="p-input-plain" id="pl-n-<?= (int) $pl['id'] ?>" name="name" maxlength="120" required value="<?= e((string) $pl['name']) ?>">
            <label class="p-sr" for="pl-k-<?= (int) $pl['id'] ?>"><?= e(t('Kind', 'Uri')) ?></label>
            <select class="p-input-plain" id="pl-k-<?= (int) $pl['id'] ?>" name="grp"><?php foreach ($kinds as $k): ?><option value="<?= e((string) $k['grp']) ?>"<?= $k['grp'] === $pl['grp'] ? ' selected' : '' ?>><?= e((string) $k['label']) ?></option><?php endforeach; ?></select>
            <label class="p-sr" for="pl-a-<?= (int) $pl['id'] ?>"><?= e(t('Other names', 'Ibang pangalan')) ?></label>
            <input class="p-input-plain" id="pl-a-<?= (int) $pl['id'] ?>" name="aliases" maxlength="300" placeholder="<?= e(t('Other names', 'Ibang pangalan')) ?>" value="<?= e(implode(', ', (array) ($pl['aliases'] ?? []))) ?>">
            <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Save', 'I-save')) ?></button>
          </form>
          <form method="post" class="st-prm">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="place_remove"><input type="hidden" name="id" value="<?= (int) $pl['id'] ?>">
            <button class="p-btn p-btn-ghost p-btn-sm" type="submit" aria-label="<?= e(t('Remove ', 'Alisin ang ') . $pl['name']) ?>"><?= e(t('Remove', 'Alisin')) ?></button>
          </form>
        </li>
      <?php endforeach; ?>
    </ul>
    <?php endif; ?>
  </div>
</section>
<?php endif; ?>

<?php if (st_on('usage')): ?>
<section class="st-pane" data-pane="usage" hidden>
  <p class="st-note"><?= e(t('Which plan each service is on and how close the barangay is to its limits. Amber at 75%, red at 90%.', 'Kung anong plano ang bawat serbisyo at gaano kalapit sa limitasyon. Dilaw sa 75%, pula sa 90%.')) ?></p>
  <div class="st-plans" id="st-plans"><p class="st-note"><?= e(t('Loading…', 'Naglo-load…')) ?></p></div>
</section>
<?php endif; ?>

<?php if (st_on('status')): ?>
<script>
(function () {
  const PLACES = <?= json_encode(SERVICE_PLACES) ?>;
  const SB_URL = <?= json_encode(supabase_url()) ?>, SB_KEY = <?= json_encode(supabase_key()) ?>;
  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const $ = id => document.getElementById(id);

  // Each service: what it does for the barangay, and what a failure means.
  const S = [
    { key: 'db',    job: T('Database', 'Database'), prov: 'Supabase', side: 'L',
      down: T('Complaints and accounts can’t be read or saved.', 'Hindi mabasa o maisave ang mga sumbong at account.') },
    { key: 'auth',  job: T('Sign-in', 'Pag-sign in'), prov: 'Supabase Auth', side: 'L',
      down: T('Nobody can sign in to the portal or the app.', 'Walang makapag-sign in sa portal o sa app.') },
    { key: 'live',  job: T('Live updates', 'Live na update'), prov: 'Supabase Realtime', side: 'L',
      down: T('New complaints won’t appear until the page is refreshed.', 'Hindi lalabas ang bagong sumbong hangga’t hindi nire-refresh.') },
    { key: 'media', job: T('Photos and videos', 'Larawan at video'), prov: 'Cloudinary', side: 'L',
      down: T('Residents’ photos and videos won’t upload or show.', 'Hindi maa-upload o makikita ang mga larawan at video.') },
    { key: 'push',  job: T('Push alerts', 'Push alert'), prov: 'Firebase, via send-dispatch-push', side: 'L',
      down: T('Push alerts to tanod phones are not going out. Call or text the tanod on duty.', 'Hindi naipapadala ang push alert sa mga tanod. Tawagan o i-text ang naka-duty.') },
    { key: 'tiles', job: T('Map tiles', 'Mapa'), prov: 'OpenFreeMap', side: 'R',
      down: T('The map shows no streets.', 'Walang kalye sa mapa.') },
    { key: 'geo',   job: T('Address lookup', 'Paghahanap ng address'), prov: 'OpenStreetMap Nominatim', side: 'R',
      down: T('New pins won’t get a street address.', 'Walang address ang bagong pin.') },
    { key: 'rain',  job: T('Rain data', 'Datos ng ulan'), prov: 'Open-Meteo · flood watch', side: 'R',
      down: T('Flood watch shows offline; flood zones stay manual.', 'Offline ang bantay-baha.') },
    { key: 'noah',  job: T('Flood zones', 'Bahaing lugar'), prov: 'Project NOAH map, stored with the portal', side: 'R',
      down: T('The flood zones can’t be drawn on the map.', 'Hindi maiguguhit ang mga bahaing lugar.') },
  ];
  const R = {};   // key -> {state: 'checking'|'ok'|'slow'|'down', ms}
  const SLOW = 1500;

  function timed(p) { const t0 = performance.now(); return p.then(ok => ({ ok, ms: Math.round(performance.now() - t0) }), () => ({ ok: false, ms: null })); }
  function reach(url) { return timed(fetch(url, { cache: 'no-store', mode: 'cors' }).then(r => r.ok)); }
  function realtime() {
    return timed(new Promise((res) => {
      let done = false; const ws = new WebSocket(SB_URL.replace(/^http/, 'ws') + '/realtime/v1/websocket?apikey=' + encodeURIComponent(SB_KEY) + '&vsn=1.0.0');
      const end = ok => { if (done) return; done = true; try { ws.close(); } catch (e) {} res(ok); };
      ws.onopen = () => end(true); ws.onerror = () => end(false); setTimeout(() => end(false), 8000);
    }));
  }
  function set(key, r) { R[key] = { state: !r.ok ? 'down' : (r.ms != null && r.ms > SLOW ? 'slow' : 'ok'), ms: r.ms }; render(); }

  async function check() {
    S.forEach(s => R[s.key] = { state: 'checking' }); render();
    const server = fetch('settings.php?check=server', { cache: 'no-store' }).then(r => r.json()).catch(() => null);
    reach('https://tiles.openfreemap.org/planet').then(r => set('tiles', r));
    reach('https://nominatim.openstreetmap.org/status?format=json').then(r => set('geo', r));
    reach('https://api.open-meteo.com/v1/forecast?latitude=14.5269&longitude=121.0155&current=precipitation').then(r => set('rain', r));
    reach('assets/map/hazards.geojson').then(r => set('noah', r));
    realtime().then(r => set('live', r));
    const sv = await server;
    ['db', 'auth', 'push', 'media'].forEach(k => set(k, sv && sv[k] ? sv[k] : { ok: false, ms: null }));
    $('st-checked').textContent = T('Checked ', 'Sinuri ') + new Date().toLocaleTimeString(window.LANG === 'fil' ? 'fil-PH' : 'en-US', { hour: 'numeric', minute: '2-digit' });
  }

  const BADGE = { ok: ['p-b-done', T('Working', 'Gumagana'), '#22c55e'], slow: ['p-b-pending', T('Slow', 'Mabagal'), '#f59e0b'], down: ['p-b-denied', T('Down', 'Hindi gumagana'), '#ef4444'], checking: ['p-b-grey', T('Checking…', 'Sinusuri…'), '#9AA1AB'] };
  const fmtMs = ms => ms == null ? '—' : ms >= 1000 ? (ms / 1000).toFixed(1) + ' s' : ms + ' ms';

  function render() {
    const st = k => (R[k] || {}).state || 'checking';
    const bad = S.filter(s => st(s.key) === 'down'), slow = S.filter(s => st(s.key) === 'slow'), busy = S.some(s => st(s.key) === 'checking');
    const tone = bad.length ? 'down' : slow.length ? 'slow' : busy ? 'checking' : 'ok';
    const b = $('st-banner'); b.dataset.tone = tone;
    const head = tone === 'checking' ? T('Checking every connection…', 'Sinusuri ang bawat koneksyon…')
      : tone === 'ok' ? T('Everything is working', 'Gumagana ang lahat')
      : [bad.length ? bad.length + T(bad.length === 1 ? ' service down' : ' services down', ' hindi gumagana') : '', slow.length ? slow.length + T(' slow', ' mabagal') : ''].filter(Boolean).join(', ');
    const why = tone === 'ok' ? T('Complaints, sign-in, photos, push alerts, maps and flood data are all reachable.', 'Naaabot ang lahat ng serbisyo.')
      : tone === 'checking' ? '' : [...bad.map(s => s.down), ...slow.map(s => s.job + T(' is answering slowly.', ' ay mabagal.'))].join(' ') + (S.length - bad.length - slow.length > 0 ? ' ' + T('Everything else is working.', 'Gumagana ang iba.') : '');
    b.innerHTML = '<span class="st-big"></span><span><b>' + esc(head) + '</b><small>' + esc(why) + '</small></span>';

    $('st-rows').innerHTML = S.map(s => { const r = R[s.key] || {}, B = BADGE[r.state || 'checking'], pl = PLACES[s.key];
      return '<tr><td><b>' + esc(s.job) + '</b><small>' + esc(s.prov) + '</small></td><td><span class="st-where"><span class="st-cc">' + esc(pl[0]) + '</span>' + esc(pl[1]) + '</span></td>' +
        '<td class="st-ms">' + (r.state === 'checking' ? '…' : s.key === 'noah' && r.state === 'ok' ? 'local' : fmtMs(r.ms)) + '</td><td><span class="p-badge ' + B[0] + '">' + esc(B[1]) + '</span></td></tr>'; }).join('');

    // The system map: the portal in the middle, a line to each service in its state's colour.
    const W = 640, H = 310, cx = 320, cy = 155, L = S.filter(s => s.side === 'L'), Rt = S.filter(s => s.side === 'R');
    const ys = (arr, i) => 20 + i * ((H - 70) / Math.max(1, arr.length - 1));
    let svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" role="img" aria-label="' + esc(T('Diagram of the portal and the services it connects to', 'Diagram ng portal at mga serbisyo')) + '">';
    const nodes = [];
    L.forEach((s, i) => nodes.push([s, 10, ys(L, i)])); Rt.forEach((s, i) => nodes.push([s, 470, ys(Rt, i)]));
    nodes.forEach(([s, x, y]) => { const r = R[s.key] || {}, c = BADGE[r.state || 'checking'][2], tx = s.side === 'L' ? x + 160 : x;
      svg += '<path class="st-flow' + (r.state === 'down' ? ' st-bad' : '') + '" stroke="' + c + '" d="M' + cx + ' ' + cy + ' C ' + (s.side === 'L' ? cx - 90 : cx + 90) + ' ' + cy + ' ' + (s.side === 'L' ? tx + 50 : tx - 50) + ' ' + (y + 15) + ' ' + tx + ' ' + (y + 15) + '"/>'; });
    svg += '<rect x="' + (cx - 75) + '" y="' + (cy - 30) + '" width="150" height="60" rx="14" fill="#00308F"/><text x="' + cx + '" y="' + (cy - 4) + '" text-anchor="middle" class="st-hub">SmartSumbong</text><text x="' + cx + '" y="' + (cy + 14) + '" text-anchor="middle" class="st-hub2">portal · Render</text>';
    const short = { db: 'Supabase', auth: 'Supabase', live: 'Supabase', media: 'Cloudinary', push: 'Firebase', tiles: 'OpenFreeMap', geo: 'Nominatim', rain: 'Open-Meteo', noah: 'Project NOAH' };
    nodes.forEach(([s, x, y]) => { const r = R[s.key] || {}, c = BADGE[r.state || 'checking'][2];
      svg += '<g class="st-node"><rect x="' + x + '" y="' + y + '" width="160" height="30" rx="8"/><circle cx="' + (x + 14) + '" cy="' + (y + 15) + '" r="4.5" fill="' + c + '"/>' +
        '<text x="' + (x + 26) + '" y="' + (y + 13) + '" class="st-t">' + esc(s.job.length > 22 ? s.job.slice(0, 21) + '…' : s.job) + '</text>' +
        '<text x="' + (x + 26) + '" y="' + (y + 25) + '" class="st-s">' + esc(short[s.key]) + ' · ' + (r.state === 'checking' ? '…' : s.key === 'noah' && r.state === 'ok' ? 'local' : fmtMs(r.ms)) + '</text></g>'; });
    $('st-map').innerHTML = svg + '</svg>';
  }

  // Plan and usage.
  const mb = b => b == null ? '—' : b >= 1073741824 ? (b / 1073741824).toFixed(2) + ' GB' : (b / 1048576).toFixed(1) + ' MB';
  function meter(label, val, pct) {
    const cls = pct == null ? '' : pct >= 90 ? 'b' : pct >= 75 ? 'w' : '';
    return '<div class="st-meter"><div class="st-lbl"><span>' + esc(label) + '</span><span>' + esc(val) + '</span></div>' +
      (pct == null ? '' : '<div class="st-bar"><i class="' + cls + '" style="width:' + Math.max(1.5, Math.min(100, pct)) + '%"></i></div>') + '</div>';
  }
  // each service's colour as an accent and a plain letter of ours; never a logo (brand rules differ)
  const ACCENT = { 'Supabase': ['S', '#3ECF8E'], 'Cloudinary': ['C', '#3448C5'], 'Render': ['R', '#6E5CF6'], 'Firebase push': ['F', '#F5A623'], 'Open-Meteo': ['O', '#2D9CDB'], 'Nominatim · OpenFreeMap': ['N', '#7EBC6F'] };
  function card(name, tier, body, catchTxt, foot) {
    const ac = ACCENT[name] || ['', '#9AA1AB'];
    return '<div class="p-card p-card-pad st-plan" style="--ac:' + ac[1] + '"><header><b><span class="st-mono" aria-hidden="true">' + ac[0] + '</span>' + esc(name) + '</b>' + (tier ? '<span class="st-tier">' + esc(tier) + '</span>' : '') + '</header>' + body +
      (catchTxt ? '<div class="st-catch">' + catchTxt + '</div>' : '') + (foot ? '<span class="st-foot">' + foot + '</span>' : '') + '</div>';
  }
  async function usage() {
    let u = null; try { u = await fetch('settings.php?usage=1', { cache: 'no-store' }).then(r => r.json()); } catch (e) {}
    if (!u) { $('st-plans').innerHTML = '<p class="st-note">' + esc(T('Usage could not be loaded. Try again.', 'Hindi ma-load. Subukan muli.')) + '</p>'; return; }
    const sb = u.supabase, P = u.plans || {}, next = new Date(); next.setMonth(next.getMonth() + 1, 1);
    const resets = T('Resets ', 'Magre-reset sa ') + next.toLocaleDateString(window.LANG === 'fil' ? 'fil-PH' : 'en-US', { month: 'short', day: 'numeric' });
    const cards = [];
    cards.push(card('Supabase', P.supabase,
      sb ? meter(T('Database', 'Database'), mb(sb.db_bytes) + ' ' + T('of', 'sa') + ' 500 MB', sb.db_bytes / 524288000 * 100)
         + meter(T('File storage', 'Imbakan'), mb(sb.storage_bytes) + ' ' + T('of', 'sa') + ' 1 GB', sb.storage_bytes / 1073741824 * 100)
         + meter(T('Active users this month', 'Aktibong user ngayong buwan'), Number(sb.active_users || 0).toLocaleString() + ' ' + T('of', 'sa') + ' 50,000', (sb.active_users || 0) / 50000 * 100)
         : '<p class="st-note">' + esc(T('Database size and active users need the system_usage function (migration 0078).', 'Kailangan ang migration 0078.')) + '</p>',
      esc(T('Free projects pause after a week with no activity. Data sent out is shown only in Supabase’s dashboard.', 'Humihinto ang libreng proyekto pagkalipas ng isang linggong walang aktibidad.')),
      esc(resets) + ' · ' + esc(T('limits shown are the Free plan’s', 'limitasyon ng Free plan'))));
    const cl = u.cloudinary, ph = u.photos;
    cards.push(card('Cloudinary', cl && cl.plan ? cl.plan : P.cloudinary,
      (cl && cl.credits_limit ? meter(T('Monthly credits', 'Buwanang credit'), (+cl.credits_used).toFixed(1) + ' ' + T('of', 'sa') + ' ' + cl.credits_limit, cl.credits_used / cl.credits_limit * 100) : '')
      + (ph ? meter(T('Complaint photos on record', 'Mga larawan sa talaan'), ph.files.toLocaleString() + ' · ' + mb(ph.bytes), null) : ''),
      cl ? esc(T('1 credit = 1 GB stored, 1 GB served or 1,000 resizes.', '1 credit = 1 GB imbak, 1 GB ipinadala o 1,000 resize.'))
         : esc(T('Credits aren’t connected yet: add CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET to the server’s environment in Render to see them here.', 'Idagdag ang CLOUDINARY_API_KEY at CLOUDINARY_API_SECRET sa server.')),
      esc(T('Photos on record are counted from the database', 'Binilang mula sa database'))));
    cards.push(card('Render', P.render, '',
      esc(T('On the Free plan the portal sleeps after 15 minutes with no visitors; the next visit takes about a minute to wake it. Open it a minute before presenting.', 'Natutulog ang portal pagkalipas ng 15 minutong walang bisita.')),
      esc(T('750 instance hours a month on the Free plan', '750 oras bawat buwan sa Free plan'))));
    cards.push(card(T('Firebase push', 'Firebase push'), T('No cost', 'Walang bayad'),
      u.alerts != null ? meter(T('Dispatch alerts this month', 'Dispatch alert ngayong buwan'), Number(u.alerts).toLocaleString(), null) : '', '',
      esc(T('Cloud Messaging has no usage charge', 'Walang singil ang Cloud Messaging'))));
    cards.push(card('Open-Meteo', 'Free', meter(T('Rain checks allowed', 'Pinapayagang pagsuri'), T('10,000 a day', '10,000 bawat araw'), null), '',
      esc(T('Free for non-commercial use · each open map checks every 10 minutes', 'Libre para sa hindi pangkomersyo · bawat 10 minuto'))));
    cards.push(card('Nominatim · OpenFreeMap', 'Free', meter(T('Address lookups', 'Paghahanap ng address'), T('at most 1 per second', 'hanggang 1 bawat segundo'), null), '',
      esc(T('OpenFreeMap tiles have no limit', 'Walang limitasyon ang OpenFreeMap'))));
    $('st-plans').innerHTML = cards.join('');
  }


  document.querySelectorAll('.st-tabs [data-st]').forEach(b => b.addEventListener('click', () => {
    document.querySelectorAll('.st-tabs [data-st]').forEach(x => x.classList.toggle('p-on', x === b));
    document.querySelectorAll('.st-pane').forEach(p => p.hidden = p.dataset.pane !== b.dataset.st);
    const live = b.dataset.st === 'status' || b.dataset.st === 'usage'; $('st-check').hidden = !live; $('st-checked').hidden = !live;
  }));
  $('st-check').addEventListener('click', () => { check(); usage(); });
  check(); usage();
})();
</script>
<?php else: ?>
<script>
document.querySelectorAll('.st-tabs [data-st]').forEach(function (b) { b.addEventListener('click', function () {
  document.querySelectorAll('.st-tabs [data-st]').forEach(function (x) { x.classList.toggle('p-on', x === b); });
  document.querySelectorAll('.st-pane').forEach(function (p) { p.hidden = p.dataset.pane !== b.dataset.st; });
}); });
</script>
<?php endif; ?>
<?php if (st_on('admins')): ?>
<script>
(function () {
  const $ = id => document.getElementById(id);
  // Administrators: search and position filter, an Edit button that opens the position and committee, an explicit Save
  (function () {
    const q = $('jp-q'), rs = $('jp-role'), rows = [...document.querySelectorAll('#jp-rows tr.ss-arow')];
    if (!q || !rs) return;
    const apply = () => {
      const t = q.value.trim().toLowerCase(), r = rs.value; let n = 0;
      rows.forEach(tr => { const ok = (!t || tr.dataset.name.includes(t)) && (!r || tr.dataset.role === r); tr.hidden = !ok; const ed = document.querySelector('tr.ss-erow[data-for="' + tr.dataset.id + '"]'); if (ed && !ok) ed.hidden = true; if (ok) n++; });
      $('jp-none').hidden = n > 0;
    };
    q.form.addEventListener('submit', function (e) { e.preventDefault(); });
    q.addEventListener('input', apply); rs.addEventListener('change', apply);
    const add = $('jp-add'), card = $('jp-addcard');
    add.addEventListener('click', () => { card.hidden = !card.hidden; add.setAttribute('aria-expanded', String(!card.hidden)); if (!card.hidden) { card.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); const f = card.querySelector('input[name=first_name]'); if (f) f.focus(); } });
    document.addEventListener('click', e => {
      const b = e.target.closest('[data-edit]'); if (!b) return;
      const id = b.dataset.edit, ed = document.querySelector('tr.ss-erow[data-for="' + id + '"]'), btn = document.querySelector('.ss-edit-btn[data-edit="' + id + '"]');
      if (!ed) return; ed.hidden = !ed.hidden; if (btn) btn.setAttribute('aria-expanded', String(!ed.hidden));
    });
    document.querySelectorAll('.ss-eform [data-role-sel]').forEach(role => {
      const f = role.form, comm = f.querySelector('[data-comm-sel]'), hint = f.querySelector('[data-hint]');
      const needs = () => role.value === 'kagawad' || role.value === 'secretary';   // 0151: a secretary works in a committee, as its moderator
      role.addEventListener('change', () => { comm.disabled = !needs(); if (!needs()) { comm.value = ''; comm.dispatchEvent(new Event('change', { bubbles: true })); } hint.hidden = true; });
      f.addEventListener('submit', e => { if (needs() && !comm.value) { e.preventDefault(); hint.hidden = false; const cb = comm.parentNode.querySelector('.sdp-btn'); if (cb) cb.focus(); } });
    });
  })();
})();
</script>
<?php endif; ?>
<script>
// Theme: Light or Dark, kept in this browser (the sidebar switch moved here, 14 Oct).
(function () {
  var wrap = document.getElementById('st-theme'); if (!wrap) return;
  var root = document.documentElement;
  function paint() { var cur = root.getAttribute('data-theme') === 'dark' ? 'dark' : 'light'; wrap.querySelectorAll('button').forEach(function (b) { b.classList.toggle('p-on', b.dataset.setTheme === cur); b.setAttribute('aria-pressed', String(b.dataset.setTheme === cur)); }); }
  wrap.addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    root.setAttribute('data-theme', b.dataset.setTheme); root.setAttribute('data-bs-theme', b.dataset.setTheme);
    try { localStorage.setItem('ss-theme', b.dataset.setTheme); } catch (x) {}
    paint(); window.dispatchEvent(new CustomEvent('themechange', { detail: b.dataset.setTheme }));
  });
  paint();
})();
</script>
<script>
// Sidebar: a handle on its edge, or a rail that opens when you point at it; kept in this browser.
(function () {
  var wrap = document.getElementById('st-side'); if (!wrap) return;
  var root = document.documentElement;
  function mode() { try { return localStorage.getItem('ss-side-mode') === 'hover' ? 'hover' : 'handle'; } catch (e) { return 'handle'; } }
  function paint() { var m = mode(); wrap.querySelectorAll('button').forEach(function (b) { b.classList.toggle('p-on', b.dataset.mode === m); b.setAttribute('aria-pressed', String(b.dataset.mode === m)); }); }
  wrap.addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    try { localStorage.setItem('ss-side-mode', b.dataset.mode); } catch (x) {}
    var min = false; try { min = localStorage.getItem('ss-side') === 'min'; } catch (x) {}
    if (b.dataset.mode === 'hover') root.setAttribute('data-side', 'hover'); else if (min) root.setAttribute('data-side', 'min'); else root.removeAttribute('data-side');
    paint(); window.dispatchEvent(new Event('resize'));
  });
  paint();
})();
</script>
<script>
// Back on the Administrators tab after adding or resetting.
// #places is a card inside Appearance: open that tab, then bring the card into view
// A tab that moved to another page (30 Oct 2026) sends the old link on to it.
var stOwner = <?= json_encode(array_merge(...array_map(fn ($p) => array_fill_keys($p['tabs'], $p['file']), array_values(ST_PAGES)))) ?>;
var stTab = location.hash === '#places' ? 'look' : location.hash.slice(1);
if (stTab && stOwner[stTab] && !document.querySelector('.st-tabs [data-st="' + stTab + '"]')) { location.replace(stOwner[stTab] + location.search + location.hash); }
else if (stTab) { var b = document.querySelector('.st-tabs [data-st="' + stTab + '"]'); if (b) b.click(); if (location.hash === '#places') document.getElementById('places').scrollIntoView(); }
if (!document.querySelector('.st-pane:not([hidden])')) { var f = document.querySelector('.st-tabs [data-st]'); if (f) f.click(); }
</script>
<script>
// Map surfaces: Glass or Solid, kept in this browser.
(function () {
  var btns = document.querySelectorAll('.st-surf'); if (!btns.length) return;
  function paint() { var solid = document.documentElement.getAttribute('data-surface') === 'solid'; btns.forEach(function (b) { b.setAttribute('aria-checked', String((b.dataset.surf === 'solid') === solid)); }); }
  btns.forEach(function (b) { b.addEventListener('click', function () {
    var solid = b.dataset.surf === 'solid';
    if (solid) document.documentElement.setAttribute('data-surface', 'solid'); else document.documentElement.removeAttribute('data-surface');
    try { localStorage.setItem('ss-surface', solid ? 'solid' : 'glass'); } catch (e) { /* kept for this visit only */ }
    paint();
  }); });
  paint();
})();
</script>
<?php if ($stPage === 'control') { app_editor_end($catOpts ?? [], $hlTop ?? [], $hlKids ?? [], $hlNums ?? [], $switches ?? []); } echo sd_chip_script(); layout_foot(); ?>
