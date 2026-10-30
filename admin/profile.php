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

layout_head(t('Edit Profile', 'I-edit ang Profile'), 'profile.php');
?>
<div class="p-topbar"><h1><?= e(t('Edit Profile', 'I-edit ang Profile')) ?></h1></div>

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
      <?php else: ?>
        <label class="p-btn" for="avatar"><?= p_icon('i-cam', 16) ?><?= e(t('Change photo', 'Palitan ang larawan')) ?></label>
        <input class="ss-file" type="file" id="avatar" name="avatar[]" form="profile-form" accept="image/jpeg,image/png,image/webp">
        <?php if (!empty($me['avatar_url'])): ?>
          <label class="p-check"><input type="checkbox" name="remove_avatar" value="1" form="profile-form"> <?= e(t('Remove my photo', 'Alisin ang aking larawan')) ?></label>
        <?php endif; ?>
      <?php endif; ?>
    </div>
  </div>
</section>

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
  <form method="post" id="profile-form" enctype="multipart/form-data" class="p-card p-card-pad ss-pf-form" data-native-confirm="<?= e(t('Save the changes to your account?', 'I-save ang mga pagbabago sa iyong account?')) ?>">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
    <input type="hidden" name="action" value="profile">
    <p class="p-eyebrow"><?= e(t('Your details', 'Iyong mga detalye')) ?></p>
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

    <?php $bp = (string) ($me['banner_preset'] ?? 'sidebar'); ?>
    <fieldset class="pf-banner">
      <legend class="p-eyebrow ss-pf-sec2"><?= e(t('Banner', 'Larawan sa itaas')) ?></legend>
      <div class="pf-presets" role="radiogroup">
        <?php foreach (['sidebar' => t('My sidebar colour', 'Kulay ng aking sidebar'), 'contour' => t('The barangay\'s contour pattern', 'Contour pattern ng barangay'), 'solid' => t('A colour', 'Isang kulay'),
                        'committee' => t('My committee\'s colour', 'Kulay ng aking komite'), 'photo' => t('My own picture', 'Sarili kong larawan')] as $pk => $pl):
              if ($pk === 'committee' && empty($me['committee'])) continue; ?>
          <label class="ib-person"><input type="radio" name="banner_preset" value="<?= e($pk) ?>"<?= $bp === $pk ? ' checked' : '' ?>> <?= e($pl) ?></label>
        <?php endforeach; ?>
      </div>
      <div class="ss-pf-2">
        <label class="p-field" for="banner_colour"><span><?= e(t('Colour', 'Kulay')) ?></span><input type="color" id="banner_colour" name="banner_colour" value="<?= e((string) ($me['banner_colour'] ?? '#00308F')) ?>"></label>
        <label class="p-field" for="banner"><span><?= e(t('Picture', 'Larawan')) ?></span><input class="ss-file-plain" type="file" id="banner" name="banner[]" accept="image/jpeg,image/png,image/webp"></label>
      </div>
      <label class="p-field" for="banner_y"><span><?= e(t('Frame the picture: drag the banner up or down, or use this', 'I-frame ang larawan: hilahin pataas o pababa ang banner, o gamitin ito')) ?></span>
        <input type="range" id="banner_y" name="banner_y" min="0" max="100" value="<?= (int) ($me['banner_y'] ?? 50) ?>"></label>
    </fieldset>

    <p class="p-eyebrow ss-pf-sec2"><?= e(t('Password', 'Password')) ?></p>
    <p class="p-hint" style="margin:-4px 0 12px"><?= e(t('To change your password, fill in all three boxes. Leave them empty to keep it.', 'Para palitan ang password, punan ang tatlong kahon. Iwanang blangko para panatilihin ito.')) ?></p>
    <div class="ss-pf-3">
      <label class="p-field" for="current_password"><span><?= e(t('Current password', 'Kasalukuyang password')) ?></span><div class="p-input"><input type="password" id="current_password" name="current_password" autocomplete="current-password"></div></label>
      <label class="p-field" for="new_password"><span><?= e(t('New password', 'Bagong password')) ?></span><div class="p-input"><input type="password" id="new_password" name="new_password" minlength="8" autocomplete="new-password"></div>
        <!-- Guidance, not a gate: the rule is eight characters. -->
        <div class="p-pw-meter" aria-hidden="true"><span id="pw-bar"></span></div>
        <small class="p-hint" id="pw-note"><?= e(t('At least 8 characters.', 'Hindi bababa sa 8 karakter.')) ?></small></label>
      <label class="p-field" for="confirm_password"><span><?= e(t('Repeat new password', 'Ulitin ang bagong password')) ?></span><div class="p-input"><input type="password" id="confirm_password" name="confirm_password" minlength="8" autocomplete="new-password"></div></label>
    </div>
    <div class="ss-pf-foot">
      <button type="button" class="p-btn p-btn-ghost" id="profile-cancel"><?= e(t('Cancel', 'Kanselahin')) ?></button>
      <button type="submit" class="p-btn p-btn-primary"><?= e(t('Save changes', 'I-save ang mga pagbabago')) ?></button>
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

  <script>
  // A picked photo shows in the banner straight away; a "Change" link from
  // the details rows lands with that box focused.
  document.getElementById('avatar').addEventListener('change', function (e) {
    var f = e.target.files && e.target.files[0]; if (!f) return;
    var p = document.getElementById('ss-photo-preview'), img = document.createElement('img');
    img.className = 'ss-pf-av'; img.id = 'ss-photo-preview'; img.alt = ''; img.src = URL.createObjectURL(f); p.replaceWith(img);
  });
  // 0157: the banner previews as it is set up, and a picture is framed by dragging the banner
  (function () {
    var b = document.getElementById('ss-pf-banner'), y = document.getElementById('banner_y'), file = document.getElementById('banner'),
        col = document.getElementById('banner_colour'), url = null;
    if (!b || !y) return;
    var SIDE = '', COM = <?= json_encode(!empty($me['committee']) ? committee_colour((string) $me['committee']) : '') ?>, PHOTO = <?= json_encode(!empty($me['banner_url']) ? cld_thumb((string) $me['banner_url'], 1600) : '') ?>;
    function pick() { var r = document.querySelector('input[name="banner_preset"]:checked'); return r ? r.value : 'sidebar'; }
    function paint() {
      var p = pick(), pic = url || PHOTO;
      b.classList.toggle('ss-pf-banner--plain', p === 'photo' || p === 'contour');
      b.style.cssText = p === 'solid' ? 'background:' + col.value
        : p === 'committee' ? 'background:' + COM
        : p === 'contour' ? 'background:var(--p-side-a) url(assets/img/texture-contours.webp) center/cover;background-blend-mode:soft-light'
        : p === 'photo' && pic ? 'background:#222 url("' + pic + '") center ' + y.value + '%/cover;cursor:ns-resize' : SIDE;
    }
    document.querySelectorAll('input[name="banner_preset"]').forEach(function (r) { r.addEventListener('change', paint); });
    col.addEventListener('input', function () { document.querySelector('input[name="banner_preset"][value="solid"]').checked = true; paint(); });
    y.addEventListener('input', paint);
    file.addEventListener('change', function () { var f = file.files && file.files[0]; if (!f) return; url = URL.createObjectURL(f); document.querySelector('input[name="banner_preset"][value="photo"]').checked = true; paint(); });
    var drag = null;
    b.addEventListener('pointerdown', function (e) { if (pick() !== 'photo') return; drag = { y: e.clientY, v: +y.value }; b.setPointerCapture(e.pointerId); });
    b.addEventListener('pointermove', function (e) { if (!drag) return; y.value = Math.max(0, Math.min(100, Math.round(drag.v - (e.clientY - drag.y) / 2))); paint(); });
    b.addEventListener('pointerup', function () { drag = null; });
  })();
  (function () {
    var box = location.hash && document.getElementById(location.hash.slice(1));
    if (box && box.focus) { box.focus(); box.scrollIntoView({ block: 'center' }); }
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
