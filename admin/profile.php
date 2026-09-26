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
        $email = (string) ($db->authUser()['email'] ?? '');
    } catch (Throwable) {
        return null;
    }
    return $email === '' ? null : str_ends_with(strtolower($email), '@auth.smartsumbong.local');
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
                $name   = trim((string) ($_POST['full_name'] ?? ''));
                $mobile = trim((string) ($_POST['mobile_number'] ?? ''));

                if (mb_strlen($name) < 2) {
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

            if ($patch !== null) {
                $db->update('users', ['id' => 'eq.' . $admin['id']], $patch);
                $_SESSION[SESSION_KEY]['full_name'] = $patch['full_name'];
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

try {
    $rows = $db->select('users', [
        'select' => 'id,full_name,email,mobile_number,role,verification_status,created_at,avatar_url',
        'id'     => 'eq.' . $admin['id'],
        'limit'  => '1',
    ]);
    $me = $rows[0] ?? null;
} catch (SupabaseError $ex) {
    $error = safe_error($ex);
}

// Knowing when the account was last used is how someone notices it was
// used by somebody else. Never worth failing the page over.
$lastSeen = null;
try {
    $lastSeen = db()->authUser()['last_sign_in_at'] ?? null;
} catch (Throwable) {
}
// Locked unless positively known to be safe to change.
$mobileLocked = signs_in_by_phone($db) !== false;

$editing = isset($_GET['edit']);

layout_head(t('Edit Profile', 'I-edit ang Profile'), 'profile.php');
?>

<?php if ($flash): ?>
  <div class="flash flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
<?php endif; ?>

<?php if ($error || !$me): ?>
  <div class="alert-bar" role="alert"><?= e($error ?? t('Your profile could not be loaded.', 'Hindi ma-load ang iyong profile.')) ?></div>
  <?php layout_foot(); exit; ?>
<?php endif; ?>

<?php
$parts    = preg_split('/\s+/', trim((string) $me['full_name'])) ?: [];
$initials = strtoupper(mb_substr($parts[0] ?? '?', 0, 1) . (count($parts) > 1 ? mb_substr(end($parts), 0, 1) : ''));
?>
<!-- Figma "Edit profile" (12:6775) and "Editing profile" (12:6938),
     branch B: the fields on the left, who is signed in on the right. -->
<section class="profile-card">
  <div class="profile-main">
    <h1 class="profile-title"><?= e(t('Profile', 'Profile')) ?></h1>

    <?php if (!$editing): ?>
      <div class="profile-field">
        <label for="pf_name"><?= e(t('Full Name', 'Buong Pangalan')) ?></label>
        <input id="pf_name" type="text" value="<?= e($me['full_name']) ?>" readonly>
      </div>
      <div class="profile-field">
        <label for="pf_mobile"><?= e(t('Mobile Number', 'Mobile Number')) ?></label>
        <input id="pf_mobile" type="text" value="<?= e($me['mobile_number']) ?>" readonly>
      </div>
      <div class="profile-field">
        <label for="pf_email"><?= e(t('Email', 'Email')) ?></label>
        <input id="pf_email" type="text" value="<?= e($me['email']) ?>" readonly>
      </div>
      <div class="profile-field">
        <label for="pf_pw"><?= e(t('Password', 'Password')) ?></label>
        <input id="pf_pw" type="password" value="************" readonly aria-describedby="pf_pw_hint">
        <p class="field-hint" id="pf_pw_hint"><?= e(t('Change it with Edit Profile.', 'Palitan ito sa I-edit ang Profile.')) ?></p>
      </div>

    <?php else: ?>
      <form method="post" id="profile-form">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
        <input type="hidden" name="action" value="profile">

        <div class="profile-field">
          <label for="full_name"><?= e(t('Full Name', 'Buong Pangalan')) ?></label>
          <input type="text" id="full_name" name="full_name" required maxlength="120"
                 value="<?= e($me['full_name']) ?>">
        </div>

        <div class="profile-field">
          <label for="mobile_number"><?= e(t('Mobile Number', 'Mobile Number')) ?></label>
          <?php if ($mobileLocked): ?>
            <!-- Sent unchanged, so the server still sees the same number. -->
            <input type="tel" id="mobile_number" name="mobile_number" readonly
                   value="<?= e($me['mobile_number']) ?>">
            <p class="field-hint">
              <?= e(t('This is how you sign in to the Smart Sumbong app, so it cannot be changed here.',
                      'Ito ang ginagamit mo sa pag-sign in sa Smart Sumbong app, kaya hindi ito mapapalitan dito.')) ?>
            </p>
          <?php else: ?>
            <input type="tel" id="mobile_number" name="mobile_number" required
                   pattern="(09|\+639)[0-9]{9}" value="<?= e($me['mobile_number']) ?>">
            <p class="field-hint"><?= e(t('Eleven digits, starting 09.', 'Labing-isang digit, nagsisimula sa 09.')) ?></p>
          <?php endif; ?>
        </div>

        <div class="profile-field">
          <label for="email_ro"><?= e(t('Email', 'Email')) ?></label>
          <input type="email" id="email_ro" value="<?= e($me['email']) ?>" disabled>
          <p class="field-hint"><?= e(t('This is your sign-in identity and cannot be changed here.', 'Ito ang iyong pagkakakilanlan sa pag-sign in at hindi mapapalitan dito.')) ?></p>
        </div>

        <p class="profile-note"><?= e(t('To change your password, fill in all three boxes below. Leave them empty to keep it.',
                                 'Para palitan ang password, punan ang tatlong kahon sa ibaba. Iwanang blangko para panatilihin ito.')) ?></p>

        <div class="profile-field">
          <label for="current_password"><?= e(t('Current Password', 'Kasalukuyang Password')) ?></label>
          <input type="password" id="current_password" name="current_password" autocomplete="current-password">
        </div>

        <div class="profile-field">
          <label for="new_password"><?= e(t('New Password', 'Bagong Password')) ?></label>
          <input type="password" id="new_password" name="new_password" minlength="8" autocomplete="new-password">
          <!-- Guidance, not a gate. The rule is eight characters; the meter
               just tells you whether you have done better than that. -->
          <div class="pw-meter" aria-hidden="true"><span id="pw-bar"></span></div>
          <p class="field-hint" id="pw-note"><?= e(t('At least 8 characters.', 'Hindi bababa sa 8 karakter.')) ?></p>
        </div>

        <div class="profile-field">
          <label for="confirm_password"><?= e(t('Repeat New Password', 'Ulitin ang Bagong Password')) ?></label>
          <input type="password" id="confirm_password" name="confirm_password" minlength="8" autocomplete="new-password">
        </div>

        <div class="profile-actions">
          <button type="button" class="profile-btn" id="profile-cancel"><?= e(t('Cancel', 'Kanselahin')) ?></button>
          <button type="submit" class="profile-btn profile-btn--save"><?= e(t('Save', 'I-save')) ?></button>
        </div>
      </form>

      <!-- Figma 12:7185 and 12:7497. -->
      <dialog class="profile-confirm" id="confirm-cancel">
        <p class="profile-confirm-title"><?= e(t('Are you Sure?', 'Sigurado ka ba?')) ?></p>
        <p class="profile-confirm-text"><?= e(t('Your changes will not be saved.', 'Hindi mase-save ang iyong mga pagbabago.')) ?></p>
        <div class="profile-confirm-actions">
          <button type="button" class="profile-btn" data-close><?= e(t('Cancel', 'Kanselahin')) ?></button>
          <a class="profile-btn profile-btn--save" href="profile.php">OK !</a>
        </div>
      </dialog>
      <dialog class="profile-confirm" id="confirm-save">
        <p class="profile-confirm-title"><?= e(t('Save Changes ?', 'I-save ang mga Pagbabago?')) ?></p>
        <div class="profile-confirm-actions">
          <button type="button" class="profile-btn" data-close><?= e(t('Cancel', 'Kanselahin')) ?></button>
          <button type="button" class="profile-btn profile-btn--save" id="confirm-save-ok">OK !</button>
        </div>
      </dialog>
    <?php endif; ?>
  </div>

  <aside class="profile-side">
    <?php if (!empty($me['avatar_url'])): ?>
      <img class="profile-avatar" src="<?= e($me['avatar_url']) ?>" alt="">
    <?php else: ?>
      <span class="profile-avatar profile-avatar--initials" aria-hidden="true"><?= e($initials) ?></span>
    <?php endif; ?>
    <p class="profile-name"><?= e($me['full_name']) ?></p>
    <p class="profile-email"><?= e($me['email']) ?></p>
    <div class="profile-pills">
      <span class="pill pill--assigned"><?= e(status_label($me['role'])) ?></span>
      <span class="pill pill--resolved"><?= e(status_label($me['verification_status'])) ?></span>
    </div>
    <?php if (!$editing): ?>
      <a class="profile-edit" href="profile.php?edit=1">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"
             stroke-linejoin="round" aria-hidden="true"><path d="M4 7h10M4 12h7M4 17h5"/><path d="m14 19 1-3 5-5 2 2-5 5-3 1z"/></svg>
        <?= e(t('Edit Profile', 'I-edit ang Profile')) ?>
      </a>
    <?php endif; ?>
    <dl class="profile-meta">
      <dt><?= e(t('Account created', 'Ginawa ang account')) ?></dt><dd><?= e(long_datetime($me['created_at'])) ?></dd>
      <?php if ($lastSeen): ?>
        <dt><?= e(t('Last signed in', 'Huling pag-sign in')) ?></dt><dd><?= e(long_datetime($lastSeen)) ?></dd>
      <?php endif; ?>
    </dl>
  </aside>
</section>

<script>
(function () {
  var form = document.getElementById('profile-form');
  if (!form) return;

  // Save asks first (Figma 12:7497); the browser's own checks run before
  // the question, so the dialog never confirms a form that cannot send.
  var ask = document.getElementById('confirm-save'), sure = false;
  form.addEventListener('submit', function (e) {
    if (sure) return;
    e.preventDefault();
    if (!form.reportValidity()) return;
    ask.showModal();
  });
  document.getElementById('confirm-save-ok').addEventListener('click', function () {
    sure = true;
    ask.close();
    form.requestSubmit();
  });

  // Cancel asks only when something was changed (Figma 12:7185).
  var start = new FormData(form), cancel = document.getElementById('confirm-cancel');
  document.getElementById('profile-cancel').addEventListener('click', function () {
    var changed = false;
    new FormData(form).forEach(function (v, k) { if (start.get(k) !== v) changed = true; });
    if (changed) cancel.showModal(); else location.href = 'profile.php';
  });
  document.querySelectorAll('.profile-confirm [data-close]').forEach(function (b) {
    b.addEventListener('click', function () { b.closest('dialog').close(); });
  });

  // A password change needs all three boxes: any one filled makes the
  // other two required, so the browser says which is missing.
  var pwBoxes = ['current_password', 'new_password', 'confirm_password'].map(function (id) {
    return document.getElementById(id);
  });
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
    bar.className = levels[score] || '';
    bar.style.width = (score / 5 * 100) + '%';
    note.textContent = v === '' ? words[0] : words[score];
  });
})();
</script>

<?php layout_foot(); ?>
