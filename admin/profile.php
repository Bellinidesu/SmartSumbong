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

session_start_once();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $flash = null;
    $level = 'ok';

    if (!csrf_check($_POST['csrf'] ?? null)) {
        $flash = 'That form expired. Please try again.';
        $level = 'error';
    } else {
        try {
            switch ($_POST['action'] ?? '') {
                case 'details':
                    $name   = trim((string) ($_POST['full_name'] ?? ''));
                    $mobile = trim((string) ($_POST['mobile_number'] ?? ''));

                    if (mb_strlen($name) < 2) {
                        throw new SupabaseError('Please enter your full name.');
                    }
                    if (!preg_match('/^09\d{9}$/', $mobile)) {
                        throw new SupabaseError('Mobile number must be 11 digits starting 09.');
                    }

                    $db->update('users', ['id' => 'eq.' . $admin['id']], [
                        'full_name'     => $name,
                        'mobile_number' => $mobile,
                    ]);

                    $_SESSION[SESSION_KEY]['full_name'] = $name;
                    $flash = 'Profile updated.';
                    break;

                case 'password':
                    $current = (string) ($_POST['current_password'] ?? '');
                    $new     = (string) ($_POST['new_password'] ?? '');
                    $confirm = (string) ($_POST['confirm_password'] ?? '');

                    if (mb_strlen($new) < 8) {
                        throw new SupabaseError('The new password must be at least 8 characters.');
                    }
                    if ($new !== $confirm) {
                        throw new SupabaseError('The two new passwords do not match.');
                    }
                    if ($new === $current) {
                        throw new SupabaseError('The new password is the same as the current one.');
                    }

                    // Proves the person at the keyboard is the account holder.
                    Supabase::signIn($admin['email'], $current);

                    $db->updateAuthUser(['password' => $new]);
                    $flash = 'Password changed. It applies the next time you sign in.';
                    break;

                default:
                    $flash = 'Unknown action.';
                    $level = 'error';
            }
        } catch (SupabaseError $ex) {
            // GoTrue answers a wrong password with a generic grant error;
            // say what actually went wrong instead.
            $msg = $ex->getMessage();
            $flash = str_contains(strtolower($msg), 'credential')
                ? 'That current password is not right.'
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
        'select' => 'id,full_name,email,mobile_number,role,verification_status,created_at',
        'id'     => 'eq.' . $admin['id'],
        'limit'  => '1',
    ]);
    $me = $rows[0] ?? null;
} catch (SupabaseError $ex) {
    $error = $ex->getMessage();
}

$editing = isset($_GET['edit']);

layout_head('Edit Profile', 'profile.php');
?>

<?php if ($flash): ?>
  <div class="flash flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
<?php endif; ?>

<?php if ($error || !$me): ?>
  <div class="alert-bar" role="alert"><?= e($error ?? 'Your profile could not be loaded.') ?></div>
  <?php layout_foot(); exit; ?>
<?php endif; ?>

<div class="case-grid">
  <section class="card card--complaint">
    <h1 class="case-heading">Profile</h1>
    <div class="case-flags">
      <span class="pill pill--assigned"><?= e(status_label($me['role'])) ?></span>
      <span class="pill pill--resolved"><?= e(status_label($me['verification_status'])) ?></span>
    </div>

    <?php if (!$editing): ?>
      <div class="case-block">
        <h3 class="case-sub">Account Details</h3>
        <dl class="detail-list">
          <dt>Full name</dt><dd><?= e($me['full_name']) ?></dd>
          <dt>Email address</dt><dd><?= e($me['email']) ?></dd>
          <dt>Mobile number</dt><dd class="mono"><?= e($me['mobile_number']) ?></dd>
          <dt>Account created</dt><dd><?= e(long_datetime($me['created_at'])) ?></dd>
        </dl>
      </div>

    <?php else: ?>
      <form method="post" class="case-block">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
        <h3 class="case-sub">Account Details</h3>

        <div class="control-field">
          <label class="field-label" for="full_name">Full name</label>
          <input type="text" id="full_name" name="full_name" required maxlength="120"
                 value="<?= e($me['full_name']) ?>">
        </div>

        <div class="control-field">
          <label class="field-label" for="mobile_number">Mobile number</label>
          <input type="tel" id="mobile_number" name="mobile_number" required
                 pattern="09[0-9]{9}" value="<?= e($me['mobile_number']) ?>">
          <p class="field-hint">Eleven digits, starting 09.</p>
        </div>

        <div class="control-field">
          <label class="field-label" for="email_ro">Email address</label>
          <input type="email" id="email_ro" value="<?= e($me['email']) ?>" disabled>
          <p class="field-hint">
            This is your sign-in identity and cannot be changed here.
          </p>
        </div>

        <div class="confirm-actions" style="justify-content:flex-start">
          <button class="btn-accept" type="submit" name="action" value="details">Save changes</button>
          <a class="btn-deny" href="profile.php">Cancel</a>
        </div>
      </form>
    <?php endif; ?>
  </section>

  <aside class="card card--controls">
    <h3 class="case-sub">Admin Controls</h3>

    <?php if (!$editing): ?>
      <a class="btn-accept" href="profile.php?edit=1" style="text-decoration:none">Edit Profile</a>
    <?php endif; ?>

    <form method="post" class="control-stack" style="margin-top:16px">
      <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
      <p class="control-note">Change your password. You will stay signed in on this device.</p>

      <div class="control-field">
        <label class="field-label" for="current_password">Current password</label>
        <input type="password" id="current_password" name="current_password" required autocomplete="current-password">
      </div>

      <div class="control-field">
        <label class="field-label" for="new_password">New password</label>
        <input type="password" id="new_password" name="new_password" required minlength="8" autocomplete="new-password">
      </div>

      <div class="control-field">
        <label class="field-label" for="confirm_password">Repeat new password</label>
        <input type="password" id="confirm_password" name="confirm_password" required minlength="8" autocomplete="new-password">
      </div>

      <button class="btn-deny-confirm" type="submit" name="action" value="password">Change password</button>
    </form>
  </aside>
</div>

<?php layout_foot(); ?>
