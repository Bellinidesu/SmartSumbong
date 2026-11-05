<?php
/**
 * Edit Profile — Figma "Edit profile" (12:6775) and its editing,
 * cancel and save states (12:6938, 12:7185, 12:7497).
 *
 * The design shows four fields and one Edit Profile button. Two of the
 * four are not editable here, for reasons worth stating rather than
 * silently greying out:
 *
 *  - Email is the sign-in identity. Changing it means changing it in
 *    GoTrue, confirming the new address, and only then updating
 *    public.users.email — three steps that can half-fail and leave an
 *    account whose login and profile disagree. Until that flow is built
 *    properly it is read-only.
 *  - Role and verification are blocked by guard_privileged_user_fields
 *    at the database level anyway. An admin editing their own row cannot
 *    promote or verify themselves, and that is deliberate.
 *
 * Password change goes through GoTrue, not the users table. Supabase
 * wants a recent session for it, so the form re-authenticates with the
 * current password first — which also stops someone changing the
 * password on an unattended machine.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/alerts.php';
require_once __DIR__ . '/includes/forwarding.php';
require_once __DIR__ . '/includes/personnel_committees.php';

$admin = require_admin();
$db    = db();

/**
 * True when this admin signs in with the phone-derived address (0021),
 * i.e. they were promoted from a resident or tanod account. For them
 * mobile_number is not contact detail: the mobile apps derive the login
 * from it, and auth.users.email is not updated when it changes, so
 * editing it here locked them out of the app. That is the exact failure
 * 0026 closes for everyone else; admins bypass that trigger, so this
 * page has to hold the line itself. Null when it could not be checked.
 */
function signs_in_by_phone(Supabase $db): ?bool
{
    try {
        $email = (string) (auth_user_once($db)['email'] ?? '');
    } catch (Throwable) {
        return null;
    }
    return $email === '' ? null : str_ends_with(strtolower($email), '@auth.smartsumbong.local');
}

/** The signed-in user from GoTrue, asked once per page (speed, 7 Oct). */
function auth_user_once(Supabase $db): array
{
    static $u = null;
    return $u ??= $db->authUser();
}

session_start_once();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $flash = null;
    $level = 'ok';

    if (!csrf_check($_POST['csrf'] ?? null)) {
        $flash = t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.');
        $level = 'error';
    } else {
        try {
            // Figma "Editing profile" (12:6938) is one form with one Save:
            // details and, when any password box is filled, the password.
            // The older single-purpose actions still work the same way.
            $action = (string) ($_POST['action'] ?? '');
            if (!in_array($action, ['profile', 'details', 'password'], true)) {
                throw new SupabaseError(t('Unknown action.', 'Hindi kilalang aksyon.'));
            }
            $current = (string) ($_POST['current_password'] ?? '');
            $new     = (string) ($_POST['new_password'] ?? '');
            $confirm = (string) ($_POST['confirm_password'] ?? '');
            $doDetails  = $action !== 'password';
            $doPassword = $action === 'password'
                || ($action === 'profile' && ($current !== '' || $new !== '' || $confirm !== ''));

            // Everything is checked before anything is written, so a wrong
            // current password or a bad mobile number changes nothing.
            $patch = null;
            if ($doDetails) {
                // Rose: asked as First / Last name, stored "Last, First" like the app.
                $first  = trim((string) ($_POST['first_name'] ?? ''));
                $last   = trim((string) ($_POST['last_name'] ?? ''));
                $name   = isset($_POST['first_name'])
                    ? ($last !== '' ? $last . ', ' . $first : $first)
                    : trim((string) ($_POST['full_name'] ?? ''));
                $mobile = trim((string) ($_POST['mobile_number'] ?? ''));

                if (mb_strlen($name) < 2 || (isset($_POST['first_name']) && $first === '')) {
                    throw new SupabaseError(t('Please enter your full name.', 'Ilagay ang iyong buong pangalan.'));
                }
                // Stored as +639XXXXXXXXX (0021), which is what the field
                // is prefilled with — the old 09-only pattern rejected
                // that prefilled value, so Save failed even when only
                // the name was changed. Either form is accepted and
                // saved in the stored form.
                if (!preg_match('/^(?:09|\+639)(\d{9})$/', $mobile, $mm)) {
                    throw new SupabaseError(t('Mobile number must be 11 digits starting 09.', 'Dapat 11 digit ang mobile number at nagsisimula sa 09.'));
                }
                $mobile = '+639' . $mm[1];

                $stored = $db->select('users', [
                    'select' => 'mobile_number',
                    'id'     => 'eq.' . $admin['id'],
                    'limit'  => '1',
                ])[0]['mobile_number'] ?? null;

                $patch = ['full_name' => $name];
                // Ace (6 Oct 2026): an admin's own photo. Shown on the portal
                // only; residents always see "Barangay" in chat.
                if (!empty($_POST['remove_avatar'])) {
                    $patch['avatar_url'] = null;
                } elseif ($pic = cloudinary_upload_files('avatar', 1, 'selfies')) {
                    $patch['avatar_url'] = $pic[0]['media_url'];
                }
                if ($mobile !== $stored) {
                    $byPhone = signs_in_by_phone($db);
                    if ($byPhone === null) {
                        throw new SupabaseError(t('Your sign-in details could not be checked, so the mobile number was not changed. Please try again.',
                            'Hindi masuri ang iyong sign-in, kaya hindi pinalitan ang mobile number. Subukan muli.'));
                    }
                    if ($byPhone) {
                        throw new SupabaseError(t('Your mobile number is how you sign in to the Smart Sumbong app, so it cannot be changed here. Nothing was changed.',
                            'Ang iyong mobile number ang ginagamit mo sa pag-sign in sa Smart Sumbong app, kaya hindi ito mapapalitan dito. Walang binago.'));
                    }
                    $patch['mobile_number'] = $mobile;
                }
            }

            if ($doPassword) {
                if (mb_strlen($new) < 8) {
                    throw new SupabaseError(t('The new password must be at least 8 characters.', 'Dapat hindi bababa sa 8 karakter ang bagong password.'));
                }
                if ($new !== $confirm) {
                    throw new SupabaseError(t('The two new passwords do not match.', 'Hindi magkatugma ang dalawang bagong password.'));
                }
                if ($new === $current) {
                    throw new SupabaseError(t('The new password is the same as the current one.', 'Kapareho ng kasalukuyang password ang bago.'));
                }
                // Proves the person at the keyboard is the account holder.
                Supabase::signIn($admin['email'], $current);
            }

            // 0157: the banner: a preset, a colour, or their own picture moved up or down to frame it
            if ($doDetails && isset($_POST['banner_preset'])) {
                $bp = (string) $_POST['banner_preset'];
                if (!in_array($bp, ['sidebar', 'contour', 'solid', 'committee', 'photo'], true)) { $bp = 'sidebar'; }
                $bUrl = null;
                if ($bp === 'photo' && ($bpic = cloudinary_upload_files('banner', 1, 'avatars'))) { $bUrl = $bpic[0]['media_url']; }
                $banner = ['p_preset' => $bp, 'p_colour' => $bp === 'solid' ? (string) ($_POST['banner_colour'] ?? '') : null, 'p_url' => $bUrl, 'p_y' => (int) ($_POST['banner_y'] ?? 50)];
            }

            if ($patch !== null) {
                $db->update('users', ['id' => 'eq.' . $admin['id']], $patch);
                $_SESSION[SESSION_KEY]['full_name'] = $patch['full_name'];
                if (array_key_exists('avatar_url', $patch)) {
                    $_SESSION[SESSION_KEY]['avatar_url'] = $patch['avatar_url'];
                }
            }
            if (isset($banner)) {
                $db->rpc('set_my_banner', $banner);
            }
            if ($doPassword) {
                $db->updateAuthUser(['password' => $new]);
            }

            $flash = match (true) {
                $doDetails && $doPassword => t('Profile updated. The new password applies the next time you sign in.', 'Na-update ang profile. Gagana ang bagong password sa susunod mong pag-sign in.'),
                $doPassword               => t('Password changed. It applies the next time you sign in.', 'Napalitan ang password. Gagana ito sa susunod mong pag-sign in.'),
                default                   => t('Profile updated.', 'Na-update ang profile.'),
            };
        } catch (SupabaseError $ex) {
            // GoTrue answers a wrong password with "Invalid login
            // credentials" specifically -- matched on that exact phrase
            // (not just "credential") so an unrelated failure elsewhere in
            // this action doesn't get relabeled as a wrong current password.
            $msg = safe_error($ex);
            $flash = str_contains(strtolower($msg), 'invalid login')
                ? t('That current password is not right.', 'Mali ang kasalukuyang password.')
                : $msg;
            $level = 'error';
        }
    }

    $_SESSION['flash'] = ['text' => $flash, 'level' => $level];
    header('Location: profile.php');
    exit;
}

