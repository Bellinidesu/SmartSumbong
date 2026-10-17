<?php
/**
 * All the widgets on one page, each with live data, so every one can be seen without changing the Workspace
 * (Ace, 17 Oct 2026). Each card is a frame of widget-view.php, loaded when it scrolls near, so the page stays light.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/widget_panel.php';

$admin  = require_admin();
$cat    = widget_catalogue();
$labels = widget_labels();
$groups = widget_group_labels();
$mine   = [];
try {
    $r = db()->select('workspace_prefs', ['select' => 'tabs', 'user_id' => 'eq.' . $admin['id'], 'limit' => '1']);
    $mine = (array) ($r[0]['tabs'] ?? WS_DEFAULT_TABS);
} catch (SupabaseError) {
    $mine = WS_DEFAULT_TABS;
}

layout_head(t('All widgets', 'Lahat ng widget'), 'workspace.php');
?>
<div class="p-topbar"><h1><?= e(t('All widgets', 'Lahat ng widget')) ?></h1>
  <a class="p-btn p-btn-ghost" href="workspace.php"><?= e(t('Back to the Workspace', 'Bumalik sa Workspace')) ?></a></div>
<p class="p-sub" style="margin:0 0 14px"><?= e(t('Every widget with live data, as it looks right now. Nothing here changes your own Workspace. To use one, open the Workspace and press + Widgets.', 'Bawat widget na may live na datos, kung paano ito ngayon. Walang binabago rito sa sarili mong Workspace. Para gamitin ang isa, buksan ang Workspace at pindutin ang + Mga widget.')) ?></p>
<link rel="stylesheet" href="assets/css/widgets-gallery.css?v=<?= e(asset_version('widgets-gallery.css')) ?>">
<div class="wg-bar">
  <label class="wg-search"><input type="search" id="wg-q" placeholder="<?= e(t('Search 120 widgets', 'Maghanap sa 120 widget')) ?>" autocomplete="off" aria-label="<?= e(t('Search widgets', 'Maghanap ng widget')) ?>"></label>
  <div class="wg-tabs" role="group" aria-label="<?= e(t('Group', 'Pangkat')) ?>">
    <button type="button" data-g="" aria-pressed="true"><?= e(t('All', 'Lahat')) ?> <b><?= count($cat) ?></b></button>
    <?php foreach ($groups as $g => $name): ?>
      <button type="button" data-g="<?= e($g) ?>" aria-pressed="false"><?= e($name) ?> <b><?= count(array_filter($cat, static fn ($c) => $c[0] === $g)) ?></b></button>
    <?php endforeach; ?>
  </div>
</div>
<div class="wg-grid" id="wg-grid">
<?php foreach ($groups as $g => $name): ?>
  <h2 class="wg-h" data-g="<?= e($g) ?>"><?= e($name) ?></h2>
  <?php foreach ($cat as $id => [$grp, $status, $needs]): if ($grp !== $g) continue; ?>
    <article class="wg-card" data-g="<?= e($g) ?>" data-s="<?= e(mb_strtolower($labels[$id][0] . ' ' . $labels[$id][1])) ?>">
      <header><div><b><?= e($labels[$id][0]) ?></b><small><?= e($labels[$id][1]) ?></small></div>
        <?php if (in_array($id, $mine, true)): ?><span class="wg-on"><?= e(t('on your Workspace', 'nasa Workspace mo')) ?></span><?php endif; ?></header>
      <iframe data-src="widget-view.php?w=<?= e($id) ?>" title="<?= e($labels[$id][0]) ?>" loading="lazy"></iframe>
    </article>
  <?php endforeach; ?>
<?php endforeach; ?>
</div>
<script src="assets/js/widgets-gallery.js?v=<?= e(asset_version('../js/widgets-gallery.js')) ?>" defer></script>
<?php layout_foot(); ?>
