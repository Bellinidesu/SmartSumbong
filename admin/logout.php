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

<section class="card confirm-card">
  <h1 class="case-heading">Log out?</h1>
  <p class="case-body">
    You are signed in as <strong><?= e($admin['full_name']) ?></strong>.
    Any complaint you left open will still be there when you come back.
  </p>

  <form method="post" class="confirm-actions">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
    <button class="btn-accept" type="submit">Log out</button>
    <a class="btn-deny" href="dashboard.php">Stay signed in</a>
  </form>
</section>

<?php layout_foot(); ?>