$flash = $_SESSION['flash'] ?? null;
unset($_SESSION['flash']);

$error = null;
$me    = null;
$browsers = [];

try {
    $rows = $db->select('users', [
        'select' => 'id,full_name,email,mobile_number,role,verification_status,created_at,avatar_url,'
                  . 'muted_notification_kinds,push_scope,push_quiet_from,push_quiet_to,push_quiet_urgent,'
                  . 'official_role,committee,admin_tier,banner_preset,banner_colour,banner_url,banner_y',
        'id'     => 'eq.' . $admin['id'],
        'limit'  => '1',
    ]);
    $me = $rows[0] ?? null;
    // their browsers with alerts on (0136); row-level security shows only their own
    $browsers = $db->select('web_push_subscriptions', ['select' => 'id,endpoint,label,created_at,last_ok_at', 'order' => 'created_at.desc']);
} catch (SupabaseError $ex) {
    $error = safe_error($ex);
}

// Knowing when the account was last used is how someone notices it was
// used by somebody else. Never worth failing the page over.
$lastSeen = null;
try {
    $lastSeen = auth_user_once($db)['last_sign_in_at'] ?? null;
} catch (Throwable) {
}
// Locked unless positively known to be safe to change.
$mobileLocked = signs_in_by_phone($db) !== false;

$editing = isset($_GET['edit']);

// 0157: today's punch card, for a Kagawad or a staff member
$punchToday = null;
if (is_scoped()) {
    try { $pc = (array) $db->rpc('punch_cards', ['p_days' => 1, 'p_user' => $admin['id']]); $punchToday = $pc[0]['days'][0] ?? null; } catch (SupabaseError) {}
}

/** The profile banner's look: the sidebar colour (default), the contour pattern, a solid colour, the committee's, or a picture. */
function profile_banner_style(array $me): string
{
    $preset = (string) ($me['banner_preset'] ?? 'sidebar');
    $com = (string) ($me['committee'] ?? '');
    return match ($preset) {
        'contour'   => 'background:var(--p-side-a) url(assets/img/texture-contours.webp) center/cover;background-blend-mode:soft-light',
        'solid'     => 'background:' . e((string) ($me['banner_colour'] ?? '#00308F')),
        'committee' => 'background:' . e($com !== '' ? committee_colour($com) : (barangay()['super_colour'] ?? SUPER_BLUE)),
        'photo'     => !empty($me['banner_url']) ? 'background:#222 url(' . e(cld_thumb((string) $me['banner_url'], 1600)) . ') center ' . (int) ($me['banner_y'] ?? 50) . '%/cover' : '',
        default     => '',
    };
}

