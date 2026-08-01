<?php
/**
 * Case Reports — Figma node 2:2230.
 *
 * Two stacked panels: unread notifications across the top, then the
 * complaint register. Both read through PostgREST with the signed-in
 * admin's token, so the rows that come back are the rows their RLS
 * policies allow. Nothing here filters by role in PHP.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin();
$db    = db();

$search = trim((string) ($_GET['q'] ?? ''));
$sort   = ($_GET['sort'] ?? 'newest') === 'oldest' ? 'created_at.asc' : 'created_at.desc';
$filter = (string) ($_GET['status'] ?? '');

$error = null;
$reports = [];
$notifications = [];

try {
    // The embedded resident is a PostgREST foreign-key expansion; the
    // join happens in the database, not in a second round trip.
    $query = [
        'select' => 'id,tracking_id,subject,category,status,created_at,is_anonymous,'
                  . 'escalation_level,resident:users!reports_resident_id_fkey(full_name)',
        'deleted_at' => 'is.null',
        'order'      => $sort,
        'limit'      => '100',
    ];
    if ($filter !== '') {
        $query['status'] = 'eq.' . $filter;
    }
    if ($search !== '') {
        // Match either the tracking id or the subject line.
        $needle = str_replace(',', ' ', $search);
        $query['or'] = "(tracking_id.ilike.*{$needle}*,subject.ilike.*{$needle}*)";
    }
    $reports = $db->select('reports', $query);

    $notifications = $db->select('notifications', [
        'select'  => 'id,kind,message,created_at,is_read,report_id',
        'user_id' => 'eq.' . $admin['id'],
        'is_read' => 'is.false',
        'order'   => 'created_at.desc',
        'limit'   => '20',
    ]);
} catch (SupabaseError $ex) {
    $error = $ex->getMessage();
}

layout_head('Case Reports', 'cases.php');
?>

<?php if ($error): ?>
  <div class="alert-bar" role="alert"><?= e($error) ?></div>
<?php endif; ?>

<!-- ---------- notifications ---------- -->
<section class="panel">
  <header class="panel-bar">
    <h2 class="panel-title">Notification (<?= count($notifications) ?>)</h2>
    <form class="panel-search" method="get">
      <?= nav_icon('search') ?>
      <input type="search" name="nq" placeholder="Search Here" value="<?= e($_GET['nq'] ?? '') ?>">
    </form>
    <div class="panel-sort">Short by: <strong>Unread</strong></div>
  </header>

  <div class="notif-list">
    <?php if (!$notifications): ?>
      <p class="empty">Nothing new. Notifications appear here when a report is
         escalated, a deadline is missed, or a tanod files a resolution.</p>
    <?php endif; ?>

    <?php foreach ($notifications as $n): ?>
      <article class="notif">
        <span class="notif-dot" aria-hidden="true"></span>
        <div class="notif-body">
          <p class="notif-msg"><?= e($n['message']) ?></p>
          <p class="notif-when"><?= e(relative_time($n['created_at'])) ?></p>
        </div>
        <?php if (!empty($n['report_id'])): ?>
          <a class="btn-review" href="case.php?id=<?= e($n['report_id']) ?>">Review</a>
        <?php endif; ?>
      </article>
    <?php endforeach; ?>
  </div>
</section>

<!-- ---------- complaint register ---------- -->
<section class="panel">
  <header class="panel-bar">
    <h2 class="panel-title">Reports (<?= count($reports) ?>)</h2>

    <form class="panel-search" method="get">
      <?= nav_icon('search') ?>
      <input type="search" name="q" placeholder="Search Here" value="<?= e($search) ?>">
      <input type="hidden" name="status" value="<?= e($filter) ?>">
      <input type="hidden" name="sort" value="<?= e($_GET['sort'] ?? 'newest') ?>">
    </form>

    <form class="panel-sort" method="get">
      <input type="hidden" name="q" value="<?= e($search) ?>">
      <label>Short by:
        <select name="sort" onchange="this.form.submit()">
          <option value="newest" <?= ($_GET['sort'] ?? '') !== 'oldest' ? 'selected' : '' ?>>Newest</option>
          <option value="oldest" <?= ($_GET['sort'] ?? '') === 'oldest' ? 'selected' : '' ?>>Oldest</option>
        </select>
      </label>
      <label class="filter-option">
        <select name="status" onchange="this.form.submit()">
          <option value="">Filter Option</option>
          <?php foreach ([
              'pending_review', 'validated', 'assigned', 'in_progress',
              'offline_investigation', 'resolved', 'closed', 'rejected',
          ] as $s): ?>
            <option value="<?= e($s) ?>" <?= $filter === $s ? 'selected' : '' ?>>
              <?= e(status_label($s)) ?>
            </option>
          <?php endforeach; ?>
        </select>
      </label>
    </form>
  </header>

  <div class="table-wrap">
    <table class="case-table">
      <thead>
        <tr>
          <th scope="col">Resident Name</th>
          <th scope="col">Complaint ID</th>
          <th scope="col">Category</th>
          <th scope="col">Status</th>
          <th scope="col">Date</th>
          <th scope="col"><span class="visually-hidden">Action</span></th>
        </tr>
      </thead>
      <tbody>
        <?php if (!$reports): ?>
          <tr class="row-empty">
            <td colspan="6">
              <?= $search !== '' || $filter !== ''
                  ? 'No complaint matches that search.'
                  : 'No complaints have been filed yet.' ?>
            </td>
          </tr>
        <?php endif; ?>

        <?php foreach ($reports as $r): ?>
          <tr>
            <td>
              <?php if (!empty($r['is_anonymous'])): ?>
                <span class="anon">Anonymous</span>
              <?php else: ?>
                <?= e($r['resident']['full_name'] ?? 'Unknown') ?>
              <?php endif; ?>
            </td>
            <td class="mono"><?= e($r['tracking_id']) ?></td>
            <td><?= e(category_label($r['category'])) ?></td>
            <td>
              <span class="pill pill--<?= e(status_class($r['status'])) ?>">
                <?= e(status_label($r['status'])) ?>
              </span>
              <?php if (($r['escalation_level'] ?? 0) > 0): ?>
                <span class="pill pill--escalated" title="Escalated">Escalated</span>
              <?php endif; ?>
            </td>
            <td><?= e(short_date($r['created_at'])) ?></td>
            <td class="cell-action">
              <a class="btn-review" href="case.php?id=<?= e($r['id']) ?>">Review</a>
            </td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</section>

<?php layout_foot(); ?>
