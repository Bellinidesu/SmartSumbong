<?php
/**
 * Sign out.
 *
 * A GET link, because that is what the Figma sidebar is, but a GET that
 * changes state can be triggered by anything that prefetches a link. So
 * the link lands here, this asks, and the confirmation is a POST with a
 * token. The cost is one extra click on the way out of a shift.
 *
 * revoke happens server-side too: logout() calls GoTrue so the refresh
 * token dies with the session rather than staying valid until it lapses.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = current_admin();

if (!$admin) {
    header('Location: login.php');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && csrf_check($_POST['csrf'] ?? null)) {
    logout();
    header('Location: login.php?out=1');
    exit;
}

layout_head('Log out', 'logout.php');
?>

<div class="p-logout-page">
  <div class="p-modal" role="dialog" aria-labelledby="lo-t">
    <div class="p-m-ico" style="background:var(--p-blue-50);color:var(--p-link)"><?= p_icon('i-out', 26) ?></div>
    <h3 id="lo-t"><?= e(t('Log out?', 'Mag-log out?')) ?></h3>
    <p><?= e(t('You are signed in as ', 'Naka-sign in ka bilang ')) ?><b><?= e(display_name($admin['full_name'])) ?></b>. <?= e(t('Any complaint you left open will still be there when you come back.', 'Nandito pa rin ang anumang sumbong na iniwan mong bukas pagbalik mo.')) ?></p>
    <form method="post" class="p-actions">
      <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
      <a class="p-btn p-btn-ghost" href="dashboard.php"><?= e(t('Stay signed in', 'Manatiling naka-sign in')) ?></a>
      <button class="p-btn p-btn-primary" type="submit"><?= e(t('Log out', 'Mag-log out')) ?></button>
    </form>
  </div>
</div>

<?php layout_foot(); ?>