$pfTitle = $editing ? t('Edit Profile', 'I-edit ang Profile') : t('Profile', 'Aking Profile');
layout_head($pfTitle, 'profile.php');
?>
<div class="p-topbar"><h1><?= e($pfTitle) ?></h1></div>

<?php if ($flash): ?>
  <div class="p-flash p-flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
<?php endif; ?>

<?php if ($error || !$me): ?>
  <div class="p-flash p-flash--error" role="alert"><?= e($error ?? t('Your profile could not be loaded.', 'Hindi ma-load ang iyong profile.')) ?></div>
  <?php layout_foot(); exit; ?>
<?php endif; ?>

<?php
$shown    = formal_name($me['full_name']);  // a profile is a record: "Lediac, Ace"
$parts    = preg_split('/\s+/', trim($shown)) ?: [];
$initials = admin_initials((string) $me['full_name']);
$pfRank = admin_ranks()[(string) ($me['id'] ?? '')] ?? rank_of($me['official_role'] ?? null);
$comma    = strpos((string) $me['full_name'], ',');
$firstVal = $comma > 0 ? trim(substr($me['full_name'], $comma + 1)) : (string) $me['full_name'];
$lastVal  = $comma > 0 ? trim(substr($me['full_name'], 0, $comma)) : '';
$change   = fn(string $field) => '<a class="ss-pf-change" href="profile.php?edit=1#' . $field . '">' . e(t('Change', 'Palitan')) . '</a>';
?>
<!-- Ace (7 Oct): banner header (idea A) over settings rows (idea B). -->
<?php if (!$editing): ?>
<section class="p-card ss-pf-head">
  <div class="ss-pf-banner<?= in_array($me['banner_preset'] ?? 'sidebar', ['photo', 'contour'], true) ? ' ss-pf-banner--plain' : '' ?>" id="ss-pf-banner" aria-hidden="true" style="<?= profile_banner_style($me) ?>"></div>
  <div class="ss-pf-id">
    <?php if (!empty($me['avatar_url'])): ?><img class="ss-pf-av" data-r="<?= e($pfRank) ?>" src="<?= e(cld_thumb($me['avatar_url'], 240, true)) ?>" alt="" id="ss-photo-preview">
    <?php else: ?><span class="ss-pf-av ss-pf-ini" data-r="<?= e($pfRank) ?>" id="ss-photo-preview"><?= e($initials) ?></span><?php endif; ?>
    <div class="ss-pf-who">
      <h2><?= e($shown) ?></h2>
      <div class="p-badges">
        <?= rank_chip(($me['admin_tier'] ?? '') === 'committee' && empty($me['official_role']) ? 'kagawad' : ($me['official_role'] ?? null)) ?>
        <span class="p-badge p-b-progress"><?= e(access_label()) ?></span>
        <?php if (!empty($me['committee'])): ?><?= committee_pill((string) $me['committee']) ?><?php endif; ?>
      </div>
    </div>
    <div class="ss-pf-act">
      <?php if (!$editing): ?>
        <a class="p-btn p-btn-orange" href="profile.php?edit=1"><?= p_icon('i-gear', 16) ?><?= e(t('Edit profile', 'I-edit ang profile')) ?></a>
      <?php endif; ?>
    </div>
  </div>
</section>
<?php endif; ?>

<?php if (!$editing): ?>
<div class="pf-grid"><div class="pf-left">
  <p class="p-eyebrow ss-pf-sec"><?= e(t('Your details', 'Iyong mga detalye')) ?></p>
  <div class="p-card ss-pf-rows">
    <div class="ss-pf-row"><span class="ss-pf-l"><?= e(t('Full name', 'Buong pangalan')) ?></span><span class="ss-pf-v"><?= e($shown) ?></span><?= $change('first_name') ?></div>
    <div class="ss-pf-row"><span class="ss-pf-l"><?= e(t('Mobile number', 'Mobile number')) ?></span>
      <span class="ss-pf-v"><?= trim((string) ($me['mobile_number'] ?? '')) === '' ? '<span class="p-sub">' . e(t('Not set', 'Wala pa')) . '</span>' : e(preg_replace('/^\+63(\d{3})(\d{3})(\d{4})$/', '0$1 $2 $3', (string) $me['mobile_number'])) ?><?php if ($mobileLocked): ?><small><?= e(t('You sign in to the app with it, so it stays as is.', 'Ito ang pang-sign in mo sa app, kaya hindi ito pinapalitan.')) ?></small><?php endif; ?></span>
      <?= $mobileLocked ? '<span></span>' : $change('mobile_number') ?></div>
    <div class="ss-pf-row"><span class="ss-pf-l"><?= e(t('Email', 'Email')) ?></span>
      <span class="ss-pf-v"><?= e($me['email']) ?><small><?= e(t('Your sign-in, and where password links are sent.', 'Ang iyong pang-sign in, at dito ipinapadala ang password link.')) ?></small></span><span></span></div>
    <div class="ss-pf-row"><span class="ss-pf-l"><?= e(t('Password', 'Password')) ?></span><span class="ss-pf-v ss-pf-dots">••••••••</span><?= $change('current_password') ?></div>
  </div>

  <?php if ($punchToday !== null): ?>
  <p class="p-eyebrow ss-pf-sec"><?= e(t('Your punch card today', 'Ang iyong punch card ngayon')) ?></p>
  <div class="p-card p-card-pad pc-today pf-punch">
    <div><small><?= e(t('In today', 'Pasok ngayon')) ?></small><b><?= e(punch_time($punchToday['first_in'] ?? null)) ?></b></div>
    <div><small><?= e(t('Out', 'Labas')) ?></small><b><?= e(!empty($punchToday['first_in']) && empty($punchToday['last_out']) ? t('Still in', 'Nasa loob pa') : punch_time($punchToday['last_out'] ?? null)) ?></b></div>
    <div><small><?= e(t('Cases touched', 'Mga kasong hinawakan')) ?></small><b><?= (int) ($punchToday['touched'] ?? 0) ?></b></div>
  </div>
  <?php endif; ?>

  <p class="p-eyebrow ss-pf-sec"><?= e(t('Account', 'Account')) ?></p>
  <div class="p-card ss-pf-rows">
    <div class="ss-pf-row"><span class="ss-pf-l"><?= e(t('Role', 'Tungkulin')) ?></span><span class="ss-pf-v"><?= e(t('Barangay administrator', 'Administrador ng barangay')) ?></span><span></span></div>
    <div class="ss-pf-row"><span class="ss-pf-l"><?= e(t('Account created', 'Ginawa ang account')) ?></span><span class="ss-pf-v"><?= e(long_datetime($me['created_at'])) ?></span><span></span></div>
    <?php if ($lastSeen): ?>
      <div class="ss-pf-row"><span class="ss-pf-l"><?= e(t('Last signed in', 'Huling pag-sign in')) ?></span><span class="ss-pf-v"><?= e(long_datetime($lastSeen)) ?></span><span></span></div>
    <?php endif; ?>
  </div>

