<?php
/**
 * Set a new password — Rose's new-administrator flow (5 Oct 2026).
 *
 * An administrator issued a temporary password (users.must_change_password)
 * lands here straight after signing in; require_admin() sends every other
 * page back here until it is done. Any administrator can also come here
 * to change their own password.
 *
 * The password is changed through GoTrue with the admin's own session,
 * then clear_password_change_flag() (0028) lifts the flag.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin  = require_admin();
$forced = !empty($admin['must_change']);
$error  = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $new    = (string) ($_POST['password'] ?? '');
    $repeat = (string) ($_POST['repeat'] ?? '');
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $error = t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.');
    } elseif (strlen($new) < 8) {
        $error = t('Use at least 8 characters.', 'Gumamit ng hindi bababa sa 8 character.');
    } elseif ($new !== $repeat) {
        $error = t('The two passwords do not match.', 'Hindi magkatugma ang dalawang password.');
    } else {
        try {
            $db = db();
            $db->updateAuthUser(['password' => $new]);
            $db->rpc('clear_password_change_flag');
            $_SESSION[SESSION_KEY]['must_change'] = false;
            $_SESSION['flash'] = ['text' => t('Password changed.', 'Napalitan na ang password.'), 'level' => 'ok'];
            header('Location: dashboard.php');
            exit;
        } catch (SupabaseError $ex) {
            $error = safe_error($ex);
        }
    }
}

layout_head(t('Set a new password', 'Magtakda ng bagong password'), '');
?>
<div style="max-width:440px;margin:24px auto">
  <div class="p-card p-card-pad" style="display:grid;gap:14px">
    <h1 style="margin:0"><?= e(t('Set a new password', 'Magtakda ng bagong password')) ?></h1>
    <?php if ($forced): ?>
      <div class="p-flash p-flash--error" role="status"><?= e(t('You signed in with a temporary password. Choose your own to continue.', 'Nag-sign in ka gamit ang pansamantalang password. Pumili ng sarili mo para magpatuloy.')) ?></div>
    <?php endif; ?>
    <?php if ($error): ?>
      <div class="p-flash p-flash--error" role="alert"><?= e($error) ?></div>
    <?php endif; ?>
    <form method="post" style="display:grid;gap:12px">
      <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
      <div class="p-cfield">
        <label class="p-flabel" for="pw-new"><?= e(t('New password', 'Bagong password')) ?></label>
        <input class="p-input-plain" type="password" id="pw-new" name="password" minlength="8" required autocomplete="new-password">
      </div>
      <div class="p-cfield">
        <label class="p-flabel" for="pw-repeat"><?= e(t('Type it again', 'I-type muli')) ?></label>
        <input class="p-input-plain" type="password" id="pw-repeat" name="repeat" minlength="8" required autocomplete="new-password">
      </div>
      <p class="p-hint" style="margin:0"><?= e(t('At least 8 characters. Do not reuse the temporary password.', 'Hindi bababa sa 8 character. Huwag gamitin muli ang pansamantalang password.')) ?></p>
      <button class="p-btn p-btn-orange p-btn-block" type="submit"><?= e(t('Save and continue', 'I-save at magpatuloy')) ?></button>
    </form>
    <?php if ($forced): ?>
      <a class="p-back" href="logout.php"><?= e(t('Sign out instead', 'Mag-sign out na lang')) ?></a>
    <?php endif; ?>
  </div>
</div>
<?php layout_foot(); ?>