</div><div class="pf-right">
  <?php
  // Alerts (0136): each person sets up what reaches them, on this browser and in the app on their phone.
  $alMuted = (array) ($me['muted_notification_kinds'] ?? []);
  $alFrom  = $me['push_quiet_from'] ?? null;
  $alTo    = $me['push_quiet_to'] ?? null;
  $alHour  = static fn (int $h): string => date('g A', mktime($h, 0, 0));
  try { $vapid = env('VAPID_PUBLIC_KEY', ''); } catch (Throwable) { $vapid = ''; }
  ?>
  <p class="p-eyebrow ss-pf-sec" id="alerts"><?= e(t('Alerts', 'Mga alerto')) ?></p>
  <div class="p-card p-card-pad ss-al" id="ss-al" data-vapid="<?= e($vapid) ?>" data-csrf="<?= e(csrf_token()) ?>">
    <div class="ss-al-here">
      <span class="ss-al-ico" aria-hidden="true"><?= p_icon('i-bell', 20) ?></span>
      <div class="ss-al-what"><b><?= e(t('This browser', 'Ang browser na ito')) ?></b><small id="ss-al-state"><?= e($vapid === '' ? t('Browser alerts are not set up on this server yet.', 'Hindi pa naka-set up ang browser alerts sa server na ito.') : t('Checking…', 'Sinusuri…')) ?></small></div>
      <div class="ss-al-btns">
        <button type="button" class="p-btn p-btn-orange p-btn-sm" id="ss-al-on" hidden><?= e(t('Turn on alerts here', 'Buksan ang alerto rito')) ?></button>
        <button type="button" class="p-btn p-btn-ghost p-btn-sm" id="ss-al-off" hidden><?= e(t('Turn off here', 'Isara rito')) ?></button>
        <button type="button" class="p-btn p-btn-ghost p-btn-sm" id="ss-al-test"><?= e(t('Send me a test', 'Padalhan ako ng test')) ?></button>
      </div>
    </div>

    <p class="ss-al-h"><?= e(t('What to alert me about', 'Ano ang ia-alerto sa akin')) ?></p>
    <div class="ss-al-kinds">
      <?php foreach (alert_kinds() as $k => [$name, $about]): ?>
        <label class="p-pub"><span><b><?= e($name) ?></b><small><?= e($about) ?></small></span><input type="checkbox" role="switch" data-kind="<?= e($k) ?>"<?= in_array($k, $alMuted, true) ? '' : ' checked' ?>></label>
      <?php endforeach; ?>
    </div>

    <div class="ss-al-pair">
      <div>
        <p class="ss-al-h" id="ss-al-scope-l"><?= e(t('Which cases', 'Aling mga kaso')) ?></p>
        <div class="p-seg-mini" role="radiogroup" aria-labelledby="ss-al-scope-l" id="ss-al-scope">
          <button type="button" role="radio" data-scope="all" aria-checked="<?= ($me['push_scope'] ?? 'all') === 'all' ? 'true' : 'false' ?>"<?= ($me['push_scope'] ?? 'all') === 'all' ? ' class="p-on"' : '' ?>><?= e(t('Every case', 'Lahat ng kaso')) ?></button>
          <button type="button" role="radio" data-scope="mine" aria-checked="<?= ($me['push_scope'] ?? '') === 'mine' ? 'true' : 'false' ?>"<?= ($me['push_scope'] ?? '') === 'mine' ? ' class="p-on"' : '' ?>><?= e(t('Only cases I handle', 'Mga hawak ko lamang')) ?></button>
        </div>
      </div>
      <div>
        <p class="ss-al-h"><?= e(t('Quiet hours', 'Tahimik na oras')) ?></p>
        <div class="ss-al-quiet">
          <label class="p-sr" for="ss-al-from"><?= e(t('Quiet from', 'Tahimik mula')) ?></label>
          <select class="p-input-plain" id="ss-al-from"><option value=""><?= e(t('Off', 'Wala')) ?></option><?php for ($h = 0; $h < 24; $h++): ?><option value="<?= $h ?>"<?= $alFrom !== null && (int) $alFrom === $h ? ' selected' : '' ?>><?= e($alHour($h)) ?></option><?php endfor; ?></select>
          <span class="ss-al-to" id="ss-al-tow"><span aria-hidden="true"><?= e(t('to', 'hanggang')) ?></span>
          <label class="p-sr" for="ss-al-to"><?= e(t('Quiet until', 'Tahimik hanggang')) ?></label>
          <select class="p-input-plain" id="ss-al-to"><?php for ($h = 0; $h < 24; $h++): ?><option value="<?= $h ?>"<?= ($alTo !== null ? (int) $alTo : 6) === $h ? ' selected' : '' ?>><?= e($alHour($h)) ?></option><?php endfor; ?></select></span>
        </div>
        <label class="p-check ss-al-urgent"><input type="checkbox" id="ss-al-urgent"<?= ($me['push_quiet_urgent'] ?? true) ? ' checked' : '' ?>> <?= e(t('Still alert me for urgent cases', 'Alertuhan pa rin ako sa urgent na kaso')) ?></label>
      </div>
    </div>

    <?php if ($browsers): ?>
      <p class="ss-al-h"><?= e(t('Your browsers with alerts on', 'Mga browser mong may alerto')) ?></p>
      <ul class="ss-al-list" id="ss-al-list">
        <?php foreach ($browsers as $b): ?>
          <li data-endpoint="<?= e((string) $b['endpoint']) ?>"><span><b><?= e((string) ($b['label'] ?: t('A browser', 'Isang browser'))) ?></b><small><?= e(t('Since ', 'Mula ') . long_datetime($b['created_at'])) ?><?= !empty($b['last_ok_at']) ? e(t(' · last alert ', ' · huling alerto ') . long_datetime($b['last_ok_at'])) : '' ?></small></span>
            <button type="button" class="p-btn p-btn-ghost p-btn-sm" data-remove><?= e(t('Remove', 'Alisin')) ?></button></li>
        <?php endforeach; ?>
      </ul>
    <?php endif; ?>
    <p class="st-note ss-al-note"><span id="ss-al-saved" role="status"></span><?= e(t('These choices also apply to the SmartSumbong app on your phone. Notifications here in the portal always keeps everything; only the alert is held back.', 'Ganito rin sa SmartSumbong app sa telepono mo. Laging kumpleto ang Notifications dito sa portal; ang alerto lamang ang hindi ipinapadala.')) ?></p>
  </div>
  <script src="assets/js/alerts.js?v=<?= e(asset_version('../js/alerts.js')) ?>" defer></script>
</div></div>
<?php else: ?>
  <form method="post" id="profile-form" enctype="multipart/form-data" class="pf-edit">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
    <input type="hidden" name="action" value="profile">
    <nav class="pf-menu" aria-label="<?= e(t('Edit profile', 'I-edit ang profile')) ?>">
      <a href="#pf-details" class="on"><?= p_icon('i-users', 18) ?><span><b><?= e(t('Your details', 'Iyong mga detalye')) ?></b><small><?= e(t('Name, mobile, email', 'Pangalan, mobile, email')) ?></small></span></a>
      <a href="#pf-look"><?= p_icon('i-cam', 18) ?><span><b><?= e(t('Profile picture', 'Larawan sa profile')) ?></b><small><?= e(t('Your face, in your role colour', 'Ang iyong mukha, sa kulay ng tungkulin')) ?></small></span></a>
      <a href="#pf-cover"><?= p_icon('i-doc', 18) ?><span><b><?= e(t('Cover photo', 'Larawan sa itaas')) ?></b><small><?= e(t('The banner on your profile', 'Ang banner ng iyong profile')) ?></small></span></a>
      <a href="#pf-password"><?= p_icon('i-shield', 18) ?><span><b><?= e(t('Password', 'Password')) ?></b><small><?= e(t('How you sign in', 'Paano ka nagsa-sign in')) ?></small></span></a>
    </nav>
    <div class="pf-sections">
      <section class="p-card p-card-pad pf-sec" id="pf-details"><h3 class="pf-h"><?= e(t('Your details', 'Iyong mga detalye')) ?></h3>
    <div class="ss-pf-2">
      <label class="p-field" for="first_name"><span><?= e(t('First name', 'Pangalan')) ?></span><div class="p-input"><input type="text" id="first_name" name="first_name" required maxlength="60" value="<?= e($firstVal) ?>"></div></label>
      <label class="p-field" for="last_name"><span><?= e(t('Last name', 'Apelyido')) ?></span><div class="p-input"><input type="text" id="last_name" name="last_name" maxlength="60" value="<?= e($lastVal) ?>"></div></label>
    </div>
    <div class="ss-pf-2">
      <label class="p-field" for="mobile_number"><span><?= e(t('Mobile number', 'Mobile number')) ?></span>
        <?php if ($mobileLocked): ?>
          <!-- Sent unchanged, so the server still sees the same number. -->
          <div class="p-input"><input type="tel" id="mobile_number" name="mobile_number" readonly value="<?= e($me['mobile_number']) ?>"></div>
          <small class="p-hint"><?= e(t('This is how you sign in to the Smart Sumbong app, so it cannot be changed here.', 'Ito ang ginagamit mo sa pag-sign in sa Smart Sumbong app, kaya hindi ito mapapalitan dito.')) ?></small>
        <?php else: ?>
          <div class="p-input"><input type="tel" id="mobile_number" name="mobile_number" required pattern="(09|\+639)[0-9]{9}" value="<?= e($me['mobile_number']) ?>"></div>
          <small class="p-hint"><?= e(t('Eleven digits, starting 09.', 'Labing-isang digit, nagsisimula sa 09.')) ?></small>
        <?php endif; ?></label>
      <label class="p-field" for="email_ro"><span><?= e(t('Email', 'Email')) ?></span><div class="p-input"><input type="email" id="email_ro" value="<?= e($me['email']) ?>" disabled></div>
        <small class="p-hint"><?= e(t('This is your sign-in identity and cannot be changed here.', 'Ito ang iyong pagkakakilanlan sa pag-sign in at hindi mapapalitan dito.')) ?></small></label>
    </div>

      </section>
      <section class="p-card p-card-pad pf-sec" id="pf-look">
        <div class="pf-fbh"><h3 class="pf-h"><?= e(t('Profile picture', 'Larawan sa profile')) ?></h3>
          <span class="pf-fba">
            <label class="p-btn" for="avatar"><?= p_icon('i-cam', 16) ?><?= e(t('Change photo', 'Palitan ang larawan')) ?></label>
            <input class="ss-file" type="file" id="avatar" name="avatar[]" accept="image/jpeg,image/png,image/webp">
            <?php if (!empty($me['avatar_url'])): ?>
              <button type="button" class="p-btn p-btn-ghost" id="avatar-adjust" data-src="<?= e(cld_thumb($me['avatar_url'], 900, true)) ?>"><?= e(t('Adjust', 'Ayusin')) ?></button>
            <?php endif; ?>
          </span></div>
        <div class="pf-fbav">
          <?php if (!empty($me['avatar_url'])): ?><img class="ss-pf-av pf-photo-av" data-r="<?= e($pfRank) ?>" src="<?= e(cld_thumb($me['avatar_url'], 360, true)) ?>" alt=""><?php else: ?><span class="ss-pf-av ss-pf-ini pf-photo-av" data-r="<?= e($pfRank) ?>"><?= e($initials) ?></span><?php endif; ?>
        </div>
        <p class="p-hint pf-fbn"><?= e(t('Shown as a circle, framed in your role colour everywhere in the portal.', 'Lalabas bilang bilog, na may kulay ng iyong tungkulin sa buong portal.')) ?></p>
        <?php if (!empty($me['avatar_url'])): ?><label class="p-check pf-fbrm"><input type="checkbox" name="remove_avatar" value="1"> <?= e(t('Remove my photo', 'Alisin ang aking larawan')) ?></label><?php endif; ?>
      </section>
      <section class="p-card p-card-pad pf-sec" id="pf-cover">
        <?php $bp = (string) ($me['banner_preset'] ?? 'sidebar'); ?>
        <div class="pf-fbh"><h3 class="pf-h"><?= e(t('Cover photo', 'Larawan sa itaas')) ?></h3>
          <span class="pf-fba">
            <label class="p-btn" for="banner"><?= p_icon('i-cam', 16) ?><?= e(t('Choose a picture', 'Pumili ng larawan')) ?></label>
            <input class="ss-file" type="file" id="banner" name="banner[]" accept="image/jpeg,image/png,image/webp">
            <?php if (!empty($me['banner_url'])): ?><button type="button" class="p-btn p-btn-ghost" id="banner-adjust" data-src="<?= e(cld_thumb((string) $me['banner_url'], 2400)) ?>"><?= e(t('Adjust', 'Ayusin')) ?></button><?php endif; ?>
          </span></div>
        <div class="ss-pf-banner pf-cover<?= in_array($bp, ['photo', 'contour'], true) ? ' ss-pf-banner--plain' : '' ?>" id="ss-pf-banner" aria-hidden="true" style="<?= profile_banner_style($me) ?>"></div>
        <fieldset class="pf-banner">
          <legend class="p-sr"><?= e(t('Cover', 'Larawan sa itaas')) ?></legend>
          <div class="pf-presets" role="radiogroup">
            <?php foreach (['sidebar' => t('My sidebar colour', 'Kulay ng aking sidebar'), 'contour' => t('The barangay\'s contour pattern', 'Contour pattern ng barangay'), 'solid' => t('A colour', 'Isang kulay'),
                            'committee' => t('My committee\'s colour', 'Kulay ng aking komite'), 'photo' => t('My own picture', 'Sarili kong larawan')] as $pk => $pl):
                  if ($pk === 'committee' && empty($me['committee'])) continue; ?>
              <label class="ib-person"><input type="radio" name="banner_preset" value="<?= e($pk) ?>"<?= $bp === $pk ? ' checked' : '' ?>> <?= e($pl) ?></label>
            <?php endforeach; ?>
          </div>
          <div class="pf-colrow"><span><?= e(t('Colour', 'Kulay')) ?></span>
            <label class="pf-col" for="banner_colour"><span class="p-sr"><?= e(t('Colour', 'Kulay')) ?></span><input type="color" id="banner_colour" name="banner_colour" value="<?= e((string) ($me['banner_colour'] ?? '#00308F')) ?>"></label>
            <span class="pf-fn" id="banner-fn"></span></div>
          <input type="hidden" id="banner_y" name="banner_y" value="<?= (int) ($me['banner_y'] ?? 50) ?>">
        </fieldset>
      </section>
      <section class="p-card p-card-pad pf-sec" id="pf-password"><h3 class="pf-h"><?= e(t('Password', 'Password')) ?></h3>
    <p class="p-hint" style="margin:-4px 0 12px"><?= e(t('To change your password, fill in all three boxes. Leave them empty to keep it.', 'Para palitan ang password, punan ang tatlong kahon. Iwanang blangko para panatilihin ito.')) ?></p>
    <div class="ss-pf-3">
      <label class="p-field" for="current_password"><span><?= e(t('Current password', 'Kasalukuyang password')) ?></span><div class="p-input"><input type="password" id="current_password" name="current_password" autocomplete="current-password"></div></label>
      <label class="p-field" for="new_password"><span><?= e(t('New password', 'Bagong password')) ?></span><div class="p-input"><input type="password" id="new_password" name="new_password" minlength="8" autocomplete="new-password"></div>
        <!-- Guidance, not a gate: the rule is eight characters. -->
        <div class="p-pw-meter" aria-hidden="true"><span id="pw-bar"></span></div>
        <small class="p-hint" id="pw-note"><?= e(t('At least 8 characters.', 'Hindi bababa sa 8 karakter.')) ?></small></label>
      <label class="p-field" for="confirm_password"><span><?= e(t('Repeat new password', 'Ulitin ang bagong password')) ?></span><div class="p-input"><input type="password" id="confirm_password" name="confirm_password" minlength="8" autocomplete="new-password"></div></label>
    </div>
      </section>
      <div class="pf-bar">
      <button type="button" class="p-btn p-btn-ghost" id="profile-cancel"><?= e(t('Cancel', 'Kanselahin')) ?></button>
      <button type="submit" class="p-btn p-btn-primary"><?= e(t('Save changes', 'I-save ang mga pagbabago')) ?></button>
    </div>
    </div>
  </form>

  <div class="p-scrim" id="confirm-save"><div class="p-modal" role="dialog" aria-modal="true" aria-labelledby="cs-t">
    <div class="p-m-ico" style="background:var(--p-green-bg);color:var(--p-green)"><?= p_icon('i-check', 26) ?></div>
    <h3 id="cs-t"><?= e(t('Save changes?', 'I-save ang mga pagbabago?')) ?></h3><p><?= e(t('Your profile will be updated right away.', 'Maa-update agad ang iyong profile.')) ?></p>
    <div class="p-actions"><button type="button" class="p-btn p-btn-ghost" data-p-close><?= e(t('Keep editing', 'Ituloy ang pag-edit')) ?></button><button type="button" class="p-btn p-btn-primary" id="confirm-save-ok"><?= e(t('Save', 'I-save')) ?></button></div></div></div>
  <div class="p-scrim" id="confirm-cancel"><div class="p-modal" role="dialog" aria-modal="true" aria-labelledby="cc-t">
    <div class="p-m-ico" style="background:var(--p-red-bg);color:var(--p-red)"><?= p_icon('i-x', 26) ?></div>
    <h3 id="cc-t"><?= e(t('Discard changes?', 'Itapon ang mga pagbabago?')) ?></h3><p><?= e(t('Anything you changed will be lost.', 'Mawawala ang anumang binago mo.')) ?></p>
    <div class="p-actions"><button type="button" class="p-btn p-btn-ghost" data-p-close><?= e(t('Keep editing', 'Ituloy ang pag-edit')) ?></button><a class="p-btn p-btn-danger-soft" href="profile.php"><?= e(t('Discard', 'Itapon')) ?></a></div></div></div>

  <script src="assets/js/cropper.js?v=<?= e(asset_version('../js/cropper.js')) ?>"></script>
  <script>
  // A picture is placed in the editor first: what is inside its frame is what is saved. The editor's result goes back into the file box, so the
  // form posts it exactly as it posted a picked file before.
  (function () {
    var $ = function (id) { return document.getElementById(id); };
    var X = <?= json_encode(['photo' => t('Your photo', 'Iyong larawan'), 'banner' => t('Your banner', 'Iyong banner'), 'use' => t('Use this picture', 'Gamitin ang larawang ito'), 'cancel' => t('Cancel', 'Kanselahin')]) ?>;
    function setFile(input, blob, name) { var dt = new DataTransfer(); dt.items.add(new File([blob], name, { type: blob.type || 'image/jpeg' })); input.files = dt.files; }
    // ---- the photo
    var av = $('avatar'), avAdj = $('avatar-adjust');
    function photoDone(b) {
      if (!b) return false; setFile(av, b, 'photo.jpg');
      var url = URL.createObjectURL(b);
      document.querySelectorAll('.ss-pf-av').forEach(function (el) {
        var img = document.createElement('img'); img.className = el.className.replace('ss-pf-ini', '').trim(); img.alt = ''; img.src = url; if (el.id) img.id = el.id; var r = el.getAttribute('data-r'); if (r) img.setAttribute('data-r', r); el.replaceWith(img);
      });
      var rm = document.querySelector('input[name="remove_avatar"]'); if (rm) rm.checked = false; return true;
    }
    var PHOTO = { round: true, aspect: 1, outW: 640, outH: 640, title: X.photo, apply: X.use, cancel: X.cancel };
    av.addEventListener('change', function () { var f = av.files && av.files[0]; if (!f) return; window.ssCrop.open(Object.assign({ file: f }, PHOTO)).then(function (b) { if (!photoDone(b)) av.value = ''; }); });
    if (avAdj) avAdj.addEventListener('click', function () { window.ssCrop.open(Object.assign({ url: avAdj.dataset.src }, PHOTO)).then(photoDone); });
    // ---- the banner
    var b = $('ss-pf-banner'), y = $('banner_y'), file = $('banner'), col = $('banner_colour'), bnAdj = $('banner-adjust'), url = null;
    if (!b || !y) return;
    var SIDE = '', COM = <?= json_encode(!empty($me['committee']) ? committee_colour((string) $me['committee']) : '') ?>, PHOTO_URL = <?= json_encode(!empty($me['banner_url']) ? cld_thumb((string) $me['banner_url'], 1600) : '') ?>;
    function pick() { var r = document.querySelector('input[name="banner_preset"]:checked'); return r ? r.value : 'sidebar'; }
    function paint() {
      var p = pick(), pic = url || PHOTO_URL;
      b.classList.toggle('ss-pf-banner--plain', p === 'photo' || p === 'contour');
      b.style.cssText = p === 'solid' ? 'background:' + col.value
        : p === 'committee' ? 'background:' + COM
        : p === 'contour' ? 'background:var(--p-side-a) url(assets/img/texture-contours.webp) center/cover;background-blend-mode:soft-light'
        : p === 'photo' && pic ? 'background:#222 url("' + pic + '") center ' + y.value + '%/cover' : SIDE;
    }
    document.querySelectorAll('input[name="banner_preset"]').forEach(function (r) { r.addEventListener('change', paint); });
    col.addEventListener('input', function () { document.querySelector('input[name="banner_preset"][value="solid"]').checked = true; paint(); });
    var BANNER = { round: false, aspect: 12, outW: 1920, outH: 160, title: X.banner, apply: X.use, cancel: X.cancel };
    function bannerDone(blob) {
      if (!blob) return false; setFile(file, blob, 'banner.jpg'); url = URL.createObjectURL(blob); y.value = 50;
      document.querySelector('input[name="banner_preset"][value="photo"]').checked = true; var fn = $('banner-fn'); if (fn) fn.textContent = 'banner.jpg'; paint(); return true;
    }
    file.addEventListener('change', function () { var f = file.files && file.files[0]; if (!f) return; window.ssCrop.open(Object.assign({ file: f }, BANNER)).then(function (blob) { if (!bannerDone(blob)) file.value = ''; }); });
    if (bnAdj) bnAdj.addEventListener('click', function () { window.ssCrop.open(Object.assign({ url: bnAdj.dataset.src }, BANNER)).then(bannerDone); });
  })();
  // the menu follows the scroll, down and up: the section whose top has passed a third of the screen is the one you are in; at the very bottom, the last
  (function () {
    var links = [].slice.call(document.querySelectorAll('.pf-menu a')), secs = links.map(function (a) { return document.getElementById(a.getAttribute('href').slice(1)); }), cur = '', tick = false;
    function on(id) { if (id === cur) return; cur = id; links.forEach(function (a) { a.classList.toggle('on', a.getAttribute('href') === '#' + id); }); }
    function spy() {
      tick = false; var line = innerHeight * 0.34, pick = secs[0] && secs[0].id;
      secs.forEach(function (s) { if (s && s.getBoundingClientRect().top <= line) pick = s.id; });
      if (innerHeight + (window.scrollY || document.documentElement.scrollTop) >= document.documentElement.scrollHeight - 4 && secs.length) pick = secs[secs.length - 1].id;
      if (pick) on(pick);
    }
    function req() { if (!tick) { tick = true; requestAnimationFrame(spy); } }
    window.addEventListener('scroll', req, { passive: true }); document.addEventListener('scroll', req, { passive: true, capture: true }); window.addEventListener('resize', req);
    links.forEach(function (a) { a.addEventListener('click', function () { on(a.getAttribute('href').slice(1)); }); });
    spy();
    var box = location.hash && document.getElementById(location.hash.slice(1));
    if (box && box.focus && /^(INPUT|SELECT|TEXTAREA)$/.test(box.tagName)) { box.focus(); box.scrollIntoView({ block: 'center' }); }
  })();
  </script>
<?php endif; ?>

<script>
(function () {
  var form = document.getElementById('profile-form');
  if (!form) return;
  // Save asks first; the browser's own checks run before the question.
  var sure = false;
  form.addEventListener('submit', function (e) {
    if (sure) return;
    e.preventDefault();
    if (!form.reportValidity()) return;
    window.pOpen('confirm-save');
  });
  document.getElementById('confirm-save-ok').addEventListener('click', function () {
    sure = true; window.pClose(); form.requestSubmit();
  });
  // Cancel asks only when something was changed.
  var start = new FormData(form);
  document.getElementById('profile-cancel').addEventListener('click', function () {
    var changed = false;
    new FormData(form).forEach(function (v, k) { if (v instanceof File ? v.size > 0 : start.get(k) !== v) changed = true; });
    if (changed) window.pOpen('confirm-cancel'); else location.href = 'profile.php';
  });
  // A password change needs all three boxes: any one filled makes the other two required.
  var pwBoxes = ['current_password', 'new_password', 'confirm_password'].map(function (id) { return document.getElementById(id); });
  pwBoxes.forEach(function (box) {
    box.addEventListener('input', function () {
      var any = pwBoxes.some(function (b) { return b.value !== ''; });
      pwBoxes.forEach(function (b) { b.required = any; });
    });
  });
})();

(function () {
  var pw = document.getElementById('new_password'),
      bar = document.getElementById('pw-bar'),
      note = document.getElementById('pw-note');
  if (!pw) return;

  pw.addEventListener('input', function () {
    var v = pw.value, score = 0;
    if (v.length >= 8)  score++;
    if (v.length >= 12) score++;
    if (/[a-z]/.test(v) && /[A-Z]/.test(v)) score++;
    if (/\d/.test(v)) score++;
    if (/[^\w\s]/.test(v)) score++;

    var levels = ['', 'weak', 'weak', 'fair', 'good', 'strong'];
    var words  = [T('At least 8 characters.', 'Hindi bababa sa 8 karakter.'),
                  T('Weak — add length.', 'Mahina — habaan pa.'), T('Weak — add length.', 'Mahina — habaan pa.'),
                  T('Fair. A longer phrase beats added symbols.', 'Katamtaman. Mas mabuti ang mas mahabang parirala kaysa dagdag na simbolo.'),
                  T('Good.', 'Mabuti.'), T('Strong.', 'Malakas.')];
    bar.className = levels[score] ? 'p-' + levels[score] : '';
    bar.style.width = (score / 5 * 100) + '%';
    note.textContent = v === '' ? words[0] : words[score];
  });
})();
</script>

<?php layout_foot(); ?>
